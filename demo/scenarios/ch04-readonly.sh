#!/usr/bin/env bash
# 第 4 章:生產環境「人只能唯讀」—— 開發者要看資料,但不能寫、不能改設定
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch04 "生產環境人只能唯讀"
UI() { (cd "$DEMO_ROOT/e2e" && node ch04-ui.mjs "$1" 2>&1 | grep -v '^$'); }

step c3-readonly "【C3 操作】gary 建立唯讀權限:AD 群組 orders-read → DeveloperRead(只有 Read,沒有 Write / Manage)" \
  "(瀏覽器)C3 → Manage role assignments → Add role assignment(Group / orders-read / DeveloperRead)" \
  'UI assign-readonly' 'c3-1-readonly-form'

step ldap-move "【AD 操作】ming 改為「只看資料」:AD 管理介面把 ming 從 orders-write 移到 orders-read" \
  "(瀏覽器)phpLDAPadmin:orders-read 加入 ming、orders-write 移除 ming" \
  'UI move-ming; date +"[%T] AD 群組異動完成"' '群組異動完成'

step wait "(等 MDS 讀取 LDAP 變更)" "(等待約 10 秒)" 'sleep 10; echo "已等待"' '已等待'

step ming-read "ming(唯讀)可以讀取 orders.events" \
  "kafka-console-consumer --command-config ming.properties --topic orders.events --from-beginning" \
  'as_consume ming orders.events' '"order":"A-1001"|Processed a total'

step ming-write "ming(唯讀)寫入 → 被拒" \
  "echo oops | kafka-console-producer --command-config ming.properties --topic orders.events" \
  'as_produce ming orders.events oops' 'not authorized|Not authorized|TopicAuthorization|Cluster authorization failed'

step ming-create "ming(唯讀)想建立 topic → 被拒" \
  "kafka-topics --command-config ming.properties --create --topic ming-test" \
  'K kafka-topics --bootstrap-server $BOOT --command-config /clients/plain-ming.properties --create --topic ming-test --partitions 1 --replication-factor 2' 'not authorized|Not authorized|Authorization failed|TopicAuthorization'

step yujie-unaffected "yujie 仍在 orders-write,不受影響:可寫入" \
  "echo still-ok | kafka-console-producer --command-config yujie.properties --topic orders.events" \
  'send_result as_produce yujie orders.events still-ok' '結果:成功'

step c3-view "【C3】ming(唯讀)登入 C3:可檢視 topics,但沒有管理功能" \
  "(瀏覽器)ming 登入 C3 → Topics" \
  'UI c3-readonly-view' 'c3-2-ming-readonly'
ch_end
