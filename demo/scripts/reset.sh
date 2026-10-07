 >/dev/null 2>&1 || true
./scripts/k.sh kafka-configs --bootstrap-server broker1:9094 --command-config /clients/token-bootstrap.properties --alter --delete-config SCRAM-SHA-512 --entity-type users --entity-name shared-ops >/dev/null 2>&1 || true
#!/usr/bin/env bash
# 把 demo 重置回「第 0 章」起始狀態(AD 群組/RBAC/服務帳號),不重建整個叢集:
#  1) LDAP:GARY 在 cluster-admin、topic-admin、rbac-admin、security;YUJIE 在 orders-write;MING 不在任何群組
#  2) RBAC:移除示範用 binding,只保留 bootstrap 建立的 7 組與平台元件
#  3) 服務帳號 svc-orders 密碼還原為 orders-secret-v1,移除輪替用的 svc-orders-v2
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/rbac-lib.sh
GROUPS_ALL="orders-read orders-write ops topic-admin cluster-admin rbac-admin security breakglass"
echo "[reset] LDAP 群組"
for u in gary yujie ming; do for g in $GROUPS_ALL; do ./scripts/ldap-group.sh remove $u $g >/dev/null 2>&1 || true; done; done
for g in cluster-admin topic-admin rbac-admin security; do ./scripts/ldap-group.sh add gary $g >/dev/null 2>&1 || true; done
./scripts/ldap-group.sh add yujie orders-write >/dev/null 2>&1 || true
echo "[reset] RBAC bindings(示範用)"
for r in DeveloperRead DeveloperWrite; do
  rbac_unbind cert bootstrap Group:orders-write $r Topic orders. PREFIXED
  rbac_unbind cert bootstrap Group:orders-read $r Topic orders. PREFIXED
  rbac_unbind cert bootstrap User:svc-orders $r Topic orders. PREFIXED
done
for g in orders-write orders-read; do rbac_unbind cert bootstrap Group:$g DeveloperRead Group demo- PREFIXED; done
rbac_unbind cert bootstrap Group:orders-write DeveloperRead Topic payments. PREFIXED   # Postman M.3 若誤授權的殘留
rbac_unbind cert bootstrap Group:orders-write DeveloperRead Topic infra. PREFIXED
rbac_unbind cert bootstrap User:legacy-orders DeveloperWrite Topic orders. PREFIXED   # 第 12 章 legacy app
rbac_unbind cert bootstrap User:svc-orders-v2 DeveloperWrite Topic orders. PREFIXED   # 第 9 章輪替殘留(中途失敗時)
rbac_unbind basic gary:gary-pw User:shared-ops DeveloperWrite Topic orders. PREFIXED   # 第 6 章反例殘留(中途失敗時)
echo "[reset] 服務帳號"
bash scripts/create-service-account.sh svc-orders orders-secret-v1
./scripts/k.sh kafka-configs --bootstrap-server broker1:9094 --command-config /clients/token-bootstrap.properties --alter --delete-config SCRAM-SHA-512 --entity-type users --entity-name svc-orders-v2 2>/dev/null || true
rm -f config/clients/scram-svc-orders-v2.properties   # 第 9 章產生的暫存設定檔
echo "[reset] 完成"
