#!/usr/bin/env bash
# ============================================================================
# sbc-lab.sh — 第 31 章:Self-Balancing(自動搬分區):加 broker、負載不均、移除 broker
# ----------------------------------------------------------------------------
# 白話:第 24 章是人工搬分區(自己算計畫、限速、收尾)。Self-Balancing 是 Confluent 內建的自動版:
#   新 broker 加進來,它自己把一部分副本搬過去;要下線一台 broker,下一個指令它就負責把副本搬走再關機。
#   這支腳本實際驗證它在什麼情況會動、什麼情況不會動,以及移除 broker 的完整過程。
# 前置條件:叢集已啟動,且已執行 scripts/sbc-setup.sh on(controller 與 broker 都啟用 balancer)
# 用法:
#   scripts/sbc-lab.sh status     balancer 狀態:跑在哪一台、觸發條件、是否正在搬
#   scripts/sbc-lab.sh add        寫入資料後啟動第 5 台(空的)broker:它自己把副本搬過去,寫入不中斷(等計畫約 15 到 20 分鐘)
#   scripts/sbc-lab.sh uneven     造出『資料全擠在兩台』的不均載:官方規則下用量太低不會觸發(實測確認)
#   scripts/sbc-lab.sh remove     kafka-remove-brokers 移除第 5 台:副本搬回去、資料筆數不變、broker 自動關機
# 會改動什麼:建立 topic sbc.data(add 時重建);啟動與移除 broker5;不改叢集設定(啟用在 sbc-setup.sh)。
# 怎麼判斷成功:每個子命令最後一行印「判定:…」。
# 常見失敗:balancer 狀態是 DISABLED → scripts/sbc-setup.sh on;remove 失敗並提示稍後重試 → 官方說明啟動後約 30 分鐘內
#   還在蒐集指標,過一會兒再試;broker5 起不來 → docker logs broker5(憑證 SAN 要有 broker5,make-certs.sh 會補)
# ============================================================================
set -uo pipefail
# shellcheck disable=SC2034  # produce_test(lib/kafka.sh)會讀
PERF_OUT=/tmp/sbc-lab-perf.out
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/kafka.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR" || exit 1
need_ha_mode

TOPIC=sbc.data
NEW_ID=15                      # broker5 的 node id(基線已有 broker1~4,實驗加入第 5 台)
NEW_NAME=broker5

# ---------- 小工具(這支腳本專用) ----------

# 執行 kafka-rebalance-cluster(balancer 的狀態查詢)。
rebalance_cluster() {
  "$DEMO_DIR/scripts/k.sh" kafka-rebalance-cluster --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config "$KAFKA_ADMIN_CONFIG" "$@" 2>&1 | grep -v -E 'SLF4J|^WARNING|WARN'
}

# 執行 kafka-remove-brokers。
remove_brokers() {
  "$DEMO_DIR/scripts/k.sh" kafka-remove-brokers --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config "$KAFKA_ADMIN_CONFIG" "$@" 2>&1 | grep -v -E 'SLF4J|^WARNING|WARN'
}

# 某 broker(node id)上有幾個分區副本(全叢集所有 topic)。
replicas_on() {
  kafka_topics --describe 2>/dev/null | grep -cE "Replicas: ([0-9]+,)*$1([, ]|[[:space:]]|$)"
}

# 給 wait_until 用:新 broker 上至少有一個副本。
new_broker_has_replicas() { [ "$(replicas_on "$NEW_ID")" -ge 1 ]; }

# 給 wait_until 用:移除作業狀態是 SUCCESS。
removal_done() { remove_brokers --broker-id "$NEW_ID" --describe | grep -q 'removal status - SUCCESS'; }

# 目前是否有進行中的分區搬移(有就回傳 0)。
reassigning() {
  "$DEMO_DIR/scripts/k.sh" kafka-reassign-partitions --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config "$KAFKA_ADMIN_CONFIG" --list 2>&1 \
    | grep -q 'Current partition reassignments'
}

# 給 wait_until 用:沒有進行中的搬移。
reassign_idle() { ! reassigning; }

# 給 wait_until 用:自 $1(UTC 時間)起,任何一台 controller 的日誌出現「沒有偵測到違反的目標」。
detector_clean() {
  local c
  for c in controller1 controller2 controller3; do
    # 先收進變數再比對:日誌很大時 grep -q 提早結束會讓上游 docker logs 吃 SIGPIPE,pipefail 下整條變成失敗
    local out; out=$(docker logs --since "$1" "$c" 2>&1)
    grep -q 'did not detect any violated goals' <<< "$out" && return 0
  done
  return 1
}

# balancer 是否已啟用(狀態不是 DISABLED 也不是空)。
need_balancer() {
  local s; s=$(rebalance_cluster --status | grep 'Balancer status')
  echo "$s" | grep -q ENABLED || die "balancer 沒有啟用($s)。先執行:scripts/sbc-setup.sh on"
}

# ---------- 各個實驗 ----------

lab_status() {
  say "balancer 的狀態:跑在哪一台、負載不均的觸發條件、目前是否在搬"
  rebalance_cluster --status | sed 's/^/  /'
  rebalance_cluster --describe | sed 's/^/  /'
  local on; on=$(rebalance_cluster --status | grep -c 'running on')
  [ "$on" -ge 1 ] && verdict "balancer 已啟用(KRaft 下跑在 active controller 上)"
}

lab_add() {
  need_balancer
  say "先建 topic $TOPIC(6 分區、副本 3)並寫入約 60 MB,讓叢集有資料可搬"
  docker compose --profile sbc stop broker5 >/dev/null 2>&1
  kafka_topics --delete --topic "$TOPIC" >/dev/null 2>&1
  kafka_topics --create --topic "$TOPIC" --partitions 6 --replication-factor 3 --config min.insync.replicas=2 | tail -1
  produce_test "$TOPIC" 60000 all 2000 >/dev/null
  local before; before=$(topic_message_count "$TOPIC")
  echo "寫入後筆數:$before;broker $NEW_ID 上的副本數:$(replicas_on "$NEW_ID")"
  say "啟動第 5 台 broker($NEW_NAME,空的);Self-Balancing 偵測到新的空 broker,自動把一部分副本搬過去"
  docker compose --profile sbc up -d "$NEW_NAME" >/dev/null 2>&1
  wait_healthy "$NEW_NAME" >/dev/null || die "$NEW_NAME 沒有 healthy:docker logs $NEW_NAME"
  say "等 Self-Balancing 計算搬移計畫:它要先蒐集到足夠的指標視窗(官方:啟動後需要一段時間蒐集指標),實測 15 到 20 分鐘"
  wait_until "新 broker 上出現副本(最多 25 分鐘)" 1500 new_broker_has_replicas || true
  say "搬家一開始就同時寫入 20000 筆(acks=all),觀察搬家過程中寫入有沒有失敗"
  produce_test "$TOPIC" 20000 all 150 >/dev/null
  wait_until "分區搬移全部完成(最多 10 分鐘)" 600 reassign_idle || true
  local after; after=$(topic_message_count "$TOPIC")
  echo "筆數:$before → $after;broker $NEW_ID 上的副本數:$(replicas_on "$NEW_ID")"
  echo "各 broker 上 $TOPIC 的資料量:"; broker_sizes "$TOPIC" | sed 's/^/  /'
  [ "$(replicas_on "$NEW_ID")" -ge 1 ] && [ "$after" = "$(( before + 20000 ))" ] \
    && verdict "空的新 broker 自動取得副本($(replicas_on "$NEW_ID") 個);搬家期間 20000 筆 acks=all 寫入全數成功,沒有人工計畫、沒有限速指令"
}

lab_uneven() {
  need_balancer
  local since; since=$(date -u +%Y-%m-%dT%H:%M:%S)
  say "把觸發條件設為 ANY_UNEVEN_LOAD(任何時候都檢查負載不均;預設 EMPTY_BROKER 只在加空 broker 時處理)"
  kafka_configs --alter --entity-type brokers --entity-default --add-config confluent.balancer.heal.uneven.load.trigger=ANY_UNEVEN_LOAD | tail -1
  say "造出不均:cap.skew 的 12 個副本全放在 broker1、broker2(約 400 MB),其他 broker 沒有這個 topic 的資料"
  bash scripts/reassign-lab.sh skew 2>&1 | tail -5
  say "等偵測器的結論(每分鐘一輪;broker 有變動後它會先暫停一段時間,demo 縮短為 3 分鐘,預設是 30 分鐘)"
  wait_until "偵測器輸出『沒有違反目標』(最多 8 分鐘)" 480 detector_clean "$since" || true
  local c
  for c in controller1 controller2 controller3; do
    docker logs --since "$since" "$c" 2>&1 | grep -E 'GoalViolationDetector' | grep -E 'did not detect|pausing|Skipping' | tail -2 | cut -c1-200 | sed 's/^/  /'
  done
  echo "觸發條件:$(rebalance_cluster --describe | grep HealUnevenLoadTrigger | tr -s ' ')"
  broker_sizes cap.skew | sed 's/^/  /'
  local ok=1; detector_clean "$since" && ok=0
  kafka_configs --alter --entity-type brokers --entity-default --delete-config confluent.balancer.heal.uneven.load.trigger >/dev/null   # 還原預設觸發條件
  [ "$ok" = 0 ] \
    && verdict "資料量低於官方觸發門檻(副本數與超過 20% 的磁碟用量才會觸發),偵測器判定沒有違反目標,不搬;小叢集不均不代表 Self-Balancing 失效"
}

lab_remove() {
  need_balancer
  docker ps --format '{{.Names}}' | grep -qx "$NEW_NAME" || die "$NEW_NAME 沒有在跑。先執行:scripts/sbc-lab.sh add"
  local before; before=$(topic_message_count "$TOPIC")
  echo "移除前:$TOPIC 筆數 $before;broker $NEW_ID 上的副本數:$(replicas_on "$NEW_ID")"
  say "下一個指令:kafka-remove-brokers --delete。它先把 broker 排除在新副本之外,再把它的副本搬走,最後關機"
  remove_brokers --broker-id "$NEW_ID" --delete | head -4
  wait_until "移除作業完成(最多 10 分鐘)" 600 removal_done || true
  remove_brokers --broker-id "$NEW_ID" --describe | head -5 | sed 's/^/  /'
  local after; after=$(topic_message_count "$TOPIC")
  echo "移除後:$TOPIC 筆數 $after;broker $NEW_ID 上的副本數:$(replicas_on "$NEW_ID");容器狀態:$(docker ps -a --format '{{.Names}} {{.Status}}' | grep "^$NEW_NAME " | cut -d' ' -f2-)"
  removal_done && [ "$(replicas_on "$NEW_ID")" = 0 ] && [ "$after" = "$before" ] \
    && verdict "broker $NEW_ID 的副本全部搬走、資料筆數不變($before)、broker 已自動關機;不需要手寫搬移計畫"
}

case "${1:-}" in
  status) lab_status ;;
  add)    lab_add ;;
  uneven) lab_uneven ;;
  remove) lab_remove ;;
  *)      usage_from_header "$0"; exit 1 ;;
esac
