#!/usr/bin/env bash
# 第 9 章(選修):服務密碼輪替(新帳號並行再停舊)、內部通道(CONTROLLER / INTERNAL)、AD 故障時的行為
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch09 "輪替、內部通道、AD 故障"
source "$DEMO_ROOT/scripts/rbac-lib.sh"
PROP="$DEMO_ROOT/config/clients"

# ---- A. 服務密碼輪替:新帳號並行 → 切換 → 停舊 ----
step rot-new "【輪替 1/4】建立新帳號 svc-orders-v2(新密碼)並給同樣的 RBAC 權限 —— 新舊並行,不中斷" \
  "kafka-configs --alter ... --entity-name svc-orders-v2   +   role binding(同 svc-orders)" \
  'bash "$DEMO_ROOT/scripts/create-service-account.sh" svc-orders-v2 orders-secret-v2; rbac_bind cert bootstrap User:svc-orders-v2 DeveloperWrite Topic orders. PREFIXED' 'HTTP 204'
sed 's/svc-orders" password="orders-secret-v1/svc-orders-v2" password="orders-secret-v2/' "$PROP/scram-svc-orders.properties" > "$PROP/scram-svc-orders-v2.properties"
sleep 5
step rot-both "【輪替 2/4】新舊帳號同時可用(應用逐步切換到新帳號)" \
  "producer(svc-orders)  與  producer(svc-orders-v2)" \
  'send_result svc_produce scram-svc-orders orders.events old-pw; send_result svc_produce scram-svc-orders-v2 orders.events new-pw' '結果:成功'
step rot-stop-old "【輪替 3/4】全部應用切換完成 → 停用舊帳號(刪除舊憑證)" \
  "kafka-configs --alter --delete-config SCRAM-SHA-512 --entity-name svc-orders" \
  'K kafka-configs --bootstrap-server $BOOT --command-config /clients/token-bootstrap.properties --alter --delete-config SCRAM-SHA-512 --entity-type users --entity-name svc-orders' 'Completed updating config'
step rot-old-dead "【輪替 4/4】舊密碼立刻失效;新帳號照常" \
  "producer(舊密碼)  /  producer(svc-orders-v2)" \
  'send_result svc_produce scram-svc-orders orders.events old-pw | tail -2; send_result svc_produce scram-svc-orders-v2 orders.events new-pw | tail -1' '結果:被拒絕'
# 還原
bash "$DEMO_ROOT/scripts/create-service-account.sh" svc-orders orders-secret-v1 >/dev/null

# ---- B. 內部通道不接受「人」或「未授權」的連線 ----
step ctl-anon "【內部通道】CONTROLLER 埠(9093):只有 TLS、沒有 SASL 身分的連線 → 拒絕"   "kafka-broker-api-versions --bootstrap-server controller1:9093 --command-config ssl-only.properties"   'K kafka-broker-api-versions --bootstrap-server controller1:9093 --command-config /clients/ssl-only.properties 2>&1 | head -3' 'Disconnected|disconnected|Timed out|timed out|fail|Fail|authenticat'
step ctl-ad "【內部通道】用 AD 人員帳密(yujie)連 CONTROLLER → 拒絕(controller 只認內部靜態帳號,不查 AD)" \
  "kafka-broker-api-versions --bootstrap-server controller1:9093 --command-config yujie.properties" \
  'K kafka-broker-api-versions --bootstrap-server controller1:9093 --command-config /clients/plain-yujie.properties 2>&1 | head -3' 'Authentication failed|authentication'
step int-svc "【內部通道】INTERNAL 埠(9092)只是另一個 SASL 埠:有效的 SCRAM 帳號(svc-orders)能「認證」進去 —— 所以必須靠防火牆只開放給 broker/controller 節點"   "kafka-topics --bootstrap-server broker1:9092 --command-config svc-orders.properties --list"   'K kafka-topics --bootstrap-server broker1:9092 --command-config /clients/scram-svc-orders.properties --list 2>&1 | grep -v "^_" | head -4' 'orders.events'
step int-svc-authz "【內部通道】但授權仍然生效:svc-orders 即使連上 INTERNAL 埠,也不能做叢集管理(建立 topic → 被拒)"   "kafka-topics --bootstrap-server broker1:9092 --command-config svc-orders.properties --create --topic hack"   'K kafka-topics --bootstrap-server broker1:9092 --command-config /clients/scram-svc-orders.properties --create --topic hack --partitions 1 --replication-factor 2 2>&1 | head -3' 'Authorization failed|not authorized|Not authorized|TopicAuthorization'

# ---- C. AD 故障時 ----
echo "    ── AD(LDAP)故障演練:停掉 openldap 容器 ──"
docker stop openldap >/dev/null
sleep 3
step ad-down-svc "【AD 掛了】服務(SCRAM)不受影響:svc-orders 照常寫入" \
  "(openldap 已停止)  producer(svc-orders)" \
  'send_result svc_produce scram-svc-orders orders.events during-ad-outage' '結果:成功'
step ad-down-human "【AD 掛了】人的「新登入」失敗:yujie 以 AD 帳密連線 → 無法驗證" \
  "(openldap 已停止)  producer(yujie)" \
  'send_result as_produce yujie orders.events during-ad-outage | tail -3' '結果:被拒絕'
docker start openldap >/dev/null; sleep 12
step ad-up "【AD 恢復】人的登入恢復" \
  "(openldap 已啟動)  producer(yujie)" \
  'for i in $(seq 1 8); do r=$(send_result as_produce yujie orders.events after-ad-recovery | tail -1); echo "$r" | grep -q "成功" && break; sleep 4; done; echo "$r"' '結果:成功'
rbac_unbind cert bootstrap User:svc-orders-v2 DeveloperWrite Topic orders. PREFIXED >/dev/null
K kafka-configs --bootstrap-server $BOOT --command-config /clients/token-bootstrap.properties --alter --delete-config SCRAM-SHA-512 --entity-type users --entity-name svc-orders-v2 >/dev/null 2>&1
ch_end
