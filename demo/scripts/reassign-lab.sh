#!/usr/bin/env bash
# ============================================================================
# reassign-lab.sh — 第 24 章:分區搬家(重新指派)加限速,以及忘了收尾的後果
# ----------------------------------------------------------------------------
# 白話:新增 broker、或某幾台 broker 資料特別多時,要把一部分分區「搬」到別台。搬家就是在新 broker 上複製一份資料,
#   會吃網路與磁碟,搬太快會拖慢正在服務的讀寫,所以要『限速(throttle)』。限速是寫在叢集設定裡的,
#   搬完如果沒有收尾(--verify),限速會一直留著,之後別的複製流量(例如重啟的 broker 追資料)也被默默限速。
#   這支腳本依序練習:造出不均的叢集 → 存回退檔 → 限速搬家(寫入不中斷)→ 取消搬到一半的搬家 → 忘了收尾的殘留與清除。
# 前置條件:HA 模式(scripts/ha.sh on:3 台 broker)
# 用法:
#   scripts/reassign-lab.sh skew       建 6 分區 topic cap.skew,所有副本只放在 broker1、broker2,寫入約 200 MB;broker3 是空的
#   scripts/reassign-lab.sh plan       存目前的指派當回退檔;看工具建議的新指派(--generate);寫出審過的均衡計畫
#   scripts/reassign-lab.sh execute    限速(預設 4 MB/s)搬家,同時背景持續寫入;用 --verify 追到完成並自動移除限速
#   scripts/reassign-lab.sh cancel     以 1 MB/s 慢慢搬回去,搬到一半 --cancel:回到搬家前的指派
#   scripts/reassign-lab.sh leftover   搬家完成後「故意不 verify」:限速設定殘留;再用 --verify 清掉
# 環境變數:THROTTLE=搬家限速(bytes/秒,預設 4000000,也就是 4 MB/s)
# 會改動什麼:建立 topic cap.skew(每次 skew 會先刪除重建);在 /tmp 存 cap-rollback.json、cap-plan.json;
#   搬家期間對 broker 與 topic 設定限速(結束前一律清除)。
# 怎麼判斷成功:最後一行印「判定:…」。
# 常見失敗:
#   「請先執行 skew / plan」→ 照順序執行(skew → plan → execute → cancel → leftover)
#   搬家一直 in progress → 限速太低或資料太多;看 THROTTLE,或 --verify 追進度(上限 15 分鐘)
# ============================================================================
set -uo pipefail
PERF_OUT=/tmp/reassign-lab-perf.out
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/kafka.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR" || exit 1
need_ha_mode

TOPIC=cap.skew
PARTITIONS=6
BROKER_IDS="${CERT_BROKER_IDS:-11 12 13}"          # broker 的 node id(測試環境 broker1/2/3 = 11/12/13)
ROLLBACK_FILE=/tmp/cap-rollback.json               # 搬家前的指派(回退用)
PLAN_FILE=/tmp/cap-plan.json                       # 審過、要執行的均衡計畫
THROTTLE="${THROTTLE:-4000000}"

# ---------- 小工具(這支腳本專用) ----------

# 把 BROKER_IDS 拆成陣列 IDS,並算出『只放前兩台』的 id 清單(造不均用)。
read -r -a IDS <<< "$BROKER_IDS"
SKEW_A=${IDS[0]}; SKEW_B=${IDS[1]}

# 目前每個分區的 Replicas 與 Isr(精簡顯示)。
show_assignment() {
  kafka_topics --describe --topic "$TOPIC" | grep "Partition:" | sed -E 's/\s+/ /g; s/Topic: [^ ]* //; s/ Offline:.*//' | cut -c1-90
}

# 只印每個分區的副本「集合」(不含 leader、ISR,副本的先後順序也不比),用來比較「搬家前後是否一致」。
#   順序不比,是因為取消搬家後同一組副本的排列(也就是 preferred leader)可能不同,但放在哪幾台是一樣的。
replica_layout() {
  local part reps
  kafka_topics --describe --topic "$TOPIC" | grep "Partition:" | sed -E 's/\s+/ /g' \
    | sed -E 's/.*Partition: ([0-9]+) .*Replicas: ([0-9,]+) .*/\1 \2/' | sort -n \
    | while read -r part reps; do
        echo -n "$part:$(echo "$reps" | tr ',' '\n' | sort -n | paste -sd, -) "
      done
}

# 檢查前置檔案存在。
need_files() {
  [ -f "$ROLLBACK_FILE" ] && [ -f "$PLAN_FILE" ] || die "請先執行 scripts/reassign-lab.sh skew 與 plan"
}

# 目前有沒有進行中的搬家(--list 沒有輸出 'No partition reassignments' 就是還在搬)。
reassign_idle() {
  "$DEMO_DIR/scripts/k.sh" kafka-reassign-partitions --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config "$KAFKA_ADMIN_CONFIG" --list 2>&1 \
    | grep -q "No partition reassignments"
}

# 目前有沒有殘留的限速設定:印 broker 層與 topic 層各幾筆。
throttle_residue() {
  local b t
  b=$(kafka_configs --entity-type brokers --entity-name "${IDS[0]}" --describe | grep -c "throttled.rate")
  t=$(kafka_configs --entity-type topics --entity-name "$TOPIC" --describe | grep -c "throttled.replicas")
  echo "broker ${IDS[0]} 的限速設定 $b 筆、topic $TOPIC 的限速設定 $t 筆"
  THROTTLE_COUNT=$((b + t))
}

# 組出「輪流放在三台」的均衡計畫:分區 p 的副本放在 IDS[p%3]、IDS[(p+1)%3]。
write_balanced_plan() {
  local p a b sep=""
  printf '{"version":1,"partitions":[' > "$PLAN_FILE"
  for p in $(seq 0 $((PARTITIONS - 1))); do
    a=${IDS[$((p % 3))]}; b=${IDS[$(((p + 1) % 3))]}
    printf '%s{"topic":"%s","partition":%d,"replicas":[%s,%s]}' "$sep" "$TOPIC" "$p" "$a" "$b" >> "$PLAN_FILE"; sep=","
  done
  printf ']}\n' >> "$PLAN_FILE"
}

# 組出「全部擠在前兩台」的計畫(用來『搬回去』的另一個方向)。
write_skew_plan() {
  local file="$1" p a b sep=""
  printf '{"version":1,"partitions":[' > "$file"
  for p in $(seq 0 $((PARTITIONS - 1))); do
    if [ $((p % 2)) = 0 ]; then a=$SKEW_A; b=$SKEW_B; else a=$SKEW_B; b=$SKEW_A; fi
    printf '%s{"topic":"%s","partition":%d,"replicas":[%s,%s]}' "$sep" "$TOPIC" "$p" "$a" "$b" >> "$file"; sep=","
  done
  printf ']}\n' >> "$file"
}

# 追搬家進度直到完成(每 10 秒 --verify 一次,最多 15 分鐘);完成時 --verify 會自動移除限速。印出花了幾秒。
verify_until_done() {
  local plan="$1" t0 out
  t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 900 ]; do
    out=$(kafka_reassign "$plan" --verify)
    if ! echo "$out" | grep -q "still in progress"; then
      note "$(( $(date +%s) - t0 )) 秒後搬家完成"; echo "$out" | grep -E "Clearing"; return 0
    fi
    sleep 10
  done
  note "等了 900 秒搬家仍未完成"; return 1
}

# ---------- 各個實驗 ----------

lab_skew() {
  say "建立一個 6 分區的 topic,故意把所有副本都放在 broker1 與 broker2,寫入約 200 MB;broker3 完全沒有資料"
  local sent
  kafka_topics --delete --if-exists --topic "$TOPIC" >/dev/null; sleep 3
  write_skew_plan /tmp/cap-skew-assign.json
  kafka_topics --create --topic "$TOPIC" --replica-assignment "$SKEW_A:$SKEW_B,$SKEW_B:$SKEW_A,$SKEW_A:$SKEW_B,$SKEW_B:$SKEW_A,$SKEW_A:$SKEW_B,$SKEW_B:$SKEW_A" \
    --config min.insync.replicas=1 | grep -E "Created|rror" || echo "失敗"
  sent=$(RECORD_SIZE=1024 produce_test "$TOPIC" 200000 all)
  echo "寫入 ${sent:-0} 筆(每筆約 1 KB)"
  echo "每台 broker 上 $TOPIC 的資料量:"
  broker_sizes "$TOPIC"
  [ "${sent:-0}" = 200000 ] && broker_sizes "$TOPIC" | grep -qE "broker ${IDS[2]} +0 MB" \
    && verdict "資料全擠在 broker1、broker2,broker3 是空的(負載不均;新增 broker 後也是這種狀態)"
}

lab_plan() {
  say "先把『目前的指派』存成回退檔——搬家出問題時,拿它就能搬回原樣。再看工具建議的新指派,最後寫出審過的計畫"
  local gen current_n
  gen=$(kafka_reassign_generate "$TOPIC" "${BROKER_IDS// /,}")
  echo "$gen" | grep '^{' | head -1 > "$ROLLBACK_FILE"
  current_n=$(grep -o '"partition"' "$ROLLBACK_FILE" | wc -l)
  echo "回退檔 $ROLLBACK_FILE:目前的指派($current_n 個分區)"
  echo "工具建議的新指派(--generate;只是草稿,起點是隨機的、也不會刻意減少搬動量):"
  echo "$gen" | grep '^{' | tail -1 | grep -o '"partition":[0-9]*,"replicas":\[[0-9,]*\]' | sed 's/^/  /'
  write_balanced_plan
  echo "審過、要執行的計畫 $PLAN_FILE(輪流放在三台,每台一樣多):"
  grep -o '"partition":[0-9]*,"replicas":\[[0-9,]*\]' "$PLAN_FILE" | sed 's/^/  /'
  [ "$current_n" = "$PARTITIONS" ] \
    && verdict "已存回退檔(搬家前的指派)並寫出均衡計畫;--generate 只當草稿,正式執行的是審過的計畫"
}

lab_execute() {
  need_files
  say "背景持續寫入 600 筆(acks=all、冪等),同時限速 $((THROTTLE / 1000000)) MB/s 搬家;追到完成,確認限速自動移除、資料不少"
  local before pp sent have secs t0
  before=$(topic_message_count "$TOPIC")
  "$DEMO_DIR/scripts/k.sh" kafka-producer-perf-test --topic "$TOPIC" --num-records 600 --throughput 10 --record-size 100 \
      --command-config "$KAFKA_ADMIN_CONFIG" \
      --producer-props bootstrap.servers="$KAFKA_BOOTSTRAP" acks=all enable.idempotence=true delivery.timeout.ms=120000 > "$PERF_OUT" 2>&1 &
  pp=$!; sleep 5
  t0=$(date +%s)
  kafka_reassign "$PLAN_FILE" --execute --throttle "$THROTTLE" | grep -E "throttle limit|Successfully"
  echo "搬家進行中的限速設定:"; throttle_residue
  sleep 10
  echo "搬家進行中的指派(Adding/Removing 表示正在複製):"; show_assignment
  verify_until_done "$PLAN_FILE" || exit 1
  secs=$(( $(date +%s) - t0 ))
  wait "$pp"
  sent=$(grep -aoE '^[0-9]+ records sent' "$PERF_OUT" | tail -1 | awk '{print $1}')
  have=$(( $(topic_message_count "$TOPIC") - before ))
  echo "搬完後的指派:"; show_assignment
  echo "每台 broker 上 $TOPIC 的資料量:"; broker_sizes "$TOPIC"
  echo "搬家期間 producer 送出 ${sent:-?} 筆;topic 多了 $have 筆;搬家共 $secs 秒"
  echo -n "搬完後:"; throttle_residue
  [ "${sent:-}" = 600 ] && [ "$have" = 600 ] && [ "$THROTTLE_COUNT" = 0 ] && ! broker_sizes "$TOPIC" | grep -q "(無)" \
    && verdict "限速搬家期間寫入零失敗(600 = 600)、三台 broker 都有資料、--verify 完成後限速自動移除"
}

lab_cancel() {
  need_files
  say "以 1 MB/s 慢慢搬回『擠在兩台』的指派,搬到一半 --cancel:應該回到搬家前的均衡指派,且限速一併清掉"
  local skew_plan=/tmp/cap-skew-plan.json before after
  write_skew_plan "$skew_plan"
  echo "搬家前的指派:"; show_assignment; before=$(replica_layout)
  kafka_reassign "$skew_plan" --execute --throttle 1000000 | grep -E "throttle limit|Successfully"
  sleep 15
  echo "搬到一半(Adding/Removing 表示還在複製):"; show_assignment
  kafka_reassign "$skew_plan" --cancel | grep -E "cancelled|Clearing"
  sleep 5
  echo "取消後的指派:"; show_assignment; after=$(replica_layout)
  echo -n "取消後:"; throttle_residue
  reassign_idle && echo "沒有進行中的搬家"
  [ "$before" = "$after" ] && [ "$THROTTLE_COUNT" = 0 ] \
    && verdict "--cancel 讓搬到一半的搬家回到搬家前的指派(前後一致),限速也一併清除"
}

lab_leftover() {
  need_files
  say "搬家完成後『故意不跑 --verify』:限速設定會一直殘留。之後任何複製流量(例如重啟的 broker 追資料)都會被默默限速"
  local skew_plan=/tmp/cap-skew-plan.json t0 residue_after_done
  write_skew_plan "$skew_plan"
  kafka_reassign "$skew_plan" --execute --throttle 20000000 | grep -E "throttle limit|Successfully"
  t0=$(date +%s)
  wait_until "搬家完成(--list 沒有進行中的搬家)" 600 reassign_idle || exit 1
  echo "搬家已完成,但我們沒有跑 --verify:"; throttle_residue; residue_after_done=$THROTTLE_COUNT
  kafka_configs --entity-type brokers --entity-name "${IDS[0]}" --describe | grep "throttled.rate" | sed -E 's/ sensitive.*//; s/^/  /'
  say "收尾:跑一次 --verify,它在搬家完成後會清掉 broker 與 topic 的限速設定"
  kafka_reassign "$skew_plan" --verify | grep -E "Clearing"
  echo -n "--verify 之後:"; throttle_residue
  say "把 topic 搬回均衡指派,留下乾淨的環境"
  kafka_reassign "$PLAN_FILE" --execute --throttle 50000000 | grep -E "Successfully"
  verify_until_done "$PLAN_FILE" >/dev/null
  [ "$residue_after_done" -gt 0 ] && [ "$THROTTLE_COUNT" = 0 ] \
    && verdict "搬家完成但沒跑 --verify:限速設定殘留(broker 與 topic 層都有);跑 --verify 後清除。搬家流程一定要以 --verify 收尾,並把殘留限速納入巡檢"
}

case "${1:-}" in
  skew)     lab_skew ;;
  plan)     lab_plan ;;
  execute)  lab_execute ;;
  cancel)   lab_cancel ;;
  leftover) lab_leftover ;;
  *)        usage_from_header "$0"; exit 1 ;;
esac
