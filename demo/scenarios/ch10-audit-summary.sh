#!/usr/bin/env bash
# ============================================================================
# ch10-audit-summary.sh — 第 10 章:收尾 —— audit log 彙整整場 demo:誰、做了什麼、結果
# ----------------------------------------------------------------------------
# 白話:把前面各章累積在 audit log(confluent-audit-log-events topic)裡的事件整理成彙總,
#       回答「誰、做了什麼、結果如何」:被擋下的動作、被允許的動作、誰嘗試改過授權。
# 前置條件:環境已建好
# 冪等:是。本章開頭自己製造要彙整的事件(允許、被拒、改授權被拒),不依賴前面跑過哪些章;重跑時彙總數字會累加(稽核日誌只增不減,這是正確行為),判定只看本章產生的事件。
# 用法:
#   ./demo.sh 10                           經由講解控制台跑這一章
#   ./scenarios/ch10-audit-summary.sh      直接跑(DEMO_PAUSE=0 不暫停)
# 會改動什麼:看不出有改動(只讀取 audit log topic 並彙總)
# 怎麼判斷成功:每一步印『✔ 符合預期』(輸出含 DENIED / ALLOWED / mds.Authorize),最後一行『第 10 章完成(失敗 0 項)』
# 實測結果摘要:
#   被拒絕事件、被允許事件分別依次數 / principal / 動作 / 資源彙總
#   權限變更紀錄(MDS mds.Authorize / AlterAccess)中,非管理員的嘗試也被記錄
# ============================================================================
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch10 "收尾:audit log 彙整(誰、做了什麼、結果)"
step prepare "【起點準備】yujie 可寫、ming 唯讀(冪等:已正確的不動;可單獨從這一章開始,也可重跑)" \
  "scripts/chapter-start.sh ch10" \
  'bash "$DEMO_ROOT/scripts/chapter-start.sh" ch10 2>&1' '\[起點\] ch10 就緒'
step make-events "【本章自己製造事件】yujie 寫入 orders.events(允許)、ming 寫入 orders.events(被拒);改授權被拒的事件在最後一步由 yujie 自己製造" \
  "kafka-console-producer(yujie / ming)" \
  'send_result as_produce yujie orders.events audit-ok | tail -1; send_result as_produce ming orders.events audit-denied | tail -1; sleep 8; echo "事件已產生"' '事件已產生'

step audit-denied "【被拒絕的事件】整場 demo 中,被 RBAC 擋下來的動作(次數 / principal / 動作 / 資源)" \
  "kafka-console-consumer --topic confluent-audit-log-events  | granted=false 彙總" \
  'audit_events --topic "^(orders|payments)\." --granted false --summary --top 10' 'DENIED'

step audit-allowed "【被允許的事件】誰實際寫入/讀取了 orders.events" \
  "kafka-console-consumer --topic confluent-audit-log-events  | granted=true 彙總" \
  'audit_events --topic "^orders\.events$" --granted true --summary --top 10' 'ALLOWED'

# 本章自己製造一次「非管理員改授權」:不依賴前面章節的執行順序(全 HA 回歸時,允許的事件多,前 8 名會把被拒那筆擠掉)
source "$DEMO_ROOT/scripts/rbac-lib.sh"
BIND_PAY="{\"scope\":{\"clusters\":{\"kafka-cluster\":\"$KAFKA_CLUSTER_ID\"}},\"resourcePatterns\":[{\"resourceType\":\"Topic\",\"name\":\"payments.\",\"patternType\":\"PREFIXED\"}]}"
step audit-mgmt "【權限變更紀錄】誰嘗試改授權(MDS 管理事件 AlterAccess)—— yujie(沒有 rbac-admin)自己加授權被拒,也被記錄" \
  "yujie POST /security/1.0/principals/Group:orders-write/roles/DeveloperWrite/bindings(預期 403);kafka-console-consumer --topic confluent-audit-log-events | mds.Authorize / AlterAccess" \
  'mds basic yujie:yujie-pw POST /security/1.0/principals/Group%3Aorders-write/roles/DeveloperWrite/bindings "$BIND_PAY" | tail -1; sleep 15
   echo "允許的(前 6 名):"; audit_events --method "^mds\.Authorize$" --topic "^(orders|payments|kafka-cluster|security-metadata)" --granted true --summary --top 6
   echo "被拒的:"; audit_events --method "^mds\.Authorize$" --granted false --summary --top 5' 'mds\.Authorize +DENIED'
ch_end
