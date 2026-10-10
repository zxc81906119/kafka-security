#!/usr/bin/env bash
# ============================================================================
# ch03-rbac-ad-group.sh — 第 3 章:授權怎麼做 —— RBAC 綁 AD 群組;AD 群組異動後 Kafka 端零變更即生效
# ----------------------------------------------------------------------------
# 白話:授權不是一個一個人設,而是在 C3 把「AD 群組 orders-write」綁上 orders.* 的寫入角色。
#       之後只要在 AD 把人加進或移出該群組,Kafka 端什麼都不用改,幾秒內就跟著生效。
# 前置條件:建議先跑過第 1 章(從 reset 後的狀態開始);需要 e2e/ 的 Playwright(操作 C3 與 phpLDAPadmin 的網頁)
# 用法:
#   ./demo.sh 3                          經由講解控制台跑這一章
#   ./scenarios/ch03-rbac-ad-group.sh    直接跑(DEMO_PAUSE=0 不暫停)
# 會改動什麼:
#   在 C3 新增 Group:orders-write 對 orders. 開頭 topic 的角色綁定(DeveloperWrite)
#   在 AD(LDAP)把 ming 加進 orders-write 群組;往 orders.events 寫入測試訊息
#   結束前不還原(第 4 章會接著用這個狀態;scripts/reset.sh 可還原)
# 怎麼判斷成功:每一步印『✔ 符合預期』,最後一行『第 03 章完成(失敗 0 項)』
# 實測結果摘要:
#   授權前 yujie 寫入被拒;在 C3 綁定後 yujie 寫入成功(授權的是 AD 群組,不是個人)
#   MDS API 查 Group:orders-write 可看到 DeveloperWrite 綁定,與 C3 畫面一致
#   ming 不在群組時被拒;AD 加入 ming 後,MDS 重新讀取 LDAP 群組(demo 設定 5 秒,預設 60 秒),ming 不需任何 Kafka 端變更就寫入成功(腳本最多重試 12 輪、每輪間隔 3 秒)
# ============================================================================
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch03 "RBAC 與 AD 群組:授權跟著群組走"
UI() { (cd "$DEMO_ROOT/e2e" && node ch03-ui.mjs "$1" 2>&1 | grep -v '^$'); }

step before "【授權前】yujie 屬於 AD 群組 orders-write,但還沒有任何 role → 寫入被拒" \
  "echo hello | kafka-console-producer --bootstrap-server broker1:9094 --command-config yujie.properties --topic orders.events" \
  'as_produce yujie orders.events before-rbac' 'not authorized|Not authorized|TopicAuthorization'

step c3-assign "【C3 操作】gary 在 Control Center 把 orders.* 的讀寫權限指派給「AD 群組」orders-write(見截圖)" \
  "(瀏覽器)C3 → Administration → Manage role assignments → Topic → Add role assignment" \
  'UI assign-developers' 'Successfully|c3-2-read-saved'

step mds-api "【MDS API / Postman 同一份資料】列出 Group:orders-write 的 role binding —— 與 C3 畫面一致" \
  "curl -u gary:*** -X POST https://broker1:8091/security/1.0/lookup/principal/Group:orders-write/resources" \
  'mds basic gary:gary-pw POST /security/1.0/lookup/principal/Group%3Aorders-write/resources "{\"clusters\":{\"kafka-cluster\":\"XyZBQ3-GTvKH2qNfP7X33A\"}}"' 'DeveloperWrite.*orders'

sleep 5
step yujie-ok "【授權後】yujie 寫入 orders.events 成功(他的權限來自 AD 群組,而不是個人帳號)" \
  "echo order-A-1001 | kafka-console-producer ... --command-config yujie.properties --topic orders.events" \
  'send_result as_produce yujie orders.events order-A-1001' '結果:成功'

step ming-denied "【對照】ming 不在任何群組 → 同一個 topic 被拒" \
  "echo hi | kafka-console-producer ... --command-config ming.properties --topic orders.events" \
  'as_produce ming orders.events hi-from-ming' 'not authorized|Not authorized|TopicAuthorization'

step ldap-add "【AD 操作】在 AD(LDAP 管理介面)把 ming 加進群組 orders-write —— Kafka/RBAC 這邊完全不動" \
  "(瀏覽器)phpLDAPadmin → cn=orders-write → member 加入 CN=MING" \
  'UI add-ming; date +"[%T] 已在 AD 加入 ming"' '已在 AD 加入'

echo "    (等待 MDS 重新讀取 LDAP 群組:demo 設定 5 秒;預設值為 60 秒)"
START=$(date +%s)
step ming-ok "【數秒後】ming 取得權限:同一個指令這次成功" \
  "echo hi | kafka-console-producer ... --command-config ming.properties --topic orders.events" \
  'for i in $(seq 1 12); do out=$(as_produce ming orders.events hello-from-ming 2>&1); echo "$out" | grep -q -i "not authorized\|TopicAuthorization" || { echo "ming 寫入成功(約 $(( $(date +%s) - '"$START"' )) 秒內生效,Kafka 端零變更)"; break; }; sleep 3; done' '寫入成功'

step c3-ming "【C3】ming 重新整理 Control Center:現在看得到 orders.* topics" \
  "(瀏覽器)ming 登入 C3 → Topics" \
  'UI ming-view' 'c3-3-ming-topics'
ch_end
