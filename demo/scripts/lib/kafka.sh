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
  # max.block.ms:topic 不存在或沒有 leader 時最多等 30 秒就放棄(perf-test 遇到 UNKNOWN_TOPIC 會一直重試,實測曾卡 27 分鐘);
  # 外層 timeout 加容器名稱是最後防線,逾時就把容器移除,不會留下卡住的 client。
  local name="perf-$$-$RANDOM"
  K_NAME="$name" timeout "${PRODUCE_TIMEOUT:-240}" "$DEMO_DIR/scripts/k.sh" kafka-producer-perf-test --topic "$1" --num-records "$2" --throughput "${4:--1}" --record-size "${RECORD_SIZE:-100}" \
    --command-config "$KAFKA_ADMIN_CONFIG" \
    --producer-props bootstrap.servers="$KAFKA_BOOTSTRAP" acks="$3" delivery.timeout.ms="${DELIVERY_MS:-20000}" request.timeout.ms=8000 max.block.ms=30000 ${PRODUCER_EXTRA:-} > "$PERF_OUT" 2>&1
  docker rm -f "$name" >/dev/null 2>&1
  grep -aoE '^[0-9]+ records sent' "$PERF_OUT" | tail -1 | awk '{print $1}'
}

# kafka_reassign <計畫 json 檔> <kafka-reassign-partitions 參數...>:執行分區重新指派工具(--execute / --verify / --cancel)。
# 做法:工具要讀容器裡的檔案,所以把本機的 json 從標準輸入送進容器,在同一個容器內存成檔案再執行。
kafka_reassign() {
  local plan="$1"; shift
  "$DEMO_DIR/scripts/k.sh" bash -c "cat > /tmp/plan.json; kafka-reassign-partitions --bootstrap-server $KAFKA_BOOTSTRAP --command-config $KAFKA_ADMIN_CONFIG --reassignment-json-file /tmp/plan.json $*" < "$plan" 2>&1 | _kafka_quiet
}

# kafka_reassign_generate <topic> <broker id 逗號清單>:印出工具建議的新指派(--generate)。輸出有兩段:目前的指派(可存起來當回退檔)與建議的指派。
kafka_reassign_generate() {
  echo "{\"version\":1,\"topics\":[{\"topic\":\"$1\"}]}" \
    | "$DEMO_DIR/scripts/k.sh" bash -c "cat > /tmp/t.json; kafka-reassign-partitions --bootstrap-server $KAFKA_BOOTSTRAP --command-config $KAFKA_ADMIN_CONFIG --topics-to-move-json-file /tmp/t.json --broker-list $2 --generate" 2>&1 | _kafka_quiet
}

# broker_sizes <topic>:每台 broker 上這個 topic 的資料量(MB)與分區編號(kafka-log-dirs)。
broker_sizes() {
  "$DEMO_DIR/scripts/k.sh" kafka-log-dirs --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config "$KAFKA_ADMIN_CONFIG" --describe --topic-list "$1" 2>/dev/null \
    | grep '^{' | tail -1 | node "$LIB_DIR/log-dirs.mjs"
}

# kafka_acls <kafka-acls 參數...>:執行 kafka-acls(一般路徑,管理身分)。
# 注意:資源名稱 * 一定要加引號('*'),否則會被 shell 展開成目前目錄的檔名。
kafka_acls() {
  timeout 90 "$DEMO_DIR/scripts/k.sh" kafka-acls --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config "$KAFKA_ADMIN_CONFIG" "$@" 2>&1 | _kafka_quiet
}
