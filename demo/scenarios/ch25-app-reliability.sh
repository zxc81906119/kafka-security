#!/usr/bin/env bash
# 第 25 章(進階):應用程式端的可靠性——冪等 producer、at-least-once、rebalance、靜態成員、交易
# 需要 HA 模式(scripts/ha.sh on);第一次執行會下載 JDK 映像(eclipse-temurin:21-jdk,約 740 MB)並複製 Kafka jar 到 Docker volume
# 實測結果摘要:
#   冪等:broker 暫停 5 秒造成逾時重送,關閉冪等寫出 5 筆重複(1500 → 1505),開啟冪等 0 筆重複
#   at-least-once:處理後、提交前當機,重啟後同一批 100 筆被再處理一次
#   rebalance:c2 加入時 eager 收回全部 6 個分區,cooperative 只收回 3 個
#   靜態成員:成員重啟時動態成員讓 c1 多經歷兩次 rebalance,靜態成員 0 次
#   交易:abort 的 10 筆 read_committed 看不到、read_uncommitted 看得到
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch25 "應用程式端的可靠性:冪等、重複處理、rebalance、交易"
AL="$DEMO_ROOT/scripts/app-lab.sh"

step app-idempotent "【冪等 producer】送 1500 筆時把 leader broker 暫停 5 秒,逾時的請求會重送:關閉冪等會寫出重複訊息,開啟冪等則不會" \
  "java Producer.java <topic> 1500 200 false|true;docker pause <leader>;java Counter.java" \
  'bash "$AL" idempotent 2>&1' '判定:關閉冪等時逾時重送寫出'

step app-atleast "【at-least-once】手動提交 offset:處理完 100 筆、提交之前當機,重啟後同一批 100 筆被重複處理" \
  "java AtLeastOnce.java <topic> <group> 100 crash-before-commit;再啟動兩次" \
  'bash "$AL" atleast 2>&1' '判定:處理後、提交前當機'

step app-rebalance "【rebalance】6 分區、c1 先加入,c2 後加入:eager 收回全部分區,cooperative 只收回要換人的分區" \
  "java RebalanceWatch.java <topic> <group> eager|cooperative <秒> <成員 id>" \
  'bash "$AL" rebalance 2>&1' '判定:c2 加入時,eager 收回全部'

step app-static "【靜態成員】c2 滾動重啟:動態成員每次都觸發 rebalance;設定 group.instance.id 的靜態成員在 session.timeout 內重啟不會" \
  "java RebalanceWatch.java <topic> <group> cooperative <秒> c2(靜態)/ 不給 id(動態)" \
  'bash "$AL" static 2>&1' '判定:c2 重啟時'

step app-txn "【交易】commit 一批、abort 一批:read_committed 只看得到 commit 的,read_uncommitted 連 abort 的都看得到" \
  "java TxnProducer.java <topic> 10 commit|abort;java Counter.java <topic> read_committed|read_uncommitted" \
  'bash "$AL" txn 2>&1' '判定:abort 的 10 筆仍寫在 log 裡'

ch_end
