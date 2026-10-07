#!/usr/bin/env bash
# 第 3 章:授權怎麼做 —— RBAC 綁 AD 群組;AD 群組異動後 Kafka 端零變更即生效
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
