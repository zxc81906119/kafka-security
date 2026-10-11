#!/usr/bin/env bash
# ============================================================================
# app-lab.sh — 第 25 章:應用程式端的可靠性——producer 重送、consumer 重複處理、rebalance、交易
# ----------------------------------------------------------------------------
# 白話:叢集再穩,應用程式的寫法不對一樣會重複或掉資料。這支腳本用 apps/ 底下幾支很短的 Java 程式,
#   實際製造狀況(broker 暫停、consumer 當機、新成員加入、交易放棄),並數結果。
#   程式是『一個檔案一個 main』,用 JDK 映像直接執行,不必在自己的電腦安裝 Java。
# 前置條件:叢集已啟動(scripts/up.sh;交易需要至少 3 台 broker);第一次執行會下載 JDK 映像(約 740 MB)。
# 用法:
#   scripts/app-lab.sh idempotent    broker 暫停造成逾時重送:關閉冪等會寫出重複訊息,開啟冪等則不會
#   scripts/app-lab.sh atleast       consumer 處理完、提交前當機:重啟後重複處理(at-least-once)
#   scripts/app-lab.sh rebalance     新成員加入:eager 全部分區先收回,cooperative 只收回要換人的分區
#   scripts/app-lab.sh static        重啟成員:動態成員每次都觸發 rebalance,靜態成員(group.instance.id)不會
#   scripts/app-lab.sh txn           交易:abort 的訊息 read_committed 看不到、read_uncommitted 看得到
# 會改動什麼:建立 topic app.*(每次執行前刪掉重建);暫停再恢復某台 broker(idempotent);結束前一律恢復。
# 怎麼判斷成功:最後一行印「判定:…」。
# 常見失敗:
#   「下載 JDK 映像失敗」→ 檢查網路;映像只需下載一次
#   idempotent 一直沒有出現重複 → 暫停時機沒對到送出期間;腳本會自動重試最多 3 次
# ============================================================================
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/kafka.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/apps.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR" || exit 1
need_ha_mode

# ---------- 小工具(這支腳本專用) ----------

# 重建 topic:app_topic <名稱> <分區數>(副本 3、min.insync.replicas 2)。
app_topic() {
  kafka_topics --delete --if-exists --topic "$1" >/dev/null; sleep 3
  kafka_topics --create --topic "$1" --partitions "$2" --replication-factor 3 --config min.insync.replicas=2 | grep -E "Created|rror" || echo "建立 topic 失敗"
}

# 某 topic 分區 0 的 leader 是哪一個 broker 容器(例如 broker2)。
leader_container() {
  local id; id=$(kafka_topics --describe --topic "$1" | grep -o 'Leader: [0-9]*' | head -1 | awk '{print $2}')
  echo "broker$((id - 10))"
}

# 等某個容器出現(最多 60 秒)。
container_running() { docker ps --format '{{.Names}}' | grep -qx "$1"; }

# 從 Counter 的輸出取「重複=N」的 N。
dup_of() { echo "$1" | grep -o ' 重複=[0-9]*' | head -1 | cut -d= -f2; }   # 前面的空白不能省:否則會先匹配到「不重複=」

# 一輪冪等實驗:一邊送 1500 筆(每秒 200),一邊把 leader broker 暫停 5 秒,最後數重複。
#   結果存在 /tmp/app-prod.out(producer 的回報)與 /tmp/app-count.out(Counter 的數量)。
#   用法:idempotent_round <topic> <true|false>
idempotent_round() {
  local topic="$1" idem="$2" leader
  app_topic "$topic" 1 >/dev/null
  leader=$(leader_container "$topic")
  run_app app-prod Producer "$topic" 1500 200 "$idem" 2000 > /tmp/app-prod.out 2>&1 &
  wait_until "producer 容器啟動" 60 container_running app-prod >/dev/null
  sleep 4                                           # 等 JVM 編譯完、開始送資料
  echo "  暫停 $leader(leader)5 秒,模擬網路卡住 / 程序凍結"
  docker pause "$leader" >/dev/null; sleep 5; docker unpause "$leader" >/dev/null
  wait
  run_app app-count Counter "$topic" read_committed > /tmp/app-count.out
  echo "  $(cat /tmp/app-prod.out)"; echo "  $(cat /tmp/app-count.out)"
}

# ---------- 各個實驗 ----------

lab_idempotent() {
  say "準備:下載 JDK 映像與 Kafka jar(只有第一次)"
  apps_prepare
  say "送 1500 筆(acks=all、retries 無限、request.timeout=2 秒),送到一半把 leader broker 暫停 5 秒。逾時的請求會重送——但原本那個請求其實已經到了 broker"
  local tries=0 dup_off=0 dup_on
  echo "【關閉冪等 enable.idempotence=false】"
  while [ "$tries" -lt 3 ]; do
    tries=$((tries + 1)); echo " 第 $tries 次:"
    idempotent_round app.idem.off false
    dup_off=$(dup_of "$(cat /tmp/app-count.out)"); [ "${dup_off:-0}" -gt 0 ] && break
  done
  echo "【開啟冪等 enable.idempotence=true】"
  idempotent_round app.idem.on true
  dup_on=$(dup_of "$(cat /tmp/app-count.out)")
  [ "${dup_off:-0}" -gt 0 ] && [ "${dup_on:-1}" = 0 ]     && verdict "關閉冪等時逾時重送寫出 ${dup_off} 筆重複;開啟冪等後重複為 0(producer 用序號讓 broker 丟掉重送的批次)"
}

lab_atleast() {
  apps_prepare
  say "先造一個有 1000 筆的 topic(冪等 producer),再用手動提交的 consumer:第一次處理 100 筆後在提交前當機"
  local group; group="g-alo-$(date +%s)"; local r1 r2 r3
  app_topic app.alo 1 >/dev/null
  run_app app-prod Producer app.alo 1000 1000 true 2000 >/dev/null
  echo "第 1 次(處理 100 筆,提交前當機):"; r1=$(run_app app-alo AtLeastOnce app.alo "$group" 100 crash-before-commit); echo "$r1" | sed 's/^/  /'
  say "重啟同一個 group:因為 offset 沒提交,會從頭再處理一次"
  echo "第 2 次(重啟,處理 100 筆後提交):"; r2=$(run_app app-alo AtLeastOnce app.alo "$group" 100 commit-after); echo "$r2" | sed 's/^/  /'
  echo "第 3 次(再啟動,處理 100 筆後提交):"; r3=$(run_app app-alo AtLeastOnce app.alo "$group" 100 commit-after); echo "$r3" | sed 's/^/  /'
  echo "$r1" | grep -q "id-0 到 id-99" && echo "$r2" | grep -q "id-0 到 id-99" && echo "$r3" | grep -q "id-100 到 id-199" \
    && verdict "處理後、提交前當機:重啟後同一批 100 筆(id-0 到 id-99)被重複處理;提交之後才往前(id-100 起)。應用程式的處理必須能容許重複(冪等或去重)"
}

lab_rebalance() {
  apps_prepare
  say "6 分區的 topic,c1 先加入群組(拿到全部 6 個分區),過一會 c2 加入。比較兩種分配策略下 c1 的事件"
  app_topic app.reb 6 >/dev/null
  local mode revoked_eager revoked_coop
  for mode in eager cooperative; do
    echo "【$mode】c1 的事件(REVOKED = 被收回、ASSIGNED = 被指派):"
    (run_app app-c1 RebalanceWatch app.reb "g-reb-$mode" "$mode" 45 c1 > /tmp/app-c1-$mode.out 2>&1) &
    wait_until "c1 啟動" 60 container_running app-c1 >/dev/null
    sleep 18
    run_app app-c2 RebalanceWatch app.reb "g-reb-$mode" "$mode" 20 c2 > /tmp/app-c2-$mode.out 2>&1
    wait
    sed 's/^/  /' /tmp/app-c1-$mode.out
  done
  revoked_eager=$(grep -m1 "REVOKED" /tmp/app-c1-eager.out | sed 's/.*REVOKED *//' | tr -cd '0-9' | wc -c)
  revoked_coop=$(grep -m1 "REVOKED" /tmp/app-c1-cooperative.out | sed 's/.*REVOKED *//' | tr -cd '0-9' | wc -c)
  echo "c2 加入時,c1 第一次被收回的分區數:eager $revoked_eager 個、cooperative $revoked_coop 個"
  [ "$revoked_eager" = 6 ] && [ "$revoked_coop" = 3 ] \
    && verdict "c2 加入時,eager 收回全部 6 個分區(整個群組暫停再重分配);cooperative 只收回要交給 c2 的 3 個,其餘持續消費"
}

lab_static() {
  apps_prepare
  say "c1 先跑;c2 加入後正常結束、再重啟一次(模擬應用程式滾動更新)。比較 c2 用動態成員與靜態成員(group.instance.id)時,c1 經歷幾次 rebalance"
  app_topic app.reb 6 >/dev/null
  local mode n_dyn n_static
  for mode in dynamic static; do
    local id2=""; [ "$mode" = static ] && id2=c2
    echo "【c2 是${mode}成員】c1 的事件:"
    (run_app app-c1 RebalanceWatch app.reb "g-st-$mode" cooperative 60 c1 > /tmp/app-c1-$mode.out 2>&1) &
    wait_until "c1 啟動" 60 container_running app-c1 >/dev/null
    sleep 14
    run_app app-c2 RebalanceWatch app.reb "g-st-$mode" cooperative 12 $id2 > /dev/null 2>&1
    run_app app-c2 RebalanceWatch app.reb "g-st-$mode" cooperative 12 $id2 > /dev/null 2>&1
    wait
    sed 's/^/  /' /tmp/app-c1-$mode.out
  done
  # 數 c1 在「c2 第一次加入之後、c1 自己結束之前」被收回分區的次數(最後一行是 c1 自己結束)
  n_dyn=$(grep -c "REVOKED" /tmp/app-c1-dynamic.out); n_static=$(grep -c "REVOKED" /tmp/app-c1-static.out)
  echo "c1 的 REVOKED 次數(含最後 c1 自己結束的那一次):動態 $n_dyn 次、靜態 $n_static 次"
  [ "$n_dyn" -gt "$n_static" ] && [ "$n_static" = 2 ] \
    && verdict "c2 重啟時:動態成員讓 c1 多經歷 rebalance(離開一次、重新加入一次);靜態成員在 session.timeout 內重啟,c1 完全沒有感覺"
}

lab_txn() {
  apps_prepare
  say "交易 producer 各寫 10 筆:一個 commit、一個 abort。再用兩種隔離等級的 consumer 數筆數"
  local rc ru
  app_topic app.txn 1 >/dev/null
  run_app app-t TxnProducer app.txn 10 commit ok
  run_app app-t TxnProducer app.txn 10 abort bad
  rc=$(run_app app-count Counter app.txn read_committed); echo "$rc"
  ru=$(run_app app-count Counter app.txn read_uncommitted); echo "$ru"
  echo "$rc" | grep -q "總筆數=10 " && echo "$ru" | grep -q "總筆數=20 " \
    && verdict "abort 的 10 筆仍寫在 log 裡:read_committed 看不到(只讀到 commit 的 10 筆),read_uncommitted 看得到(20 筆)。要用交易的 consumer 一定要設 read_committed"
}

case "${1:-}" in
  idempotent) lab_idempotent ;;
  atleast)    lab_atleast ;;
  rebalance)  lab_rebalance ;;
  static)     lab_static ;;
  txn)        lab_txn ;;
  *)          usage_from_header "$0"; exit 1 ;;
esac
