#!/usr/bin/env bash
# 列出某個主體最近對 MDS 的呼叫(從 broker 的 MDS 請求日誌擷取;次數 × 方法 × 端點)。
# 用法: scripts/mds-calls-by.sh <principal> [秒數,預設 60]
export MSYS_NO_PATHCONV=1
p="$1"; s="${2:-60}"
for b in broker1 broker2; do
  docker logs "$b" --since "${s}s" 2>&1 | grep -E "> (GET|POST|PUT|DELETE) https://[^ ]+ -- [0-9]+ > User Principal: $p\$"
done | sed -E 's#.*> (GET|POST|PUT|DELETE) https://[^/]+(/[^ ?]+).*User Principal: (.*)#\3 \1 \2#' | sort | uniq -c | sort -rn
