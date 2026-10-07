#!/usr/bin/env bash
# 第 11 章(進階):維運分權 —— 平常人人唯讀,「看叢集」「管 topic」「管授權」拆成不同 AD 群組,需要時經核准臨時加入、做完收回
# 2026-10-07 依「簡報的 7 組」重寫:ops = Operator、topic-admin = ResourceOwner(Topic*、Group*)、rbac-admin = UserAdmin。
# 三組的 role binding 在 bootstrap 時就綁好,日常這些群組是空的;臨時提權 = 只在 AD 把人加進群組,Kafka 端零變更。
# 能力以實測為準(spike/group-roles-aligned/run.log):ops 看得到 topic 清單但不能建、不能讀、不能改授權;
# topic-admin 能建/刪 topic、讀資料、並且能在自己的 Topic* 範圍內改授權(所以是強角色);rbac-admin 只能改授權。
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch11 "維運分權:唯讀 / 維運(ops)/ topic 管理(topic-admin)/ 授權管理(rbac-admin)"
source "$DEMO_ROOT/scripts/rbac-lib.sh"
UI() { (cd "$DEMO_ROOT/e2e" && node ch11-ui.mjs "$@" 2>&1 | grep -v '^$'); }
CL='{"clusters":{"kafka-cluster":"XyZBQ3-GTvKH2qNfP7X33A"}}'
BIND_DEV='{"scope":{"clusters":{"kafka-cluster":"XyZBQ3-GTvKH2qNfP7X33A"}},"resourcePatterns":[{"resourceType":"Topic","name":"infra.","patternType":"PREFIXED"}]}'
as_admin() { K kafka-topics --bootstrap-server $BOOT --command-config /clients/token-bootstrap.properties "$@"; }
DENY='not authorized|Not authorized|Authorization failed|authorization failed|TopicAuthorization|Topic authorization'
# AD 群組異動後確認結果(之前只印「完成」,UI 操作失敗也看不出來):grant = 應該在群組內、revoke = 不應該在
ldap_check() { local has=0; docker exec openldap ldapsearch -x -LLL -D cn=admin,dc=corp,dc=demo -w adminpw -b "cn=$3,ou=groups,dc=corp,dc=demo" member | grep -qi "^member: cn=$2," && has=1; [ "$1" = grant ] && [ $has = 1 ] && return 0; [ "$1" = revoke ] && [ $has = 0 ] && return 0; echo "AD 群組異動沒有生效:$1 $2 $3"; return 1; }

# ---- 起始狀態:ming 唯讀(orders-read)、yujie 一般開發者(orders-write)、三個維運群組都沒有人;清掉上次殘留 ----
for u in yujie ming; do for g in ops topic-admin rbac-admin; do ldapg remove $u $g >/dev/null 2>&1; done; done
ldapg remove ming orders-write >/dev/null 2>&1; ldapg add ming orders-read >/dev/null 2>&1
rbac_unbind cert bootstrap Group:orders-write DeveloperRead Topic infra. PREFIXED >/dev/null
as_admin --delete --topic infra.ops-demo >/dev/null 2>&1
rbac_bind basic gary:gary-pw Group:orders-read DeveloperRead Topic orders. PREFIXED >/dev/null
# consumer group 的讀取權(console consumer 需要)與測試資料:讓「讀得到/讀不到」只取決於 topic 權限
rbac_bind basic gary:gary-pw Group:orders-read DeveloperRead Group demo- PREFIXED >/dev/null
rbac_bind basic gary:gary-pw Group:orders-write DeveloperRead Group demo- PREFIXED >/dev/null
echo '{"order":"A-1001"}' | K kafka-console-producer --bootstrap-server $BOOT --command-config /clients/plain-gary.properties --topic orders.events >/dev/null 2>&1
sleep 6

step matrix "【角色對照】三個維運群組的 role 在 bootstrap 時就綁好了,日常這些群組是空的(gary 以 MDS API 查詢)" \
  "POST /security/1.0/lookup/rolebindings/principal/Group:<群組>" \
  'for g in ops topic-admin rbac-admin; do mds basic gary:gary-pw POST "/security/1.0/lookup/rolebindings/principal/Group%3A$g" "$CL" | grep -o "\"Group:[a-z-]*\":{\"[A-Za-z]*\""; done' 'Operator.*|ResourceOwner|UserAdmin'

step c3-matrix "【C3】gary 在 Manage role assignments 檢視:群組 → 角色" \
  "(瀏覽器)C3 → Administration → Manage role assignments → Cluster / Topic" \
  'UI c3-matrix' 'c11-2-matrix-topic'

sleep 6
step ming-daily "【日常】ming(orders-read)可讀資料" \
  "kafka-console-consumer --command-config ming.properties --topic orders.events --from-beginning" \
  'as_consume ming orders.events' 'Processed a total of [1-9]'

step yujie-before "【日常】yujie 想建立 infra.ops-demo topic → 被拒(他是開發者,不是 topic 管理)" \
  "kafka-topics --command-config yujie.properties --create --topic infra.ops-demo" \
  'K kafka-topics --bootstrap-server $BOOT --command-config /clients/plain-yujie.properties --create --topic infra.ops-demo --partitions 1 --replication-factor 2' "$DENY"

# ---- 第一種提權:ops(Operator)——看得到叢集,但什麼都改不了 ----
step grant-ops "【臨時提權 1】經核准,AD 管理員把 yujie 加進 ops(Kafka 端零變更)" \
  "(瀏覽器)phpLDAPadmin:ops 加入 yujie" \
  'UI grant yujie ops; ldap_check grant yujie ops && date +"[%T] AD 群組異動完成"' '群組異動完成'
echo "    (等 MDS 讀取 LDAP 變更 …)"; sleep 10

step ops-limits "【分權重點】ops(Operator)能看叢集,但不能建 topic:yujie 建立 infra.ops-demo → 仍被拒" \
  "kafka-topics --command-config yujie.properties --create --topic infra.ops-demo" \
  'K kafka-topics --bootstrap-server $BOOT --command-config /clients/plain-yujie.properties --create --topic infra.ops-demo --partitions 1 --replication-factor 2' "$DENY"

step ops-noacl "【分權重點】ops 也不能改授權:yujie 嘗試給 orders-write 開 infra.* 讀取權 → 403" \
  "POST /security/1.0/principals/Group:orders-write/roles/DeveloperRead/bindings   # yujie" \
  'mds basic yujie:yujie-pw POST /security/1.0/principals/Group%3Aorders-write/roles/DeveloperRead/bindings "$BIND_DEV"' 'HTTP 403'

step ops-revoke "【收回 1】AD 管理員把 yujie 移出 ops" \
  "(瀏覽器)phpLDAPadmin:ops 移除 yujie" \
  'UI revoke yujie ops; ldap_check revoke yujie ops && date +"[%T] AD 群組異動完成"' '群組異動完成'
echo "    (等 MDS 讀取 LDAP 變更 …)"; sleep 10

# ---- 第二種提權:topic-admin(ResourceOwner)——能管 topic,但是強角色 ----
step grant-topic "【臨時提權 2】經核准,AD 管理員把 yujie 加進 topic-admin" \
  "(瀏覽器)phpLDAPadmin:topic-admin 加入 yujie" \
  'UI grant yujie topic-admin; ldap_check grant yujie topic-admin && date +"[%T] AD 群組異動完成"' '群組異動完成'
echo "    (等 MDS 讀取 LDAP 變更 …)"; sleep 10

step topic-create "【topic 管理】yujie(topic-admin)建立 infra.ops-demo → 成功" \
  "kafka-topics --command-config yujie.properties --create --topic infra.ops-demo" \
  'K kafka-topics --bootstrap-server $BOOT --command-config /clients/plain-yujie.properties --create --topic infra.ops-demo --partitions 1 --replication-factor 2' 'Created topic infra.ops-demo'

# 先由 gary 放一筆資料,讓「讀得到」可以被看見
echo "ops-secret-1" | K kafka-console-producer --bootstrap-server $BOOT --command-config /clients/plain-gary.properties --topic infra.ops-demo >/dev/null 2>&1
step topic-read "【注意:這是強角色】ResourceOwner 連資料都讀得到:yujie 消費 infra.ops-demo → 讀到 ops-secret-1" \
  "kafka-console-consumer --command-config yujie.properties --topic infra.ops-demo --from-beginning" \
  'as_consume yujie infra.ops-demo' 'ops-secret-1'

step topic-acl "【注意:這是強角色】在自己的 Topic* 範圍內還能改授權:yujie 給 orders-write 開 infra.* 讀取權 → 204" \
  "POST /security/1.0/principals/Group:orders-write/roles/DeveloperRead/bindings   # yujie(topic-admin)" \
  'mds basic yujie:yujie-pw POST /security/1.0/principals/Group%3Aorders-write/roles/DeveloperRead/bindings "$BIND_DEV"' 'HTTP 204'
rbac_unbind cert bootstrap Group:orders-write DeveloperRead Topic infra. PREFIXED >/dev/null   # 這條只是示範,先收掉,後面才看得出 rbac-admin 的效果

step topic-revoke "【收回 2】工作完成:AD 管理員把 yujie 移出 topic-admin" \
  "(瀏覽器)phpLDAPadmin:topic-admin 移除 yujie" \
  'UI revoke yujie topic-admin; ldap_check revoke yujie topic-admin && date +"[%T] AD 群組異動完成"' '群組異動完成'
echo "    (等 MDS 讀取 LDAP 變更 …)"; sleep 10

# ---- 第三種提權:rbac-admin(UserAdmin)——只管授權 ----
step grant-rbac "【臨時提權 3】經核准,AD 管理員把 ming 加進 rbac-admin" \
  "(瀏覽器)phpLDAPadmin:rbac-admin 加入 ming" \
  'UI grant ming rbac-admin; ldap_check grant ming rbac-admin && date +"[%T] AD 群組異動完成"' '群組異動完成'
echo "    (等 MDS 讀取 LDAP 變更 …)"; sleep 10

step rbac-bind "【授權管理】ming(rbac-admin)可以調整授權:替 orders-write 開 infra.* 讀取權 → 204" \
  "POST /security/1.0/principals/Group:orders-write/roles/DeveloperRead/bindings   # ming" \
  'mds basic ming:ming-pw POST /security/1.0/principals/Group%3Aorders-write/roles/DeveloperRead/bindings "$BIND_DEV"' 'HTTP 204'

step rbac-nodata "【分權重點】授權管理者不能管 topic:ming 建立 topic → 被拒(rbac-admin 只管授權)" \
  "kafka-topics --command-config ming.properties --create --topic infra.ming-test" \
  'K kafka-topics --bootstrap-server $BOOT --command-config /clients/plain-ming.properties --create --topic infra.ming-test --partitions 1 --replication-factor 2' "$DENY"

sleep 6
step dev-effect "授權生效:yujie(開發者)現在讀得到 infra.ops-demo" \
  "kafka-console-consumer --command-config yujie.properties --topic infra.ops-demo --from-beginning" \
  'as_consume yujie infra.ops-demo demo-yujie-effect' 'ops-secret-1'

step rbac-revoke "【收回 3】AD 管理員把 ming 移出 rbac-admin" \
  "(瀏覽器)phpLDAPadmin:rbac-admin 移除 ming" \
  'UI revoke ming rbac-admin; ldap_check revoke ming rbac-admin && date +"[%T] AD 群組異動完成"' '群組異動完成'
echo "    (等 MDS 讀取 LDAP 變更 …)"; sleep 10

step topic-revoked "收回後:yujie 再建立 topic → 又被拒(回到日常開發者狀態)" \
  "kafka-topics --command-config yujie.properties --create --topic infra.ops-demo2" \
  'K kafka-topics --bootstrap-server $BOOT --command-config /clients/plain-yujie.properties --create --topic infra.ops-demo2 --partitions 1 --replication-factor 2' "$DENY"

step rbac-revoked "收回後:ming 再改授權 → 403" \
  "POST .../roles/DeveloperRead/bindings   # ming" \
  'mds basic ming:ming-pw POST /security/1.0/principals/Group%3Aorders-write/roles/DeveloperRead/bindings "$BIND_DEV"' 'HTTP 403'

echo "    (等待 audit log …)"; sleep 8
step audit "【稽核】誰在什麼時候做了授權變更、誰被拒:mds.Authorize 與 infra.* 的事件" \
  "kafka-console-consumer --topic confluent-audit-log-events | 整理" \
  'audit_events --method "^(mds\.Authorize|kafka\.CreateTopics)$" --topic "^infra\." --last 10' 'User:YUJIE.*DENIED|User:MING.*ALLOWED'
EV_SHOW=14 true
# 清理
rbac_unbind cert bootstrap Group:orders-write DeveloperRead Topic infra. PREFIXED >/dev/null
rbac_unbind cert bootstrap Group:orders-read DeveloperRead Group demo- PREFIXED >/dev/null
rbac_unbind cert bootstrap Group:orders-write DeveloperRead Group demo- PREFIXED >/dev/null
rbac_unbind cert bootstrap Group:orders-read DeveloperRead Topic orders. PREFIXED >/dev/null
as_admin --delete --topic infra.ops-demo >/dev/null 2>&1
ch_end
