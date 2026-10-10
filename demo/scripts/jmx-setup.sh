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
if [ -f "$J" ] && [ -f "$J.version" ] && [ "$(cat "$J.version")" = "$V" ]; then echo "[jmx] 已有 jmx_prometheus_javaagent $V"; HAVE_JAR=1; fi
if [ -z "${HAVE_JAR:-}" ]; then
echo "[jmx] 下載 $BASE"
curl -sSL --retry 3 -o "$J.tmp" "$BASE"
want=$(curl -sSL "$BASE.sha1" | tr -d ' \r\n' | cut -c1-40); have=$(sha1sum "$J.tmp" | awk '{print $1}')
[ -n "$want" ] && [ "$want" = "$have" ] || { echo "SHA-1 不符或取不到校驗值(官方 $want / 實際 $have)"; rm -f "$J.tmp"; exit 1; }
mv "$J.tmp" "$J"; printf '%s' "$V" > "$J.version"
echo "[jmx] 就緒:$J($(du -k "$J" | cut -f1) KB,SHA-1 $have 與 Maven Central 相符)"
fi

# 各元件的 exporter 設定:用 Confluent 官方 jmx-monitoring-stacks(Apache-2.0)維護的設定檔,不自己重寫——
#   官方檔以「黑名單 + 通用規則」匯出完整指標,命名與官方 Grafana 面板、告警一致,隨版本更新有人維護;broker、controller 各一份。
#   釘在固定 commit 並校驗 SHA-256,確保可重現。startDelaySeconds: 120(官方預設:啟動後 2 分鐘才開始匯出,避開啟動期的雜訊)。
OFFICIAL_COMMIT=f376263fc6d7270185ab6abab9a8c379079e2a92
OB="https://raw.githubusercontent.com/confluentinc/jmx-monitoring-stacks/$OFFICIAL_COMMIT/shared-assets/jmx-exporter"
fetch_official() { # fetch_official <檔名> <sha256>
  local f="$1" want="$2" have
  if [ -f "config/jmx/$f" ] && [ "$(sha256sum "config/jmx/$f" | awk '{print $1}')" = "$want" ]; then return 0; fi
  curl -sSL --retry 3 -o "config/jmx/$f.tmp" "$OB/$f"
  have=$(sha256sum "config/jmx/$f.tmp" | awk '{print $1}')
  [ "$have" = "$want" ] || { echo "SHA-256 不符:$f(官方釘定 $want / 實際 $have)"; rm -f "config/jmx/$f.tmp"; exit 1; }
  mv "config/jmx/$f.tmp" "config/jmx/$f"; echo "[jmx] 官方設定 $f(commit ${OFFICIAL_COMMIT:0:7},SHA-256 已校驗)"
}
fetch_official kafka_broker.yml 23a478e7af3ab5ca42581b78fe4f7cb5b15dc89c99119676534e9d1b52c17bc0
fetch_official kafka_controller.yml 46ff997447842970a5d152b7fcee7b1e53c3c7047912ddfca4d80785ad6848c6

# exporter 自己的 HTTPS + Basic 帳密(官方 kafka_broker_ssl_basic_auth.yml 的 httpServer 區塊做法),broker 與 controller 都套用:
#   - HTTPS 用本環境的 server keystore(SAN 含所有節點名稱);帳號 Prometheus、密碼隨機產生並存在 config/c3/jmx_exporter.pw(不進版本庫,
#     Prometheus 以 password_file 讀取,不把密碼寫進抓取設定);正式環境密碼由 CyberArk 產生與保管並定期輪替。
#   - 密碼雜湊與官方 utils/jmxexporter_hash_password_PBKDF2WithHmacSHA512.py 相同:PBKDF2-HMAC-SHA512、210000 次、輸出 128 位元組(hex)。
#   - JMX exporter 1.0.1 只支援 TLS + Basic 帳密,不支援 mTLS(實測 jar 內沒有相關設定);要 mTLS 的元件(blackbox)另外處理。
PWF=config/c3/jmx_exporter.pw
[ -s "$PWF" ] || { head -c 18 /dev/urandom | base64 | tr -d '\n=+/' > "$PWF"; echo "[jmx] 產生 exporter 的 Basic 密碼 → $PWF(不進版本庫)"; }
node -e '
const fs=require("fs"), c=require("crypto");
const pw=fs.readFileSync("config/c3/jmx_exporter.pw","utf8").trim();
const salt=c.createHash("sha256").update(pw).digest("hex").slice(0,10);
const hash=c.pbkdf2Sync(pw, salt, 210000, 128, "sha512").toString("hex");
const http="httpServer:\n  ssl:\n    keyStore:\n      type: PKCS12\n      filename: /etc/kafka/secrets/server.keystore.p12\n      password: changeit\n    certificate:\n      alias: server\n  authentication:\n    basic:\n      username: Prometheus\n      passwordHash: "+hash+"\n      algorithm: PBKDF2WithHmacSHA512\n      salt: "+salt+"\n";
for (const n of ["kafka_broker","kafka_controller"]) {
  let y=fs.readFileSync("config/jmx/"+n+".yml","utf8").replace(/^---\r?\n/,"");
  fs.writeFileSync("config/jmx/"+n+"_tls.yml","---\n"+http+y);
}'
echo "[jmx] kafka_broker_tls.yml、kafka_controller_tls.yml:官方設定 + HTTPS + Basic 帳密(Prometheus)"
