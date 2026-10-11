#!/usr/bin/env bash
# ============================================================================
# ch09-rotate-internal.sh — 第 9 章(選修):服務密碼輪替(新帳號並行再停舊)、內部通道(CONTROLLER / INTERNAL)、AD 故障時的行為
# ----------------------------------------------------------------------------
# 白話:三個維運演練。A 服務密碼輪替:先建新帳號並行、切換完再停舊,不中斷服務。
#       B 內部通道:CONTROLLER / INTERNAL 埠只認 mTLS 憑證,帳密與沒憑證的連線都進不去,連上也沒有超級權限。
#       C AD 故障:AD 掛了時服務(SCRAM)照常運作,但人的新登入失敗,AD 恢復後即恢復。
# 前置條件:需先跑過第 3 章(yujie 所在的 orders-write 對 orders. 的寫入權限)與第 7 章(svc-orders 帳號與寫入權限已存在);Docker 可用(會停止 / 啟動 openldap 容器);config/clients/ 需有 mtls-legacy-orders.properties 等設定檔
# 用法:
#   ./demo.sh 9                            經由講解控制台跑這一章
#   ./scenarios/ch09-rotate-internal.sh    直接跑(DEMO_PAUSE=0 不暫停)
# 會改動什麼:
#   建立 svc-orders-v2(SCRAM 帳號 + User:svc-orders-v2 對 orders. 的 DeveloperWrite 綁定),並產生 config/clients/scram-svc-orders-v2.properties
#   停用 svc-orders(覆寫成隨機密碼),隨後以 create-service-account.sh 還原成 orders-secret-v1
#   docker stop openldap 後再 docker start openldap(等 12 秒);往 orders.events 寫入數則測試訊息
#   結束前還原:解除 svc-orders-v2 的綁定並停用該帳號(scram-disable.sh)
# 怎麼判斷成功:每一步印『✔ 符合預期』,最後一行『第 09 章完成(失敗 0 項)』
# 實測結果摘要:
#   輪替:新舊帳號並行都可寫;停舊後舊密碼立刻失效、新帳號照常;停用是覆寫成隨機密碼,不用 --delete-config
#   CONTROLLER 埠(9093)是 mTLS:無憑證在 TLS 握手就被拒;SCRAM 帳密也被拒(此埠不接受 SASL,只認憑證)
#   INTERNAL 埠(9092)也是 mTLS:同一個 CA 簽的任何 client 憑證(如 CN=legacy-orders)都能完成 TLS 並列出 topic,所以仍要靠防火牆只開放給 broker / controller 節點
#   授權仍生效:CN=legacy-orders 不是 super user,連上 INTERNAL 埠也不能建立 topic;只有 CN=kafka-internal(broker 與 controller 共用)是 super user
#   AD 掛掉:服務(SCRAM)照常寫入,人的新登入失敗;AD 恢復後人的登入恢復
# ============================================================================
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
step int-svc-authz "【內部通道】但授權仍然生效:CN=legacy-orders 不是 super user,連上 INTERNAL 埠也不能做叢集管理(建立 topic → 被拒);只有 CN=kafka-internal(broker 與 controller 共用那張)才是 super user"   "kafka-topics --bootstrap-server broker1:9092 --command-config mtls-legacy-orders.properties --create --topic hack"   'K kafka-topics --bootstrap-server broker1:9092 --command-config /clients/mtls-legacy-orders.properties --create --topic hack --partitions 1 --replication-factor 3 2>&1 | head -3' 'Authorization failed|not authorized|Not authorized|TopicAuthorization'

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
