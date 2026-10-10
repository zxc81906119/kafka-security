#!/usr/bin/env bash
# ============================================================================
# rp.sh — 以 curl 容器呼叫 REST Proxy(與 Postman 相同的 HTTP 請求;人用 AD 帳密 Basic)
# ----------------------------------------------------------------------------
# 白話:不裝 curl,在 docker 容器裡對 REST Proxy 送 HTTP 請求,等同 Postman 做的事。機器用憑證請改用 rp-cert.sh。
# 前置條件:demo 環境與 REST Proxy 已啟動(scripts/up.sh --with-restproxy)。
# 用法:
#   scripts/rp.sh <user:pass|none> <METHOD> <path> [json-body] [content-type]
#     none = 不帶帳密;content-type 預設 application/vnd.kafka.json.v2+json
# 會改動什麼:取決於你送的請求(GET 只查詢;POST 可能寫入訊息);腳本本身不留下任何檔案。
# 怎麼判斷成功:回應內容之後會印一行「[HTTP 狀態碼]」,2xx 為成功,401/403 表示被擋。
# ============================================================================
export MSYS_NO_PATHCONV=1
D="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
who="$1"; method="$2"; path="$3"; body="${4:-}"; ct="${5:-application/vnd.kafka.json.v2+json}"
args=(-s --cacert /certs/ca.pem -X "$method" -H "Accept: application/vnd.kafka.v2+json" -w "\n[HTTP %{http_code}]\n")
[ "$who" != none ] && args+=(-u "$who")
[ -n "$body" ] && args+=(-H "Content-Type: $ct" -d "$body")
exec docker run --rm --network cpsec_default -v "$D/certs:/certs:ro" --entrypoint curl curlimages/curl:latest "${args[@]}" "https://restproxy:8086$path"
