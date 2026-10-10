#!/usr/bin/env bash
# ============================================================================
# mds-impersonate.sh — 以某張 client 憑證呼叫 MDS 的 impersonate 端點
# ----------------------------------------------------------------------------
# 白話:REST Proxy 代「機器」取得 token 時,就是呼叫這個 impersonate 端點。這支腳本用指定憑證直接打一次,
#   看 MDS 是否允許該憑證代指定的主體取 token。
# 前置條件:demo 環境已啟動(scripts/up.sh),certs/ 內有 client-<憑證名稱> 憑證
# 用法:
#   scripts/mds-impersonate.sh <憑證名稱> <要代的主體>            印出 HTTP 狀態碼
#   scripts/mds-impersonate.sh <憑證名稱> <要代的主體> claims    印出 token 內容(claims,不印 token 本身)
# 會改動什麼:什麼都不改(只向 MDS 要 token)。
# 怎麼判斷成功:預設模式印 HTTP 狀態碼(2xx 為成功);claims 模式印 JSON claims。
# 常見失敗:claims 模式印「(沒有 token,HTTP nnn)」(結束碼 1)→ MDS 沒有核發 token(多半是該憑證不被允許代這個主體)
# ============================================================================
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
