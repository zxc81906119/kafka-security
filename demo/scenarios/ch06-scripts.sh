#!/usr/bin/env bash
# ============================================================================
# ch06-scripts.sh — 第 6 章:維運腳本怎麼辦 —— 腳本共用、憑證各人各自;反例:共用帳號 → 稽核看不到「是誰」
# ----------------------------------------------------------------------------
# 白話:全組共用一支維運腳本沒問題,但腳本裡不能寫帳號密碼,而是讀「執行者自己的」client.properties,
#       這樣權限和稽核都跟著人走。反例是全組共用一個帳號:唯讀的人也能寫,audit log 也只看到共用帳號。
# 前置條件:環境已建好;需要 scripts/ops/orders-heartbeat.sh
# 冪等:是。第一步 scripts/chapter-start.sh 把環境收斂到本章起點(不必先跑前面的章節),重跑結果相同。
# 用法:
#   ./demo.sh 6                      經由講解控制台跑這一章
#   ./scenarios/ch06-scripts.sh      直接跑(DEMO_PAUSE=0 不暫停)
# 會改動什麼:
#   建立反面教材用的 SCRAM 帳號 shared-ops,並綁 User:shared-ops 對 orders. 的 DeveloperWrite;往 orders.events 寫入心跳訊息
#   結束前會還原:解除該綁定、以 scripts/scram-disable.sh 停用 shared-ops
# 怎麼判斷成功:每一步印『✔ 符合預期』,最後一行『第 06 章完成(失敗 0 項)』
# 實測結果摘要:
#   同一支腳本:yujie 執行成功(OK: 已送出)、ming 執行被拒(他是 orders-read)——權限跟著各人的設定走
#   共用帳號 shared-ops:yujie、ming 用都成功(連唯讀的人都能寫);audit log 的 principal 全部是 User:shared-ops,看不出是誰
# ============================================================================
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch06 "維運腳本:腳本共用、憑證各人各自"
source "$DEMO_ROOT/scripts/rbac-lib.sh"
step prepare "【起點準備】yujie 在 orders-write(可寫)、ming 只在 orders-read(唯讀);上次留下的 shared-ops 已清掉(冪等:已正確的不動;可單獨從這一章開始,也可重跑)" \
  "scripts/chapter-start.sh ch06" \
  'bash "$DEMO_ROOT/scripts/chapter-start.sh" ch06 2>&1' '\[起點\] ch06 就緒'

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
