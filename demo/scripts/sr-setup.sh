#!/usr/bin/env bash
# 第 20 章:啟動 Schema Registry(RBAC)並完成授權。可重複執行。
# 身分:SR 自己用 client 憑證(CN=schema-registry)向 MDS 換 token(與 REST Proxy 同一種做法),不是 AD 帳號;人用 AD 帳密(Basic)。
# SR 需要的授權(實測逐一補齊,少一項就會在日誌看到 TopicAuthorizationException 或 403):
#   _schemas topic 與 consumer group schema-registry   → ResourceOwner(存 schema)
#   _confluent-command                                  → DeveloperRead / DeveloperWrite(license 檢查)
#   _dek_registry 開頭的 topic                          → ResourceOwner(DEK Registry 存 KEK / DEK;沒有就啟動失敗)
#   SR 叢集範圍的 SecurityAdmin                         → 代使用者向 MDS 查授權(沒有:KEK 端點回 500,日誌 "not permitted for requestor")
# 人的授權(AD 群組):topic-admin → 全部 subject 的 ResourceOwner;security → 全部 KEK 的 ResourceOwner(KEK 保管人);
#   orders-write → orders. 開頭 subject 的讀寫,與 KEK orders-kek 的讀取
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
source scripts/rbac-lib.sh
D="$(pwd -W 2>/dev/null || pwd)"

bash scripts/make-certs.sh >/dev/null    # 補 SR 的 client 憑證與 server 憑證 SAN(已有的略過)

echo "[sr] 授權 SR 自己(kafka 叢集範圍)"
rbac_bind cert bootstrap User:schema-registry ResourceOwner Topic _schemas LITERAL
rbac_bind cert bootstrap User:schema-registry ResourceOwner Group schema-registry LITERAL
rbac_bind cert bootstrap User:schema-registry DeveloperRead Topic _confluent-command LITERAL
rbac_bind cert bootstrap User:schema-registry DeveloperWrite Topic _confluent-command LITERAL
rbac_bind cert bootstrap User:schema-registry ResourceOwner Topic _dek_registry PREFIXED

# SR 叢集範圍的綁定:scope 要多一個 schema-registry-cluster(= schema.registry.group.id)
srbind() { # srbind <principal> <role> [<resourceType> <name> <patternType>]
  local enc="${1/:/%3A}" scope body path
  scope="{\"clusters\":{\"kafka-cluster\":\"$KAFKA_CLUSTER_ID\",\"schema-registry-cluster\":\"schema-registry\"}}"
  if [ -n "${3:-}" ]; then
    path="/security/1.0/principals/$enc/roles/$2/bindings"
    body="{\"scope\":$scope,\"resourcePatterns\":[{\"resourceType\":\"$3\",\"name\":\"$4\",\"patternType\":\"${5:-LITERAL}\"}]}"
  else
    path="/security/1.0/principals/$enc/roles/$2"; body="$scope"
  fi
  echo "  bind $1 $2 ${3:+$3:$4} -> $(bash scripts/mds.sh cert bootstrap POST "$path" "$body" | tail -1)"
}
echo "[sr] SR 叢集範圍"
srbind User:schema-registry SecurityAdmin
srbind Group:topic-admin ResourceOwner Subject '*' LITERAL
srbind Group:security ResourceOwner Kek '*' LITERAL
srbind Group:orders-write DeveloperRead Subject orders. PREFIXED
srbind Group:orders-write DeveloperWrite Subject orders. PREFIXED
srbind Group:orders-write DeveloperRead Kek orders-kek LITERAL

echo "[sr] 啟動 Schema Registry"
docker compose --profile sr up -d --wait --wait-timeout 240 schema-registry 2>&1 | grep -E "schema-registry (Healthy|Error)" | tail -1 || true
echo "[sr] 等待授權生效(SR 對 MDS 的授權快取)…"
for i in $(seq 1 24); do
  code=$(docker run --rm --network cpsec_default -v "$D/certs:/certs:ro" --entrypoint curl curlimages/curl:latest -s -o /dev/null -w '%{http_code}' --cacert /certs/ca.pem -u gary:gary-pw https://schema-registry:8081/dek-registry/v1/keks || true)
  [ "$code" = 200 ] && { echo "[sr] 就緒(gary 可列 KEK)"; exit 0; }
  sleep 5
done
echo "[sr] 授權尚未生效(最後狀態碼 $code);稍後再試"; exit 1
