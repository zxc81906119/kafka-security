#!/usr/bin/env bash
# ============================================================================
# connect-setup.sh — 啟動或關閉第 29 章的 Kafka Connect(RBAC、每個連接器自己的身分、config provider)
# ----------------------------------------------------------------------------
# 白話:Connect 是「把資料搬進搬出 Kafka」的服務,連接器(connector)是它跑的工作。兩個安全重點:
#   (1) 誰能建立、查看、刪除連接器——交給 AD 群組與 RBAC(和其他元件同一套);
#   (2) 連接器讀寫 Kafka 用什麼身分——每個連接器用自己的 AD 服務帳號(最小權限),不共用 worker 的大權限。
#   這支腳本備妥:worker 的 client 憑證與角色、連接器的 AD 服務帳號與角色、使用者(群組)對連接器的角色、外掛、密碼檔。
# 前置條件:HA 模式(scripts/ha.sh on);記憶體吃緊時先 scripts/observability.sh off、docker stop control-center
# 用法:
#   scripts/connect-setup.sh on       備妥並啟動(可重複執行)
#   scripts/connect-setup.sh off      停掉 Connect(topic、角色、帳號保留)
#   scripts/connect-setup.sh status   顯示容器狀態
# 會改動什麼:config/connect/plugins/ 放下載的外掛 jar、config/connect/secrets/ 放連接器密碼檔(都不進版本庫);
#   在模擬 AD 新增服務帳號 SVC-ORDERS-SINK;用 MDS 建立角色綁定;建立 topic orders.sink、orders.sink.dlq。
# 怎麼判斷成功:最後印 [connect] 就緒;gary 能列出連接器(REST 回 200)。
# 常見失敗:worker 起不來 → docker logs connect(常見:角色還沒生效、topic 沒有權限);REST 403 → 角色綁定的 scope 要含 connect-cluster
# ============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/kafka.sh"
source "$(dirname "${BASH_SOURCE[0]}")/rbac-lib.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR"

PLUGIN_DIR=config/connect/plugins/connect-file
SECRETS=config/connect/secrets
FILE_CONNECTOR_VERSION=4.3.1
FILE_CONNECTOR_URL="https://repo1.maven.org/maven2/org/apache/kafka/connect-file/$FILE_CONNECTOR_VERSION/connect-file-$FILE_CONNECTOR_VERSION.jar"
CONNECT_CLUSTER_ID=connect-cluster          # = worker 的 group.id
SINK_USER=SVC-ORDERS-SINK                   # 連接器 orders-sink 專用的 AD 服務帳號(使用者名稱 = CN)
SINK_PASSWORD='connector-orders-sink-pw'    # 測試值;正式環境由 CyberArk 產生、保管與輪替,寫進密碼檔的動作也由 CyberArk 完成

# 下載外掛:Apache Kafka 的 connect-file(FileStream 連接器,示範用),校驗 Maven Central 一併發佈的 SHA-1。
fetch_plugin() {
  mkdir -p "$PLUGIN_DIR"
  local jar="$PLUGIN_DIR/connect-file-$FILE_CONNECTOR_VERSION.jar" want have
  [ -s "$jar" ] && return 0
  say "下載 connect-file $FILE_CONNECTOR_VERSION 並校驗 SHA-1(Confluent 映像不含 FileStream 連接器)"
  curl -sSL --retry 3 -o "$jar.tmp" "$FILE_CONNECTOR_URL"
  want=$(curl -sSL "$FILE_CONNECTOR_URL.sha1" | tr -d ' \r\n' | cut -c1-40); have=$(sha1sum "$jar.tmp" | awk '{print $1}')
  if [ -z "$want" ] || [ "$want" != "$have" ]; then rm -f "$jar.tmp"; die "SHA-1 不符或取不到校驗值(官方 $want / 實際 $have)"; fi
  mv "$jar.tmp" "$jar"; note "已取得 $jar"
}

# 模擬 AD:新增連接器的服務帳號(已存在就略過)。
prepare_ad_account() {
  local base="dc=corp,dc=demo" dn="cn=$SINK_USER,ou=svc,ou=users,dc=corp,dc=demo"
  if docker exec openldap ldapsearch -x -H ldap://localhost -D "cn=admin,$base" -w adminpw -b "$dn" -s base dn >/dev/null 2>&1; then return 0; fi
  say "在模擬 AD 新增服務帳號 $SINK_USER(放在 ou=svc 底下)"
  docker exec -i openldap ldapadd -x -H ldap://localhost -D "cn=admin,$base" -w adminpw >/dev/null 2>&1 <<EOF || true
dn: ou=svc,ou=users,$base
objectClass: organizationalUnit
ou: svc

dn: $dn
objectClass: inetOrgPerson
cn: $SINK_USER
sn: ConnectorOrdersSink
displayName: Kafka Connect orders-sink connector service account
userPassword: $SINK_PASSWORD
EOF
}

# 連接器的密碼檔:config provider 的 FileConfigProvider 讀 key=value 格式。正式環境這個檔案由 CyberArk 產生並定期輪替。
prepare_secret_file() {
  mkdir -p "$SECRETS"
  printf 'username=%s\npassword=%s\n' "$SINK_USER" "$SINK_PASSWORD" > "$SECRETS/orders-sink.properties"
  chmod 644 "$SECRETS/orders-sink.properties"       # 容器內的使用者不是檔案擁有者;測試環境簡化
}

# Connect 叢集範圍的角色綁定(scope 多一個 connect-cluster):connect_bind <principal> <role> [<資源類型> <名稱> <pattern>]
connect_bind() {
  local enc="${1/:/%3A}" scope body path
  scope="{\"clusters\":{\"kafka-cluster\":\"$KAFKA_CLUSTER_ID\",\"connect-cluster\":\"$CONNECT_CLUSTER_ID\"}}"
  if [ -n "${3:-}" ]; then
    path="/security/1.0/principals/$enc/roles/$2/bindings"
    body="{\"scope\":$scope,\"resourcePatterns\":[{\"resourceType\":\"$3\",\"name\":\"$4\",\"patternType\":\"${5:-LITERAL}\"}]}"
  else
    path="/security/1.0/principals/$enc/roles/$2"; body="$scope"
  fi
  note "bind $1 $2 ${3:+$3:$4} -> $(bash scripts/mds.sh cert bootstrap POST "$path" "$body" | tail -1)"
}

# 角色綁定。worker:存放自己狀態的 topic 與 group;連接器的服務帳號:只能讀自己的來源 topic、寫自己的 DLQ;人:依 AD 群組。
prepare_roles() {
  say "worker(client 憑證 CN=connect)的角色:自己的內部 topic(connect- 開頭)、group connect-cluster、授權查詢(SecurityAdmin)"
  rbac_bind cert bootstrap User:connect ResourceOwner Topic connect- PREFIXED
  rbac_bind cert bootstrap User:connect ResourceOwner Group connect-cluster LITERAL
  rbac_bind cert bootstrap User:connect DeveloperRead Topic _confluent-command LITERAL
  rbac_bind cert bootstrap User:connect DeveloperWrite Topic _confluent-command LITERAL
  connect_bind User:connect SecurityAdmin
  say "連接器 orders-sink 的服務帳號 $SINK_USER:只讀 orders.sink、group connect-orders- 開頭(連接器的 group 固定叫 connect-<連接器名稱>)、只寫自己的 DLQ"
  rbac_bind cert bootstrap "User:$SINK_USER" DeveloperRead Topic orders.sink LITERAL
  rbac_bind cert bootstrap "User:$SINK_USER" DeveloperRead Group connect-orders- PREFIXED
  rbac_bind cert bootstrap "User:$SINK_USER" DeveloperWrite Topic orders.sink.dlq LITERAL
  say "使用者(AD 群組)對連接器的角色:topic-admin 管全部、orders-write 只管 orders- 開頭的連接器"
  connect_bind Group:topic-admin ResourceOwner Connector '*' LITERAL
  connect_bind Group:orders-write ResourceOwner Connector orders- PREFIXED
}

prepare_topics() {
  local t
  for t in orders.sink orders.sink.dlq; do
    kafka_topics --create --if-not-exists --topic "$t" --partitions 1 --replication-factor 3 --config min.insync.replicas=2 | grep -E "Created|rror|already" || true
  done
}

turn_on() {
  need_ha_mode
  bash scripts/make-certs.sh >/dev/null           # 補 connect 的 client 憑證(已有的略過)
  fetch_plugin; prepare_ad_account; prepare_secret_file; prepare_topics; prepare_roles
  say "啟動 Connect worker"
  docker compose --profile connect up -d connect1 connect2 >/dev/null 2>&1
  wait_healthy connect1 connect2 >/dev/null || die "Connect 沒有 healthy:docker logs connect1 / connect2"
  say "等 REST 與授權就緒(gary 可以列出連接器)"
  wait_until "gary 能列出連接器" 180 connect_rest_ready || die "REST 授權沒有就緒:docker logs connect1"
  note "[connect] 就緒:https://localhost:8083(AD 帳密,Basic)"
}

connect_rest_ready() {
  [ "$(dcurl -u gary:gary-pw https://connect:8083/connectors 2>/dev/null | tail -1)" = "[HTTP 200]" ]
}

turn_off() {
  say "停掉 Connect(Kafka 裡的內部 topic、角色與 AD 帳號保留)"
  docker compose --profile connect stop connect1 connect2 >/dev/null 2>&1 || true
  docker compose --profile connect rm -f connect1 connect2 >/dev/null 2>&1 || true
  note "[connect] 已關閉"
}

case "${1:-status}" in
  on)     turn_on ;;
  off)    turn_off ;;
  status) docker ps -a --format '{{.Names}} {{.Status}}' | grep -E '^connect[12] ' || echo "Connect 沒有在跑" ;;
  *)      usage_from_header "$0"; exit 1 ;;
esac
