#!/usr/bin/env bash
# 第 6 章:維運腳本怎麼辦 —— 腳本共用、憑證各人各自;反例:共用帳號 → 稽核看不到「是誰」
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch06 "維運腳本:腳本共用、憑證各人各自"
source "$DEMO_ROOT/scripts/rbac-lib.sh"

step script-content "【一支腳本,全組共用】腳本裡沒有任何帳號密碼" \
  "cat orders-heartbeat.sh" 'cat "$DEMO_ROOT/scripts/ops/orders-heartbeat.sh" | grep -v "^#"' 'CFG='

step yujie-run "【yujie 執行】讀的是他自己的 ~/.kafka/client.properties(AD 帳號 yujie)→ 成功" \
  "HOME=~yujie  ./orders-heartbeat.sh" \
  'as_script yujie orders-heartbeat.sh' 'OK: 已送出'

step ming-run "【ming 執行】同一支腳本,讀的是 ming 自己的設定(他是 orders-read)→ 被拒" \
  "HOME=~ming  ./orders-heartbeat.sh" \
  'as_script ming orders-heartbeat.sh' 'not authorized|Not authorized|TopicAuthorization|Cluster authorization failed'

# 反面教材:建立「共用維運帳號」
bash "$DEMO_ROOT/scripts/create-service-account.sh" shared-ops shared-ops-secret >/dev/null
rbac_bind basic gary:gary-pw User:shared-ops DeveloperWrite Topic orders. PREFIXED >/dev/null
sleep 5
step shared-yujie "【反面教材】全組共用一份 client.properties(帳號 shared-ops):yujie 用 → 成功" \
  "HOME=~shared  ./orders-heartbeat.sh        # yujie 執行" \
  'as_script shared orders-heartbeat.sh' 'OK: 已送出'
step shared-ming "【反面教材】同一份共用設定,換 ming 用 → 也成功(連唯讀的人都能寫了!)" \
  "HOME=~shared  ./orders-heartbeat.sh        # ming 執行" \
  'as_script shared orders-heartbeat.sh' 'OK: 已送出'

echo "    (等待 audit log 寫入 …)"; sleep 8
step audit "【稽核:誰做了什麼】orders.events 的 audit log(最近事件)" \
  "kafka-console-consumer --topic confluent-audit-log-events | 整理" \
  'audit_events --method "^kafka\.Produce$" --topic "^orders\.events$" --last 7' 'User:shared-ops.*ALLOWED'
EV_SHOW=14 true
# 清理反面教材
rbac_unbind basic gary:gary-pw User:shared-ops DeveloperWrite Topic orders. PREFIXED >/dev/null
bash "$DEMO_ROOT/scripts/scram-disable.sh" shared-ops >/dev/null 2>&1
ch_end
