#!/usr/bin/env bash
# 第 22 章:準備 Prometheus 官方的 JMX exporter(Java agent)。從 Maven Central 下載並校驗 SHA-1(Maven 官方一併發佈的校驗檔),
# 放在 config/jmx/(不進版本庫)。版本可用 JMX_EXPORTER_VERSION 覆蓋。
# 正式環境(RHEL VM):同樣下載一次、驗證校驗值,放到 /opt/jmx/,再以 systemd override 在 KAFKA_OPTS 加 -javaagent。
set -euo pipefail
cd "$(dirname "$0")/.."
V="${JMX_EXPORTER_VERSION:-1.0.1}"
J="config/jmx/jmx_prometheus_javaagent.jar"
BASE="https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/$V/jmx_prometheus_javaagent-$V.jar"
mkdir -p config/jmx
if [ -f "$J" ] && [ -f "$J.version" ] && [ "$(cat "$J.version")" = "$V" ]; then echo "[jmx] 已有 jmx_prometheus_javaagent $V"; exit 0; fi
echo "[jmx] 下載 $BASE"
curl -sSL --retry 3 -o "$J.tmp" "$BASE"
want=$(curl -sSL "$BASE.sha1" | tr -d ' \r\n' | cut -c1-40); have=$(sha1sum "$J.tmp" | awk '{print $1}')
[ -n "$want" ] && [ "$want" = "$have" ] || { echo "SHA-1 不符或取不到校驗值(官方 $want / 實際 $have)"; rm -f "$J.tmp"; exit 1; }
mv "$J.tmp" "$J"; printf '%s' "$V" > "$J.version"
echo "[jmx] 就緒:$J($(du -k "$J" | cut -f1) KB,SHA-1 $have 與 Maven Central 相符)"
