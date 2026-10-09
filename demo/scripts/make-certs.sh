#!/usr/bin/env bash
# 產生 demo 用 CA、「單一共用 server 憑證」、MDS token 金鑰。
# 客戶情境:所有元件共用同一張 server 憑證(同一把 private key、同一個 DN),憑證只做傳輸加密。
# 另外為「對照章節(第 8 章)」產生兩張不同 DN 的 client 憑證,用來示範:共用 DN 無法區分元件。
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
OUT="$(pwd -W 2>/dev/null || pwd)/certs"
mkdir -p certs
PASS=changeit

if [ -f certs/.done ]; then
  # 已有 CA:共用 server 憑證的 SAN 若缺 prometheus / alertmanager(監控 TLS 用),用同一把 key、同一個 CA 重簽(不換身分、不用重發 client 憑證)
  if ! grep -q "DNS:conjur" certs/san.cnf 2>/dev/null; then
    sed -i "s/DNS:openldap,IP:127.0.0.1/DNS:openldap,DNS:prometheus,DNS:alertmanager,DNS:conjur,IP:127.0.0.1/" certs/san.cnf
    docker run --rm -v "$OUT:/certs" --entrypoint sh alpine/openssl -c "cd /certs; openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out server.pem -days 825 -sha256 -extfile san.cnf -extensions v3 2>/dev/null; openssl pkcs12 -export -in server.pem -inkey server.key -certfile ca.pem -name server -out server.keystore.p12 -passout pass:$PASS; chmod 644 server.*"
    echo "server 憑證 SAN 已補 prometheus / alertmanager / conjur(同 key、同 CA)"
  fi
  # 已有 CA:共用 server 憑證的 SAN 若缺 schema-registry(第 20 章),同樣用同一把 key、同一個 CA 重簽
  if ! grep -q "DNS:schema-registry" certs/san.cnf 2>/dev/null; then
    sed -i "s/DNS:conjur,IP:127.0.0.1/DNS:conjur,DNS:schema-registry,IP:127.0.0.1/" certs/san.cnf
    docker run --rm -v "$OUT:/certs" --entrypoint sh alpine/openssl -c "cd /certs; openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out server.pem -days 825 -sha256 -extfile san.cnf -extensions v3 2>/dev/null; openssl pkcs12 -export -in server.pem -inkey server.key -certfile ca.pem -name server -out server.keystore.p12 -passout pass:$PASS; chmod 644 server.pem server.keystore.p12"
    echo "server 憑證 SAN 已補 schema-registry(同 key、同 CA)"
  fi
  # 已有 CA:補產內部通道共用憑證(CN=kafka-internal,mTLS;broker↔broker 與 broker↔controller 共用)
  if [ ! -f certs/internal.keystore.p12 ]; then
    docker run --rm -v "$OUT:/certs" --entrypoint sh alpine/openssl -c "cd /certs; printf '[req]\ndistinguished_name=dn\nreq_extensions=v3\nprompt=no\n[dn]\nCN=kafka-internal\nO=Demo\n[v3]\nsubjectAltName=DNS:broker1,DNS:broker2,DNS:controller1,DNS:localhost\nextendedKeyUsage=serverAuth,clientAuth\n' > internal.cnf; openssl genrsa -out internal.key 2048 2>/dev/null; openssl req -new -key internal.key -out internal.csr -config internal.cnf; openssl x509 -req -in internal.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out internal.pem -days 825 -sha256 -extfile internal.cnf -extensions v3 2>/dev/null; openssl pkcs12 -export -in internal.pem -inkey internal.key -certfile ca.pem -name internal -out internal.keystore.p12 -passout pass:$PASS; chmod 644 internal.* "
    echo "補產內部通道共用憑證: internal(CN=kafka-internal)"
  fi
  # 已有 CA:僅補產缺少的 client 憑證
  for n in c3 restproxy bootstrap legacy-orders schema-registry; do
    if [ ! -f certs/client-$n.keystore.p12 ]; then
      docker run --rm -v "$OUT:/certs" --entrypoint sh alpine/openssl -c "cd /certs; openssl genrsa -out client-$n.key 2048 2>/dev/null; openssl req -new -key client-$n.key -subj \"/CN=$n/O=Demo\" -out client-$n.csr; openssl x509 -req -in client-$n.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out client-$n.pem -days 825 -sha256 2>/dev/null; openssl pkcs12 -export -in client-$n.pem -inkey client-$n.key -certfile ca.pem -name $n -out client-$n.keystore.p12 -passout pass:$PASS; chmod 644 client-$n.*"
      echo "補產 client 憑證: $n"
    fi
  done
  for f in keystore_creds sslkey_creds truststore_creds; do [ -f certs/$f ] || printf '%s' "$PASS" > certs/$f; done   # 密碼檔(cp 映像用 *_CREDENTIALS 讀檔)
  echo "certs 已存在,略過其餘"; exit 0
fi

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
subjectAltName=DNS:kafka.demo.local,DNS:localhost,DNS:controller1,DNS:broker1,DNS:broker2,DNS:restproxy,DNS:control-center,DNS:openldap,DNS:prometheus,DNS:alertmanager,DNS:conjur,DNS:schema-registry,IP:127.0.0.1
extendedKeyUsage=serverAuth,clientAuth
EOF
openssl genrsa -out server.key 2048 2>/dev/null
openssl req -new -key server.key -out server.csr -config san.cnf
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out server.pem -days 825 -sha256 -extfile san.cnf -extensions v3 2>/dev/null
openssl pkcs12 -export -in server.pem -inkey server.key -certfile ca.pem -name server -out server.keystore.p12 -passout pass:'"$PASS"'
# --- 對照用:兩張不同 DN 的 client 憑證 ---
for n in c3 restproxy bootstrap legacy-orders schema-registry; do
  openssl genrsa -out client-$n.key 2048 2>/dev/null
  openssl req -new -key client-$n.key -subj "/CN=$n/O=Demo" -out client-$n.csr
  openssl x509 -req -in client-$n.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out client-$n.pem -days 825 -sha256 2>/dev/null
  openssl pkcs12 -export -in client-$n.pem -inkey client-$n.key -certfile ca.pem -name $n -out client-$n.keystore.p12 -passout pass:'"$PASS"'
done
# --- 內部通道共用憑證:broker↔broker(INTERNAL)與 broker↔controller(CONTROLLER)都用這一張,做 mTLS 身分 ---
# CN=kafka-internal;SAN 含 broker1、broker2、controller1(同一張同時當 server 與 client 憑證,所以 EKU 兩個都要)
cat > internal.cnf <<EOF2
[req]
distinguished_name=dn
req_extensions=v3
prompt=no
[dn]
CN=kafka-internal
O=Demo
[v3]
subjectAltName=DNS:broker1,DNS:broker2,DNS:controller1,DNS:localhost
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
# truststore(PKCS12),用 cp-server 內的 keytool
docker run --rm -v "$OUT:/certs" --entrypoint bash confluentinc/cp-server:8.3.2 -c "
rm -f /certs/truststore.p12
keytool -importcert -noprompt -alias demo-ca -file /certs/ca.pem -keystore /certs/truststore.p12 -storetype PKCS12 -storepass $PASS >/dev/null
chmod 644 /certs/truststore.p12
"
# keystore / key / truststore 的密碼檔:docker-compose 以 KAFKA_SSL_*_CREDENTIALS 指定檔名,cp 映像啟動時讀取(沒有這三個檔 controller / broker 會啟動失敗)
for f in keystore_creds sslkey_creds truststore_creds; do printf '%s' "$PASS" > certs/$f; done
touch certs/.done
echo "OK: certs 完成 → demo/certs"
