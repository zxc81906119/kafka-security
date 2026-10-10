#!/usr/bin/env bash
# 第 22 章:官方列的平台告警真的被觸發。需要 HA 模式(scripts/ha.sh on)且 prometheus、alertmanager 已啟動(docker compose --profile c3 up -d prometheus alertmanager)。
#   scripts/monitor-lab.sh jmx-endpoint  確認每個 broker 與 controller 都開了 JMX exporter(7778 埠),關鍵指標都在;顯示 agent 的 SHA-1(與 Maven Central 相符)
#   scripts/monitor-lab.sh protect       監控端點的保護:JMX exporter(HTTPS + Basic 帳密)、blackbox(HTTPS + mTLS)、Prometheus 驗證憑證鏈抓取
#   scripts/monitor-lab.sh rules       7 條平台告警規則已載入並評估,基準狀態沒有告警
#   scripts/monitor-lab.sh urp         停 1 台 broker → KafkaUnderReplicatedPartitions 觸發、送到 Alertmanager;恢復後解除
#   scripts/monitor-lab.sh offline     RF=1 的 topic 所在 broker 掉線 → KafkaOfflinePartitions 觸發;恢復後解除
#   scripts/monitor-lab.sh controller  停 1 台 controller → KafkaControllerMissing;再停 1 台(失去多數)→ KafkaActiveControllerCountNotOne;恢復後解除
# 指標來源:SRC=telemetry(預設,Confluent telemetry → Prometheus)或 SRC=jmx(JMX exporter → Prometheus,銀行自有監控的建議路徑);兩組規則同一組告警、名稱不同(JMX 版加 Jmx)。
# 時間:telemetry 每 60 秒送一次、規則每 60 秒評估一次,每個實驗約 4 到 9 分鐘。所有等待都有上限。
set -uo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
grep -q '^COMPOSE_FILE=.*docker-compose.ha.yml' .env 2>/dev/null || { echo "目前不是 HA 模式:先執行 scripts/ha.sh on"; exit 1; }
docker ps --format '{{.Names}}' | grep -q '^prometheus$' || { echo "prometheus 沒有在跑:docker compose --profile c3 up -d prometheus alertmanager"; exit 1; }
DC=./scripts/dcurl.sh
SRC="${SRC:-telemetry}"
GROUP=$([ "$SRC" = jmx ] && echo kafka-platform-jmx || echo kafka-platform)
A() { [ "$SRC" = jmx ] && echo "KafkaJmx${1#Kafka}" || echo "$1"; }   # 告警名稱:JMX 版加 Jmx
TOK=/clients/token-bootstrap.properties
BS=broker1:9094,broker2:9094,broker3:9094
KT() { timeout 60 ./scripts/k.sh kafka-topics --bootstrap-server $BS --command-config $TOK "$@" 2>&1 | grep -v -E "^WARNING|SLF4J"; }
NAMES="KafkaUnderReplicatedPartitions KafkaUnderMinIsrPartitions KafkaOfflinePartitions KafkaActiveControllerCountNotOne KafkaControllerMissing KafkaUncleanLeaderElection KafkaBrokerFenced"
firing() { # 目前 firing 的平台告警名稱(逗號分隔;沒有印 -)
  local out; out=$(bash $DC -u ops:ops-prom-pw https://prometheus:9090/api/v1/alerts 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const i=s.indexOf("{");const j=JSON.parse(s.slice(i,s.lastIndexOf("}")+1));console.log(j.data.alerts.filter(a=>a.state==="firing"&&/^Kafka/.test(a.labels.alertname)&&a.labels.alertname!=="KafkaAuthFailuresBurst").map(a=>a.labels.alertname).sort().join(",")||"-")}catch(e){console.log("?")}})')
  echo "$out"
}
am_has() { # Alertmanager 是否收到某告警(1/0)
  bash $DC -u ops:ops-am-pw https://alertmanager:9093/api/v2/alerts 2>/dev/null | grep -c "\"alertname\":\"$1\"" | sed 's/^0$/0/; s/^[1-9].*$/1/'
}
wait_fire() { # wait_fire <告警名> <最多秒數>:等到該告警 firing;印耗時
  local n="$1" max="$2" t0=$(date +%s) f
  while [ $(( $(date +%s) - t0 )) -lt "$max" ]; do f=$(firing); case ",$f," in *",$n,"*) echo "   $(( $(date +%s) - t0 )) 秒後 $n 觸發(目前 firing:$f)"; return 0;; esac; sleep 10; done
  echo "   等了 $max 秒仍未觸發 $n(目前 firing:$(firing))"; return 1
}
wait_clear() { # wait_clear <告警名> <最多秒數>
  local n="$1" max="$2" t0=$(date +%s) f
  while [ $(( $(date +%s) - t0 )) -lt "$max" ]; do f=$(firing); case ",$f," in *",$n,"*) sleep 10;; *) echo "   $(( $(date +%s) - t0 )) 秒後 $n 解除"; return 0;; esac; done
  echo "   等了 $max 秒仍未解除 $n"; return 1
}
healthy() { local c i; for c in "$@"; do for i in $(seq 1 30); do docker ps --format '{{.Names}} {{.Status}}' | grep -q "^$c .*(healthy)" && break; sleep 5; done; done; }

case "${1:-}" in
jmx-endpoint)
  PW=$(cat config/c3/jmx_exporter.pw)
  sha=$(sha1sum config/jmx/jmx_prometheus_javaagent.jar | awk '{print $1}'); ver=$(cat config/jmx/jmx_prometheus_javaagent.jar.version 2>/dev/null)
  echo "agent:jmx_prometheus_javaagent $ver,SHA-1 $sha(下載時已與 Maven Central 的 .sha1 比對)"
  echo "JVM 參數(broker1):$(docker inspect broker1 --format '{{range .Config.Env}}{{println .}}{{end}}' | grep '^KAFKA_OPTS=' | cut -c1-150)"
  miss=0
  for n in broker1 broker2 broker3 controller1 controller2 controller3; do
    c=$(bash $DC -u Prometheus:$PW https://$n:7778/metrics 2>/dev/null | grep -c '^kafka_'); echo "  $n:7778(HTTPS + Basic)→ $c 個 kafka_ 指標"; [ "$c" -gt 50 ] || miss=1
  done
  echo "broker1 的關鍵指標:"; bash $DC -u Prometheus:$PW https://broker1:7778/metrics 2>/dev/null | grep -E '^kafka_server_replicamanager_(underreplicatedpartitions|underminisrpartitioncount) ' | sed 's/^/  /'
  echo "controller1 的關鍵指標:"; bash $DC -u Prometheus:$PW https://controller1:7778/metrics 2>/dev/null | grep -E '^kafka_controller_kafkacontroller_(offlinepartitionscount|activecontrollercount) ' | sed 's/^/  /'
  [ "$miss" = 0 ] && echo "判定:6 個節點都開了 JMX exporter(7778 埠,HTTPS + Basic 帳密),URP、離線分區、active controller 等關鍵指標都在"
  ;;
protect)
  PW=$(cat config/c3/jmx_exporter.pw)
  echo "① 6 個節點的 JMX exporter(HTTPS + Basic 帳密):"
  bad=0
  for n in broker1 broker2 broker3 controller1 controller2 controller3; do
    a=$(bash $DC https://$n:7778/metrics 2>/dev/null | tail -1); b=$(bash $DC -u Prometheus:wrong-pw https://$n:7778/metrics 2>/dev/null | tail -1); c=$(bash $DC -u Prometheus:$PW https://$n:7778/metrics 2>/dev/null | tail -1); h=$(bash $DC http://$n:7778/metrics 2>/dev/null | tail -1)
    echo "  $n:不帶帳密 $a;錯密碼 $b;正確 $c;明文 http $h"
    [ "$a" = "[HTTP 401]" ] && [ "$b" = "[HTTP 401]" ] && [ "$c" = "[HTTP 200]" ] && [ "$h" = "[HTTP 000]" ] || bad=1
  done
  echo "② blackbox exporter(HTTPS + mTLS,要求並驗證 client 憑證;它能替人連任何端點,所以比一般 exporter 更嚴):"
  P='https://blackbox-exporter:9115/probe?module=tls_connect&target=broker1:9094'
  n1=$(bash $DC "$P" 2>/dev/null | tail -1)
  n2=$(bash $DC --cert /certs/client-rogue.pem --key /certs/client-rogue.key "$P" 2>/dev/null | tail -1)
  n3=$(bash $DC --cert /certs/client-monitor.pem --key /certs/client-monitor.key "$P" 2>/dev/null | tail -1)
  ok=$(bash $DC --cert /certs/client-monitor.pem --key /certs/client-monitor.key "$P" 2>/dev/null | grep -c '^probe_success 1')
  echo "  不帶 client 憑證 $n1;不是行內 CA 簽的 client 憑證(rogue)$n2;Prometheus 的 monitor 憑證 $n3(probe_success 1:$ok)"
  echo "  (HTTP 000 = TLS 握手被拒,請求根本沒送進去)"
  [ "$n1" = "[HTTP 000]" ] && [ "$n2" = "[HTTP 000]" ] && [ "$n3" = "[HTTP 200]" ] && [ "$ok" = 1 ] || bad=1
  d=$(bash $DC -u ops:ops-prom-pw -G --data-urlencode 'query=count(up{job=~"kafka-jmx|tls-expiry|tls-expiry-mtls"} == 0)' https://prometheus:9090/api/v1/query 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const i=s.indexOf("{");const j=JSON.parse(s.slice(i,s.lastIndexOf("}")+1));console.log(j.data.result.length?j.data.result[0].value[1]:"0")}catch(e){console.log("?")}})')
  t=$(bash $DC -u ops:ops-prom-pw -G --data-urlencode 'query=count(up{job=~"kafka-jmx|tls-expiry|tls-expiry-mtls"} == 1)' https://prometheus:9090/api/v1/query 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const i=s.indexOf("{");const j=JSON.parse(s.slice(i,s.lastIndexOf("}")+1));console.log(j.data.result.length?j.data.result[0].value[1]:"0")}catch(e){console.log("?")}})')
  echo "③ Prometheus 以 https(驗證憑證鏈)+ 帳密 / mTLS 抓取:目標 up=1 的有 $t 個,up=0 的有 $d 個"
  [ "$d" = 0 ] && [ "$t" -ge 18 ] || bad=1
  echo "④ Prometheus 與 Alertmanager 的帳號依用途分開(機制仍是 HTTPS + Basic):"
  pa=""; for u in c3:prom-pw telemetry:telemetry-pw ops:ops-prom-pw nobody:x; do pa="$pa $u→$(bash $DC -u $u https://prometheus:9090/-/healthy 2>/dev/null | tail -1)"; done
  aa=""; for u in c3:am-pw prometheus:prom-am-pw opmenu:am-opmenu-pw ops:ops-am-pw nobody:x; do aa="$aa $u→$(bash $DC -u $u https://alertmanager:9093/-/healthy 2>/dev/null | tail -1)"; done
  echo "  Prometheus:$pa"; echo "  Alertmanager:$aa"
  tk=$(docker inspect broker1 --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -c 'C3PLUSPLUS_API_KEY=telemetry'); ak=$(grep -A2 'basic_auth' config/c3/prometheus-generated.yml | grep -c 'username: prometheus')
  echo "  broker 的 telemetry reporter 用 telemetry 帳號:$([ "$tk" = 1 ] && echo 是 || echo 否);Prometheus 送告警用 prometheus 帳號:$([ "$ak" = 1 ] && echo 是 || echo 否)"
  case "$pa$aa" in *"nobody:x→[HTTP 401]"*"nobody:x→[HTTP 401]"*) ;; *) bad=1;; esac
  [ "$(echo "$pa" | grep -o 'HTTP 200' | wc -l)" = 3 ] && [ "$(echo "$aa" | grep -o 'HTTP 200' | wc -l)" = 4 ] && [ "$tk" = 1 ] && [ "$ak" = 1 ] || bad=1
  [ "$bad" = 0 ] && echo "判定:監控端點全部受保護:6 個 exporter 都是 HTTPS + Basic(不帶帳密與錯密碼 401、明文無回應),blackbox 要求 mTLS(沒有或不被信任的 client 憑證握手被拒),Prometheus 正常抓取;Prometheus 與 Alertmanager 的帳號依用途分開(各自有效、未知帳號 401)"
  ;;
rules)
  t0=$(date +%s); ok=0
  while [ $(( $(date +%s) - t0 )) -lt 240 ]; do
    out=$(bash $DC -u ops:ops-prom-pw https://prometheus:9090/api/v1/rules 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const i=s.indexOf("{");const j=JSON.parse(s.slice(i,s.lastIndexOf("}")+1));const g=j.data.groups.find(x=>x.name==="'$GROUP'");if(!g){console.log("0 0");return}console.log(g.rules.length+" "+g.rules.filter(r=>r.health==="ok").length)})')
    [ "$out" = "7 7" ] && { ok=1; break; }; sleep 10
  done
  bash $DC -u ops:ops-prom-pw https://prometheus:9090/api/v1/rules 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const i=s.indexOf("{");const j=JSON.parse(s.slice(i,s.lastIndexOf("}")+1));const g=j.data.groups.find(x=>x.name==="'$GROUP'");for(const r of g.rules)console.log("  "+r.name.padEnd(36)+r.health.padEnd(6)+(r.state||""))})'
  echo "目前 firing 的平台告警:$(firing)"
  [ "$ok" = 1 ] && [ "$(firing)" = "-" ] && echo "判定:7 條平台告警規則已載入並評估(health ok),基準狀態沒有告警(來源:$SRC)"
  ;;
urp)
  echo "停 broker3"; docker stop broker3 >/dev/null
  wait_fire "$(A KafkaUnderReplicatedPartitions)" 420 && f1=1
  echo "Alertmanager 收到 $(A KafkaUnderReplicatedPartitions):$(am_has "$(A KafkaUnderReplicatedPartitions)")(1=是)"
  docker start broker3 >/dev/null; healthy broker3; echo "恢復 broker3;等 ISR 補齊後告警應解除"
  wait_clear "$(A KafkaUnderReplicatedPartitions)" 420 && f2=1
  [ "${f1:-0}" = 1 ] && [ "${f2:-0}" = 1 ] && echo "判定:停 1 台 broker 觸發 URP 告警並送到 Alertmanager,恢復後解除(來源:$SRC)"
  ;;
offline)
  KT --delete --if-exists --topic mon.offline >/dev/null; sleep 3
  out=$(KT --create --topic mon.offline --replica-assignment 13 --config min.insync.replicas=1); echo "$out" | grep -q Created || { echo "建立單副本 topic 失敗:$out" | head -3; exit 1; }   # --replica-assignment 不能和 --partitions 一起用
  echo "這個 topic 只有 1 份副本、放在 broker3(id 13);停 broker3"; docker stop broker3 >/dev/null
  wait_fire "$(A KafkaOfflinePartitions)" 420 && f1=1
  echo "Alertmanager 收到 $(A KafkaOfflinePartitions):$(am_has "$(A KafkaOfflinePartitions)")(1=是)"
  docker start broker3 >/dev/null; healthy broker3; echo "恢復 broker3"
  wait_clear "$(A KafkaOfflinePartitions)" 420 && f2=1
  KT --delete --if-exists --topic mon.offline >/dev/null
  [ "${f1:-0}" = 1 ] && [ "${f2:-0}" = 1 ] && echo "判定:單副本 topic 所在的 broker 掉線,觸發離線分區告警並送到 Alertmanager,恢復後解除(來源:$SRC)"
  ;;
controller)
  echo "停 controller3(剩 2/3 仍有多數)"; docker stop controller3 >/dev/null
  wait_fire "$(A KafkaControllerMissing)" 480 && f1=1
  echo "再停 controller2(只剩 1/3,失去多數)"; docker stop controller2 >/dev/null
  wait_fire "$(A KafkaActiveControllerCountNotOne)" 480 && f2=1
  echo "Alertmanager 收到 $(A KafkaActiveControllerCountNotOne):$(am_has "$(A KafkaActiveControllerCountNotOne)")(1=是)"
  docker start controller2 controller3 >/dev/null; healthy controller2 controller3; echo "恢復 controller2、controller3"
  wait_clear "$(A KafkaActiveControllerCountNotOne)" 480 && f3=1
  wait_clear "$(A KafkaControllerMissing)" 480 && f4=1
  [ "${f1:-0}" = 1 ] && [ "${f2:-0}" = 1 ] && [ "${f3:-0}" = 1 ] && [ "${f4:-0}" = 1 ] && echo "判定:controller 掉線觸發 ControllerMissing;失去多數時 active controller 數不是 1 的告警觸發,恢復後都解除(來源:$SRC)"
  ;;
*) sed -n 2,7p "$0"; exit 1;;
esac
