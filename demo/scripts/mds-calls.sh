#!/usr/bin/env bash
# ============================================================================
# mds-calls.sh — 對照「人」與「機器」進 REST Proxy 時,REST Proxy 對 MDS 做了哪些呼叫
# ----------------------------------------------------------------------------
# 白話:人與機器經 REST Proxy 進來時,REST Proxy 向 MDS 做的事不同,用 MDS 的請求日誌對照。
#   做法:各發一個請求(人=yujie 的 Basic;機器=legacy-orders 的 client 憑證),再讀 broker 的 MDS 請求日誌。
# 前置條件:demo 環境已啟動(含 REST Proxy;scripts/rp.sh、scripts/rp-cert.sh 可用),certs/ 內有 client-legacy-orders
# 用法:
#   scripts/mds-calls.sh      不需參數
# 會改動什麼:什麼都不改(對 REST Proxy 發兩次 GET /topics,讀最近 25 秒的 broker 日誌)。
# 怎麼判斷成功:輸出格式 <方法> <MDS 端點>   MDS 看到的主體: <principal>(authenticate / impersonate 端點)。
# ============================================================================
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
./scripts/rp.sh yujie:yujie-pw GET /topics >/dev/null
./scripts/rp-cert.sh legacy-orders GET /topics >/dev/null
sleep 3
for b in broker1 broker2 broker3 broker4; do   # REST Proxy 會向 4 台 MDS 中的任一台換 token,要看全部
  docker logs "$b" --since 25s 2>&1 | grep -E "> (GET|POST) https://[^ ]+/security/1.0/(authenticate|impersonate)"
done | sed -E 's#.*> (GET|POST) https://[^/]+(/[^ ]+) .*User Principal: (.*)#\1 \2   MDS 看到的主體: \3#' | sort -u
