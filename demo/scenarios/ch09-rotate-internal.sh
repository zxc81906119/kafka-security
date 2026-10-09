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
step rot-stop-old "【輪替 3/4】全部應用切換完成 → 停用舊帳號(把舊憑證覆寫成隨機密碼;不刪除)" \
  "scripts/scram-disable.sh svc-orders   # 覆寫成隨機密碼,不用 --delete-config" \
  'bash "$DEMO_ROOT/scripts/scram-disable.sh" svc-orders' 'Completed updating config'
step rot-old-dead "【輪替 4/4】舊密碼立刻失效;新帳號照常" \
  "producer(舊密碼)  /  producer(svc-orders-v2)" \
  'send_result svc_produce scram-svc-orders orders.events old-pw | tail -2; send_result svc_produce scram-svc-orders-v2 orders.events new-pw | tail -1' '結果:被拒絕'
# 還原
bash "$DEMO_ROOT/scripts/create-service-account.sh" svc-orders orders-secret-v1 >/dev/null

# ---- B. 內部通道不接受「人」或「未授權」的連線 ----
step ctl-anon "【內部通道】CONTROLLER 埠(9093)是 mTLS:沒有 client 憑證的連線 → TLS 握手就被拒(不是 SASL,帳密在這裡沒有用)"   "kafka-broker-api-versions --bootstrap-server controller1:9093 --command-config ssl-only.properties"   'K kafka-broker-api-versions --bootstrap-server controller1:9093 --command-config /clients/ssl-only.properties 2>&1 | head -3' 'Disconnected|disconnected|Timed out|timed out|fail|Fail|authenticat|handshake'
step ctl-ad "【內部通道】拿 SCRAM 帳密(svc-orders)連 CONTROLLER → 拒絕:這個埠根本不接受 SASL,只認憑證" \
  "kafka-broker-api-versions --bootstrap-server controller1:9093 --command-config svc-orders.properties" \
  'K kafka-broker-api-versions --bootstrap-server controller1:9093 --command-config /clients/scram-svc-orders.properties 2>&1 | head -3' 'handshake is not completed|Authentication failed|authentication|isconnected'
step int-svc "【內部通道】INTERNAL 埠(9092)也是 mTLS:同一個 CA 簽的任何 client 憑證(這裡用 CN=legacy-orders)都能完成 TLS、能列出 topic —— 所以仍然要靠防火牆只開放給 broker/controller 節點"   "kafka-topics --bootstrap-server broker1:9092 --command-config mtls-legacy-orders.properties --list"   'K kafka-topics --bootstrap-server broker1:9092 --command-config /clients/mtls-legacy-orders.properties --list 2>&1 | head -4' '__internal_confluent_only_broker_info|orders.events'
step int-svc-authz "【內部通道】但授權仍然生效:CN=legacy-orders 不是 super user,連上 INTERNAL 埠也不能做叢集管理(建立 topic → 被拒);只有 CN=kafka-internal(broker 與 controller 共用那張)才是 super user"   "kafka-topics --bootstrap-server broker1:9092 --command-config mtls-legacy-orders.properties --create --topic hack"   'K kafka-topics --bootstrap-server broker1:9092 --command-config /clients/mtls-legacy-orders.properties --create --topic hack --partitions 1 --replication-factor 2 2>&1 | head -3' 'Authorization failed|not authorized|Not authorized|TopicAuthorization'

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
bash "$DEMO_ROOT/scripts/scram-disable.sh" svc-orders-v2 >/dev/null 2>&1
ch_end
