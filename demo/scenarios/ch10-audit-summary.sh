#!/usr/bin/env bash
# 第 10 章:收尾 —— audit log 彙整整場 demo:誰、做了什麼、結果
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch10 "收尾:audit log 彙整(誰、做了什麼、結果)"

step audit-denied "【被拒絕的事件】整場 demo 中,被 RBAC 擋下來的動作(次數 / principal / 動作 / 資源)" \
  "kafka-console-consumer --topic confluent-audit-log-events  | granted=false 彙總" \
  'audit_events --topic "^(orders|payments)\." --granted false --summary --top 10' 'DENIED'

step audit-allowed "【被允許的事件】誰實際寫入/讀取了 orders.events" \
  "kafka-console-consumer --topic confluent-audit-log-events  | granted=true 彙總" \
  'audit_events --topic "^orders\.events$" --granted true --summary --top 10' 'ALLOWED'

step audit-mgmt "【權限變更紀錄】誰嘗試改授權(MDS 管理事件 AlterAccess)—— 非管理員的嘗試也被記錄" \
  "kafka-console-consumer --topic confluent-audit-log-events  | mds.Authorize / AlterAccess" \
  'audit_events --method "^mds\.Authorize$" --topic "^(orders|payments|kafka-cluster|security-metadata)" --summary --top 8' 'mds.Authorize'
ch_end
