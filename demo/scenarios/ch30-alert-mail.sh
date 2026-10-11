#!/usr/bin/env bash
# ============================================================================
# ch30-alert-mail.sh — 第 30 章:告警寄成信(Alertmanager → 自架郵件伺服器)
# ----------------------------------------------------------------------------
# 白話:告警只在 Prometheus 與 Alertmanager 亮燈,半夜值班的人不會知道。這一章讓告警變成信寄給人,並驗證:依嚴重度分流、同類告警合併不洗版、真實故障有「發生」與「解除」兩封、郵件伺服器本身有被保護。demo 用 Mailpit 代替行內的郵件伺服器。
# 前置條件:HA 模式與 Prometheus、Alertmanager:scripts/ha.sh on --with-c3;docker compose --profile c3 up -d prometheus alertmanager blackbox-exporter
# 用法:
#   ./demo.sh 30                  經由講解控制台跑這一章(DEMO_PAUSE=0 不暫停)
#   ./scenarios/ch30-alert-mail.sh    直接跑
# 會改動什麼:啟動 mailpit 容器、把 config/c3/alertmanager-generated.yml 換成郵件版(原檔備份成 .orig)、重啟 alertmanager;real 步驟暫時停止 broker3(結束前啟動回來)。
# 怎麼判斷成功:每一步印「✔ 符合預期」,最後一行「第 30 章完成(失敗 0 項)」
# 實測結果摘要:
#   告警變成信(主旨 [Kafka][FIRING] 告警名稱(嚴重度));critical 寄值班信箱、warning 寄維運群組信箱;
#   同一種告警 3 個實例合併成 1 封;停 broker3 約 30 秒收到 FIRING、恢復後約 40 秒收到 RESOLVED;
#   郵件伺服器強制 STARTTLS 並要帳密,Alertmanager 的密碼從檔案讀
# ============================================================================
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch30 "告警寄成信:Alertmanager → 自架郵件伺服器"
MS="$DEMO_ROOT/scripts/mail-setup.sh"
ML="$DEMO_ROOT/scripts/mail-lab.sh"

step mail-on "【啟動】備妥郵件伺服器的帳密、啟動 mailpit(SMTP 強制 STARTTLS 並要帳密)、把 Alertmanager 換成郵件版設定(密碼從檔案讀、依嚴重度分流、同類合併)" \
  "scripts/mail-setup.sh on" \
  'bash "$MS" on 2>&1 | tail -2' '\[mail\] 完成'

step mail-send "【告警變成信】送一個測試告警,收件匣收到一封:主旨、收件人、內文正確" \
  "POST /api/v2/alerts(Alertmanager);GET /api/v1/messages(郵件伺服器)" \
  'bash "$ML" send 2>&1' '判定:告警變成信'

step mail-route "【依嚴重度分流】critical 寄給值班信箱,warning 寄給維運群組信箱" \
  "route.routes: severity=\"critical\" → oncall-critical" \
  'bash "$ML" route 2>&1' '判定:依嚴重度分流'

step mail-group "【同類合併】同一種告警在 3 個實例發生,只寄 1 封(group_by),不洗版" \
  "route.group_by: [alertname, severity]" \
  'bash "$ML" group 2>&1' '判定:3 個實例的同一種告警合併成 1 封信'

step mail-real "【真實故障】停 broker3 → URP 告警 → 收到 FIRING;恢復後收到 RESOLVED" \
  "docker stop broker3;等 FIRING 信;docker start broker3;等 RESOLVED 信" \
  'bash "$ML" real 2>&1' '判定:真實故障走完整條路徑'

step mail-security "【郵件伺服器的保護】不用 STARTTLS、沒帳密、錯密碼都被拒;正確帳密才收;Alertmanager 的密碼不在設定檔裡" \
  "curl smtp://mailpit:1025(--ssl-reqd、--user)" \
  'bash "$ML" security 2>&1' '判定:郵件伺服器強制 STARTTLS 並要帳密'

ch_end
