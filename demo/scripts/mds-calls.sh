#!/usr/bin/env bash
# 對照「人」與「機器」進 REST Proxy 時,REST Proxy 對 MDS 做了哪些呼叫(從 MDS 的請求日誌擷取)。
# 做法:各發一個請求(人=yujie 的 Basic;機器=legacy-orders 的 client 憑證),再讀 broker 的 MDS 請求日誌。
# 輸出格式: <方法> <MDS 端點>   MDS 看到的主體: <principal>
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
./scripts/rp.sh yujie:yujie-pw GET /topics >/dev/null
./scripts/rp-cert.sh legacy-orders GET /topics >/dev/null
sleep 3
for b in broker1 broker2; do
  docker logs "$b" --since 25s 2>&1 | grep -E "> (GET|POST) https://[^ ]+/security/1.0/(authenticate|impersonate)"
done | sed -E 's#.*> (GET|POST) https://[^/]+(/[^ ]+) .*User Principal: (.*)#\1 \2   MDS 看到的主體: \3#' | sort -u
