#!/usr/bin/env bash
# ============================================================================
# lib/kafka.sh — 在 demo 網路內執行 Kafka 指令的小工具
# ----------------------------------------------------------------------------
# 前置:先 source lib/common.sh。指令都透過 scripts/k.sh 在容器內執行(不用在本機裝 Kafka)。
# 兩條管理路徑(要分清楚,見 Lab 23):
#   一般路徑:CLIENT 埠(9094),用 bootstrap 的 OAuth token——日常使用
#   帶外路徑:INTERNAL 埠(9092),用內部 mTLS 憑證——CLIENT 埠的憑證壞了時的緊急通道,權限是 super user,只在回退時用
# ============================================================================
KAFKA_BOOTSTRAP="${KAFKA_BOOTSTRAP:-broker1:9094,broker2:9094,broker3:9094}"
KAFKA_ADMIN_CONFIG=/clients/token-bootstrap.properties
KAFKA_OOB_BOOTSTRAP="broker1:9092,broker2:9092,broker3:9092"

# 內部用:把 Kafka 工具輸出裡沒意義的警告行濾掉。
_kafka_quiet() { grep -v -E '^WARNING|SLF4J'; }

# kafka_topics <參數...>:執行 kafka-topics(一般路徑,最多等 60 秒)。
kafka_topics() { timeout "${KAFKA_TIMEOUT:-60}" "$DEMO_DIR/scripts/k.sh" kafka-topics --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config "$KAFKA_ADMIN_CONFIG" "$@" 2>&1 | _kafka_quiet; }

# kafka_configs <參數...>:執行 kafka-configs(一般路徑,最多等 90 秒)。
kafka_configs() { timeout 90 "$DEMO_DIR/scripts/k.sh" kafka-configs --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config "$KAFKA_ADMIN_CONFIG" "$@" 2>&1 | _kafka_quiet; }

# kafka_configs_oob <參數...>:執行 kafka-configs(帶外路徑:INTERNAL mTLS 埠)。回退「剛被弄壞的 CLIENT 憑證」時一定要用這個。
kafka_configs_oob() { timeout 90 "$DEMO_DIR/scripts/k.sh" kafka-configs --bootstrap-server "$KAFKA_OOB_BOOTSTRAP" --command-config /clients/internal.properties "$@" 2>&1 | _kafka_quiet; }

# kafka_quorum <參數...>:執行 kafka-metadata-quorum(KRaft controller 的狀態;走 INTERNAL 埠)。
kafka_quorum() { "$DEMO_DIR/scripts/k.sh" kafka-metadata-quorum --bootstrap-server "$KAFKA_OOB_BOOTSTRAP" --command-config /clients/internal.properties "$@" 2>&1 | _kafka_quiet; }

# topic_message_count <topic>:該 topic 目前「看得到」的訊息總數(各分區 end offset 相加)。
topic_message_count() { "$DEMO_DIR/scripts/k.sh" kafka-get-offsets --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config "$KAFKA_ADMIN_CONFIG" --topic "$1" 2>/dev/null | awk -F: '{s+=$3} END {print s+0}'; }

# produce_test <topic> <筆數> <acks> [每秒筆數]:用 kafka-producer-perf-test 寫入;輸出存到 $PERF_OUT,印出「成功送出幾筆」。
# 為什麼要用固定檔 $PERF_OUT:這個函式常在 $(...) 裡呼叫,變數傳不出來,用檔案讓呼叫者事後還能看錯誤細節。
PERF_OUT="${PERF_OUT:-/tmp/lab-perf.out}"
produce_test() {
  "$DEMO_DIR/scripts/k.sh" kafka-producer-perf-test --topic "$1" --num-records "$2" --throughput "${4:--1}" --record-size 100 \
    --command-config "$KAFKA_ADMIN_CONFIG" \
    --producer-props bootstrap.servers="$KAFKA_BOOTSTRAP" acks="$3" delivery.timeout.ms="${DELIVERY_MS:-20000}" request.timeout.ms=8000 > "$PERF_OUT" 2>&1
  grep -aoE '^[0-9]+ records sent' "$PERF_OUT" | tail -1 | awk '{print $1}'
}
