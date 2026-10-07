#!/usr/bin/env bash
# 以 curl 容器呼叫 REST Proxy(與 Postman 相同的 HTTP 請求)。
# 用法: scripts/rp.sh <user:pass|none> <METHOD> <path> [json-body] [content-type]
export MSYS_NO_PATHCONV=1
D="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
who="$1"; method="$2"; path="$3"; body="${4:-}"; ct="${5:-application/vnd.kafka.json.v2+json}"
args=(-s --cacert /certs/ca.pem -X "$method" -H "Accept: application/vnd.kafka.v2+json" -w "\n[HTTP %{http_code}]\n")
[ "$who" != none ] && args+=(-u "$who")
[ -n "$body" ] && args+=(-H "Content-Type: $ct" -d "$body")
exec docker run --rm --network cpsec_default -v "$D/certs:/certs:ro" --entrypoint curl curlimages/curl:latest "${args[@]}" "https://restproxy:8086$path"
