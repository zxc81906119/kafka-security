 >/dev/null 2>&1 || true
bash scripts/scram-disable.sh shared-ops >/dev/null 2>&1 || true   # 不用 --delete-config:刪除 SCRAM 憑證會讓之後重啟 broker 失敗(見 scram-disable.sh)
#!/usr/bin/env bash
# ============================================================================
# reset.sh — 把 demo 重置回「第 0 章」起始狀態(AD 群組、RBAC、服務帳號),不重建整個叢集
# ----------------------------------------------------------------------------
# 白話:示範各章會改 AD 群組、授權和服務帳號密碼。每次要重新示範、或跑完一輪要回到乾淨狀態時,
#   跑這支就能把「示範用的變動」全部還原,比重建整個叢集快得多。
# 前置條件:demo 環境已啟動(scripts/up.sh)。
# 用法:
#   scripts/reset.sh        (也可用 ./demo.sh reset)
# 會改動什麼(做完即是還原後的狀態,不需再還原):
#   1) LDAP:GARY 在 cluster-admin、topic-admin、rbac-admin、security;YUJIE 在 orders-write;MING 不在任何群組
#   2) RBAC:移除示範用 binding(orders. 開頭 topic 的 DeveloperRead/Write、demo- 開頭 consumer group 的讀取、
#      payments./infra. 的殘留授權、legacy-orders、svc-orders-v2、shared-ops 的殘留綁定),只保留 bootstrap 建立的 7 組與平台元件
#   3) 服務帳號 svc-orders 密碼還原為 orders-secret-v1;停用輪替用的 svc-orders-v2 與 shared-ops
#      (SCRAM 憑證覆寫成隨機密碼,不用 --delete-config:刪除 SCRAM 憑證會讓之後重啟 broker 失敗,見 scram-disable.sh);
#      刪除第 9 章產生的暫存設定檔 config/clients/scram-svc-orders-v2.properties
# 怎麼判斷成功:最後印「[reset] 完成」。各步驟的失敗多半被忽略(|| true),所以這行只代表跑完,不代表每一步都成功。
# ============================================================================
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
bash scripts/scram-disable.sh svc-orders-v2 >/dev/null 2>&1 || true
rm -f config/clients/scram-svc-orders-v2.properties   # 第 9 章產生的暫存設定檔
echo "[reset] 完成"
