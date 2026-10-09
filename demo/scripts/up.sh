#!/usr/bin/env bash
# 一鍵啟動核心環境(LDAP + KRaft controller + 2 brokers + MDS RBAC),並完成初始化。
# 用法: scripts/up.sh [--with-restproxy] [--with-c3]
set -euo pipefail
cd "$(dirname "$0")/.."
hp() { local v; v=$(sed -n "s/^HOST_PORT_$1=//p" .env 2>/dev/null | tail -1); echo "${v:-$2}"; }   # 主機埠:.env 的 HOST_PORT_* 覆蓋(Windows 保留埠範圍時用),預設同 docker-compose.yml
export MSYS_NO_PATHCONV=1
PROFILES=""
for a in "$@"; do case "$a" in --with-restproxy) PROFILES="$PROFILES --profile restproxy";; --with-c3) PROFILES="$PROFILES --profile c3";; esac; done

# HA 模式(scripts/ha.sh on)時:3 台 controller、3 台 broker、topic 副本 3
if grep -q '^COMPOSE_FILE=.*docker-compose.ha.yml' .env 2>/dev/null; then CTRLS="controller1 controller2 controller3"; BROKERS="broker1 broker2 broker3"; RF=3; else CTRLS="controller1"; BROKERS="broker1 broker2"; RF=2; fi
bash scripts/make-certs.sh
echo "[up] 啟動 LDAP(模擬 AD)與 controller ..."
docker compose up -d --wait --wait-timeout 180 openldap ldapadmin $CTRLS   # --wait:等 healthcheck 通過(openldap、controller1)
echo "[up] 等待 LDAP 種子資料 ..."
for i in $(seq 1 30); do docker exec openldap ldapsearch -x -H ldap://localhost -b dc=corp,dc=demo -D cn=admin,dc=corp,dc=demo -w adminpw "(uid=gary)" dn 2>/dev/null | grep -q "uid=gary" && break; sleep 2; done
echo "[up] 授權 bind DN 唯讀查詢帳號(userPassword 仍不可讀)"
docker cp ldap-config/acl-bind-dn.ldif openldap:/tmp/acl.ldif >/dev/null
docker exec openldap ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/acl.ldif >/dev/null 2>&1 || echo "  (ACL 可能已套用)"
echo "[up] 載入密碼政策(ppolicy;鎖定預設關閉,第 19 章才打開)"
docker cp ldap-config/ppolicy-overlay.ldif openldap:/tmp/pp-overlay.ldif >/dev/null; docker cp ldap-config/ppolicy-default.ldif openldap:/tmp/pp-default.ldif >/dev/null
docker exec openldap ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/pp-overlay.ldif >/dev/null 2>&1 || echo "  (ppolicy overlay 可能已載入)"
docker exec openldap ldapadd -x -H ldap://localhost -D cn=admin,dc=corp,dc=demo -w adminpw -f /tmp/pp-default.ldif >/dev/null 2>&1 || echo "  (密碼政策項目可能已存在)"
echo "[up] 啟動 brokers ..."
docker compose up -d --wait --wait-timeout 240 $BROKERS
echo "[up] 等待 MDS ..."
for i in $(seq 1 60); do [ "$(curl -sk -o /dev/null -w '%{http_code}' https://localhost:$(hp MDS 8091)/security/1.0/features)" = 200 ] && break; sleep 4; done
sleep 8
echo "[up] bootstrap 身分建立第一批 role binding"
bash scripts/bootstrap-rbac.sh
echo "[up] 建立服務帳號與 topics"
bash scripts/create-service-account.sh svc-orders orders-secret-v1
for t in orders.events orders.payments payments.events; do
  ./scripts/k.sh kafka-topics --bootstrap-server broker1:9094 --command-config /clients/token-bootstrap.properties --create --if-not-exists --topic "$t" --partitions 1 --replication-factor $RF 2>&1 | grep -v "^WARNING\|SLF4J" | tail -1 || true
done
if [ -n "$PROFILES" ]; then echo "[up] 啟動選用元件: $PROFILES"; docker compose $PROFILES up -d --wait --wait-timeout 300; fi
echo "[up] 完成。"
