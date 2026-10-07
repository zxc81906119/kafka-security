#!/usr/bin/env bash
# C3 到 Prometheus / Alertmanager 的連線狀態(C3 自己的 API;用 client 憑證換來的 token 呼叫)。
# 用法: scripts/c3-services-status.sh [憑證名稱,預設 legacy-orders]
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
T=$(./scripts/mds-token.sh "${1:-legacy-orders}") || exit 1
for s in prometheus alertmanager; do
  ./scripts/dcurl.sh -H "Authorization: Bearer $T" https://control-center:9022/3.0/services/$s/status | tr '\n' ' ' | grep -o '"componentName":"[A-Z_]*","componentStatus":"[A-Z]*"'
done
