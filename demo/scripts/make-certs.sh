#!/usr/bin/env bash
# ============================================================================
# make-certs.sh — 產生 demo 用 CA、「單一共用 server 憑證」、MDS token 金鑰,以及各元件的 client 與內部通道憑證
# ----------------------------------------------------------------------------
# 白話:demo 的 TLS、mTLS 與 MDS token 都需要憑證與金鑰。這支腳本一次產生全部;已存在就只「補」缺的部分,不會換掉已發出的身分。
# 客戶情境:所有元件共用同一張 server 憑證(同一把 private key、同一個 DN),憑證只做傳輸加密。
# 另外為「對照章節(第 8 章)」產生兩張不同 DN 的 client 憑證,用來示範:共用 DN 無法區分元件。
# 產生的東西(皆在 demo/certs/):
#   CA(Demo Private CA)、共用 server 憑證(CN=kafka.demo.local,SAN 涵蓋各元件名稱)、truststore.p12、
#   client 憑證 c3 restproxy bootstrap legacy-orders schema-registry monitor connect、
#   內部通道共用憑證 internal(CN=kafka-internal,broker↔broker 與 broker↔controller 做 mTLS,同時當 server 與 client 所以 EKU 兩個都要)、
#   MDS token 金鑰(keypair.pem / public.pem)、密碼檔 keystore_creds / sslkey_creds / truststore_creds(cp 映像以 *_CREDENTIALS 讀檔,沒有這三個檔 controller / broker 會啟動失敗)。
# 前置條件:Docker 已啟動(用 alpine/openssl 與 cp-server 映像的 keytool)。
# 用法:
#   scripts/make-certs.sh        通常由 scripts/up.sh 與 scripts/sr-setup.sh 自動呼叫,可重複執行
# 會改動什麼:在 demo/certs/ 建立或補產上述檔案,最後建立 certs/.done。
#   已有 certs/.done 時:若 server 憑證的 SAN 缺某個名稱(prometheus、alertmanager、conjur、schema-registry、blackbox-exporter、
#   grafana、node-exporter、kafka-exporter、loki、tempo、connect、mailpit、broker3、broker4、controller2、controller3、minio),
#   就改 san.cnf(內部憑證則改 internal.cnf),用同一把 key、同一個 CA 重簽(不換身分、不用重發 client 憑證);
#   缺的 client 憑證與內部通道憑證也補產;其餘略過。
# 怎麼判斷成功:全新建立最後印「OK: certs 完成 → demo/certs」;已存在則印「certs 已存在,略過其餘」。
# 常見失敗:docker 沒啟動 → 先啟動 Docker Desktop;重簽後 broker 仍拒絕新名稱 → 憑證在 broker 重啟(或動態重載)後才生效。
# ============================================================================
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/lib/common.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$SELF_DIR/.."
export MSYS_NO_PATHCONV=1
OUT="$(pwd -W 2>/dev/null || pwd)/certs"
mkdir -p certs
PASS=changeit

# ---------- 小工具 ----------

# openssl_in_certs <sh 指令…>:在 alpine/openssl 容器裡,以 certs/ 為工作目錄執行一段 sh。
openssl_in_certs() {
  docker run --rm -v "$OUT:/certs" --entrypoint sh alpine/openssl -c "cd /certs; $1"
}

# resign_server:用同一把 key 與同一個 CA,依目前的 san.cnf 重簽共用 server 憑證,並重新打包 keystore。
resign_server() {
  openssl_in_certs "
    openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out server.pem -days 825 -sha256 -extfile san.cnf -extensions v3 2>/dev/null
    openssl pkcs12 -export -in server.pem -inkey server.key -certfile ca.pem -name server -out server.keystore.p12 -passout pass:$PASS
    chmod 644 server.*"
}

# resign_internal:同上,對象是內部通道憑證(internal.cnf)。
resign_internal() {
  openssl_in_certs "
    openssl x509 -req -in internal.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out internal.pem -days 825 -sha256 -extfile internal.cnf -extensions v3 2>/dev/null
    openssl pkcs12 -export -in internal.pem -inkey internal.key -certfile ca.pem -name internal -out internal.keystore.p12 -passout pass:$PASS
    chmod 644 internal.*"
}

# add_server_san <判斷用的字串> <sed 規則> <訊息>:san.cnf 裡沒有該字串就改 SAN、重簽,並印訊息。
#   <判斷用的字串> 是 grep 的樣式;<sed 規則> 是改 san.cnf 的 sed 運算式。
add_server_san() {
  grep -q "$1" certs/san.cnf 2>/dev/null && return 0
  sed -i "$2" certs/san.cnf
  resign_server
  echo "server 憑證 SAN 已補 $3(同 key、同 CA)"
}

# add_internal_san <判斷用的字串> <sed 規則> <訊息>:內部憑證版(internal.cnf 不存在就略過)。
add_internal_san() {
  [ -f certs/internal.cnf ] || return 0
  grep -q "$1" certs/internal.cnf 2>/dev/null && return 0
  sed -i "$2" certs/internal.cnf
  resign_internal
  echo "內部憑證 SAN 已補 $3(同 key、同 CA)"
}

# ---------- 已有 CA:只補缺的部分 ----------

if [ -f certs/.done ]; then
  # 每一段:什麼時候(哪一章)需要這個名稱 → 改 san.cnf 並重簽。順序有意義:後面的 sed 規則靠前面已補上的名稱定位。
  # 第 17 章:監控 TLS(prometheus、alertmanager)與 CyberArk(conjur)
  add_server_san "DNS:conjur" 's/DNS:openldap,IP:127.0.0.1/DNS:openldap,DNS:prometheus,DNS:alertmanager,DNS:conjur,IP:127.0.0.1/' \
    "prometheus / alertmanager / conjur"
  # 第 20 章:Schema Registry(與第 22 章的 blackbox-exporter 一起放進這個位置,舊環境可能只缺其一)
  add_server_san "DNS:schema-registry" 's/DNS:conjur,IP:127.0.0.1/DNS:conjur,DNS:schema-registry,DNS:blackbox-exporter,IP:127.0.0.1/' \
    "schema-registry"

  # 內部通道共用憑證(CN=kafka-internal,mTLS;broker↔broker 與 broker↔controller 共用),舊環境沒有就補產
  if [ ! -f certs/internal.keystore.p12 ]; then
    openssl_in_certs "
      printf '[req]\ndistinguished_name=dn\nreq_extensions=v3\nprompt=no\n[dn]\nCN=kafka-internal\nO=Demo\n[v3]\nsubjectAltName=DNS:broker1,DNS:broker2,DNS:broker3,DNS:broker4,DNS:controller1,DNS:controller2,DNS:controller3,DNS:localhost\nextendedKeyUsage=serverAuth,clientAuth\n' > internal.cnf
      openssl genrsa -out internal.key 2048 2>/dev/null
      openssl req -new -key internal.key -out internal.csr -config internal.cnf
      openssl x509 -req -in internal.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out internal.pem -days 825 -sha256 -extfile internal.cnf -extensions v3 2>/dev/null
      openssl pkcs12 -export -in internal.pem -inkey internal.key -certfile ca.pem -name internal -out internal.keystore.p12 -passout pass:$PASS
      chmod 644 internal.*"
    echo "補產內部通道共用憑證: internal(CN=kafka-internal)"
  fi

  # 第 22 章:blackbox exporter 啟用 TLS
  add_server_san "DNS:blackbox-exporter" \
    's/DNS:conjur,DNS:schema-registry,/DNS:conjur,DNS:schema-registry,DNS:blackbox-exporter,/; s/DNS:conjur,IP:127.0.0.1/DNS:conjur,DNS:blackbox-exporter,IP:127.0.0.1/' "blackbox-exporter"
  # 第 26 章:Grafana 與 node / kafka exporter 啟用 TLS
  add_server_san "DNS:grafana" 's/DNS:blackbox-exporter,/DNS:blackbox-exporter,DNS:grafana,DNS:node-exporter,DNS:kafka-exporter,/' \
    "grafana / node-exporter / kafka-exporter"
  # 第 27 章:Loki 與 Tempo 啟用 TLS
  add_server_san "DNS:loki" 's/DNS:kafka-exporter,/DNS:kafka-exporter,DNS:loki,DNS:tempo,/' "loki / tempo"
  # 第 29 章:Kafka Connect 的 REST 走 HTTPS(判斷字串帶逗號,避免和其他名稱誤判)
  add_server_san "DNS:connect," 's/DNS:tempo,/DNS:tempo,DNS:connect,/' "connect"
  # 第 30 章:郵件伺服器(SMTP STARTTLS)
  add_server_san "DNS:mailpit" 's/DNS:connect,/DNS:connect,DNS:mailpit,/' "mailpit"
  # 第 21 章:HA 環境的 broker3、controller2、controller3(server 憑證與內部憑證都要)
  add_server_san "DNS:broker3" 's/DNS:broker2,/DNS:broker2,DNS:broker3,DNS:controller2,DNS:controller3,/' "broker3 / controller2 / controller3"
  add_internal_san "DNS:broker3" 's/DNS:broker2,DNS:controller1,/DNS:broker2,DNS:broker3,DNS:controller1,DNS:controller2,DNS:controller3,/' \
    "broker3 / controller2 / controller3"
  # 第 31 章:Self-Balancing 加 / 移除 broker 實驗的第 4 台 broker
  add_server_san "DNS:broker4" 's/DNS:broker3,/DNS:broker3,DNS:broker4,/' "broker4"
  add_internal_san "DNS:broker4" 's/DNS:broker3,/DNS:broker3,DNS:broker4,/' "broker4"
  # 第 32 章:Tiered Storage 的物件儲存 MinIO(HTTPS)
  add_server_san "DNS:minio" 's/DNS:broker4,/DNS:broker4,DNS:minio,/' "minio"
  # 單一基線:REST Proxy、Schema Registry、Connect 各 2 台,各自的名稱要在 server 憑證的 SAN
  add_server_san "DNS:restproxy1" 's/DNS:restproxy,/DNS:restproxy,DNS:restproxy1,DNS:restproxy2,DNS:schema-registry1,DNS:schema-registry2,DNS:connect1,DNS:connect2,/' \
    "restproxy1/2、schema-registry1/2、connect1/2"
  # 第 33 章:動態 quorum 汰換 controller 實驗的第 4 台 controller(server 憑證與內部憑證都要)
  add_server_san "DNS:controller4" 's/DNS:controller3,/DNS:controller3,DNS:controller4,/' "controller4"
  add_internal_san "DNS:controller4" 's/DNS:controller3,/DNS:controller3,DNS:controller4,/' "controller4"

  # 缺的 client 憑證(舊環境升級時補產)
  for n in c3 restproxy bootstrap legacy-orders schema-registry monitor connect; do
    if [ ! -f "certs/client-$n.keystore.p12" ]; then
      openssl_in_certs "
        openssl genrsa -out client-$n.key 2048 2>/dev/null
        openssl req -new -key client-$n.key -subj \"/CN=$n/O=Demo\" -out client-$n.csr
        openssl x509 -req -in client-$n.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out client-$n.pem -days 825 -sha256 2>/dev/null
        openssl pkcs12 -export -in client-$n.pem -inkey client-$n.key -certfile ca.pem -name $n -out client-$n.keystore.p12 -passout pass:$PASS
        chmod 644 client-$n.*"
      echo "補產 client 憑證: $n"
    fi
  done
  # 密碼檔(cp 映像用 *_CREDENTIALS 讀檔)
  for f in keystore_creds sslkey_creds truststore_creds; do [ -f "certs/$f" ] || printf '%s' "$PASS" > "certs/$f"; done
  echo "certs 已存在,略過其餘"; exit 0
fi

# ---------- 全新建立 ----------

say "產生 CA、共用 server 憑證、client 憑證、內部通道憑證、MDS token 金鑰(在 alpine/openssl 容器內)"
docker run --rm -v "$OUT:/certs" --entrypoint sh alpine/openssl -c '
set -e
cd /certs
# --- CA ---
openssl genrsa -out ca.key 4096 2>/dev/null
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 -subj "/CN=Demo Private CA/O=Demo" -out ca.pem
# --- 共用 server 憑證(單一 DN、多 SAN) ---
cat > san.cnf <<EOF
[req]
distinguished_name=dn
req_extensions=v3
prompt=no
[dn]
CN=kafka.demo.local
O=Demo
[v3]
subjectAltName=DNS:kafka.demo.local,DNS:localhost,DNS:controller1,DNS:controller2,DNS:controller3,DNS:controller4,DNS:broker1,DNS:broker2,DNS:broker3,DNS:broker4,DNS:minio,DNS:restproxy,DNS:restproxy1,DNS:restproxy2,DNS:schema-registry1,DNS:schema-registry2,DNS:connect1,DNS:connect2,DNS:control-center,DNS:openldap,DNS:prometheus,DNS:alertmanager,DNS:conjur,DNS:schema-registry,DNS:blackbox-exporter,DNS:grafana,DNS:node-exporter,DNS:kafka-exporter,DNS:loki,DNS:tempo,DNS:connect,DNS:mailpit,IP:127.0.0.1
extendedKeyUsage=serverAuth,clientAuth
EOF
openssl genrsa -out server.key 2048 2>/dev/null
openssl req -new -key server.key -out server.csr -config san.cnf
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out server.pem -days 825 -sha256 -extfile san.cnf -extensions v3 2>/dev/null
openssl pkcs12 -export -in server.pem -inkey server.key -certfile ca.pem -name server -out server.keystore.p12 -passout pass:'"$PASS"'
# --- 對照用:各元件的 client 憑證(不同 DN) ---
for n in c3 restproxy bootstrap legacy-orders schema-registry monitor connect; do
  openssl genrsa -out client-$n.key 2048 2>/dev/null
  openssl req -new -key client-$n.key -subj "/CN=$n/O=Demo" -out client-$n.csr
  openssl x509 -req -in client-$n.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out client-$n.pem -days 825 -sha256 2>/dev/null
  openssl pkcs12 -export -in client-$n.pem -inkey client-$n.key -certfile ca.pem -name $n -out client-$n.keystore.p12 -passout pass:'"$PASS"'
done
# --- 內部通道共用憑證:broker↔broker(INTERNAL)與 broker↔controller(CONTROLLER)都用這一張,做 mTLS 身分 ---
# CN=kafka-internal;SAN 含全部 broker 與 controller(HA 與第 4 台 broker 用)(同一張同時當 server 與 client 憑證,所以 EKU 兩個都要)
cat > internal.cnf <<EOF2
[req]
distinguished_name=dn
req_extensions=v3
prompt=no
[dn]
CN=kafka-internal
O=Demo
[v3]
subjectAltName=DNS:broker1,DNS:broker2,DNS:broker3,DNS:broker4,DNS:controller1,DNS:controller2,DNS:controller3,DNS:controller4,DNS:localhost
extendedKeyUsage=serverAuth,clientAuth
EOF2
openssl genrsa -out internal.key 2048 2>/dev/null
openssl req -new -key internal.key -out internal.csr -config internal.cnf
openssl x509 -req -in internal.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out internal.pem -days 825 -sha256 -extfile internal.cnf -extensions v3 2>/dev/null
openssl pkcs12 -export -in internal.pem -inkey internal.key -certfile ca.pem -name internal -out internal.keystore.p12 -passout pass:'"$PASS"'
# --- MDS token 金鑰 ---
openssl genrsa -out keypair.pem 2048 2>/dev/null
openssl rsa -in keypair.pem -outform PEM -pubout -out public.pem 2>/dev/null
chmod 644 *.pem *.p12 *.key
'

say "建立 truststore(PKCS12),用 cp-server 映像內的 keytool"
docker run --rm -v "$OUT:/certs" --entrypoint bash confluentinc/cp-server:8.3.2 -c "
rm -f /certs/truststore.p12
keytool -importcert -noprompt -alias demo-ca -file /certs/ca.pem -keystore /certs/truststore.p12 -storetype PKCS12 -storepass $PASS >/dev/null
chmod 644 /certs/truststore.p12
"

# keystore / key / truststore 的密碼檔:docker-compose 以 KAFKA_SSL_*_CREDENTIALS 指定檔名,cp 映像啟動時讀取(沒有這三個檔 controller / broker 會啟動失敗)
for f in keystore_creds sslkey_creds truststore_creds; do printf '%s' "$PASS" > "certs/$f"; done
touch certs/.done
echo "OK: certs 完成 → demo/certs"
