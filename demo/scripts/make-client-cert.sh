#!/usr/bin/env bash
# ============================================================================
# make-client-cert.sh — 為 legacy app 發一張 client 憑證
# ----------------------------------------------------------------------------
# 白話:無法使用 Kafka client 的 legacy app 改用 client 憑證(mTLS)證明身分。憑證由 demo CA 簽發,
#   CN = app 名稱 = RBAC 主體。加 --self-signed 會產生「非本 CA 簽發」的憑證,供對照(應被拒絕)。
# 前置條件:certs/ 內有 ca.pem 與 ca.key(demo CA);Docker 可用
# 用法:
#   scripts/make-client-cert.sh <name>                 例: scripts/make-client-cert.sh legacy-orders
#   scripts/make-client-cert.sh <name> --self-signed   產生「非本 CA 簽發」的憑證(對照用:應被拒絕)
#   產出: certs/client-<name>.{key,pem}
# 會改動什麼:在 certs/ 建立 client-<name>.key 與 client-<name>.pem(CA 簽發版若 .pem 已存在就不重發,效期 825 天;
#   自簽版每次覆寫,效期 2 天)。不會自動刪除。
# 怎麼判斷成功:最後印出憑證的 subject、issuer(CA 簽發版另印 dates);CA 簽發版 issuer 應是 demo CA,自簽版 subject 與 issuer 相同。
# ============================================================================
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
