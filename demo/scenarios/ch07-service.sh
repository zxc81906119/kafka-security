#!/usr/bin/env bash
# ============================================================================
# ch07-service.sh — 第 7 章:機器(不在 AD)—— 服務身分 = Kafka 內的 SCRAM 帳號,授權仍走 RBAC,且最小權限
# ----------------------------------------------------------------------------
# 白話:機器 / 應用程式不在 AD 裡,所以用 Kafka 內建的 SCRAM 帳號當服務身分(密碼放密碼庫)。
#       授權仍然走同一套 RBAC,與 AD 群組並列在 C3 同一張表,而且只給最小權限。
# 前置條件:環境已建好;需要 e2e/ 的 Playwright(操作 C3);scripts/create-service-account.sh、scripts/rbac-lib.sh
# 冪等:是。第一步 scripts/chapter-start.sh 把環境收斂到本章起點(不必先跑前面的章節),重跑結果相同。
# 用法:
#   ./demo.sh 7                      經由講解控制台跑這一章
#   ./scenarios/ch07-service.sh      直接跑(DEMO_PAUSE=0 不暫停)
# 會改動什麼:
#   建立 SCRAM 帳號 svc-orders(密碼 orders-secret-v1);在 C3 指派 User:svc-orders 對 orders. 的 DeveloperWrite
#   在 config/clients/ 產生 scram-svc-orders-wrong.properties、plain-svc-orders.properties(測試用設定檔);往 orders.events 寫入一則訊息
#   結束前不還原(第 9 章會接著用 svc-orders;scripts/reset.sh 可還原)
# 怎麼判斷成功:每一步印『✔ 符合預期』,最後一行『第 07 章完成(失敗 0 項)』
# 實測結果摘要:
#   授權前 svc-orders 認證成功但寫入被拒;在 C3 授權後寫入成功
#   最小權限:svc-orders 寫 payments.* 被拒
#   密碼錯誤 → SCRAM 認證失敗;用 AD(SASL/PLAIN)方式驗證 svc-orders → 失敗,服務身分與人完全分開
#   audit log 看得到 principal = User:svc-orders
# ============================================================================
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch07 "機器怎麼辦(不在 AD):服務帳號 SCRAM + RBAC"
source "$DEMO_ROOT/scripts/rbac-lib.sh"
UI() { (cd "$DEMO_ROOT/e2e" && node ch07-ui.mjs "$1" 2>&1 | grep -v '^$'); }

step prepare "【起點準備】svc-orders 還沒有任何示範綁定(冪等:已正確的不動;可單獨從這一章開始,也可重跑)" \
  "scripts/chapter-start.sh ch07" \
  'bash "$DEMO_ROOT/scripts/chapter-start.sh" ch07 2>&1' '\[起點\] ch07 就緒'
step create-svc "【建立服務身分】AD 裡沒有這個帳號:在 Kafka 內建立 SCRAM 帳號 svc-orders(密碼存密碼庫,不是 AD)" \
  "kafka-configs --alter --add-config 'SCRAM-SHA-512=[password=***]' --entity-type users --entity-name svc-orders" \
  'bash "$DEMO_ROOT/scripts/create-service-account.sh" svc-orders orders-secret-v1' 'Completed updating config for user svc-orders'

step svc-before "【授權前】svc-orders 認證成功,但還沒有任何 role → 寫入被拒" \
  "echo order | kafka-console-producer --command-config svc-orders.properties --topic orders.events" \
  'svc_produce scram-svc-orders orders.events before-rbac' 'not authorized|Not authorized|TopicAuthorization'

step c3-svc "【C3 操作】gary 在 Control Center 把 orders.* 的寫入權限指派給「User:svc-orders」—— 與 AD 群組並列在同一張表" \
  "(瀏覽器)C3 → Manage role assignments → Topic → Add role assignment(User / svc-orders / DeveloperWrite / orders.)" \
  'UI assign-svc' 'c7-1-svc-saved'

sleep 5
step svc-ok "【授權後】svc-orders 寫入 orders.events 成功" \
  "echo order-S-1 | kafka-console-producer --command-config svc-orders.properties --topic orders.events" \
  'send_result svc_produce scram-svc-orders orders.events order-S-1' '結果:成功'

step svc-denied "【最小權限】svc-orders 碰 payments.* → 被拒" \
  "echo x | kafka-console-producer --command-config svc-orders.properties --topic payments.events" \
  'svc_produce scram-svc-orders payments.events x' 'not authorized|Not authorized|TopicAuthorization'

step svc-wrongpw "【密碼錯誤】SCRAM 認證失敗" \
  "kafka-topics --command-config svc-orders-wrong.properties --list" \
  'sed "s/orders-secret-v1/WRONG/" "$DEMO_ROOT/config/clients/scram-svc-orders.properties" > "$DEMO_ROOT/config/clients/scram-svc-orders-wrong.properties"; K kafka-topics --bootstrap-server $BOOT --command-config /clients/scram-svc-orders-wrong.properties --list' 'Authentication failed'

step svc-not-ad "【不在 AD】用 AD 的方式(LDAP)驗證 svc-orders → 失敗;服務身分與人完全分開" \
  "kafka-topics --command-config plain-svc-orders.properties --list     # SASL/PLAIN 走 AD" \
  'sed "s/yujie/svc-orders/; s/svc-orders-pw/orders-secret-v1/; s/\"svc-orders\" password=\"yujie-pw\"/\"svc-orders\" password=\"orders-secret-v1\"/" "$DEMO_ROOT/config/clients/plain-yujie.properties" > "$DEMO_ROOT/config/clients/plain-svc-orders.properties"; K kafka-topics --bootstrap-server $BOOT --command-config /clients/plain-svc-orders.properties --list' 'Authentication failed'

echo "    (等待 audit log …)"; sleep 8
step audit "【稽核】audit log:服務的行為也看得到(principal = User:svc-orders)" \
  "kafka-console-consumer --topic confluent-audit-log-events | 整理" \
  'audit_events --topic "^(orders|payments)\." --last 60 | grep "svc-orders" | tail -5' 'User:svc-orders'
ch_end
