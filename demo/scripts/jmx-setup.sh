#!/usr/bin/env bash
# ============================================================================
# jmx-setup.sh — 準備 JMX exporter(把 Kafka 內部指標變成 Prometheus 讀得懂的網頁)
# ----------------------------------------------------------------------------
# 白話:Kafka 的內部指標(例如「副本不足的分區數」)藏在 JMX 裡,Prometheus 讀不到。
#   JMX exporter 是掛在 Kafka 上的小程式(Java agent),把這些指標用 HTTPS 網頁吐出來。
#   這支腳本準備三樣東西:(1) agent 的 jar,(2) Confluent 官方維護的各元件設定檔,(3) 加上 HTTPS 與 Basic 帳密的版本。
#   每樣東西下載後都校驗雜湊值,確認內容沒被動過。
# 前置條件:能連到 repo1.maven.org 與 raw.githubusercontent.com(已下載過的不會重抓)
# 用法:
#   scripts/jmx-setup.sh            準備全部(已經備妥的會略過)
#   JMX_EXPORTER_VERSION=1.0.1 scripts/jmx-setup.sh    指定 agent 版本
# 會改動什麼:在 config/jmx/ 放 agent jar 與 yml;在 config/c3/ 產生 exporter 的 Basic 密碼檔 jmx_exporter.pw
#   (這些都不進版本庫,見 .gitignore)。
# 怎麼判斷成功:每個步驟印 [jmx] 開頭的訊息,最後一行 [jmx] 表示設定檔已產生;雜湊不符會印錯誤並結束。
# 常見失敗:
#   「SHA-1 不符或取不到校驗值」→ 網路問題或下載被截斷;重跑一次
#   「SHA-256 不符」→ 官方檔案內容和釘定的版本不同(commit 被動過?),不要略過,先查原因
# 正式環境(RHEL VM):同樣下載一次、驗證校驗值,放到 /opt/jmx/,再以 systemd override 在 KAFKA_OPTS 加 -javaagent。
# ============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR"

AGENT_VERSION="${JMX_EXPORTER_VERSION:-1.0.1}"
AGENT_JAR="config/jmx/jmx_prometheus_javaagent.jar"
AGENT_URL="https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/$AGENT_VERSION/jmx_prometheus_javaagent-$AGENT_VERSION.jar"

# 官方 jmx-monitoring-stacks(Apache-2.0)維護的設定檔:釘在固定 commit 並校驗 SHA-256,確保可重現。
#   官方檔以「黑名單 + 通用規則」匯出完整指標,命名與官方 Grafana 面板、告警一致;broker、controller 各一份。
#   startDelaySeconds: 120(官方預設:啟動後 2 分鐘才開始匯出,避開啟動期的雜訊)。
OFFICIAL_COMMIT=f376263fc6d7270185ab6abab9a8c379079e2a92
OFFICIAL_URL="https://raw.githubusercontent.com/confluentinc/jmx-monitoring-stacks/$OFFICIAL_COMMIT/shared-assets/jmx-exporter"
BROKER_YML_SHA256=23a478e7af3ab5ca42581b78fe4f7cb5b15dc89c99119676534e9d1b52c17bc0
CONTROLLER_YML_SHA256=46ff997447842970a5d152b7fcee7b1e53c3c7047912ddfca4d80785ad6848c6
# 生態系元件(Schema Registry、Connect、REST Proxy):同一個 commit 的官方檔,job 名稱照官方 prometheus.yml(schema-registry、kafka-connect、rest-proxy)
SR_YML_SHA256=b3f02cd957e9ed3f87409550f6525575d719e26060e23ba2942efa3b7e109e87
CONNECT_YML_SHA256=0eeb25a65af4e12513edbe5804884c48ba02dd027645862f0ab5f7aca629b75a
REST_YML_SHA256=98c0e895056b6b02c9c979a3138155b8f527d721dbb6798e9e154c1f26beeba4
PASSWORD_FILE=config/c3/jmx_exporter.pw

# 1. agent jar:從 Maven Central 下載,和 Maven 官方一併發佈的 .sha1 比對。
download_agent() {
  if [ -f "$AGENT_JAR" ] && [ -f "$AGENT_JAR.version" ] && [ "$(cat "$AGENT_JAR.version")" = "$AGENT_VERSION" ]; then
    note "[jmx] 已有 jmx_prometheus_javaagent $AGENT_VERSION"; return 0
  fi
  local want have
  say "下載 JMX exporter agent $AGENT_VERSION 並和 Maven Central 的 .sha1 比對"
  note "[jmx] 下載 $AGENT_URL"
  curl -sSL --retry 3 -o "$AGENT_JAR.tmp" "$AGENT_URL"
  want=$(curl -sSL "$AGENT_URL.sha1" | tr -d ' \r\n' | cut -c1-40)
  have=$(sha1sum "$AGENT_JAR.tmp" | awk '{print $1}')
  if [ -z "$want" ] || [ "$want" != "$have" ]; then
    rm -f "$AGENT_JAR.tmp"; die "SHA-1 不符或取不到校驗值(官方 $want / 實際 $have)"
  fi
  mv "$AGENT_JAR.tmp" "$AGENT_JAR"; printf '%s' "$AGENT_VERSION" > "$AGENT_JAR.version"
  note "[jmx] 就緒:$AGENT_JAR($(du -k "$AGENT_JAR" | cut -f1) KB,SHA-1 $have 與 Maven Central 相符)"
}

# 2. 官方設定檔:fetch_official <檔名> <預期 SHA-256>(已經有而且雜湊正確就略過)。
fetch_official() {
  local file="$1" want="$2" have
  if [ -f "config/jmx/$file" ] && [ "$(sha256sum "config/jmx/$file" | awk '{print $1}')" = "$want" ]; then return 0; fi
  say "下載官方設定 $file 並校驗 SHA-256"
  curl -sSL --retry 3 -o "config/jmx/$file.tmp" "$OFFICIAL_URL/$file"
  have=$(sha256sum "config/jmx/$file.tmp" | awk '{print $1}')
  if [ "$have" != "$want" ]; then
    rm -f "config/jmx/$file.tmp"; die "SHA-256 不符:$file(官方釘定 $want / 實際 $have)"
  fi
  mv "config/jmx/$file.tmp" "config/jmx/$file"
  note "[jmx] 官方設定 $file(commit ${OFFICIAL_COMMIT:0:7},SHA-256 已校驗)"
}

# 3. exporter 自己的 HTTPS + Basic 帳密(官方 kafka_broker_ssl_basic_auth.yml 的 httpServer 區塊做法)。
#   HTTPS 用本環境的 server keystore;帳號 Prometheus、密碼隨機產生存在 $PASSWORD_FILE(Prometheus 以 password_file 讀取,
#   不把密碼寫進抓取設定);正式環境密碼由 CyberArk 產生與保管並定期輪替。
#   JMX exporter 1.0.1 只支援 TLS + Basic 帳密,不支援 mTLS(實測 jar 內沒有相關設定);要 mTLS 的元件(blackbox)另外處理。
make_tls_configs() {
  if [ ! -s "$PASSWORD_FILE" ]; then
    head -c 18 /dev/urandom | base64 | tr -d '\n=+/' > "$PASSWORD_FILE"
    note "[jmx] 產生 exporter 的 Basic 密碼 → $PASSWORD_FILE(不進版本庫)"
  fi
  node "$LIB_DIR/jmx-tls-config.mjs" "$PASSWORD_FILE" config/jmx
  note "[jmx] kafka_broker、kafka_controller、confluent_schemaregistry、kafka_connect、confluent_rest 的 _tls.yml:官方設定 + HTTPS + Basic 帳密(Prometheus)"
}

mkdir -p config/jmx
download_agent
fetch_official kafka_broker.yml "$BROKER_YML_SHA256"
fetch_official kafka_controller.yml "$CONTROLLER_YML_SHA256"
fetch_official confluent_schemaregistry.yml "$SR_YML_SHA256"
fetch_official kafka_connect.yml "$CONNECT_YML_SHA256"
fetch_official confluent_rest.yml "$REST_YML_SHA256"
make_tls_configs
