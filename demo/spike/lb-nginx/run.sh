#!/usr/bin/env bash
# LB 實驗:legacy app 的 client 憑證經過不同型態的 LB 後,REST Proxy 認不認得。在 demo/ 目錄執行。
# 事前:demo 叢集與 restproxy 在跑;docker compose -f spike/lb-nginx/docker-compose.yml up -d
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/../.."; export DEMO_ROOT="$PWD"
D="$(pwd -W 2>/dev/null || pwd)"
source scripts/rbac-lib.sh
BODY='{"records":[{"value":{"order":"LB-1","by":"legacy-app"}}]}'

# call <憑證名稱|none> <埠|direct> [網址主機名,預設 restproxy]
call() {
  local who="$1" port="$2" host="${3:-restproxy}" a=(-s --cacert /certs/ca.pem -X POST -H "Accept: application/vnd.kafka.v2+json" -H "Content-Type: application/vnd.kafka.json.v2+json" -d "$BODY" -w "  [HTTP %{http_code}] curl_exit=%{exitcode}")
  [ "$who" != none ] && a+=(--cert "/certs/client-$who.pem" --key "/certs/client-$who.key")
  local url="https://$host:8086/topics/orders.events"
  if [ "$port" != direct ]; then
    if [ "$host" = restproxy ]; then a+=(--connect-to "restproxy:8086:lb-nginx:$port"); else url="https://$host:$port/topics/orders.events"; fi
  fi
  docker run --rm --network cpsec_default -v "$D/certs:/certs:ro" --entrypoint curl curlimages/curl:latest "${a[@]}" "$url" 2>&1 | tr '\n' ' ' | cut -c1-230; echo
}
t() { printf '%-62s' "$1"; shift; call "$@"; }

echo "== 前置:legacy-orders 綁 orders. 的 DeveloperWrite;legacy-other 沒有任何 role"
rbac_bind cert bootstrap User:legacy-orders DeveloperWrite Topic orders. PREFIXED >/dev/null; sleep 6
echo
echo "== [0] 基線:不經 LB,直連 REST Proxy"
t "legacy-orders(有授權)" legacy-orders direct
t "legacy-other(有效憑證、沒授權)" legacy-other direct
t "不帶憑證" none direct
echo "== [1] L4 透傳(F5 FastL4 / TCP):TLS 端到端"
t "legacy-orders" legacy-orders 9443
t "legacy-other" legacy-other 9443
t "不帶憑證" none 9443
t "偽造憑證(自簽)" rogue 9443
t "網址用 LB 自己的名稱 lb-nginx(server 憑證 SAN 沒有它)" legacy-orders 9443 lb-nginx
echo "== [2] L7-A:LB 終止 TLS,連後端不帶憑證"
t "legacy-orders" legacy-orders 9444
t "不帶憑證" none 9444
echo "== [3] L7-B:LB 終止 TLS,憑證資訊放 header 轉給後端"
t "legacy-orders(header 帶 DN)" legacy-orders 9445
echo "== [4] L7-C:LB 用固定一張 client 憑證(legacy-orders)連後端"
t "legacy-orders" legacy-orders 9446
t "legacy-other(應該沒權限,但經 LB 會變成誰?)" legacy-other 9446
t "不帶憑證(連憑證都沒有)" none 9446
rbac_unbind cert bootstrap User:legacy-orders DeveloperWrite Topic orders. PREFIXED >/dev/null
