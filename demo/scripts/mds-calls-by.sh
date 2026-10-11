#!/usr/bin/env bash
# ============================================================================
# mds-calls-by.sh — 列出某個主體最近對 MDS 的呼叫
# ----------------------------------------------------------------------------
# 白話:從 broker 的 MDS 請求日誌擷取,看某個主體最近打了哪些 MDS 端點、各幾次(次數 × 方法 × 端點)。
# 用法:
#   scripts/mds-calls-by.sh <principal> [秒數]      預設 60 秒
# 會改動什麼:什麼都不改(只讀 broker1、broker2 的 docker 日誌)。
# 怎麼判斷成功:每行「次數 主體 方法 端點」,依次數由多到少;沒有輸出代表該時段內沒有呼叫。
# ============================================================================
export MSYS_NO_PATHCONV=1
p="$1"; s="${2:-60}"
for b in broker1 broker2 broker3 broker4; do   # 元件會向 4 台 MDS 中的任一台呼叫,要看全部
  docker logs "$b" --since "${s}s" 2>&1 | grep -E "> (GET|POST|PUT|DELETE) https://[^ ]+ -- [0-9]+ > User Principal: $p\$"
done | sed -E 's#.*> (GET|POST|PUT|DELETE) https://[^/]+(/[^ ?]+).*User Principal: (.*)#\3 \1 \2#' | sort | uniq -c | sort -rn
