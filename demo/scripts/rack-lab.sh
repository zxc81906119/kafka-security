#!/usr/bin/env bash
# ============================================================================
# rack-lab.sh — 第 35 章的實驗:整個機架斷電時,副本 3 / min.insync.replicas 2 撐不撐得住
# ----------------------------------------------------------------------------
# 白話:副本會依 broker.rack 分散到不同機架,每個分區橫跨 min(機架數, 副本數) 個機架。
#   2 個機架:副本 3 一定有一個機架放 2 份;那個機架斷電 → 只剩 1 份 < min.isr 2 → 那些分區 acks=all 寫不進去。
#   3 個機架:3 份副本各在一個機架;任一機架斷電 → 每個分區還有 2 份 → 全部照常寫入。
# 前置條件:先用 scripts/rack-setup.sh two 或 three 設好機架。
# 用法:
#   scripts/rack-lab.sh placement <topic>     建立 6 分區、副本 3 的 topic,列出每個分區的副本在哪些機架
#   scripts/rack-lab.sh rack-down <topic> <機架>   停掉該機架的所有 broker,acks=all 寫 600 筆,統計寫得進去的分區;最後恢復
# 會改動什麼:建立 / 刪除指定 topic;暫停並恢復 broker。
# 怎麼判斷成功:以「判定:…」結尾。
# ============================================================================
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/kafka.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR" || exit 1

# rack_map:每行「node id 機架」(例如 11 rack-a)
rack_map() {
  "$DEMO_DIR/scripts/k.sh" kafka-broker-api-versions --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config "$KAFKA_ADMIN_CONFIG" 2>/dev/null \
    | grep -oE 'id: [0-9]+ rack: [^)]*' | sort -u | awk '{print $2, $4}'
}

# placement_table <topic>:每個分區一行「分區 副本 副本所在機架 機架數」
placement_table() {
  local map; map=$(rack_map)
  kafka_topics --describe --topic "$1" 2>/dev/null | grep -oE 'Partition: [0-9]+.*Replicas: [0-9,]+' \
    | sed -E 's/Partition: ([0-9]+).*Replicas: ([0-9,]+)/\1 \2/' | while read -r p reps; do
      racks=$(echo "$reps" | tr ',' '\n' | while read -r id; do echo "$map" | awk -v i="$id" '$1==i{print $2}'; done | tr '\n' ',' | sed 's/,$//')
      n=$(echo "$racks" | tr ',' '\n' | sort -u | grep -c .)
      echo "$p $reps $racks $n"
    done
}

# brokers_in_rack <機架>:該機架的容器名稱(node id 11~14 = broker1~4)
brokers_in_rack() { rack_map | awk -v r="$1" '$2==r{print "broker" ($1-10)}' | tr '\n' ' '; }

case "${1:-}" in
  placement)
    t="${2:?topic}"
    say "建立 $t(6 分區、副本 3),看每個分區的副本分散到哪些機架"
    echo "目前的機架:"; rack_map | sed 's/^/  node /'
    kafka_topics --delete --if-exists --topic "$t" >/dev/null 2>&1; sleep 3
    kafka_topics --create --topic "$t" --partitions 6 --replication-factor 3 | grep -E "Created|rror"
    sleep 3
    echo "分區 副本 機架 機架數:"; placement_table "$t" | sed 's/^/  /'
    racks=$(rack_map | awk '{print $2}' | sort -u | grep -c .); want=$(( racks < 3 ? racks : 3 ))
    bad=$(placement_table "$t" | awk -v w="$want" '$4!=w' | grep -c .)
    [ "$bad" = 0 ] && verdict "共 $racks 個機架:每個分區都橫跨 $want 個機架(= min(機架數, 副本數))" ;;
  rack-down)
    t="${2:?topic}"; r="${3:?機架}"; b=$(brokers_in_rack "$r")
    [ -n "$b" ] || die "機架 $r 沒有 broker"
    say "機架 $r 整個斷電:停 $b"
    before=$(topic_message_count "$t")
    stop_containers $b; sleep 20
    echo "低於 min.insync.replicas 的分區(acks=all 會被擋):"
    under=$(kafka_topics --describe --topic "$t" --under-min-isr-partitions 2>/dev/null | grep -c "Partition:")
    kafka_topics --describe --topic "$t" --under-min-isr-partitions 2>/dev/null | grep -oE 'Partition: [0-9]+.*Isr: [0-9,]*' | sed 's/^/  /'
    echo "  共 $under 個分區(總共 6 個)"
    # 用 RoundRobinPartitioner 讓每個分區都分到資料(等同「每個 key 都要寫得進去」):預設的自適應分區會把沒有 key 的訊息
    #   繞到健康的分區(實測:3 個分區低於 min.isr 時 600 筆仍全部寫入),那只對無 key 訊息有效;有 key 的訊息仍會失敗
    sent=$(DELIVERY_MS=30000 PRODUCE_TIMEOUT=120 PRODUCER_EXTRA="partitioner.class=org.apache.kafka.clients.producer.RoundRobinPartitioner" produce_test "$t" 600 all)
    got=$(( $(topic_message_count "$t") - before ))
    echo "acks=all 寫 600 筆(輪流寫到 6 個分區,每個分區約 100 筆):topic 實際多了 $got 筆"
    start_containers $b; wait_healthy $b >/dev/null
    wait_until "副本補齊" 300 bash -c "[ -z \"\$(\"$DEMO_DIR/scripts/k.sh\" kafka-topics --bootstrap-server $KAFKA_BOOTSTRAP --command-config $KAFKA_ADMIN_CONFIG --describe --under-replicated-partitions 2>/dev/null | grep Partition)\" ]" >/dev/null || true
    if [ "$under" = 0 ] && [ "$got" = 600 ]; then
      verdict "機架 $r 斷電後,所有分區仍有 2 份以上同步副本,600 筆全部寫入(撐得過整個機架故障)"
    elif [ "$under" -gt 0 ] && [ "$got" -lt 600 ]; then
      verdict "機架 $r 斷電後,$under 個分區低於 min.insync.replicas,只寫進 $got / 600 筆(撐不過整個機架故障)"
    else
      echo "判定:不符合(低於 min.isr 的分區 $under、寫入 $got / 600)"
    fi ;;
  *) usage_from_header "$0"; exit 1 ;;
esac
