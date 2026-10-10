#!/usr/bin/env bash
# 第 22 章:官方列的平台告警真的被觸發。需要 HA 模式(scripts/ha.sh on)且 prometheus、alertmanager 已啟動(docker compose --profile c3 up -d prometheus alertmanager)。
#   scripts/monitor-lab.sh jmx-endpoint  確認每個 broker 與 controller 都開了 JMX exporter(7778 埠),關鍵指標都在;顯示 agent 的 SHA-1(與 Maven Central 相符)
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
  local out; out=$(bash $DC -u c3:prom-pw https://prometheus:9090/api/v1/alerts 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const i=s.indexOf("{");const j=JSON.parse(s.slice(i,s.lastIndexOf("}")+1));console.log(j.data.alerts.filter(a=>a.state==="firing"&&/^Kafka/.test(a.labels.alertname)&&a.labels.alertname!=="KafkaAuthFailuresBurst").map(a=>a.labels.alertname).sort().join(",")||"-")}catch(e){console.log("?")}})')
  echo "$out"
}
am_has() { # Alertmanager 是否收到某告警(1/0)
  bash $DC -u c3:am-pw https://alertmanager:9093/api/v2/alerts 2>/dev/null | grep -c "\"alertname\":\"$1\"" | sed 's/^0$/0/; s/^[1-9].*$/1/'
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
  sha=$(sha1sum config/jmx/jmx_prometheus_javaagent.jar | awk '{print $1}'); ver=$(cat config/jmx/jmx_prometheus_javaagent.jar.version 2>/dev/null)
  echo "agent:jmx_prometheus_javaagent $ver,SHA-1 $sha(下載時已與 Maven Central 的 .sha1 比對)"
  echo "JVM 參數(broker1):$(docker inspect broker1 --format '{{range .Config.Env}}{{println .}}{{end}}' | grep '^KAFKA_OPTS=' | cut -c1-140)"
  miss=0
  for n in broker1 broker2 broker3 controller1 controller2 controller3; do
    out=$(docker exec $n sh -c '(exec 3<>/dev/tcp/localhost/7778 && printf "GET /metrics HTTP/1.0\r\n\r\n" >&3 && cat <&3) 2>/dev/null')
    c=$(echo "$out" | grep -c '^kafka_'); echo "  $n:7778/metrics → $c 個 kafka_ 指標"; [ "$c" -gt 5 ] || miss=1
  done
  echo "broker1 的關鍵指標:"; docker exec broker1 sh -c '(exec 3<>/dev/tcp/localhost/7778 && printf "GET /metrics HTTP/1.0\r\n\r\n" >&3 && cat <&3) 2>/dev/null' | grep -E '^kafka_server_replicamanager_(underreplicatedpartitions|underminisrpartitioncount) ' | sed 's/^/  /'
  echo "controller1 的關鍵指標:"; docker exec controller1 sh -c '(exec 3<>/dev/tcp/localhost/7778 && printf "GET /metrics HTTP/1.0\r\n\r\n" >&3 && cat <&3) 2>/dev/null' | grep -E '^kafka_controller_kafkacontroller_(offlinepartitionscount|activecontrollercount) ' | sed 's/^/  /'
  [ "$miss" = 0 ] && echo "判定:6 個節點都開了 JMX exporter(7778 埠),URP、離線分區、active controller 等關鍵指標都在"
  ;;
rules)
  t0=$(date +%s); ok=0
  while [ $(( $(date +%s) - t0 )) -lt 240 ]; do
    out=$(bash $DC -u c3:prom-pw https://prometheus:9090/api/v1/rules 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const i=s.indexOf("{");const j=JSON.parse(s.slice(i,s.lastIndexOf("}")+1));const g=j.data.groups.find(x=>x.name==="'$GROUP'");if(!g){console.log("0 0");return}console.log(g.rules.length+" "+g.rules.filter(r=>r.health==="ok").length)})')
    [ "$out" = "7 7" ] && { ok=1; break; }; sleep 10
  done
  bash $DC -u c3:prom-pw https://prometheus:9090/api/v1/rules 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const i=s.indexOf("{");const j=JSON.parse(s.slice(i,s.lastIndexOf("}")+1));const g=j.data.groups.find(x=>x.name==="'$GROUP'");for(const r of g.rules)console.log("  "+r.name.padEnd(36)+r.health.padEnd(6)+(r.state||""))})'
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
