#!/usr/bin/env bash
# ============================================================================
# create-service-account.sh — 建立「服務」身分(不在 AD):Kafka SCRAM 帳號
# ----------------------------------------------------------------------------
# 白話:給應用程式用的帳號不放 AD,而是建立 Kafka SCRAM 帳號。
# 前置條件:demo 環境已啟動(scripts/up.sh)
# 用法:
#   scripts/create-service-account.sh <name> <password>
# 會改動什麼:在 Kafka 建立 SCRAM-SHA-512 憑證(同名帳號會被覆寫密碼);不會還原。
# 怎麼判斷成功:印出 kafka-configs 輸出的最後一行(成功時通常是 Completed updating config…)。
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/k.sh kafka-configs --bootstrap-server broker1:9094 --command-config /clients/token-bootstrap.properties \
  --alter --add-config "SCRAM-SHA-512=[password=$2]" --entity-type users --entity-name "$1" 2>&1 | grep -v "^WARNING\|SLF4J" | tail -1
