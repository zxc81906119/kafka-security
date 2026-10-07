#!/usr/bin/env bash
# 以「client 憑證」呼叫 REST Proxy(機器/legacy app 的做法;人用 rp.sh 的 Basic)。
# 用法: scripts/rp-cert.sh <憑證名稱|none> <METHOD> <path> [json-body]
#   憑證名稱 = certs/client-<名稱>.{pem,key};none = 不帶任何憑證與帳密
export MSYS_NO_PATHCONV=1
D="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
who="$1"; method="$2"; path="$3"; body="${4:-}"
args=(-s --cacert /certs/ca.pem -X "$method" -H "Accept: application/vnd.kafka.v2+json" -w "\n[HTTP %{http_code}]\n")
[ "$who" != none ] && args+=(--cert "/certs/client-$who.pem" --key "/certs/client-$who.key")
[ -n "$body" ] && args+=(-H "Content-Type: application/vnd.kafka.json.v2+json" -d "$body")
exec docker run --rm --network cpsec_default -v "$D/certs:/certs:ro" --entrypoint curl curlimages/curl:latest "${args[@]}" "https://restproxy:8086$path"
