#!/usr/bin/env bash
# 以某張 client 憑證呼叫 MDS 的 impersonate 端點(REST Proxy 代「機器」取得 token 的那個呼叫)。
# 用法: scripts/mds-impersonate.sh <憑證名稱> <要代的主體>            印出 HTTP 狀態碼
#       scripts/mds-impersonate.sh <憑證名稱> <要代的主體> claims    印出 token 內容(claims,不印 token 本身)
export MSYS_NO_PATHCONV=1
D="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
cert="$1"; target="$2"; mode="${3:-code}"
out=$(docker run --rm --network cpsec_default -v "$D/certs:/certs:ro" --entrypoint curl curlimages/curl:latest -s \
  --cacert /certs/ca.pem --cert "/certs/client-$cert.pem" --key "/certs/client-$cert.key" \
  -H 'Accept: application/json' -H 'Content-Type: application/json' -w '\n%{http_code}' \
  -X POST https://broker1:8091/security/1.0/impersonate \
  -d "{\"targetPrincipalName\":\"$target\",\"targetPrincipalType\":\"USER\"}")
code=$(printf '%s' "$out" | tail -1)
if [ "$mode" = claims ]; then
  tok=$(printf '%s' "$out" | grep -o '"auth_token":"[^"]*"' | cut -d'"' -f4)
  [ -z "$tok" ] && { echo "(沒有 token,HTTP $code)"; exit 1; }
  printf '%s' "$tok" | cut -d. -f2 | tr '_-' '/+' | awk '{ while (length($0) % 4) $0 = $0 "="; print }' | base64 -d 2>/dev/null; echo
else
  echo "$code"
fi
