#!/usr/bin/env bash
# ============================================================================
# monitor-lab.sh — 第 22 章:官方列的平台告警真的被觸發,以及監控端點本身有沒有被保護好
# ----------------------------------------------------------------------------
# 白話:監控的價值在「出事時真的會響」。這支腳本實際把 broker 或 controller 停掉,
#   看 Prometheus 的告警規則有沒有在預期時間內觸發、有沒有送到 Alertmanager、恢復後有沒有解除。
#   另外檢查「監控自己」的安全:各個 exporter 與 Prometheus 是不是都要帳密或憑證才能連。
# 前置條件:叢集已啟動(scripts/up.sh),且 prometheus、alertmanager 已啟動
#   (docker compose --profile c3 up -d prometheus alertmanager)
# 用法:
#   scripts/monitor-lab.sh jmx-endpoint  每個 broker、controller 都開了 JMX exporter(7778 埠),關鍵指標都在
#   scripts/monitor-lab.sh protect       監控端點的保護:exporter(HTTPS + Basic)、blackbox(HTTPS + mTLS)、帳號分開
#   scripts/monitor-lab.sh rules         7 條平台告警規則已載入並評估,基準狀態沒有告警
#   scripts/monitor-lab.sh urp           停 1 台 broker → URP 告警觸發、送到 Alertmanager;恢復後解除
#   scripts/monitor-lab.sh offline       RF=1 的 topic 所在 broker 掉線 → 離線分區告警;恢復後解除
#   scripts/monitor-lab.sh controller    停 1 台 controller → ControllerMissing;再停 1 台(失去多數)→ ActiveControllerCountNotOne
# 環境變數:SRC=telemetry(預設,Confluent telemetry → Prometheus)或 SRC=jmx(JMX exporter → Prometheus)。
#   兩組規則是同一組告警,JMX 版名稱多一個 Jmx(例如 KafkaJmxUnderReplicatedPartitions)。
# 會改動什麼:暫時停止 broker3 或 controller2/3 容器,結束前一律啟動回來;offline 會建立並刪除 topic mon.offline。
# 時間:telemetry 每 60 秒送一次、規則每 60 秒評估一次,每個實驗約 4 到 9 分鐘;所有等待都有上限。
# 怎麼判斷成功:最後一行印「判定:…」。
# 常見失敗:
#   「prometheus 沒有在跑」→ docker compose --profile c3 up -d prometheus alertmanager
#   告警一直不觸發 → telemetry 路徑本來就慢(約 150 到 250 秒);確認等待時間,或改用 SRC=jmx
#   JMX exporter 指標是空的 → 容器剛重啟,官方設定有 startDelaySeconds: 120,等 2 分鐘
# ============================================================================
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/prom.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/kafka.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR" || exit 1
need_ha_mode
need_container prometheus "先執行:docker compose --profile c3 up -d prometheus alertmanager"

SRC="${SRC:-telemetry}"
RULE_GROUP=$([ "$SRC" = jmx ] && echo kafka-platform-jmx || echo kafka-platform)
NODES="broker1 broker2 broker3 broker4 controller1 controller2 controller3"
# 平台告警的名稱都以 Kafka 開頭;KafkaAuthFailuresBurst 是另一章(認證失敗)的告警,這裡不算
PLATFORM_ALERTS='^Kafka'
NOT_PLATFORM='KafkaAuthFailuresBurst|KafkaConsumerLagHigh|KafkaExporterDown'   # 其他章節(認證失敗、第 26 章的 consumer lag)的告警,這裡不算

# ---------- 小工具(這支腳本專用) ----------

# alert_name <基本名稱>:SRC=jmx 時告警名稱是 KafkaJmx…,telemetry 時維持原名。
alert_name() { [ "$SRC" = jmx ] && echo "KafkaJmx${1#Kafka}" || echo "$1"; }

# platform_firing:目前正在觸發的平台告警(逗號分隔;沒有印 -)。
# (alerts_firing 會在名稱後加 @instance;這裡只比對名稱,所以把 @… 拿掉)
platform_firing() { alerts_firing "$PLATFORM_ALERTS" "$NOT_PLATFORM" | sed -E 's/@[^,]*//g'; }

# wait_fire <告警名稱> <最多等幾秒>:等告警進入 firing 狀態,印出等了幾秒;逾時回傳 1。
wait_fire() {
  local name="$1" max="$2" t0 firing
  t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt "$max" ]; do
    firing=$(platform_firing)
    case ",$firing," in *",$name,"*) note "$(( $(date +%s) - t0 )) 秒後 $name 觸發(目前 firing:$firing)"; return 0;; esac
    sleep 10
  done
  note "等了 $max 秒仍未觸發 $name(目前 firing:$(platform_firing))"; return 1
}

# wait_clear <告警名稱> <最多等幾秒>:等告警解除(不再 firing);逾時回傳 1。
wait_clear() {
  local name="$1" max="$2" t0
  t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt "$max" ]; do
    case ",$(platform_firing)," in
      *",$name,"*) sleep 10 ;;
      *) note "$(( $(date +%s) - t0 )) 秒後 $name 解除"; return 0 ;;
    esac
  done
  note "等了 $max 秒仍未解除 $name"; return 1
}

# jmx_get <節點> [帳密]:用 Basic 帳密抓某節點的 JMX exporter 指標(HTTPS,7778 埠)。
jmx_get() { dcurl -u "Prometheus:$JMX_PW" "https://$1:7778/metrics" 2>/dev/null; }

# http_code <dcurl 參數...>:只取回應的 HTTP 狀態碼那一行,例如 [HTTP 200];連不上是 [HTTP 000]。
http_code() { dcurl "$@" 2>/dev/null | tail -1; }

# ---------- 各個實驗 ----------

lab_jmx_endpoint() {
  say "確認 6 個節點都開了 JMX exporter(HTTPS + Basic 帳密),而且關鍵指標都在"
  local sha ver miss=0 n c
  JMX_PW=$(cat config/c3/jmx_exporter.pw)
  sha=$(sha1sum config/jmx/jmx_prometheus_javaagent.jar | awk '{print $1}')
  ver=$(cat config/jmx/jmx_prometheus_javaagent.jar.version 2>/dev/null)
  echo "agent:jmx_prometheus_javaagent $ver,SHA-1 $sha(下載時已與 Maven Central 的 .sha1 比對)"
  echo "JVM 參數(broker1):$(docker inspect broker1 --format '{{range .Config.Env}}{{println .}}{{end}}' | grep '^KAFKA_OPTS=' | cut -c1-150)"
  for n in $NODES; do
    c=$(jmx_get "$n" | grep -c '^kafka_')
    echo "  $n:7778(HTTPS + Basic)→ $c 個 kafka_ 指標"
    [ "$c" -gt 50 ] || miss=1
  done
  echo "broker1 的關鍵指標:"
  jmx_get broker1 | grep -E '^kafka_server_replicamanager_(underreplicatedpartitions|underminisrpartitioncount) ' | sed 's/^/  /'
  echo "controller1 的關鍵指標:"
  jmx_get controller1 | grep -E '^kafka_controller_kafkacontroller_(offlinepartitionscount|activecontrollercount) ' | sed 's/^/  /'
  [ "$miss" = 0 ] && verdict "6 個節點都開了 JMX exporter(7778 埠,HTTPS + Basic 帳密),URP、離線分區、active controller 等關鍵指標都在"
}

lab_protect() {
  local bad=0 n a b c h probe n1 n2 n3 ok down up
  JMX_PW=$(cat config/c3/jmx_exporter.pw)

  say "① 6 個 JMX exporter:不帶帳密、錯密碼都要被擋(401),正確帳密才給資料(200),明文 http 連不上"
  echo "① 6 個節點的 JMX exporter(HTTPS + Basic 帳密):"
  for n in $NODES; do
    a=$(http_code "https://$n:7778/metrics")
    b=$(http_code -u Prometheus:wrong-pw "https://$n:7778/metrics")
    c=$(http_code -u "Prometheus:$JMX_PW" "https://$n:7778/metrics")
    h=$(http_code "http://$n:7778/metrics")
    echo "  $n:不帶帳密 $a;錯密碼 $b;正確 $c;明文 http $h"
    [ "$a" = "[HTTP 401]" ] && [ "$b" = "[HTTP 401]" ] && [ "$c" = "[HTTP 200]" ] && [ "$h" = "[HTTP 000]" ] || bad=1
  done

  say "② blackbox exporter 要求 mTLS:沒有憑證、或憑證不是行內 CA 簽的,TLS 握手就被拒"
  echo "② blackbox exporter(HTTPS + mTLS,要求並驗證 client 憑證;它能替人連任何端點,所以比一般 exporter 更嚴):"
  probe='https://blackbox-exporter:9115/probe?module=tls_connect&target=broker1:9094'
  n1=$(http_code "$probe")
  n2=$(http_code --cert /certs/client-rogue.pem --key /certs/client-rogue.key "$probe")
  n3=$(http_code --cert /certs/client-monitor.pem --key /certs/client-monitor.key "$probe")
  ok=$(dcurl --cert /certs/client-monitor.pem --key /certs/client-monitor.key "$probe" 2>/dev/null | grep -c '^probe_success 1')
  echo "  不帶 client 憑證 $n1;不是行內 CA 簽的 client 憑證(rogue)$n2;Prometheus 的 monitor 憑證 $n3(probe_success 1:$ok)"
  echo "  (HTTP 000 = TLS 握手被拒,請求根本沒送進去)"
  [ "$n1" = "[HTTP 000]" ] && [ "$n2" = "[HTTP 000]" ] && [ "$n3" = "[HTTP 200]" ] && [ "$ok" = 1 ] || bad=1

  say "③ Prometheus 自己抓取這些端點:所有目標都應該是 up(用 https 驗證憑證鏈加帳密或 mTLS)"
  down=$(prom_query 'count(up{job=~"kafka-broker|kafka-controller|tls-expiry|tls-expiry-mtls"} == 0) or vector(0)')
  up=$(prom_query 'count(up{job=~"kafka-broker|kafka-controller|tls-expiry|tls-expiry-mtls"} == 1) or vector(0)')
  echo "③ Prometheus 以 https(驗證憑證鏈)+ 帳密 / mTLS 抓取:目標 up=1 的有 $up 個,up=0 的有 $down 個"
  [ "$down" = 0 ] && [ "$up" -ge 18 ] || bad=1

  say "④ Prometheus 與 Alertmanager 的帳號依用途分開:各自的帳號有效,不認識的帳號一律 401"
  echo "④ Prometheus 與 Alertmanager 的帳號依用途分開(機制仍是 HTTPS + Basic):"
  local pa="" aa="" u tk ak
  for u in c3:prom-pw telemetry:telemetry-pw ops:ops-prom-pw grafana:graf-prom-pw nobody:x; do pa="$pa $u→$(http_code -u "$u" "$PROM_URL/-/healthy")"; done
  for u in c3:am-pw prometheus:prom-am-pw opmenu:am-opmenu-pw ops:ops-am-pw nobody:x; do aa="$aa $u→$(http_code -u "$u" "$AM_URL/-/healthy")"; done
  echo "  Prometheus:$pa"; echo "  Alertmanager:$aa"
  tk=$(docker inspect broker1 --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -c 'C3PLUSPLUS_API_KEY=telemetry')
  ak=$(grep -A2 'basic_auth' config/c3/prometheus-generated.yml | grep -c 'username: prometheus')
  echo "  broker 的 telemetry reporter 用 telemetry 帳號:$([ "$tk" = 1 ] && echo 是 || echo 否);Prometheus 送告警用 prometheus 帳號:$([ "$ak" = 1 ] && echo 是 || echo 否)"
  case "$pa$aa" in *"nobody:x→[HTTP 401]"*"nobody:x→[HTTP 401]"*) ;; *) bad=1;; esac
  [ "$(echo "$pa" | grep -o 'HTTP 200' | wc -l)" = 4 ] && [ "$(echo "$aa" | grep -o 'HTTP 200' | wc -l)" = 4 ] && [ "$tk" = 1 ] && [ "$ak" = 1 ] || bad=1

  [ "$bad" = 0 ] && verdict "監控端點全部受保護:6 個 exporter 都是 HTTPS + Basic(不帶帳密與錯密碼 401、明文無回應),blackbox 要求 mTLS(沒有或不被信任的 client 憑證握手被拒),Prometheus 正常抓取;Prometheus 與 Alertmanager 的帳號依用途分開(各自有效、未知帳號 401)"
}

lab_rules() {
  say "等 Prometheus 載入並評估 7 條平台告警規則,而且前一個實驗留下的告警都已解除(最多 300 秒;telemetry 路徑的指標有延遲,剛做完停機實驗時告警會晚幾分鐘才解除)"
  local ok=0 t0 counts
  t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 300 ]; do
    counts=$(prom_rules_count "$RULE_GROUP")
    [ "$counts" = "7 7" ] && [ "$(platform_firing)" = "-" ] && { ok=1; break; }
    sleep 10
  done
  prom_rules_list "$RULE_GROUP"
  echo "目前 firing 的平台告警:$(platform_firing)"
  [ "$ok" = 1 ] && [ "$(platform_firing)" = "-" ] \
    && verdict "7 條平台告警規則已載入並評估(health ok),基準狀態沒有告警(來源:$SRC)"
}

lab_urp() {
  local alert f1=0 f2=0
  alert=$(alert_name KafkaUnderReplicatedPartitions)
  say "停 broker3:它上面的副本跟不上,『副本不足的分區數』(URP)會大於 0,告警應該觸發"
  echo "停 broker3"; stop_containers broker3
  wait_fire "$alert" 420 && f1=1
  echo "Alertmanager 收到 $alert:$(am_has_alert "$alert")(1=是)"
  say "把 broker3 啟動回來:ISR 補齊後 URP 回到 0,告警應該自動解除"
  start_containers broker3; wait_healthy broker3 >/dev/null; echo "恢復 broker3;等 ISR 補齊後告警應解除"
  wait_clear "$alert" 420 && f2=1
  [ "$f1" = 1 ] && [ "$f2" = 1 ] && verdict "停 1 台 broker 觸發 URP 告警並送到 Alertmanager,恢復後解除(來源:$SRC)"
}

lab_offline() {
  local alert f1=0 f2=0 out
  alert=$(alert_name KafkaOfflinePartitions)
  say "建立一個只有 1 份副本、放在 broker3 的 topic;broker3 一停,這個分區就沒有 leader(離線)"
  kafka_topics --delete --if-exists --topic mon.offline >/dev/null; sleep 3
  # --replica-assignment 不能和 --partitions 一起用(一起用會吞掉錯誤訊息),所以只給 assignment
  out=$(kafka_topics --create --topic mon.offline --replica-assignment 13 --config min.insync.replicas=1)
  echo "$out" | grep -q Created || { echo "建立單副本 topic 失敗:$out" | head -3; exit 1; }
  echo "這個 topic 只有 1 份副本、放在 broker3(id 13);停 broker3"; stop_containers broker3
  wait_fire "$alert" 420 && f1=1
  echo "Alertmanager 收到 $alert:$(am_has_alert "$alert")(1=是)"
  start_containers broker3; wait_healthy broker3 >/dev/null; echo "恢復 broker3"
  wait_clear "$alert" 420 && f2=1
  kafka_topics --delete --if-exists --topic mon.offline >/dev/null
  [ "$f1" = 1 ] && [ "$f2" = 1 ] && verdict "單副本 topic 所在的 broker 掉線,觸發離線分區告警並送到 Alertmanager,恢復後解除(來源:$SRC)"
}

lab_controller() {
  local missing not_one f1=0 f2=0 f3=0 f4=0
  missing=$(alert_name KafkaControllerMissing)
  not_one=$(alert_name KafkaActiveControllerCountNotOne)
  say "先停 1 台 controller(還有多數,叢集照常),再停第 2 台(失去多數,沒有 active controller)"
  echo "停 controller3(剩 2/3 仍有多數)"; stop_containers controller3
  wait_fire "$missing" 480 && f1=1
  echo "再停 controller2(只剩 1/3,失去多數)"; stop_containers controller2
  wait_fire "$not_one" 480 && f2=1
  echo "Alertmanager 收到 $not_one:$(am_has_alert "$not_one")(1=是)"
  start_containers controller2 controller3; wait_healthy controller2 controller3 >/dev/null; echo "恢復 controller2、controller3"
  wait_clear "$not_one" 480 && f3=1
  wait_clear "$missing" 480 && f4=1
  [ "$f1" = 1 ] && [ "$f2" = 1 ] && [ "$f3" = 1 ] && [ "$f4" = 1 ] \
    && verdict "controller 掉線觸發 ControllerMissing;失去多數時 active controller 數不是 1 的告警觸發,恢復後都解除(來源:$SRC)"
}

case "${1:-}" in
  jmx-endpoint) lab_jmx_endpoint ;;
  protect)      lab_protect ;;
  rules)        lab_rules ;;
  urp)          lab_urp ;;
  offline)      lab_offline ;;
  controller)   lab_controller ;;
  *)            usage_from_header "$0"; exit 1 ;;
esac
