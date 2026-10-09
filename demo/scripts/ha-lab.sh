#!/usr/bin/env bash
# 第 21 章(HA 叢集)的實驗腳本。需要先 scripts/ha.sh on(3 controller + 3 broker,副本 3、min.insync.replicas 2)。
#   scripts/ha-lab.sh quorum         KRaft quorum 狀態:3 個 voter、1 個 leader
#   scripts/ha-lab.sh topic          建 RF=3、min.isr=2 的 topic,寫入 300 筆並比對
#   scripts/ha-lab.sh broker-down    停 1 台 broker:寫入仍成功,URP>0,ISR=2;恢復後 ISR 補齊
#   scripts/ha-lab.sh brokers-down   停 2 台 broker(剩 1):acks=all 寫不進去;acks=1 寫得進去但讀不到;恢復後才出現
#   scripts/ha-lab.sh ctrl-down      停 1 台 controller:叢集仍可管理與寫入
#   scripts/ha-lab.sh ctrls-down     停 2 台 controller(失去多數):不能建 topic、不能 describe;既有 topic 仍可讀寫
#   scripts/ha-lab.sh rolling        背景持續寫入時,依序重啟 3 台 broker、再 3 台 controller(active 最後),比對筆數
set -uo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
grep -q '^COMPOSE_FILE=.*docker-compose.ha.yml' .env 2>/dev/null || { echo "目前不是 HA 模式:先執行 scripts/ha.sh on"; exit 1; }
BS=broker1:9094,broker2:9094,broker3:9094
TOK=/clients/token-bootstrap.properties
PERF_OUT=/tmp/ha-lab-perf.out
KT() { timeout "${KT_TIMEOUT:-60}" ./scripts/k.sh kafka-topics --bootstrap-server $BS --command-config $TOK "$@" 2>&1 | grep -v -E "^WARNING|SLF4J"; }
KQ() { ./scripts/k.sh kafka-metadata-quorum --bootstrap-server broker1:9092,broker2:9092,broker3:9092 --command-config /clients/internal.properties "$@" 2>&1 | grep -v -E "^WARNING|SLF4J"; }
total() { ./scripts/k.sh kafka-get-offsets --bootstrap-server $BS --command-config $TOK --topic "$1" 2>/dev/null | awk -F: '{s+=$3} END {print s+0}'; }
perf() { # perf <topic> <筆數> <acks> [每秒筆數]:印 sent 數;其餘輸出存 $PERF_OUT(固定檔,子 shell 也讀得到)
  :
  ./scripts/k.sh kafka-producer-perf-test --topic "$1" --num-records "$2" --throughput "${4:--1}" --record-size 100 --command-config $TOK \
    --producer-props bootstrap.servers=$BS acks="$3" delivery.timeout.ms="${DELIVERY_MS:-20000}" request.timeout.ms=8000 > "$PERF_OUT" 2>&1
  grep -oE '^[0-9]+ records sent' "$PERF_OUT" | tail -1 | awk '{print $1}'
}
healthy() { # healthy <容器...>:等到全部 healthy(最多 150 秒)
  local c i; for c in "$@"; do for i in $(seq 1 30); do docker ps --format '{{.Names}} {{.Status}}' | grep -q "^$c .*(healthy)" && break; sleep 5; done; done
}
isr_full() { # 等所有分區 ISR 補齊、沒有離線(最多 150 秒)
  local i; for i in $(seq 1 30); do [ -z "$(KT --describe --under-replicated-partitions)" ] && [ -z "$(KT --describe --unavailable-partitions)" ] && return 0; sleep 5; done; return 1
}
fresh() { for t in "$@"; do KT --delete --if-exists --topic "$t" >/dev/null; done; sleep 3; }
isrline() { KT --describe --topic "$1" | grep -E "Partition:" | sed -E 's/\s+/ /g; s/TopicId: [^ ]* //' | cut -c1-110; }

case "${1:-}" in
quorum)
  out=$(KQ describe --status); echo "$out" | grep -E "LeaderId|CurrentVoters|CurrentObservers" | cut -c1-200
  v=$(echo "$out" | grep CurrentVoters | grep -o '"id"' | wc -l); o=$(echo "$out" | grep CurrentObservers | grep -o '"id"' | wc -l)
  echo "kraft.version / metadata.version:"; ./scripts/k.sh kafka-features --bootstrap-server broker1:9092 --command-config /clients/internal.properties describe 2>&1 | grep -E "kraft.version|metadata.version" | sed -E 's/\s+/ /g' | cut -c1-140
  [ "$v" = 3 ] && echo "判定:3 個 controller 都是 voter(quorum 容得下 1 台故障),$o 台 broker 是 observer"
  ;;
topic)
  fresh ha.test; KT --create --topic ha.test --partitions 3 --replication-factor 3 --config min.insync.replicas=2 | grep -E "Created|rror"
  isrline ha.test
  s=$(perf ha.test 300 all); echo "寫入(acks=all):送出 ${s:-0} 筆;topic 實際 $(total ha.test) 筆"
  [ "${s:-0}" = 300 ] && [ "$(total ha.test)" = 300 ] && echo "判定:副本 3、min.isr 2 的 topic 寫入與讀回正常(300 = 300)"
  ;;
broker-down)
  b0=$(total ha.test); echo "停 broker3"; docker stop broker3 >/dev/null; sleep 20
  isrline ha.test; urp=$(KT --describe --under-replicated-partitions | grep -c Partition:); echo "URP(副本不足的分區)數:$urp"
  s=$(perf ha.test 200 all); echo "只剩 2 台,acks=all 寫入:送出 ${s:-0} 筆"
  docker start broker3 >/dev/null; healthy broker3; isr_full && echo "恢復 broker3:ISR 補齊、URP=0"
  [ "${s:-0}" = 200 ] && [ "$urp" -gt 0 ] && echo "判定:停 1 台 broker 時寫入不中斷(ISR 剩 2 ≥ min.isr 2),URP 大於 0 是告警訊號,恢復後補齊"
  ;;
brokers-down)
  b0=$(total ha.test); echo "目前 topic 筆數:$b0"; echo "停 broker2、broker3(只剩 broker1)"; docker stop broker2 broker3 >/dev/null; sleep 25
  isrline ha.test
  DELIVERY_MS=15000 s_all=$(perf ha.test 50 all); echo "acks=all 寫入 50 筆:成功 ${s_all:-0} 筆(ISR 1 < min.isr 2,被拒絕,producer 重試到逾時)"
  grep -oE "NotEnoughReplicas|TimeoutException: Expiring [0-9]+ record" "$PERF_OUT" | sort | uniq -c | head -2 | sed 's/^/   /'
  s_one=$(perf ha.test 50 1); b1=$(total ha.test)
  echo "acks=1 寫入 50 筆:producer 回報成功 ${s_one:-0} 筆;但 consumer 看得到的筆數仍是 $b1(原本 $b0)——高水位沒有前進,這 50 筆讀不到"
  echo -n "用 consumer group 讀取:"; ./scripts/k.sh kafka-console-consumer --bootstrap-server broker1:9094 --command-config $TOK --topic ha.test --group g-ha-down --from-beginning --timeout-ms 15000 2>&1 | grep -c -E "TimeoutException" | sed 's/^1$/ 逾時(內部 topic __consumer_offsets 的 min.isr 也不足,加入不了群組)/; s/^0$/ 有回應/'
  docker start broker2 broker3 >/dev/null; healthy broker2 broker3; isr_full; sleep 10; b2=$(total ha.test); echo "恢復後 topic 筆數:$b2"
  [ "${s_all:-0}" = 0 ] && [ "${s_one:-0}" = 50 ] && [ "$b1" = "$b0" ] && [ "$b2" = $((b0 + 50)) ] && echo "判定:ISR 低於 min.isr 時,acks=all 被擋,acks=1 看似成功卻讀不到(恢復後才出現)——這就是要用 acks=all 加 min.isr 的理由"
  ;;
ctrl-down)
  fresh ha.c1; echo "停 controller3(剩 2/3,仍有多數)"; docker stop controller3 >/dev/null; sleep 15
  echo -n "建立 topic:"; KT --create --topic ha.c1 --partitions 1 --replication-factor 3 | grep -E "Created|rror" || echo "失敗"
  s=$(perf ha.test 100 all); echo "寫入既有 topic:送出 ${s:-0} 筆"
  KQ describe --status | grep -E "LeaderId"
  docker start controller3 >/dev/null; healthy controller3
  [ "${s:-0}" = 100 ] && KT --describe --topic ha.c1 | grep -q "Partition:" && echo "判定:停 1 台 controller 仍有多數,建立 topic 與寫入都正常"
  ;;
ctrls-down)
  fresh ha.c2; echo "停 controller2、controller3(剩 1/3,失去多數)"; docker stop controller2 controller3 >/dev/null; sleep 25
  echo -n "建立 topic(等 25 秒):"; KT_TIMEOUT=25 KT --create --topic ha.c2 --partitions 1 --replication-factor 3 | grep -E "Created|rror" || echo "沒有回應(逾時)"
  echo -n "describe topic(等 25 秒):"; KT_TIMEOUT=25 KT --describe --topic ha.test | grep -c "Partition:" | sed 's/^0$/沒有回應(逾時)/'
  s=$(perf ha.test 100 all); echo "寫入既有 topic(acks=all):送出 ${s:-0} 筆"
  c=0; for p in 0 1 2; do n=$(./scripts/k.sh kafka-console-consumer --bootstrap-server $BS --command-config $TOK --topic ha.test --partition $p --offset earliest --timeout-ms 12000 2>/dev/null | wc -l); c=$((c + n)); done; echo "讀取既有 topic 全部分區:$c 筆"
  docker start controller2 controller3 >/dev/null; healthy controller2 controller3; sleep 15
  echo -n "恢復後建立 topic:"; KT --create --topic ha.c2 --partitions 1 --replication-factor 3 | grep -E "Created|rror" || echo "失敗"
  [ "${s:-0}" = 100 ] && [ "$c" -gt 0 ] && echo "判定:失去 controller 多數時,資料面(既有 topic 的讀寫)繼續運作,但控制面(建 topic、describe、換 leader)停擺;恢復多數後才恢復"
  ;;
rolling)
  fresh ha.roll; KT --create --topic ha.roll --partitions 6 --replication-factor 3 --config min.insync.replicas=2 | grep -E "Created|rror"
  N="${2:-2400}"; echo "背景 producer:$N 筆、每秒 6 筆、acks=all、冪等;同時依序重啟 broker1 → broker2 → broker3 → 非 active controller → active controller"
  :
  ./scripts/k.sh kafka-producer-perf-test --topic ha.roll --num-records "$N" --throughput 6 --record-size 100 --command-config $TOK \
    --producer-props bootstrap.servers=$BS acks=all enable.idempotence=true delivery.timeout.ms=120000 request.timeout.ms=30000 > "$PERF_OUT" 2>&1 &
  PP=$!; sleep 20
  leader=$(KQ describe --status | awk '/LeaderId/ {print $2}'); active="controller$leader"
  order="broker1 broker2 broker3"; for c in controller1 controller2 controller3; do [ "$c" != "$active" ] && order="$order $c"; done; order="$order $active"
  echo "active controller = $active(最後重啟)"
  for c in $order; do
    docker restart "$c" >/dev/null; healthy "$c"
    case "$c" in broker*) isr_full && echo "  重啟 $c → 健康,URP=0" || echo "  重啟 $c → 健康,但 URP 未回 0";; *) sleep 10; echo "  重啟 $c → 健康";; esac
  done
  wait $PP
  sent=$(grep -oE '^[0-9]+ records sent' "$PERF_OUT" | tail -1 | awk '{print $1}'); have=$(total ha.roll)
  fails=$(grep -cE "ERROR|Expiring|expired|Failed to send" "$PERF_OUT" || true)
  echo "producer 回報送出 ${sent:-?} 筆;topic 實際 $have 筆;送出失敗 $fails 筆"
  [ "${sent:-}" = "$N" ] && [ "$have" = "$N" ] && [ "$fails" = 0 ] && echo "判定:滾動重啟 3 台 broker 與 3 台 controller 期間,producer 零失敗、零遺失($N = $have)" || echo "判定:不符合(送出 ${sent:-?}、topic $have、失敗 $fails)"
  KQ describe --status | grep -E "LeaderId"
  ;;
*) sed -n 2,10p "$0"; exit 1;;
esac
