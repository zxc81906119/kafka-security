#!/usr/bin/env bash
# 機器(自動化)呼叫 C3 API:用 client 憑證向 MDS 換 token 後帶 Bearer;對照不帶 token。
# 用法: scripts/c3-api-check.sh [憑證名稱,預設 legacy-orders]
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
cert="${1:-legacy-orders}"
T=$(./scripts/mds-token.sh "$cert") || exit 1
A=$(./scripts/dcurl.sh -H "Authorization: Bearer $T" https://control-center:9022/2.0/clusters/kafka | tail -1)
B=$(./scripts/dcurl.sh https://control-center:9022/2.0/clusters/kafka | tail -1)
echo "帶 token($cert)→ $A ;沒有 token → $B"
