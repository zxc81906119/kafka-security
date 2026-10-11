#!/usr/bin/env bash
# ============================================================================
# ha-lab.sh — 第 21 章(HA 叢集)的實驗:停掉 broker 或 controller,看叢集怎麼反應
# ----------------------------------------------------------------------------
# 白話:銀行要的是「壞掉一兩台,服務照常」。這支腳本實際把 broker、controller 一台一台停掉,
#   觀察寫入、讀取、建 topic 哪些還能做、哪些會卡住,最後再練習不中斷服務的滾動重啟。
#   每個實驗結束都會把停掉的容器啟動回來。
# 前置條件:叢集已啟動(scripts/ha.sh on:3 controller + 4 broker,副本 3、min.insync.replicas 2)
# 用法:
#   scripts/ha-lab.sh quorum         KRaft quorum 狀態:3 個 voter、1 個 leader
#   scripts/ha-lab.sh topic          建 RF=3、min.isr=2 的 topic,寫入 300 筆並比對
#   scripts/ha-lab.sh broker-down    停 1 台 broker:寫入仍成功,URP>0,ISR=2;恢復後 ISR 補齊
#   scripts/ha-lab.sh brokers-down   停 2 台 broker(剩 1):acks=all 寫不進去;acks=1 寫得進去但讀不到;恢復後才出現
#   scripts/ha-lab.sh ctrl-down      停 1 台 controller:叢集仍可管理與寫入
#   scripts/ha-lab.sh ctrls-down     停 2 台 controller(失去多數):不能建 topic、不能 describe;既有 topic 仍可讀寫
#   scripts/ha-lab.sh rolling [筆數]  背景持續寫入時,依序重啟 3 台 broker、再 3 台 controller(active 最後),比對筆數
# 會改動什麼:建立 topic ha.test、ha.c1、ha.c2、ha.roll(每次執行前會先刪掉重建);
#   暫時停止 broker 或 controller 容器,結束前一律啟動回來。
# 怎麼判斷成功:最後一行印「判定:…」;條件不成立就不印這一行(rolling 會印「判定:不符合」)。
# 常見失敗:
#   「叢集沒有在跑」→ 先 scripts/up.sh
#   寫入筆數是 0 → broker 還沒完全恢復,等 ISR 補齊(isr_full)再重跑
# ============================================================================
set -uo pipefail
PERF_OUT=/tmp/ha-lab-perf.out        # 壓測輸出固定存這個檔(produce_test 會讀 $PERF_OUT)
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/kafka.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR" || exit 1
need_ha_mode

# ---------- 小工具(這支腳本專用) ----------

# 印出 topic 每個分區的 Leader / Replicas / Isr(去掉多餘空白,方便肉眼看)。
show_partitions() {
  kafka_topics --describe --topic "$1" | grep -E "Partition:" | sed -E 's/\s+/ /g; s/TopicId: [^ ]* //' | cut -c1-110
}

# 等所有分區的 ISR 補齊(沒有「副本不足」也沒有「離線」),最多 150 秒。
isr_is_full() {
  [ -z "$(kafka_topics --describe --under-replicated-partitions)" ] \
    && [ -z "$(kafka_topics --describe --unavailable-partitions)" ]
}
wait_isr_full() { wait_until "ISR 補齊" 150 isr_is_full; }

# 把舊的實驗 topic 刪掉,重新開始(不存在也不算錯)。
reset_topics() {
  local t
  for t in "$@"; do kafka_topics --delete --if-exists --topic "$t" >/dev/null; done
  sleep 3
}

# 建立 topic 並只印結果行(Created 或錯誤);失敗時印「失敗」。
create_topic() {
  kafka_topics --create "$@" | grep -E "Created|rror" || echo "失敗"
}

# 確保實驗用的 ha.test 存在(不存在就建立)。為什麼:子命令可能單獨執行,topic 還沒建;沒有這個 topic,producer 會一直收到
# UNKNOWN_TOPIC_OR_PARTITION 重試,而且是在已經停掉 controller 之後才發現,等於卡死。
ensure_test_topic() {
  kafka_topics --describe --topic ha.test | grep -q "Partition:" && return 0
  create_topic --topic ha.test --replica-assignment 11:12:13,12:13:11,13:11:12 --config min.insync.replicas=2 >/dev/null
  sleep 3
}

# 目前有幾個分區處於「副本不足」。
count_urp() { kafka_topics --describe --under-replicated-partitions | grep -c Partition: ; }

# 讀某 topic 的全部分區,印出讀到幾筆(逐分區讀再加總,因為資料可能集中在某一個分區)。
read_all_partitions() {
  local p n total=0
  for p in 0 1 2; do
    n=$("$DEMO_DIR/scripts/k.sh" kafka-console-consumer --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config "$KAFKA_ADMIN_CONFIG" \
          --topic "$1" --partition "$p" --offset earliest --timeout-ms 12000 2>/dev/null | wc -l)
    total=$((total + n))
  done
  echo "$total"
}

# ---------- 各個實驗 ----------

lab_quorum() {
  say "看 KRaft controller quorum:應該有 3 個 voter(controller)、1 個 leader;broker 是 observer"
  local out voters observers
  out=$(kafka_quorum describe --status)
  echo "$out" | grep -E "LeaderId|CurrentVoters|CurrentObservers" | cut -c1-200
  voters=$(echo "$out" | grep CurrentVoters | grep -o '"id"' | wc -l)
  observers=$(echo "$out" | grep CurrentObservers | grep -o '"id"' | wc -l)
  echo "kraft.version / metadata.version:"
  "$DEMO_DIR/scripts/k.sh" kafka-features --bootstrap-server broker1:9092 --command-config /clients/internal.properties describe 2>&1 \
    | grep -E "kraft.version|metadata.version" | sed -E 's/\s+/ /g' | cut -c1-140
  [ "$voters" = 3 ] && verdict "3 個 controller 都是 voter(quorum 容得下 1 台故障),$observers 台 broker 是 observer"
}

lab_topic() {
  say "建立 3 分區、副本 3、min.insync.replicas=2 的 topic(副本固定放 broker1~3;第 4 台不放,這樣停 2 台時才有『一個分區同時失去 2 個副本』的情境可看),用 acks=all 寫 300 筆再數筆數"
  local sent
  reset_topics ha.test
  create_topic --topic ha.test --replica-assignment 11:12:13,12:13:11,13:11:12 --config min.insync.replicas=2
  show_partitions ha.test
  sent=$(produce_test ha.test 300 all)
  echo "寫入(acks=all):送出 ${sent:-0} 筆;topic 實際 $(topic_message_count ha.test) 筆"
  [ "${sent:-0}" = 300 ] && [ "$(topic_message_count ha.test)" = 300 ] \
    && verdict "副本 3、min.isr 2 的 topic 寫入與讀回正常(300 = 300)"
}

lab_broker_down() {
  say "停 1 台 broker(broker3):ISR 剩 2,仍 ≥ min.insync.replicas 2,所以 acks=all 寫入應該不受影響"
  local urp sent
  echo "停 broker3"; stop_containers broker3; sleep 20
  show_partitions ha.test
  urp=$(count_urp); echo "URP(副本不足的分區)數:$urp"
  sent=$(produce_test ha.test 200 all); echo "ha.test 只剩 2 份副本(broker 剩 3 台),acks=all 寫入:送出 ${sent:-0} 筆"
  say "把 broker3 啟動回來,等 ISR 補齊"
  start_containers broker3; wait_healthy broker3 >/dev/null; wait_isr_full >/dev/null && echo "恢復 broker3:ISR 補齊、URP=0"
  [ "${sent:-0}" = 200 ] && [ "$urp" -gt 0 ] \
    && verdict "停 1 台 broker 時寫入不中斷(ISR 剩 2 ≥ min.isr 2),URP 大於 0 是告警訊號,恢復後補齊"
}

lab_brokers_down() {
  say "停 2 台 broker(只剩 broker1):ISR 剩 1,低於 min.insync.replicas 2,看 acks=all 與 acks=1 的差別"
  local before after_one after_restore sent_all sent_one
  before=$(topic_message_count ha.test); echo "目前 topic 筆數:$before"
  echo "停 broker2、broker3(只剩 broker1)"; stop_containers broker2 broker3; sleep 25
  show_partitions ha.test

  say "acks=all 寫 50 筆:應該被拒絕,producer 重試到逾時"
  sent_all=$(DELIVERY_MS=15000 produce_test ha.test 50 all)
  echo "acks=all 寫入 50 筆:成功 ${sent_all:-0} 筆(ISR 1 < min.isr 2,被拒絕,producer 重試到逾時)"
  grep -aoE "NotEnoughReplicas|TimeoutException: Expiring [0-9]+ record" "$PERF_OUT" | sort | uniq -c | head -2 | sed 's/^/   /'

  say "acks=1 寫 50 筆:producer 會回報成功,但資料還沒被確認(高水位不前進),consumer 讀不到"
  sent_one=$(produce_test ha.test 50 1); after_one=$(topic_message_count ha.test)
  echo "acks=1 寫入 50 筆:producer 回報成功 ${sent_one:-0} 筆;但 consumer 看得到的筆數仍是 $after_one(原本 $before)——高水位沒有前進,這 50 筆讀不到"

  say "用 consumer group 讀:連 __consumer_offsets 的 ISR 也不足,會加入不了群組"
  echo -n "用 consumer group 讀取:"
  "$DEMO_DIR/scripts/k.sh" kafka-console-consumer --bootstrap-server broker1:9094 --command-config "$KAFKA_ADMIN_CONFIG" \
      --topic ha.test --group g-ha-down --from-beginning --timeout-ms 15000 2>&1 \
    | grep -c -E "TimeoutException" \
    | sed 's/^1$/ 逾時(內部 topic __consumer_offsets 的 min.isr 也不足,加入不了群組)/; s/^0$/ 有回應/'

  say "把 broker2、broker3 啟動回來:那 50 筆(acks=1)恢復後才會出現"
  start_containers broker2 broker3; wait_healthy broker2 broker3 >/dev/null; wait_isr_full >/dev/null; sleep 10
  after_restore=$(topic_message_count ha.test); echo "恢復後 topic 筆數:$after_restore"
  [ "${sent_all:-0}" = 0 ] && [ "${sent_one:-0}" = 50 ] && [ "$after_one" = "$before" ] && [ "$after_restore" = $((before + 50)) ] \
    && verdict "ISR 低於 min.isr 時,acks=all 被擋,acks=1 看似成功卻讀不到(恢復後才出現)——這就是要用 acks=all 加 min.isr 的理由"
}

lab_ctrl_down() {
  say "停 1 台 controller(controller3):剩 2/3 仍有多數,叢集照常運作"
  local sent
  reset_topics ha.c1
  echo "停 controller3(剩 2/3,仍有多數)"; stop_containers controller3; sleep 15
  echo -n "建立 topic:"; create_topic --topic ha.c1 --partitions 1 --replication-factor 3
  sent=$(produce_test ha.test 100 all); echo "寫入既有 topic:送出 ${sent:-0} 筆"
  kafka_quorum describe --status | grep -E "LeaderId"
  start_containers controller3; wait_healthy controller3 >/dev/null
  [ "${sent:-0}" = 100 ] && kafka_topics --describe --topic ha.c1 | grep -q "Partition:" \
    && verdict "停 1 台 controller 仍有多數,建立 topic 與寫入都正常"
}

lab_ctrls_down() {
  say "停 2 台 controller(剩 1/3,失去多數):控制面(建 topic、describe)會卡住,資料面(讀寫既有 topic)應該還能用"
  local sent read_count
  reset_topics ha.c2
  echo "停 controller2、controller3(剩 1/3,失去多數)"; stop_containers controller2 controller3; sleep 25
  echo -n "建立 topic(等 25 秒):"
  KAFKA_TIMEOUT=25 kafka_topics --create --topic ha.c2 --partitions 1 --replication-factor 3 | grep -E "Created|rror" || echo "沒有回應(逾時)"
  echo -n "describe topic(等 25 秒):"
  KAFKA_TIMEOUT=25 kafka_topics --describe --topic ha.test | grep -c "Partition:" | sed 's/^0$/沒有回應(逾時)/'
  sent=$(produce_test ha.test 100 all)
  if [ "${sent:-0}" != 100 ]; then
    # 偶發:曾有一輪(從零重建後第一次跑)送出 0 筆,原因未查明(同樣步驟其餘多次都是 100 筆)。留下第一個錯誤,重試一次。
    note "第一次送出 ${sent:-0} 筆;錯誤:$(grep -a -m1 -E 'Exception|Timeout|error' "$PERF_OUT" | cut -c1-160)"; sleep 10
    sent=$(produce_test ha.test 100 all)
  fi
  echo "寫入既有 topic(acks=all):送出 ${sent:-0} 筆"
  read_count=$(read_all_partitions ha.test); echo "讀取既有 topic 全部分區:$read_count 筆"
  say "把 controller2、controller3 啟動回來,恢復多數後控制面才恢復"
  start_containers controller2 controller3; wait_healthy controller2 controller3 >/dev/null; sleep 15
  echo -n "恢復後建立 topic:"; create_topic --topic ha.c2 --partitions 1 --replication-factor 3
  [ "${sent:-0}" = 100 ] && [ "$read_count" -gt 0 ] \
    && verdict "失去 controller 多數時,資料面(既有 topic 的讀寫)繼續運作,但控制面(建 topic、describe、換 leader)停擺;恢復多數後才恢復"
}

lab_rolling() {
  local total_records="${1:-2400}" pp leader active order c sent have fails
  say "背景用冪等 producer(acks=all)持續寫入,同時依序重啟所有節點;最後比對『送出幾筆』與『topic 實際幾筆』"
  reset_topics ha.roll
  create_topic --topic ha.roll --partitions 6 --replication-factor 3 --config min.insync.replicas=2
  echo "背景 producer:$total_records 筆、每秒 6 筆、acks=all、冪等;同時依序重啟 broker1 → broker2 → broker3 → broker4 → 非 active controller → active controller"
  "$DEMO_DIR/scripts/k.sh" kafka-producer-perf-test --topic ha.roll --num-records "$total_records" --throughput 6 --record-size 100 \
      --command-config "$KAFKA_ADMIN_CONFIG" \
      --producer-props bootstrap.servers="$KAFKA_BOOTSTRAP" acks=all enable.idempotence=true delivery.timeout.ms=120000 request.timeout.ms=30000 \
      > "$PERF_OUT" 2>&1 &
  pp=$!; sleep 20

  say "重啟順序:先 4 台 broker,再 controller;active controller(leader)放最後,避免 leader 來回切換"
  leader=$(kafka_quorum describe --status | awk '/LeaderId/ {print $2}'); active="controller$leader"
  order="broker1 broker2 broker3 broker4"
  for c in controller1 controller2 controller3; do [ "$c" != "$active" ] && order="$order $c"; done
  order="$order $active"
  echo "active controller = $active(最後重啟)"
  for c in $order; do
    docker restart "$c" >/dev/null; wait_healthy "$c" >/dev/null
    case "$c" in
      broker*) wait_isr_full >/dev/null && echo "  重啟 $c → 健康,URP=0" || echo "  重啟 $c → 健康,但 URP 未回 0";;
      *)       sleep 10; echo "  重啟 $c → 健康";;
    esac
  done
  wait "$pp"

  sent=$(grep -aoE '^[0-9]+ records sent' "$PERF_OUT" | tail -1 | awk '{print $1}'); have=$(topic_message_count ha.roll)
  fails=$(grep -acE "ERROR|Expiring|expired|Failed to send" "$PERF_OUT" || true)
  echo "producer 回報送出 ${sent:-?} 筆;topic 實際 $have 筆;送出失敗 $fails 筆"
  if [ "${sent:-}" = "$total_records" ] && [ "$have" = "$total_records" ] && [ "$fails" = 0 ]; then
    verdict "滾動重啟 4 台 broker 與 3 台 controller 期間,producer 零失敗、零遺失($total_records = $have)"
  else
    verdict "不符合(送出 ${sent:-?}、topic $have、失敗 $fails)"
  fi
  kafka_quorum describe --status | grep -E "LeaderId"
}

case "${1:-}" in broker-down|brokers-down|ctrl-down|ctrls-down|rolling) ensure_test_topic ;; esac

case "${1:-}" in
  quorum)        lab_quorum ;;
  topic)         lab_topic ;;
  broker-down)   lab_broker_down ;;
  brokers-down)  lab_brokers_down ;;
  ctrl-down)     lab_ctrl_down ;;
  ctrls-down)    lab_ctrls_down ;;
  rolling)       lab_rolling "${2:-2400}" ;;
  *)             usage_from_header "$0"; exit 1 ;;
esac
