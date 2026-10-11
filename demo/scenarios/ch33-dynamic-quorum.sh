#!/usr/bin/env bash
# ============================================================================
# ch33-dynamic-quorum.sh — 第 33 章:動態 quorum(靜態 → 動態、不停機汰換壞掉的 controller)
# ----------------------------------------------------------------------------
# 白話:靜態 quorum 的 controller 名單寫在每台的設定檔;換一台壞掉的 controller 要改全部設定並全部重啟。
#   動態 quorum 把名單放進叢集 metadata,換 controller 是「新的加進來、舊的移出去」兩個指令。官方建議正式環境用動態 quorum。
#   這一章從 demo 的靜態 quorum 升級成動態,再模擬一台 controller 主機損壞並汰換。
# 前置條件:HA 模式且是全新環境(scripts/ha.sh on);這一章會永久改變 voter 名單(3 換成 4),做完建議 scripts/ha.sh on 重建。
# 用法:
#   ./demo.sh 33                  經由講解控制台跑這一章(DEMO_PAUSE=0 不暫停)
#   ./scenarios/ch33-dynamic-quorum.sh    直接跑
# 會改動什麼:.env 的 COMPOSE_FILE 多 docker-compose.dynq.yml;controller 與 broker 依序重建;停 controller3、controller1(結束前啟動回來);
#   啟動 controller4(profile quorum);建立 topic quorum.t、quorum.after。整章約 12 分鐘。
# 怎麼判斷成功:每一步印「✔ 符合預期」,最後一行「第 33 章完成(失敗 0 項)」
# 實測結果摘要:見各步驟證據檔(evidence/ch33)
# ============================================================================
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch33 "動態 quorum:靜態 → 動態、汰換壞掉的 controller"
QL="$DEMO_ROOT/scripts/quorum-lab.sh"

step quorum-status "【現況】靜態 quorum:kraft.version=0,voter 名單來自設定檔,沒有 directory id" \
  "kafka-features describe;kafka-metadata-quorum describe --status" \
  'bash "$QL" status 2>&1' '判定:目前是 靜態 quorum'

step quorum-upgrade "【升級】kraft.version=1、設定改成 bootstrap.servers、controller 一台一台重啟,背景持續寫入" \
  "kafka-features upgrade --feature kraft.version=1;docker-compose.dynq.yml;依序重啟" \
  'bash "$QL" upgrade 2>&1' '判定:靜態 → 動態完成'

step quorum-replace "【汰換】停 controller3 → 全新 controller4 加入 → 移出 controller3;再停 controller1 驗證新名單可服務" \
  "kafka-metadata-quorum add-controller / remove-controller" \
  'bash "$QL" replace 2>&1' '判定:控制器汰換完成'

ch_end
