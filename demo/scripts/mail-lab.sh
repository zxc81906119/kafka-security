#!/usr/bin/env bash
# ============================================================================
# mail-lab.sh — 第 30 章:告警寄成信(Alertmanager → 郵件伺服器)
# ----------------------------------------------------------------------------
# 白話:告警只在 Prometheus 與 Alertmanager 亮燈,值班的人看不到。這支腳本實際驗證:
#   告警真的變成信、依嚴重度寄給不同的人、同類告警合併成一封不會洗版、真的壞一台 broker 會收到「發生」與「解除」兩封,
#   以及郵件伺服器本身有沒有被保護(強制 STARTTLS、要帳密)。
# 前置條件:HA 模式(或基礎環境)、Prometheus 與 Alertmanager 已啟動,並已執行 scripts/mail-setup.sh on
# 用法:
#   scripts/mail-lab.sh send      送一個測試告警,收件匣收到一封;主旨、收件人、內文正確
#   scripts/mail-lab.sh route     critical 寄給值班信箱,warning 寄給維運群組信箱
#   scripts/mail-lab.sh group     同一種告警的多個實例合併成一封
#   scripts/mail-lab.sh real      停 1 台 broker → 收到「FIRING」;恢復 → 收到「RESOLVED」(需要 HA 模式的 JMX 告警規則)
#   scripts/mail-lab.sh security  郵件伺服器:不 STARTTLS、沒帳密、錯密碼都被拒,正確帳密才收
# 會改動什麼:清空測試郵件伺服器的收件匣;向 Alertmanager 送測試告警(自動過期);real 會暫時停止 broker3(結束前啟動回來)。
# 怎麼判斷成功:最後一行印「判定:…」。
# 常見失敗:收不到信 → docker logs alertmanager(常見:SMTP 驗證失敗、憑證不被信任);group_wait 與規則評估都有延遲,腳本最多等 2 分鐘
# ============================================================================
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/prom.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/kafka.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR" || exit 1
need_container mailpit "先執行:scripts/mail-setup.sh on"
need_container alertmanager "先執行:docker compose --profile c3 up -d prometheus alertmanager"

MAIL_UI=https://mailpit:8025
MAIL_UI_AUTH="ops:$(cat config/mail/ui.pw)"
SMTP_PW=$(cat config/mail/smtp.pw)

# ---------- 小工具(這支腳本專用) ----------

# 郵件伺服器網頁 API:mail_api <curl 參數…>(帶網頁帳密)。
mail_api() { dcurl -u "$MAIL_UI_AUTH" "$@" 2>/dev/null; }

# 清空收件匣。
mail_clear() { mail_api -X DELETE "$MAIL_UI/api/v1/messages" >/dev/null; }

# 列出收件匣:每封一行「主旨 | 收件人 | 內文開頭」。
mail_list() { mail_api "$MAIL_UI/api/v1/messages?limit=50" | node "$LIB_DIR/mailpit-list.mjs"; }

# 收件匣有幾封信。
mail_count() { mail_list | grep -c . ; }

# 給 wait_until 用:收件匣至少有 N 封信。
mail_at_least() { [ "$(mail_count)" -ge "$1" ]; }

# 給 wait_until 用:收件匣裡有主旨含某字串的信。
mail_has() { mail_list | grep -q -F -- "$1"; }

# 向 Alertmanager 送測試告警:send_alert <alertname> <severity> <instance> [存活秒數,預設 120]。
send_alert() {
  local ends; ends=$(date -u -d "+${4:-120} seconds" +%Y-%m-%dT%H:%M:%SZ)
  dcurl -u "$AM_AUTH" -X POST -H 'Content-Type: application/json' "$AM_URL/api/v2/alerts" \
    -d "[{\"labels\":{\"alertname\":\"$1\",\"severity\":\"$2\",\"instance\":\"$3\"},\"annotations\":{\"summary\":\"測試告警 $1 @ $3\"},\"endsAt\":\"$ends\"}]" 2>/dev/null | tail -1
}

# 用 curl 容器寄一封信到郵件伺服器,印出結果的第一個錯誤或「已接受」:smtp_try <選項…>(例如 --ssl-reqd、--user)。
smtp_try() {
  local out
  out=$(printf 'From: a@corp.demo\r\nTo: b@corp.demo\r\nSubject: smtp-test\r\n\r\nhello\r\n' \
    | docker run --rm -i --network cpsec_default -v "$DEMO_DIR/certs:/certs:ro" --entrypoint curl curlimages/curl:latest \
        -sS --cacert /certs/ca.pem --url smtp://mailpit:1025 --mail-from a@corp.demo --mail-rcpt b@corp.demo -T - "$@" 2>&1)
  if [ -z "$out" ]; then echo "已接受"; else echo "$out" | head -1 | cut -c1-120; fi
}

# ---------- 各個實驗 ----------

lab_send() {
  say "送一個 warning 測試告警給 Alertmanager;依設定等 group_wait(10 秒)後寄出,收件匣應該收到一封"
  mail_clear
  echo "送出測試告警:$(send_alert MailTest warning demo-1)"
  wait_until "收到主旨含 MailTest 的信" 90 mail_has "MailTest" || true
  echo "收件匣:"; mail_list | sed 's/^/  /'
  mail_list | grep -q "\[Kafka\]\[FIRING\] MailTest(warning) | kafka-ops@corp.demo" \
    && verdict "告警變成信:主旨「[Kafka][FIRING] MailTest(warning)」,寄給維運群組信箱 kafka-ops@corp.demo"
}

lab_route() {
  say "同時送 critical 與 warning 兩個告警:依嚴重度分流,critical 寄給值班信箱,warning 寄給維運群組信箱"
  mail_clear
  echo "critical:$(send_alert RouteCrit critical demo-1);warning:$(send_alert RouteWarn warning demo-1)"
  wait_until "兩封信都到" 90 mail_at_least 2 || true
  echo "收件匣:"; mail_list | sed 's/^/  /'
  mail_list | grep -q "RouteCrit | kafka-oncall@corp.demo" && mail_list | grep -q "RouteWarn(warning) | kafka-ops@corp.demo" \
    && verdict "依嚴重度分流:critical 只寄給值班信箱 kafka-oncall@corp.demo,warning 寄給維運群組信箱 kafka-ops@corp.demo"
}

lab_group() {
  say "同一種告警(GroupTest)同時在 3 個實例發生:依 group_by 合併成一封信,而不是三封"
  mail_clear
  send_alert GroupTest warning broker1 >/dev/null; send_alert GroupTest warning broker2 >/dev/null; send_alert GroupTest warning broker3 >/dev/null
  wait_until "收到 GroupTest 的信" 90 mail_has "GroupTest" || true
  sleep 20      # 多等一會:如果沒有合併,另外兩封也會陸續到
  local n; n=$(mail_list | grep -c "GroupTest")
  echo "收到 GroupTest 的信 $n 封"; mail_list | sed 's/^/  /'
  [ "$n" = 1 ] && verdict "3 個實例的同一種告警合併成 1 封信(group_by alertname、severity);一次壞多台不會洗版"
}

lab_real() {
  need_ha_mode
  say "真的停 broker3:JMX 告警 KafkaJmxUnderReplicatedPartitions(warning)觸發 → 寄出 FIRING;恢復後告警解除 → 寄出 RESOLVED"
  local fired=0 resolved=0
  mail_clear
  echo "停 broker3"; stop_containers broker3
  wait_until "收到 FIRING 信(最多 4 分鐘)" 240 mail_has "[FIRING] KafkaJmxUnderReplicatedPartitions" && fired=1
  echo "恢復 broker3"; start_containers broker3; wait_healthy broker3 >/dev/null
  wait_until "收到 RESOLVED 信(最多 6 分鐘)" 360 mail_has "[RESOLVED] KafkaJmxUnderReplicatedPartitions" && resolved=1
  echo "收件匣:"; mail_list | sed 's/^/  /'
  [ "$fired" = 1 ] && [ "$resolved" = 1 ] \
    && verdict "真實故障走完整條路徑:停 1 台 broker → Prometheus 規則 → Alertmanager → 郵件(FIRING),恢復後收到 RESOLVED"
}

lab_security() {
  say "郵件伺服器的保護:不用 STARTTLS 寄、有 STARTTLS 但沒帳密、錯密碼,都被拒;正確帳密才收"
  local a b c d
  a=$(smtp_try);                                                      echo "不用 TLS、沒帳密:$a"
  b=$(smtp_try --ssl-reqd);                                           echo "STARTTLS、沒帳密:$b"
  c=$(smtp_try --ssl-reqd --user "alertmanager:wrong-password");      echo "STARTTLS、錯密碼:$c"
  d=$(smtp_try --ssl-reqd --user "alertmanager:$SMTP_PW");            echo "STARTTLS、正確帳密:$d"
  echo "Alertmanager 的設定:密碼來源 $(grep -o 'smtp_auth_password_file: .*' config/c3/alertmanager-generated.yml | head -1)(設定檔裡沒有密碼本身)"
  mail_api -X DELETE "$MAIL_UI/api/v1/messages" >/dev/null
  [ "$a" != "已接受" ] && [ "$b" != "已接受" ] && [ "$c" != "已接受" ] && [ "$d" = "已接受" ] && ! grep -q 'smtp_auth_password:' config/c3/alertmanager-generated.yml \
    && verdict "郵件伺服器強制 STARTTLS 並要帳密(無 TLS、無帳密、錯密碼都被拒);Alertmanager 的密碼從檔案讀,設定檔裡沒有密碼"
}

case "${1:-}" in
  send)     lab_send ;;
  route)    lab_route ;;
  group)    lab_group ;;
  real)     lab_real ;;
  security) lab_security ;;
  *)        usage_from_header "$0"; exit 1 ;;
esac
