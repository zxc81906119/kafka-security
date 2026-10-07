#!/usr/bin/env bash
# 建立「服務」身分(不在 AD):Kafka SCRAM 帳號。用法: scripts/create-service-account.sh <name> <password>
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/k.sh kafka-configs --bootstrap-server broker1:9094 --command-config /clients/token-bootstrap.properties \
  --alter --add-config "SCRAM-SHA-512=[password=$2]" --entity-type users --entity-name "$1" 2>&1 | grep -v "^WARNING\|SLF4J" | tail -1
