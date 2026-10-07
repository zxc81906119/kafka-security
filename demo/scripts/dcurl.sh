#!/usr/bin/env bash
# 在 demo 網路內執行 curl(信任 demo CA、可用 /certs 內的 client 憑證;結尾印出 HTTP 狀態碼)。
# 用法: scripts/dcurl.sh [curl 參數...] <URL>
#   例: scripts/dcurl.sh -u c3:prom-pw https://prometheus:9090/api/v1/query?query=up
#       scripts/dcurl.sh --cert /certs/client-c3.pem --key /certs/client-c3.key https://broker1:8091/security/1.0/authenticate
export MSYS_NO_PATHCONV=1
D="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
exec docker run --rm --network cpsec_default -v "$D/certs:/certs:ro" --entrypoint curl curlimages/curl:latest \
  -s -m 15 --cacert /certs/ca.pem -w "\n[HTTP %{http_code}]\n" "$@"
