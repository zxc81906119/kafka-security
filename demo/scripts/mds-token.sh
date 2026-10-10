#!/usr/bin/env bash
# ============================================================================
# mds-token.sh — 以 client 憑證向 MDS 換 token(GET /security/1.0/authenticate)
# ----------------------------------------------------------------------------
# 白話:C3 自己的服務身分就是這樣取得 token 的。c3-api-check.sh 等腳本也靠它取 token。
# 前置條件:demo 環境已啟動(scripts/up.sh),certs/ 內有 client-<憑證名稱> 憑證
# 用法:
#   scripts/mds-token.sh <憑證名稱>            印出 token(給其他指令用,請勿外流)
#   scripts/mds-token.sh <憑證名稱> claims     印出 token 內容(claims,不印 token 本身)
# 會改動什麼:什麼都不改(只向 MDS 要 token)。
# 怎麼判斷成功:token 模式印出一串 token;claims 模式印 JSON;結束碼 0。
# 常見失敗:印「(取得 token 失敗)」(結束碼 1)→ 憑證不存在或 MDS 不接受
# ============================================================================
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
cert="$1"; mode="${2:-token}"
tok=$(./scripts/dcurl.sh --cert "/certs/client-$cert.pem" --key "/certs/client-$cert.key" -H 'Accept: application/json' \
  https://broker1:8091/security/1.0/authenticate | grep -o '"auth_token":"[^"]*"' | cut -d'"' -f4)
[ -z "$tok" ] && { echo "(取得 token 失敗)"; exit 1; }
if [ "$mode" = claims ]; then
  printf '%s' "$tok" | cut -d. -f2 | tr '_-' '/+' | awk '{ while (length($0) % 4) $0 = $0 "="; print }' | base64 -d 2>/dev/null; echo
else
  printf '%s' "$tok"
fi
