#!/usr/bin/env bash
# ============================================================================
# observability.sh — 啟動或關閉第 27 章的日誌與追蹤(Loki、Tempo、Alloy),資料經 Kafka 傳輸
# ----------------------------------------------------------------------------
# 白話:日誌和 trace 不直接送進 Loki 與 Tempo,而是先寫進 Kafka,再由另一段讀出來送進去。
#   好處:Loki 或 Tempo 掛掉、升級時,資料留在 Kafka,恢復後補上,不掉。
#   這支腳本備妥 Kafka 這一側(兩個專用帳號、只開需要的 ACL、兩個 topic),再啟動三個容器。
# 前置條件:叢集已啟動(scripts/up.sh)與 Grafana(scripts/grafana.sh on);記憶體吃緊時先停 Control Center:
#   docker stop control-center(本 Lab 不需要它)
# 用法:
#   scripts/observability.sh on       備妥並啟動(可重複執行)
#   scripts/observability.sh off      停掉三個容器(Kafka 帳號、topic 與資料保留)
#   scripts/observability.sh status   顯示三個容器的狀態
# 會改動什麼:config/observability/secrets/ 產生密碼檔、下載 OpenTelemetry Java agent(都不進版本庫);
#   在 Kafka 建立 SCRAM 帳號 alloy-producer、alloy-consumer、topic otel-logs、otel-traces 與它們的 ACL;重啟 grafana 容器(載入資料來源)。
#   停用帳號一律不刪 SCRAM 憑證(KAFKA-20774),所以 off 不動 Kafka 的帳號。
# 怎麼判斷成功:最後印 [observability] 完成;三個容器在跑。
# 常見失敗:Alloy 一直重啟 → docker logs alloy(常見:密碼檔不存在、ACL 沒建、Loki/Tempo 還沒起來)
# ============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/kafka.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR"

SECRETS=config/observability/secrets
SERVICES="loki tempo alloy"
AGENT_VERSION=2.32.0
AGENT_JAR=config/observability/otel-javaagent.jar
AGENT_BASE="https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v$AGENT_VERSION"
AGENT_URL="$AGENT_BASE/opentelemetry-javaagent.jar"

# 產生一個隨機密碼寫進檔案(檔案已存在就保留)。
make_secret() { [ -s "$1" ] || { head -c 18 /dev/urandom | base64 | tr -d '\n=+/' > "$1"; note "產生 $1"; }; }

# 建立一個 SCRAM 帳號(密碼取自密碼檔)。重複執行會把密碼設成同一個值,安全。
make_scram_user() {
  kafka_configs --entity-type users --entity-name "$1" --alter --add-config "SCRAM-SHA-512=[password=$(cat "$SECRETS/$1.pw")]" | tail -1
}

# 建立 topic(已存在就略過):副本 3、min.insync.replicas 2,保留 6 小時(範例值;Loki / Tempo 才是長期儲存)。
make_topic() {
  kafka_topics --create --if-not-exists --topic "$1" --partitions 3 --replication-factor 3 \
    --config min.insync.replicas=2 --config retention.ms=21600000 | grep -E "Created|rror|already" || true
}

# 最小權限的 ACL:
#   alloy-producer:只能寫 otel-logs、otel-traces(--producer 包含 Write、Describe、Create 與冪等寫入)
#   alloy-consumer:只能讀 otel-logs、otel-traces、稽核 topic,且 group 限定 alloy-* 開頭
make_acls() {
  local t
  for t in otel-logs otel-traces; do
    kafka_acls --add --allow-principal User:alloy-producer --producer --topic "$t" | grep -E 'rror' || true
    kafka_acls --add --allow-principal User:alloy-consumer --operation Read --operation Describe --topic "$t" | grep -E 'rror' || true
  done
  kafka_acls --add --allow-principal User:alloy-consumer --operation Read --operation Describe --topic confluent-audit-log-events | grep -E 'rror' || true
  kafka_acls --add --allow-principal User:alloy-consumer --operation Read --group 'alloy-' --resource-pattern-type prefixed | grep -E 'rror' || true
  note "alloy-producer 的 ACL:$(kafka_acls --list --principal User:alloy-producer | grep -c ResourcePattern) 個資源;alloy-consumer:$(kafka_acls --list --principal User:alloy-consumer | grep -c ResourcePattern) 個資源"
}

# 下載 OpenTelemetry Java agent(讓第 25 章的 Java 程式不改程式碼就產生 trace),校驗 GitHub release 一併發佈的 checksums.txt。
fetch_agent() {
  [ -s "$AGENT_JAR" ] && return 0
  local want have
  say "下載 OpenTelemetry Java agent $AGENT_VERSION 並校驗 SHA-256"
  curl -sSL --retry 3 -o "$AGENT_JAR.tmp" "$AGENT_URL"
  want=$(curl -sSL "$AGENT_BASE/checksums.txt" | grep 'opentelemetry-javaagent.jar$' | awk '{print $1}' | head -1)
  have=$(sha256sum "$AGENT_JAR.tmp" | awk '{print $1}')
  if [ -z "$want" ] || [ "$want" != "$have" ]; then rm -f "$AGENT_JAR.tmp"; die "SHA-256 不符或取不到校驗值(官方 $want / 實際 $have)"; fi
  mv "$AGENT_JAR.tmp" "$AGENT_JAR"; note "已取得 $AGENT_JAR"
}

turn_on() {
  need_ha_mode
  need_container grafana "先執行:scripts/grafana.sh on"
  mkdir -p "$SECRETS"
  say "備妥 Kafka 這一側:密碼、兩個專用帳號、兩個 topic、最小權限的 ACL"
  make_secret "$SECRETS/alloy-producer.pw"; make_secret "$SECRETS/alloy-consumer.pw"; chmod 644 "$SECRETS"/*.pw
  make_scram_user alloy-producer; make_scram_user alloy-consumer
  make_topic otel-logs; make_topic otel-traces
  make_acls
  fetch_agent
  say "啟動 Loki、Tempo、Alloy,並讓 Grafana 載入 Loki 與 Tempo 資料來源(重啟 grafana 容器)"
  docker compose --profile observability up -d $SERVICES >/dev/null 2>&1
  wait_until "alloy 在跑" 60 docker inspect -f '{{.State.Running}}' alloy >/dev/null || die "Alloy 沒有起來:docker logs alloy"
  docker restart grafana >/dev/null; wait_healthy grafana >/dev/null
  note "[observability] 完成:Alloy UI 只在 demo 網路內(12345);Grafana 的 Explore 選 Loki 或 Tempo 查詢"
}

turn_off() {
  say "停掉 Loki、Tempo、Alloy(Kafka 的帳號與 topic、容器資料保留)"
  docker compose --profile observability stop $SERVICES >/dev/null 2>&1 || true
  docker compose --profile observability rm -f $SERVICES >/dev/null 2>&1 || true
  note "[observability] 已關閉"
}

case "${1:-status}" in
  on)     turn_on ;;
  off)    turn_off ;;
  status) docker ps -a --format '{{.Names}} {{.Status}}' | grep -E '^(loki|tempo|alloy) ' || echo "沒有執行中的 observability 容器" ;;
  *)      usage_from_header "$0"; exit 1 ;;
esac
