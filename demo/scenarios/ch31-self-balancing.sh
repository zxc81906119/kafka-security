#!/usr/bin/env bash
# ============================================================================
# ch31-self-balancing.sh — 第 31 章:Self-Balancing(自動搬分區):加 broker、負載不均、移除 broker
# ----------------------------------------------------------------------------
# 白話:第 24 章是人工搬分區。Self-Balancing 是 Confluent 內建的自動版:新 broker 加進來自己搬、要下線一台下一個指令就搬走並關機。
#   這一章驗證它「會動」與「不會動」的情況,以及移除 broker 的完整過程。
# 前置條件:叢集已啟動(scripts/up.sh);第一步會執行 scripts/sbc-setup.sh on(依序重建 controller 與 broker)
# 用法:
#   ./demo.sh 31                  經由講解控制台跑這一章(DEMO_PAUSE=0 不暫停)
#   ./scenarios/ch31-self-balancing.sh    直接跑
# 會改動什麼:.env 加 SBC_ENABLE=true;controller 與 broker 依序重建;啟動與移除 broker5(node id 15);建立 topic sbc.data、cap.skew。
#   結束後保留 SBC 啟用狀態(scripts/sbc-setup.sh off 還原)。整章約 40 分鐘(等待 Self-Balancing 蒐集指標占大部分)。
# 怎麼判斷成功:每一步印「✔ 符合預期」,最後一行「第 31 章完成(失敗 0 項)」
# 實測結果摘要:
#   KRaft 下 balancer 跑在 active controller,controller 也要設 confluent.balancer.enable 與 inter.broker.listener.name
#   (只動態開 broker 狀態仍是 DISABLED;controller 沒設 listener 會丟 IllegalArgumentException);
#   加入空 broker:等指標視窗後自動搬副本,20000 筆 acks=all 寫入全成功;kafka-remove-brokers 約 2 分鐘搬完並關機,筆數不變;
#   新建 topic 後約 18 分鐘內(要 6 個有效指標視窗)加 / 移除 broker 的計畫算不出來,所以負載不均放在最後;資料量小不觸發負載不均
# ============================================================================
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch31 "Self-Balancing:自動搬分區(加 broker、負載不均、移除 broker)"
SS="$DEMO_ROOT/scripts/sbc-setup.sh"
SL="$DEMO_ROOT/scripts/sbc-lab.sh"

step sbc-on "【啟用】SBC_ENABLE=true,controller 與 broker 依序重建(controller 也要設 balancer.enable 與 inter.broker.listener.name)" \
  "scripts/sbc-setup.sh on" \
  'bash "$SS" on 2>&1 | tail -3' '\[sbc\] 完成'

step sbc-status "【狀態】balancer 啟用、跑在 active controller、觸發條件" \
  "kafka-rebalance-cluster --status / --describe" \
  'bash "$SL" status 2>&1' '判定:balancer 已啟用'

step sbc-add "【加 broker】啟動空的 broker5:等指標視窗後自動搬副本,搬家期間寫入不中斷" \
  "docker compose --profile sbc up -d broker5;等新 broker 取得副本" \
  'bash "$SL" add 2>&1' '判定:空的新 broker 自動取得副本'

step sbc-remove "【移除 broker】kafka-remove-brokers --delete:副本搬走、筆數不變、broker 自動關機" \
  "kafka-remove-brokers --broker-id 15 --delete / --describe" \
  'bash "$SL" remove 2>&1' '判定:broker 15 的副本全部搬走'

step sbc-uneven "【負載不均】資料量低於官方觸發門檻:偵測器判定沒有違反目標,不搬" \
  "scripts/reassign-lab.sh skew;看 GoalViolationDetector 日誌" \
  'bash "$SL" uneven 2>&1' '判定:資料量低於官方觸發門檻'

ch_end
