#!/usr/bin/env bash
# 以 client 憑證向 MDS 換 token(GET /security/1.0/authenticate)—— C3 自己的服務身分就是這樣取得 token 的。
# 用法: scripts/mds-token.sh <憑證名稱>            印出 token(給其他指令用,請勿外流)
#       scripts/mds-token.sh <憑證名稱> claims     印出 token 內容(claims,不印 token 本身)
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
