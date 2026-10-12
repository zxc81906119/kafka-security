#!/usr/bin/env bash
# ============================================================================
# ch34-watchdog.sh — 第 34 章:看門狗——監控自己壞掉時,誰會知道?
# ----------------------------------------------------------------------------
# 白話:Prometheus、Alertmanager 各只有一台。它們自己壞掉、或設定被改壞時,不會有任何告警送出——最危險的是「安靜」。
#   看門狗的做法:一條永遠在觸發的 Watchdog 告警當心跳,送到外部看門狗(代表行內既有的企業監控平台);心跳停了就是異常。
#   這一章實測三種失效:停 Prometheus、停 Alertmanager、元件都健康但設定錯(HA 也察覺不到的那種)。
# 前置條件:叢集已啟動(scripts/up.sh);第一步會執行 scripts/watchdog-setup.sh on(重啟 prometheus、alertmanager)。
# 冪等:是。第一步 scripts/chapter-start.sh 確認起點(本章不需要前面的章節),重跑結果相同。
# 用法:
#   ./demo.sh 34                  經由講解控制台跑這一章(DEMO_PAUSE=0 不暫停)
#   ./scenarios/ch34-watchdog.sh  直接跑
# 會改動什麼:啟動 watchdog 容器;Prometheus 加 Watchdog 規則、Alertmanager 加心跳路由(結束時保留;scripts/watchdog-setup.sh off 移除);
#   暫停並恢復 prometheus、alertmanager。整章約 20 分鐘(停 Prometheus 那一步要等告警過期)。
# 怎麼判斷成功:每一步印「✔ 符合預期」,最後一行「第 34 章完成(失敗 0 項)」
# ============================================================================
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch34 "看門狗:監控自己壞掉時,誰會知道"
WL="$DEMO_ROOT/scripts/watchdog-lab.sh"

step prepare "【起點準備】這一章不需要額外準備,確認環境可直接開始(冪等:可單獨從這一章開始,也可重跑)" \
  "scripts/chapter-start.sh ch34" \
  'bash "$DEMO_ROOT/scripts/chapter-start.sh" ch34 2>&1' '\[起點\] ch34 就緒'

step wd-setup "【啟用】Prometheus 加一條永遠在觸發的 Watchdog;Alertmanager 每 60 秒把它送到外部看門狗(HTTPS + Basic);看門狗 180 秒沒收到就判定失效" \
  "scripts/watchdog-setup.sh on" \
  'bash "$DEMO_ROOT/scripts/watchdog-setup.sh" on 2>&1 | tail -3; for i in $(seq 1 18); do s=$(bash "$DEMO_ROOT/scripts/watchdog-setup.sh" status); case "$s" in *\"OK\"*) break;; esac; sleep 10; done; echo "$s"' '"state": "OK"'

step wd-baseline "【正常】心跳正常,看門狗狀態 OK" \
  "scripts/watchdog-lab.sh baseline" \
  'bash "$WL" baseline 2>&1' '判定:看門狗狀態 OK'

step wd-stop-am "【Alertmanager 停了】告警算得出來但送不出去:心跳停止,看門狗判定監控鏈路失效" \
  "docker stop alertmanager;等看門狗判定失效;docker start alertmanager" \
  'bash "$WL" stop-am 2>&1' '判定:停 Alertmanager 後'

step wd-stop-prom "【Prometheus 停了】沒有人算規則:Alertmanager 手上的 Watchdog 要等過期才停止重送,所以發現得比較慢" \
  "docker stop prometheus;等看門狗判定失效;docker start prometheus" \
  'bash "$WL" stop-prom 2>&1' '判定:停 Prometheus 後'

step wd-misconfig "【設定錯了】Prometheus、Alertmanager 都健康(HA 不會切換),但送心跳的密碼設錯:只有看門狗發現得到" \
  "把 config/c3/watchdog-am.pw 改成錯的密碼;等看門狗判定失效;改回" \
  'bash "$WL" misconfig 2>&1' '判定:元件都健康、只是設定錯時'

ch_end
