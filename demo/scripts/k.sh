#!/usr/bin/env bash
# ============================================================================
# k.sh — 在 demo 網路內執行 Kafka CLI
# ----------------------------------------------------------------------------
# 白話:使用 cp-server 映像內的工具,避免 Windows 指令差異。容器內 /etc/kafka/secrets 是 certs/,
#   /clients 是 config/clients,/scripts 是 config/scripts。
# 環境變數:K_NAME=容器名稱(給 --name;produce_test 用來在逾時時移除卡住的 client)
# 用法:
#   scripts/k.sh <kafka-cli> <args...>
#   例: scripts/k.sh kafka-topics --bootstrap-server broker1:9094 --command-config /clients/plain-yujie.properties --list
# 會改動什麼:腳本本身什麼都不改(臨時 --rm 容器);是否改動 Kafka 取決於你執行的 CLI。
# 怎麼判斷成功:結束碼等於該 Kafka CLI 的結束碼。
# ============================================================================
export MSYS_NO_PATHCONV=1
D="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
exec docker run --rm -i ${K_NAME:+--name "$K_NAME"} --network cpsec_default \
  -v "$D/certs:/etc/kafka/secrets:ro" -v "$D/config/clients:/clients:ro" -v "$D/config/scripts:/scripts:ro" \
  -e KAFKA_OPTS="" -e KAFKA_HEAP_OPTS="-Xmx256m" --entrypoint "$1" confluentinc/cp-server:8.3.2 "${@:2}"
