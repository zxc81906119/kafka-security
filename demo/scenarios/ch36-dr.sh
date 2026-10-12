#!/usr/bin/env bash
# ============================================================================
# ch36-dr.sh — 第 36 章:DR 與演練——整個機房掛掉時,切到 DR 站
# ----------------------------------------------------------------------------
# 白話:Cluster Linking 把主站的 topic 鏡像到 DR 站。這一章把 DR 演練做成可重複的腳本:主站一邊寫入一邊整站斷電 → DR 站 failover
#   → 應用程式改連 → 量測 RPO / RTO → 主站恢復後切回 → 產生演練紀錄(evidence/dr-drills/)。
# 前置條件:叢集已啟動(scripts/up.sh);DR 站約需 3 GB 記憶體(會暫停 Connect×2 與 Control Center,結束時恢復)。
# 冪等:是。第一步 scripts/chapter-start.sh 確認起點(本章不需要前面的章節),重跑結果相同。
# 用法:
#   ./demo.sh 36             經由講解控制台跑這一章(DEMO_PAUSE=0 不暫停)
#   ./scenarios/ch36-dr.sh   直接跑
# 會改動什麼:啟動 DR 站(dr-controller1、dr-broker1~3)並在結束時刪除;主站 topic dr.orders;主站的 broker 與 controller 會整站停止再恢復;
#   主站與 DR 站新增 link 用的 SCRAM 帳號與綁定。整章約 40 分鐘。
# 怎麼判斷成功:每一步印「✔ 符合預期」,最後一行「第 36 章完成(失敗 0 項)」
# ============================================================================
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch36 "DR 與演練:整個機房掛掉時,切到 DR 站"
DS="$DEMO_ROOT/scripts/dr-setup.sh"; DL="$DEMO_ROOT/scripts/dr-lab.sh"

step prepare "【起點準備】這一章不需要額外準備,確認環境可直接開始(冪等:可單獨從這一章開始,也可重跑)" \
  "scripts/chapter-start.sh ch36" \
  'bash "$DEMO_ROOT/scripts/chapter-start.sh" ch36 2>&1' '\[起點\] ch36 就緒'

step dr-setup "【建立 DR 站】縮小版(1 controller + 3 broker);DR 站主動連主站建立 Cluster Linking,link 身分是主站上只有讀取權限的 SCRAM 帳號" \
  "scripts/dr-setup.sh up;scripts/dr-setup.sh status" \
  'bash "$DS" up 2>&1 | tail -4; bash "$DS" status 2>&1' 'ACTIVE'

step dr-mirror "【鏡像】DR 站的 dr.orders 是主站的鏡像(唯讀);consumer group 的 offset 也同步過來" \
  "kafka-mirrors --create --mirror-topic dr.orders --link main-to-dr" \
  'bash "$DL" mirror 2>&1' '判定:DR 站鏡像與主站一致'

step dr-rbac "【授權不會跟著過去】RBAC 綁定存在各自的 MDS:DR 站要另外建,而且要在災難前就做好" \
  "yujie 在 DR 站讀 → 被拒;DR 站補建綁定 → 可讀" \
  'bash "$DL" rbac 2>&1' '判定:DR 站的授權要另外建立'

step dr-failover "【演練】主站一邊寫入一邊整站斷電 → DR 站 failover → 應用程式改連;量測 RPO 與 RTO" \
  "docker stop broker1~4 controller1~3;kafka-mirrors --failover --topics dr.orders;client 改連 DR 站" \
  'bash "$DL" failover 2>&1' '判定:主站斷電後'

step dr-failback "【切回】主站重建為 DR 站的鏡像 → 零落後 → promote → 應用程式改回主站 → DR 站恢復為主站的鏡像" \
  "kafka-cluster-links --create --link dr-to-main(在主站);kafka-mirrors --promote" \
  'bash "$DL" failback 2>&1' '判定:切回完成'

step dr-report "【演練紀錄】把量測值與演練清單寫成紀錄;刪除 DR 站、恢復 Connect 與 C3" \
  "scripts/dr-lab.sh report;scripts/dr-setup.sh down" \
  'bash "$DL" report 2>&1; bash "$DS" down 2>&1 | tail -1' '演練紀錄已產生'

ch_end
