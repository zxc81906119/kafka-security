#!/usr/bin/env bash
# 以「某個人的家目錄」執行維運腳本(模擬各人登入跳板機後的 ~/.kafka/client.properties)。
# 用法: scripts/as-user.sh <user|shared> <ops 腳本檔名> [args...]
export MSYS_NO_PATHCONV=1
D="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
u="$1"; s="$2"; shift 2
exec docker run --rm -i --network cpsec_default -e DEMO_USER="$u" -e KAFKA_HEAP_OPTS="-Xmx256m" \
  -v "$D/certs:/etc/kafka/secrets:ro" -v "$D/scripts/ops:/ops:ro" -v "$D/config/home/$u/.kafka:/home/appuser/.kafka:ro" \
  --entrypoint bash confluentinc/cp-server:8.3.2 "/ops/$s" "$@"
