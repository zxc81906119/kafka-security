#!/usr/bin/env bash
# ============================================================================
# ch33-dynamic-quorum.sh — 第 33 章:動態 quorum(不停機汰換壞掉的 controller)
# ----------------------------------------------------------------------------
# 白話:這個叢集一開始就是動態 quorum(官方建議的正式環境做法):controller 名單存在叢集 metadata。換一台壞掉的 controller
#   只要「新的加進來、舊的移出去」兩個指令,不用改別台設定、不用重啟。這一章模擬一台 controller 主機損壞並汰換。
# 前置條件:全新環境(scripts/ha.sh on);這一章會永久改變 voter 名單(3 換成 4),做完建議 scripts/ha.sh on 重建。
# 用法:
#   ./demo.sh 33                  經由講解控制台跑這一章(DEMO_PAUSE=0 不暫停)
#   ./scenarios/ch33-dynamic-quorum.sh    直接跑
# 會改動什麼:停 controller3(永久移出名單)、controller1(結束前啟動回來);啟動 controller4(profile quorum);
#   建立 topic quorum.t、quorum.after。整章約 3 分鐘。
# 怎麼判斷成功:每一步印「✔ 符合預期」,最後一行「第 33 章完成(失敗 0 項)」
# 實測結果摘要:見各步驟證據檔(evidence/ch33)
# ============================================================================
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch33 "動態 quorum:汰換壞掉的 controller"
QL="$DEMO_ROOT/scripts/quorum-lab.sh"

step quorum-status "【現況】動態 quorum:kraft.version=1,3 個 voter 各有 directory id(controller 名單存在叢集 metadata)" \
  "kafka-features describe;kafka-metadata-quorum describe --status" \
  'bash "$QL" status 2>&1' '判定:目前是 動態 quorum'

step quorum-replace "【汰換】停 controller3 → 全新 controller4 加入 → 移出 controller3;再停 controller1 驗證新名單可服務" \
  "kafka-metadata-quorum add-controller / remove-controller" \
  'bash "$QL" replace 2>&1' '判定:控制器汰換完成'

ch_end
