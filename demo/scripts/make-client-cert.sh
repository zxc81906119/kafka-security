#!/usr/bin/env bash
# 為「無法使用 Kafka client 的 legacy app」發一張 client 憑證(由 demo CA 簽發;CN = app 名稱 = RBAC 主體)。
# 用法: scripts/make-client-cert.sh <name>            例: scripts/make-client-cert.sh legacy-orders
#       scripts/make-client-cert.sh <name> --self-signed   產生「非本 CA 簽發」的憑證(對照用:應被拒絕)
# 產出: certs/client-<name>.{key,pem}
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
OUT="$(pwd -W 2>/dev/null || pwd)/certs"
name="$1"; mode="${2:-ca}"
if [ "$mode" = "--self-signed" ]; then
  docker run --rm -v "$OUT:/certs" --entrypoint sh alpine/openssl -c "
    cd /certs; openssl req -x509 -newkey rsa:2048 -nodes -keyout client-$name.key -out client-$name.pem -subj '/CN=$name/O=Demo' -days 2 2>/dev/null
    chmod 644 client-$name.*; openssl x509 -in client-$name.pem -noout -subject -issuer"
else
  docker run --rm -v "$OUT:/certs" --entrypoint sh alpine/openssl -c "
    cd /certs
    [ -f client-$name.pem ] || {
      openssl genrsa -out client-$name.key 2048 2>/dev/null
      openssl req -new -key client-$name.key -subj '/CN=$name/O=Demo' -out client-$name.csr
      openssl x509 -req -in client-$name.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out client-$name.pem -days 825 -sha256 2>/dev/null
      chmod 644 client-$name.*
    }
    openssl x509 -in client-$name.pem -noout -subject -issuer -dates"
fi
