#!/usr/bin/env bash
# 證明:C3 的服務身分(憑證 CN=c3 換到的 token)擁有管理員權限 —— 能建立與刪除 role binding(測試用,做完即清除)。
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
T=$(./scripts/mds-token.sh c3) || exit 1
BODY='{"scope":{"clusters":{"kafka-cluster":"XyZBQ3-GTvKH2qNfP7X33A"}},"resourcePatterns":[{"resourceType":"Topic","name":"probe-","patternType":"PREFIXED"}]}'
URL="https://broker1:8091/security/1.0/principals/User%3Aprobe-user/roles/DeveloperRead/bindings"
H=(-H "Authorization: Bearer $T" -H "Content-Type: application/json" -H "Accept: application/json")
A=$(./scripts/dcurl.sh -X POST "${H[@]}" "$URL" -d "$BODY" | tail -1)
B=$(./scripts/dcurl.sh -X DELETE "${H[@]}" "$URL" -d "$BODY" | tail -1)
echo "用 c3 的 token 建立 role binding → $A ;清除 → $B"
