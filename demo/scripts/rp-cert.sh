#!/usr/bin/env bash
# ============================================================================
# rp-cert.sh — 以「client 憑證」呼叫 REST Proxy(機器/legacy app 的做法;人用 rp.sh 的 Basic)
# ----------------------------------------------------------------------------
# 白話:模擬 legacy app 這類機器用憑證(mTLS)打 REST Proxy 的 HTTP 請求,不用裝 curl,在 docker 容器裡執行。
# 前置條件:demo 環境與 REST Proxy 已啟動(scripts/up.sh --with-restproxy)。
# 用法:
#   scripts/rp-cert.sh <憑證名稱|none> <METHOD> <path> [json-body]
#     憑證名稱 = certs/client-<名稱>.{pem,key};none = 不帶任何憑證與帳密
# 會改動什麼:取決於你送的請求(GET 只查詢;POST 可能寫入訊息);腳本本身不留下任何檔案。
# 怎麼判斷成功:回應內容之後會印一行「[HTTP 狀態碼]」,2xx 為成功,401/403 表示被擋。
# ============================================================================
export MSYS_NO_PATHCONV=1
D="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
who="$1"; method="$2"; path="$3"; body="${4:-}"
args=(-s --cacert /certs/ca.pem -X "$method" -H "Accept: application/vnd.kafka.v2+json" -w "\n[HTTP %{http_code}]\n")
[ "$who" != none ] && args+=(--cert "/certs/client-$who.pem" --key "/certs/client-$who.key")
[ -n "$body" ] && args+=(-H "Content-Type: application/vnd.kafka.json.v2+json" -d "$body")
exec docker run --rm --network cpsec_default -v "$D/certs:/certs:ro" --entrypoint curl curlimages/curl:latest "${args[@]}" "https://restproxy:8086$path"
