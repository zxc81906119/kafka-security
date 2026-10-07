#!/usr/bin/env bash
# 在 demo 網路內執行 Kafka CLI(使用 cp-server 映像內的工具,避免 Windows 指令差異)。
# 用法: scripts/k.sh <kafka-cli> <args...>      例: scripts/k.sh kafka-topics --bootstrap-server broker1:9094 --command-config /clients/plain-yujie.properties --list
export MSYS_NO_PATHCONV=1
D="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
exec docker run --rm -i --network cpsec_default \
  -v "$D/certs:/etc/kafka/secrets:ro" -v "$D/config/clients:/clients:ro" -v "$D/config/scripts:/scripts:ro" \
  -e KAFKA_OPTS="" -e KAFKA_HEAP_OPTS="-Xmx256m" --entrypoint "$1" confluentinc/cp-server:8.3.2 "${@:2}"
