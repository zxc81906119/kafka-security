#!/usr/bin/env bash
# ============================================================================
# dr-setup.sh — 第 36 章的前置:啟動 DR 站、建立 Cluster Linking(主站 → DR 站)
# ----------------------------------------------------------------------------
# 白話:DR 站是另一座 Kafka 叢集(demo 為縮小版:1 controller + 3 broker),用同一個 AD、同一個行內 CA,但有自己的 MDS / RBAC。
#   Cluster Linking 由 DR 站主動連主站(官方預設的方向:destination-initiated),把指定的 topic 鏡像過來(mirror topic,唯讀),
#   並同步 consumer group 的 offset;切換時 DR 站的 consumer 從接近的位置接著讀。
#   link 的身分是主站上的 SCRAM 服務帳號 svc-dr-link(官方有範例的做法;用 MDS token 的寫法官方沒有範例),在主站只有讀取權限。
# 前置條件:主站已啟動(scripts/up.sh)。記憶體:DR 站約 3 GB;這支腳本會先暫停 Connect×2 與 Control Center(DR Lab 期間)。
# 用法:
#   scripts/dr-setup.sh up        啟動 DR 站、DR 端 RBAC 基本綁定、主站建 link 帳號與授權、在 DR 站建立 link
#   scripts/dr-setup.sh down      刪除 DR 站(容器與資料)、主站的 link 帳號停用;恢復 Connect 與 C3
#   scripts/dr-setup.sh status    DR 站容器與 link 狀態
# 會改動什麼:啟動 dr-controller1、dr-broker1~3;config/dr/secrets/(link 帳號密碼與設定,不進版本庫);
#   主站新增 SCRAM 帳號 svc-dr-link 與 DeveloperRead 綁定(Topic dr. / orders.、Group dr-);DR 站建立 link main-to-dr。
# 怎麼判斷成功:最後印 [dr] 完成,status 顯示 link 為 ACTIVE。
# ============================================================================
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/kafka.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR" || exit 1
export MSYS_NO_PATHCONV=1
source scripts/rbac-lib.sh

DR_ID=6UO2af5JhMr17GUHZbnmug
DR_BOOT=dr-broker1:9094,dr-broker2:9094,dr-broker3:9094
DR_ADMIN=/clients/token-bootstrap-dr.properties
SEC=config/dr/secrets
LINK=main-to-dr
# 同步 offset 的 consumer group 範圍:開啟 offset 同步時,CLI 要求用 --consumer-group-filters-json-file 傳入(寫在 link 設定檔裡會被拒絕)
GF_JSON='{"groupFilters":[{"name":"dr-","patternType":"PREFIXED","filterType":"INCLUDE"}]}'
DC=(docker compose -f docker-compose.yml -f docker-compose.dr.yml --profile dr)

# dr_kafka <工具> <參數…>:以 DR 站的 bootstrap 身分執行 Kafka CLI
dr_kafka() { local t="$1"; shift; "$DEMO_DIR/scripts/k.sh" "$t" --bootstrap-server "$DR_BOOT" --command-config "$DR_ADMIN" "$@"; }

# link_status:link 的狀態(只取名稱、主站是否連得到、狀態,例如「main-to-dr 主站可連:true 狀態:ACTIVE」)
link_status() {
  dr_kafka kafka-cluster-links --list 2>/dev/null | grep -E "Link name: '$LINK'" \
    | sed -E "s/.*Link name: '([^']*)'.*remote cluster available: '([^']*)'.*link state: '([^']*)'.*/\1 主站可連:\2 狀態:\3/"
}

case "${1:-status}" in
  up)
    bash scripts/make-certs.sh >/dev/null                                   # 補 dr-* 的 SAN(server 與內部憑證)
    say "暫停 Connect×2 與 Control Center(DR Lab 期間騰出記憶體;結束時 scripts/dr-setup.sh down 會恢復)"
    docker stop connect1 connect2 control-center >/dev/null 2>&1 || true
    say "啟動 DR 站(1 controller + 3 broker)"
    "${DC[@]}" up -d --wait --wait-timeout 300 dr-controller1 dr-broker1 dr-broker2 dr-broker3 2>&1 | grep -E "Healthy|Error" | tail -4
    wait_until "DR 站的 MDS 就緒" 180 bash -c "[ \"\$(bash '$DEMO_DIR/scripts/dcurl.sh' -o /dev/null https://dr-broker1:8091/security/1.0/features | tail -1)\" = '[HTTP 200]' ]" >/dev/null \
      || die "DR 站 MDS 沒有就緒:docker logs dr-broker1"
    say "DR 站的 RBAC 基本綁定(與主站相同的 7 組 AD 群組與平台元件;各應用的業務授權不在這裡——RBAC 不會隨 Cluster Linking 同步)"
    MDS_URL=https://dr-broker1:8091 KAFKA_CLUSTER_ID=$DR_ID bash scripts/bootstrap-rbac.sh 2>&1 | grep -cE "HTTP 20[0-9]" | sed 's/^/  成功的綁定:/'
    say "主站:link 專用服務帳號 svc-dr-link(SCRAM;密碼隨機產生,不進版本庫),只給讀取權限"
    mkdir -p "$SEC"
    [ -s "$SEC/link-password" ] || head -c 18 /dev/urandom | base64 | tr -d '\n=+/' > "$SEC/link-password"
    bash scripts/create-service-account.sh svc-dr-link "$(cat "$SEC/link-password")" | tail -1
    for t in dr. orders.; do rbac_bind cert bootstrap User:svc-dr-link DeveloperRead Topic "$t" PREFIXED; done
    rbac_bind cert bootstrap User:svc-dr-link DeveloperRead Group dr- PREFIXED
    # 建鏡像時 link 要讀來源 topic 的設定(DescribeConfigs);DeveloperRead 只含 Read、Describe(實測被拒:Denied Operation = DescribeConfigs)。
    #   只補這一項用 ACL(本叢集 access.rule.providers 含 KRAFT_ACL),不用 DeveloperManage(會多出建立、刪除、改設定)
    for t in dr. orders.; do kafka_acls --add --allow-principal User:svc-dr-link --operation DescribeConfigs --topic "$t" --resource-pattern-type prefixed 2>&1 | grep -E "Adding" | head -1; done
    say "DR 站:建立 link $LINK(DR 主動連主站;同步 dr- 開頭 consumer group 的 offset)"
    cat > "$SEC/link.properties" <<EOF
bootstrap.servers=broker1:9094,broker2:9094,broker3:9094,broker4:9094
security.protocol=SASL_SSL
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="svc-dr-link" password="$(cat "$SEC/link-password")";
ssl.truststore.location=/etc/kafka/secrets/truststore.p12
ssl.truststore.type=PKCS12
ssl.truststore.password=changeit
consumer.offset.sync.enable=true
consumer.offset.sync.ms=5000
EOF
    chmod 600 "$SEC/link.properties"
    "$DEMO_DIR/scripts/k.sh" bash -c "cat > /tmp/link.properties; printf %s '$GF_JSON' > /tmp/gf.json; kafka-cluster-links --bootstrap-server $DR_BOOT --command-config $DR_ADMIN --create --link $LINK --config-file /tmp/link.properties --consumer-group-filters-json-file /tmp/gf.json; rm -f /tmp/link.properties /tmp/gf.json" < "$SEC/link.properties" 2>&1 | grep -vE "^WARN|SLF4J|^\s*--|^\s{20,}" | tail -3
    sleep 5; echo "link:"; link_status || die "link $LINK 沒有建立成功"
    note "[dr] 完成" ;;
  down)
    say "刪除 DR 站(容器與資料);停用主站的 link 帳號;恢復 Connect 與 Control Center"
    "${DC[@]}" rm -sfv dr-controller1 dr-broker1 dr-broker2 dr-broker3 >/dev/null 2>&1
    bash scripts/scram-disable.sh svc-dr-link >/dev/null 2>&1 || true
    for t in dr. orders.; do rbac_unbind cert bootstrap User:svc-dr-link DeveloperRead Topic "$t" PREFIXED >/dev/null; done
    rbac_unbind cert bootstrap User:svc-dr-link DeveloperRead Group dr- PREFIXED >/dev/null
    for t in dr. orders.; do kafka_acls --remove --force --allow-principal User:svc-dr-link --operation DescribeConfigs --topic "$t" --resource-pattern-type prefixed >/dev/null 2>&1; done
    docker start connect1 connect2 control-center >/dev/null 2>&1 || true
    note "[dr] 已移除 DR 站" ;;
  status)
    docker ps --format '{{.Names}} {{.Status}}' | grep -E '^dr-' || echo "DR 站沒有在跑"
    link_status || true ;;
  *) usage_from_header "$0"; exit 1 ;;
esac
