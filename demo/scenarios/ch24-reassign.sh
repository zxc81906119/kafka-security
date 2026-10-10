#!/usr/bin/env bash
# 第 24 章(進階):容量與再平衡——分區重新指派加限速
# 需要 HA 模式:scripts/ha.sh on(3 台 broker)
# 實測結果摘要:
#   造不均:6 分區 topic 的副本全放在 broker1、broker2(各約 200 MB),broker3 是空的
#   搬家:--generate 只是草稿(起點隨機、不刻意減少搬動量),正式執行審過的計畫;--execute --throttle 限速,背景寫入零失敗;--verify 完成後自動移除限速
#   取消:--cancel 讓搬到一半的搬家回到搬家前的副本配置,並清除限速
#   收尾:搬家完成後若不跑 --verify,broker 層與 topic 層的限速設定會殘留(之後任何複製流量都被限速)
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch24 "容量與再平衡:分區重新指派加限速"
RL="$DEMO_ROOT/scripts/reassign-lab.sh"

step reassign-skew "【造出不均】6 分區的 topic,所有副本只放在 broker1、broker2,寫入約 200 MB;broker3 是空的(新增 broker 之後就是這種狀態)" \
  "kafka-topics --create --replica-assignment …;kafka-producer-perf-test;kafka-log-dirs --describe" \
  'bash "$RL" skew 2>&1' '判定:資料全擠在 broker1、broker2'

step reassign-plan "【回退檔與計畫】先把目前的指派存成回退檔;看工具建議的新指派(--generate,只是草稿);寫出審過的均衡計畫" \
  "kafka-reassign-partitions --generate --topics-to-move-json-file … --broker-list 11,12,13" \
  'bash "$RL" plan 2>&1' '判定:已存回退檔'

step reassign-execute "【限速搬家】背景持續寫入 600 筆,同時限速 4 MB/s 搬家;--verify 追到完成並自動移除限速;三台 broker 的資料量變平均" \
  "kafka-reassign-partitions --execute --throttle 4000000;--verify;kafka-log-dirs" \
  'bash "$RL" execute 2>&1' '判定:限速搬家期間寫入零失敗'

step reassign-cancel "【取消搬家】以 1 MB/s 慢慢搬,搬到一半 --cancel:回到搬家前的副本配置,限速一併清除" \
  "kafka-reassign-partitions --execute --throttle 1000000;--cancel" \
  'bash "$RL" cancel 2>&1' '判定:--cancel 讓搬到一半的搬家回到搬家前的指派'

step reassign-leftover "【忘了收尾】搬家完成但不跑 --verify:限速設定殘留在 broker 與 topic;跑一次 --verify 才清掉" \
  "kafka-reassign-partitions --list;kafka-configs --describe(leader/follower.replication.throttled.*)" \
  'bash "$RL" leftover 2>&1' '判定:搬家完成但沒跑 --verify'

ch_end
