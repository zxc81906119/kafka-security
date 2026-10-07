#!/usr/bin/env bash
# 維運腳本(全組共用同一份):不含任何帳號密碼。
# 連線設定由「執行者自己」的 ~/.kafka/client.properties 提供 —— 腳本共用、憑證各人各自。
set -uo pipefail
CFG="${KAFKA_CLIENT_CONFIG:-$HOME/.kafka/client.properties}"
OUT=$(echo "heartbeat from ${DEMO_USER:-$(whoami)} at $(date -u +%FT%TZ)" \
  | kafka-console-producer --bootstrap-server broker1:9094 --command-config "$CFG" --producer-property enable.idempotence=false --topic orders.events 2>&1)
if echo "$OUT" | grep -q -E "Exception|authorization failed|Authentication failed"; then
  echo "$OUT" | grep -E "Exception|failed" | head -2
  echo "FAILED: 沒有權限(使用 $CFG)"; exit 1
fi
echo "OK: 已送出 heartbeat(使用 $CFG)"
