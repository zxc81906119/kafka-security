#!/usr/bin/env bash
# ============================================================================
# ch15-offboarding.sh — 第 15 章:人員異動:AD 收回群組後,已發出的 token 失去權限
# ----------------------------------------------------------------------------
# 白話:員工離職或調職時,只要在 AD 把他移出群組,他手上已發出且尚未到期的 MDS token 也會立刻失去權限。
#   因為授權是依「現在的群組」判斷,不是依發 token 當下;Kafka 與 token 本身都不用動。
# 前置條件:環境已建好(AD、MDS、REST Proxy)
# 用法:
#   ./demo.sh 15                  經由講解控制台跑這一章
#   ./scenarios/ch15-offboarding.sh      直接跑(DEMO_PAUSE=0 不暫停)
# 會改動什麼:開頭確保 yujie 在 orders-write,並綁 Group:orders-write 對 orders. 的 DeveloperWrite 與 DeveloperRead;中途把 yujie 移出 orders-write;暫存 token 於 demo/.tok-yujie。
#   結束前:刪除 .tok-yujie、把 yujie 加回 orders-write、解除上述兩條 role binding。
# 怎麼判斷成功:每一步印『✔ 符合預期』,最後一行『第 15 章完成(失敗 0 項)』
# 實測結果摘要:yujie 取得的 token 是 JWT,效期 1 小時,sub 為 YUJIE
#   收回前用該 token 寫入 200;AD 移出群組(等群組快取刷新約 12 秒)後,同一個未到期的 token 再寫入 403
#   帳號仍在 AD 時還是能登入(HTTP 200),只是沒有任何 role、看不到業務 topic
# ============================================================================
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
