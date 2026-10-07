#!/usr/bin/env bash
# 用 curl 容器呼叫 MDS REST(可用 client 憑證 mTLS 或 AD 帳密 Basic)。
# 用法:
#   scripts/mds.sh cert <name> <METHOD> <path> [json-body]     # 以 certs/client-<name>.pem 驗證(服務/平台元件身分)
#   scripts/mds.sh basic <user:pass> <METHOD> <path> [json-body]
export MSYS_NO_PATHCONV=1
D="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
mode="$1"; who="$2"; method="$3"; path="$4"; body="${5:-}"
MDS="${MDS_URL:-https://broker1:8091}"
args=(-s --cacert /certs/ca.pem -X "$method" -H "Content-Type: application/json" -w "\n[HTTP %{http_code}]\n")
if [ "$mode" = cert ]; then args+=(--cert "/certs/client-$who.pem" --key "/certs/client-$who.key"); else args+=(-u "$who"); fi
[ -n "$body" ] && args+=(-d "$body")
exec docker run --rm --network cpsec_default -v "$D/certs:/certs:ro" --entrypoint curl curlimages/curl:latest "${args[@]}" "$MDS$path"
