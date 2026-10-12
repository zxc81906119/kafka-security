#!/usr/bin/env bash
# ============================================================================
# grafana.sh — 啟動或關閉第 26 章的 Grafana、node_exporter、kafka_exporter
# ----------------------------------------------------------------------------
# 白話:Control Center 只看得到 broker 與 controller。Grafana 可以把「全部」放在同一個畫面:
#   Kafka(官方儀表板)、主機的磁碟與 CPU(node_exporter)、consumer 落後多少(kafka_exporter)。
#   這支腳本把要用的東西一次備妥:密碼、AD 查詢帳號、kafka_exporter 專用的 Kafka 帳號(只有 Describe 權限)、
#   官方儀表板(固定版本、校驗雜湊),再啟動三個容器並讓 Prometheus 載入新的抓取設定與告警規則。
# 前置條件:叢集已啟動(scripts/up.sh),Prometheus、Alertmanager 已啟動
#   (docker compose --profile c3 up -d prometheus alertmanager);需要網路下載儀表板與 node_exporter 映像。
# 用法:
#   scripts/grafana.sh on       備妥並啟動(可重複執行)
#   scripts/grafana.sh off      停掉三個容器、移除 Prometheus 的抓取設定(密碼與帳號保留)
#   scripts/grafana.sh status   顯示三個容器的狀態
# 會改動什麼:
#   config/grafana/secrets/ 產生密碼檔、config/grafana/dashboards/ 放官方儀表板、config/c3/grafana_scrape.yml(都不進版本庫);
#   在模擬 AD 新增唯讀查詢帳號 svc-grafana-ldap 並放寬它的讀取權限;
#   在 Kafka 建立 SCRAM 帳號 kafka-exporter 與 ACL(Describe);重啟 prometheus 容器。
#   停用帳號一律不刪除 SCRAM 憑證(KAFKA-20774),所以 off 不動 Kafka 的帳號。
# 怎麼判斷成功:最後印 [grafana] 開頭的完成訊息;容器 healthy。
# 常見失敗:
#   下載儀表板「SHA-256 不符」→ 官方檔案內容和釘定版本不同,先查原因,不要略過
#   Grafana 起不來 → docker logs grafana(常見:密碼檔不存在、憑證路徑錯)
# ============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/kafka.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR"

SECRETS=config/grafana/secrets
DASH_DIR=config/grafana/dashboards
OWN_DASH=config/grafana/own/cp-host-lag.json   # 本專案自己的儀表板(進版本庫)
SERVICES="grafana node-exporter kafka-exporter"
OFFICIAL_COMMIT=f376263fc6d7270185ab6abab9a8c379079e2a92
DASH_URL="https://raw.githubusercontent.com/confluentinc/jmx-monitoring-stacks/$OFFICIAL_COMMIT/jmxexporter-prometheus-grafana/assets/grafana/provisioning/dashboards"
# 官方儀表板與它們的 SHA-256(釘在固定 commit,確保可重現)
DASHBOARDS=(
  "kafka-cluster-kraft.json 298dba58d38054e634eafd5e2b85ad26b92c0d6c6aecf9de65d79c6ff4b4fce3"
  "kafka-topics-kraft.json ae026091d57ac5d4b73ab5bf00dbaa67ac77f7d0abcd0f42af18dbbebb946ee5"
  "kraft.json df3a991a4916da6086dd5540d3d9429039788b36af82c5ff477f738bee4d760f"
  "confluent-platform-kraft.json 3edcece0052b9f678c8e4f3bf737d41b36ec1adb611baa821ba90244e4787b87"
  "confluent-rbac.json fe1145473ccf5f1ecf6a5f7bb2ddb33bed598b6732433af2dd60264ee6d21340"
  # 生態系元件(job schema-registry、kafka-connect、rest-proxy,由各元件的 JMX exporter 提供)
  "schema-registry-cluster.json 65c45eef4a52f6713154cdfa4988e844e2a5b8027fbdb457e4ca427dbfde682e"
  "kafka-connect-cluster.json b93fc882cc413c00198ca684818d1db4db4bdef60b377161a8530eefed61f16a"
  "rest-proxy.json 432c8bae7d0bc9717778fa71ec6ad3c5b6465cbf875b10c09628cfa8628fd464"
)

# 產生一個隨機密碼寫進檔案(檔案已存在就保留)。用法:make_secret <檔案>
make_secret() {
  [ -s "$1" ] || { head -c 18 /dev/urandom | base64 | tr -d '\n=+/' > "$1"; note "產生 $1"; }
}

# 備妥所有密碼檔。prometheus.pw 與 ldap-bind.pw 是測試值(要和 Prometheus 的 bcrypt、模擬 AD 的帳號一致);
# 其餘隨機產生。正式環境全部由 CyberArk 產生、保管與輪替。
prepare_secrets() {
  mkdir -p "$SECRETS" "$DASH_DIR"
  printf '%s' 'graf-prom-pw' > "$SECRETS/prometheus.pw"        # 測試值:對應 web-config-prom.yml 的 grafana 帳號
  printf '%s' 'ldap-grafana-pw' > "$SECRETS/ldap-bind.pw"      # 測試值:對應 ldap/10_users.ldif 的 svc-grafana-ldap
  make_secret "$SECRETS/admin.pw"
  make_secret "$SECRETS/metrics.pw"
  make_secret "$SECRETS/kafka-exporter.pw"
  cp "$SECRETS/metrics.pw" config/c3/grafana_metrics.pw         # Prometheus 抓 Grafana /metrics 用(password_file)
  chmod 644 "$SECRETS"/*.pw config/c3/grafana_metrics.pw         # 容器內的使用者不是檔案擁有者;測試環境簡化,正式環境用 secret 管理
}

# 下載官方儀表板並校驗 SHA-256(已經有而且雜湊正確就略過)。
fetch_dashboards() {
  local entry file want have
  for entry in "${DASHBOARDS[@]}"; do
    file=${entry% *}; want=${entry#* }
    if [ -f "$DASH_DIR/$file" ] && [ "$(sha256sum "$DASH_DIR/$file" | awk '{print $1}')" = "$want" ]; then continue; fi
    say "下載官方儀表板 $file 並校驗 SHA-256"
    curl -sSL --retry 3 -o "$DASH_DIR/$file.tmp" "$DASH_URL/$file"
    have=$(sha256sum "$DASH_DIR/$file.tmp" | awk '{print $1}')
    if [ "$have" != "$want" ]; then rm -f "$DASH_DIR/$file.tmp"; die "SHA-256 不符:$file(釘定 $want / 實際 $have)"; fi
    mv "$DASH_DIR/$file.tmp" "$DASH_DIR/$file"
    note "已取得 $file"
  done
}

# 模擬 AD:新增 Grafana 專用的唯讀查詢帳號,並放寬它的讀取權限(和 broker 用的帳號分開)。可重複執行。
prepare_ldap() {
  local base="dc=corp,dc=demo" dn="cn=svc-grafana-ldap,ou=system,dc=corp,dc=demo"
  if ! docker exec openldap ldapsearch -x -H ldap://localhost -D "cn=admin,$base" -w adminpw -b "$dn" -s base dn >/dev/null 2>&1; then
    say "在模擬 AD 新增 Grafana 的唯讀查詢帳號 svc-grafana-ldap"
    docker exec -i openldap ldapadd -x -H ldap://localhost -D "cn=admin,$base" -w adminpw >/dev/null <<EOF
dn: $dn
objectClass: organizationalRole
objectClass: simpleSecurityObject
cn: svc-grafana-ldap
description: Read-only LDAP query account (bind DN) used by Grafana login
userPassword: ldap-grafana-pw
EOF
  fi
  if ! docker exec openldap ldapsearch -Y EXTERNAL -H ldapi:/// -b "olcDatabase={1}mdb,cn=config" olcAccess 2>/dev/null | grep -q "svc-grafana-ldap"; then
    say "放寬 svc-grafana-ldap 的讀取權限(ACL)"
    docker cp ldap-config/acl-bind-dn.ldif openldap:/tmp/acl-grafana.ldif >/dev/null
    # 把先前的 {2} 規則換成含 Grafana 帳號的版本:先刪除舊的再加新的
    docker exec openldap sh -c 'printf "dn: olcDatabase={1}mdb,cn=config\nchangetype: modify\ndelete: olcAccess\nolcAccess: {2}\n" | ldapmodify -Y EXTERNAL -H ldapi:/// >/dev/null 2>&1; ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/acl-grafana.ldif >/dev/null'
  fi
}

# Kafka:建立 kafka_exporter 專用的 SCRAM 帳號,只給 Describe 權限(topic、group、cluster)。
prepare_kafka_account() {
  local pw; pw=$(cat "$SECRETS/kafka-exporter.pw")
  say "建立 kafka_exporter 專用的 SCRAM 帳號,並只授予 Describe 權限(看得到 topic、group 與 offset,讀不到訊息內容)"
  kafka_configs --entity-type users --entity-name kafka-exporter --alter --add-config "SCRAM-SHA-512=[password=$pw]" | tail -1
  local resource
  for resource in "--topic" "--group" "--cluster"; do
    if [ "$resource" = "--cluster" ]; then
      kafka_acls --add --allow-principal User:kafka-exporter --operation Describe --operation DescribeConfigs --cluster | grep -E 'rror' || true
    else
      kafka_acls --add --allow-principal User:kafka-exporter --operation Describe --operation DescribeConfigs "$resource" '*' | grep -E 'rror' || true
    fi
  done
  note "kafka-exporter 的 ACL:$(kafka_acls --list --principal User:kafka-exporter | grep -c 'ResourcePattern') 個資源(topic *、group *、cluster)"
}

# 等容器 healthy(有 healthcheck 的)或在跑。
wait_running() {
  local c
  for c in "$@"; do wait_until "$c 在跑" 120 docker inspect -f '{{.State.Running}}' "$c" || die "$c 沒有起來:docker logs $c"; done
}

turn_on() {
  need_ha_mode
  need_container prometheus "先執行:docker compose --profile c3 up -d prometheus alertmanager"
  say "備妥密碼、官方儀表板、AD 查詢帳號、kafka_exporter 的 Kafka 帳號"
  prepare_secrets; fetch_dashboards; cp "$OWN_DASH" "$DASH_DIR/"; prepare_ldap; prepare_kafka_account
  say "讓 Prometheus 載入抓取設定、告警規則與 grafana 帳號(重啟 prometheus 容器)"
  cp config/c3/grafana-scrape.tpl config/c3/grafana_scrape.yml
  docker restart prometheus >/dev/null; wait_healthy prometheus >/dev/null
  say "啟動 Grafana、node_exporter、kafka_exporter"
  docker compose --profile grafana up -d $SERVICES >/dev/null 2>&1
  wait_healthy grafana >/dev/null || die "Grafana 沒有 healthy:docker logs grafana"
  wait_running node-exporter kafka-exporter >/dev/null
  note "[grafana] 完成:https://localhost:3000(AD 帳號登入;本機 admin 的密碼在 $SECRETS/admin.pw)"
}

turn_off() {
  say "停掉三個容器並移除 Prometheus 的抓取設定(密碼檔與 Kafka、AD 的帳號保留)"
  docker compose --profile grafana stop $SERVICES >/dev/null 2>&1 || true
  docker compose --profile grafana rm -f $SERVICES >/dev/null 2>&1 || true
  rm -f config/c3/grafana_scrape.yml
  if docker ps --format '{{.Names}}' | grep -qx prometheus; then docker restart prometheus >/dev/null; fi
  note "[grafana] 已關閉"
}

case "${1:-status}" in
  on)     turn_on ;;
  off)    turn_off ;;
  status) docker ps -a --format '{{.Names}} {{.Status}}' | grep -E '^(grafana|node-exporter|kafka-exporter) ' || echo "沒有執行中的 Grafana 相關容器" ;;
  *)      usage_from_header "$0"; exit 1 ;;
esac
