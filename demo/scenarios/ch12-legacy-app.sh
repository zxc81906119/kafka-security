#!/usr/bin/env bash
# 第 12 章(進階):legacy app 只能用 HTTP → 經 REST Proxy 丟資料;人(Basic)與機器(client 憑證)並存,身分一路傳到 broker
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch12 "legacy app 經 REST Proxy:機器用 client 憑證,人用 Basic,並存"
source "$DEMO_ROOT/scripts/rbac-lib.sh"
UI() { (cd "$DEMO_ROOT/e2e" && node ch12-ui.mjs "$1" 2>&1 | grep -v '^$'); }
rpc() { "$DEMO_ROOT/scripts/rp-cert.sh" "$@"; }
BODY='{"records":[{"value":{"order":"L-1","by":"legacy-app"}}]}'

# ---- 起點狀態:清掉上次殘留 ----
rbac_unbind cert bootstrap User:legacy-orders DeveloperWrite Topic orders. PREFIXED >/dev/null
rbac_unbind cert bootstrap Group:orders-write DeveloperWrite Topic orders. PREFIXED >/dev/null
sleep 6

step issue-cert "【發憑證】legacy app 無法用 Kafka client → 發一張 client 憑證(CN = app 名稱 = RBAC 主體;由客戶的 CA 簽發)" \
  "openssl x509 -in client-legacy-orders.pem -noout -subject -issuer -dates" \
  'bash "$DEMO_ROOT/scripts/make-client-cert.sh" legacy-orders' 'subject=.*CN *= *legacy-orders'

step no-role "【授權前】憑證通過認證,但還沒有任何 role → 寫入被拒(403)" \
  "curl --cert client-legacy-orders.pem --key client-legacy-orders.key -X POST https://restproxy:8086/topics/orders.events -d '{...}'" \
  'rpc legacy-orders POST /topics/orders.events "$BODY"' 'HTTP 403'

step c3-assign "【C3 操作】gary 把 orders.* 寫入權限指派給「User:legacy-orders」(憑證身分只能綁 User:,不支援群組)" \
  "(瀏覽器)C3 → Manage role assignments → Topic → Add role assignment(User / legacy-orders / DeveloperWrite / orders.)" \
  'UI assign-legacy' 'c12-1-legacy-saved'
sleep 6

step ok "【授權後】legacy app 用憑證寫入 orders.events 成功(200)" \
  "curl --cert client-legacy-orders.pem ... -X POST https://restproxy:8086/topics/orders.events" \
  'rpc legacy-orders POST /topics/orders.events "$BODY"' 'HTTP 200'

step least-priv "【最小權限】同一個 app 寫 payments.events → 403" \
  "curl --cert client-legacy-orders.pem ... -X POST https://restproxy:8086/topics/payments.events" \
  'rpc legacy-orders POST /topics/payments.events "$BODY"' 'HTTP 403'

step no-cert "【沒憑證也沒帳密】→ 401" \
  "curl -X POST https://restproxy:8086/topics/orders.events" \
  'rpc none POST /topics/orders.events "$BODY"' 'HTTP 401'

bash "$DEMO_ROOT/scripts/make-client-cert.sh" legacy-other >/dev/null
step other-cert "【憑證有效但沒授權】同一個 CA 簽發的另一個 app(CN=legacy-other,沒有任何 role)→ 403" \
  "curl --cert client-legacy-other.pem ... -X POST https://restproxy:8086/topics/orders.events" \
  'rpc legacy-other POST /topics/orders.events "$BODY"' 'HTTP 403'

bash "$DEMO_ROOT/scripts/make-client-cert.sh" rogue --self-signed >/dev/null
step rogue-cert "【偽造憑證】自簽、非客戶 CA 簽發(連 CN 都寫 legacy-orders)→ TLS 握手就被拒(HTTP 000)" \
  "curl --cert client-rogue.pem ... https://restproxy:8086/topics/orders.events" \
  'rpc rogue POST /topics/orders.events "$BODY"' 'HTTP 000'

# 人與機器並存:同一個 REST Proxy,人照常用 Basic(AD 帳密)
rbac_bind cert bootstrap Group:orders-write DeveloperWrite Topic orders. PREFIXED >/dev/null
sleep 6
step human "【並存】同一個 REST Proxy,人(yujie)照常用 Basic(AD 帳密)→ 200" \
  "curl -u yujie:*** -X POST https://restproxy:8086/topics/orders.events" \
  'mds basic gary:gary-pw POST /security/1.0/principals/Group%3Aorders-write/roles/DeveloperWrite/bindings "{\"scope\":{\"clusters\":{\"kafka-cluster\":\"XyZBQ3-GTvKH2qNfP7X33A\"}},\"resourcePatterns\":[{\"resourceType\":\"Topic\",\"name\":\"orders.\",\"patternType\":\"PREFIXED\"}]}"; sleep 6; rp yujie:yujie-pw POST /topics/orders.events "{\"records\":[{\"value\":{\"order\":\"H-1\",\"by\":\"yujie\"}}]}"' 'HTTP 200'

echo "    (等待 audit log …)"; sleep 10
step audit "【稽核】broker 端看到的主體是 User:legacy-orders(不是 restproxy);人是 User:YUJIE" \
  "kafka-console-consumer --topic confluent-audit-log-events | 整理" \
  'audit_events --topic "^(orders|payments)\." --last 40 | grep -E "legacy|yujie" | tail -8' 'User:legacy-orders.*ALLOWED'

step mds-log "【MDS 日誌】人與機器走的路不同:人 → /authenticate(MDS 看到 yujie);機器 → /impersonate(MDS 看到 restproxy 代 legacy-orders 申請)" \
  "docker logs broker | grep -E \"/security/1.0/(authenticate|impersonate)\"" \
  'bash "$DEMO_ROOT/scripts/mds-calls.sh"' 'impersonate .*restproxy'

step token "【代為申請的 token】restproxy 的憑證向 MDS 申請「代 legacy-orders」的 token:sub 是 legacy-orders,cp_proxy 記錄代理者,有效 1 小時" \
  "POST /security/1.0/impersonate  {targetPrincipalName: legacy-orders}   (憑證 CN=restproxy)" \
  'bash "$DEMO_ROOT/scripts/mds-impersonate.sh" restproxy legacy-orders claims' 'cp_proxy'

step impersonate-scope "【風險】REST Proxy 的憑證能代誰?一般使用者可以;受保護清單內的特權身分(GARY、c3、bootstrap)不行;不是 impersonation 超級使用者的憑證(c3 的憑證)也不行。注意:清單區分大小寫,要寫 AD 記錄的 User:GARY;寫成 User:gary 擋不住 GARY(實測踩過)" \
  "POST /security/1.0/impersonate(憑證 CN=restproxy / c3;目標 yujie、legacy-orders、GARY、bootstrap)" \
  'for t in yujie legacy-orders GARY c3 bootstrap; do printf "restproxy 憑證代 %-14s → HTTP " $t; bash "$DEMO_ROOT/scripts/mds-impersonate.sh" restproxy $t; done; printf "c3 憑證代 %-19s → HTTP " yujie; bash "$DEMO_ROOT/scripts/mds-impersonate.sh" c3 yujie' 'GARY +→ HTTP 403'

# 清理
rbac_unbind cert bootstrap User:legacy-orders DeveloperWrite Topic orders. PREFIXED >/dev/null
rbac_unbind cert bootstrap Group:orders-write DeveloperWrite Topic orders. PREFIXED >/dev/null
ch_end
