#!/usr/bin/env bash
# 第 15 章(進階):人員異動/離職 —— AD 群組一收回,已發出的 MDS token 立刻失去權限(token 本身未到期)
source "$(dirname "$0")/../scripts/lib-ev.sh"
source "$DEMO_ROOT/scripts/rbac-lib.sh"
ch_begin ch15 "人員異動:AD 收回群組後,已發出的 token 失去權限"
DC="$DEMO_ROOT/scripts/dcurl.sh"
BODY='{"records":[{"value":{"order":"offboard-1"}}]}'
HDR=(-H "Accept: application/vnd.kafka.v2+json" -H "Content-Type: application/vnd.kafka.json.v2+json")
brief() { grep -o -E '"error_code":[0-9]+|"offsets":\[[^]]*\]|\[HTTP [0-9]+\]' | awk '!s[$0]++' | tr '\n' ' '; echo; }

# 前置(不顯示):yujie 在 orders-write,並授權該群組寫 orders.*
./scripts/ldap-group.sh add yujie orders-write >/dev/null 2>&1 || true
rbac_bind cert bootstrap Group:orders-write DeveloperWrite Topic orders. PREFIXED >/dev/null
rbac_bind cert bootstrap Group:orders-write DeveloperRead Topic orders. PREFIXED >/dev/null
sleep 12

step issue "【發 token】yujie 以 AD 帳密向 MDS 登入,拿到 token(JWT,效期 1 小時,尚未到期)" \
  "curl -u yujie:*** https://broker1:8091/security/1.0/authenticate    # 取得 auth_token" \
  'T=$(bash "$DC" -u yujie:yujie-pw -H "Accept: application/json" https://broker1:8091/security/1.0/authenticate | grep -o "\"auth_token\":\"[^\"]*\"" | cut -d\" -f4); echo "$T" > "$DEMO_ROOT/.tok-yujie"; printf "%s" "$T" | cut -d. -f2 | tr "_-" "/+" | awk "{ while (length(\$0) % 4) \$0 = \$0 \"=\"; print }" | base64 -d 2>/dev/null | grep -o -E "\"sub\":\"[^\"]*\"|\"exp\":[0-9]+|\"iat\":[0-9]+" | tr "\n" " "; echo' '"sub":"YUJIE"'

step ok "【收回前】拿這個 token(Bearer)寫入 → 成功(他的權限來自 AD 群組)" \
  "curl -H 'Authorization: Bearer <token>' -X POST https://restproxy:8086/topics/orders.events -d '{...}'" \
  'bash "$DC" -H "Authorization: Bearer $(cat "$DEMO_ROOT/.tok-yujie")" "${HDR[@]}" -X POST https://restproxy:8086/topics/orders.events -d "$BODY" | brief' '"offsets".*\[HTTP 200\]'

step revoke "【AD 收回】把 yujie 移出 orders-write(只在 AD 操作,Kafka 與 token 都沒動)" \
  "ldapmodify: cn=orders-write 刪除 member CN=YUJIE" \
  './scripts/ldap-group.sh remove yujie orders-write; sleep 12; echo "已移出群組並等待群組快取刷新"' '已移出群組'

step denied "【收回後】同一個 token(還沒到期)再寫入 → 403:授權依「現在的群組」判斷,不是依發 token 當下" \
  "curl -H 'Authorization: Bearer <同一個 token>' -X POST https://restproxy:8086/topics/orders.events -d '{...}'" \
  'bash "$DC" -H "Authorization: Bearer $(cat "$DEMO_ROOT/.tok-yujie")" "${HDR[@]}" -X POST https://restproxy:8086/topics/orders.events -d "$BODY" | brief' '40301.*\[HTTP 403\]|\[HTTP 403\]'

step login "【帳號仍在 AD】他還是能登入(AD 帳號沒停用),只是沒有任何 role → 看不到業務 topic" \
  "curl -u yujie:*** https://restproxy:8086/topics" \
  'bash "$DEMO_ROOT/scripts/rp.sh" yujie:yujie-pw GET /topics | grep -o -E "\"orders[^\"]*\"|\[HTTP [0-9]+\]" | tr "\n" " "; echo' '\[HTTP 200\]'

# 清理
rm -f "$DEMO_ROOT/.tok-yujie"
./scripts/ldap-group.sh add yujie orders-write >/dev/null 2>&1 || true
rbac_unbind cert bootstrap Group:orders-write DeveloperWrite Topic orders. PREFIXED >/dev/null
rbac_unbind cert bootstrap Group:orders-write DeveloperRead Topic orders. PREFIXED >/dev/null
ch_end
