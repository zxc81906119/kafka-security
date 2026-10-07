#!/usr/bin/env bash
# OP menu 安全回歸測試(2026-10-06 批 A):在 Rocky jump host 容器裡以 gary 執行,每項印 PASS / FAIL。
# 用「不合規範的中性輸入」驗證 allowlist:不在清單的主機與服務、非數字、含空白或分隔符的名稱、受保護的 topic、不允許的 role 與動作。
# 另外驗:紀錄欄位不會因輸入而斷行、帳密不出現在行程清單、強制終止後的殘留清理、測試後門在正式設定下無效。
# 事前:docker compose -f rocky/compose.yml up -d(在 demo/)且 demo cluster 在跑。
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
J=rocky-jump; pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1  ← $2"; fail=$((fail+1)); }
run() { docker exec -e OPMENU_PASS=gary-pw -e OPMENU_YES=1 -e OPMENU_TICKET=CHG-2026-0080 -e OPMENU_REASON=test "$J" su -s /bin/bash -p gary -c "cd /tmp && /opt/opmenu/opmenu.sh --run $*" </dev/null 2>&1; }
rejects() { local d="$1"; shift; local out; out=$(run "$@"); if echo "$out" | grep -q "輸入不接受\|不允許\|受保護\|必須\|不在允許清單\|不可小於"; then ok "$d"; else bad "$d" "$(echo "$out" | grep -v '^$' | tail -1 | cut -c1-90)"; fi; }
accepts() { local d="$1"; shift; local out; out=$(run "$@"); if echo "$out" | grep -q "輸入不接受\|不允許\|不在允許清單\|登入失敗\|執行失敗\|無法連到"; then bad "$d" "$(echo "$out" | grep -v '^$' | tail -1 | cut -c1-90)"; else ok "$d"; fi; }

echo "== 1 主機、服務、數字(21–24)"
rejects "24 node 不在清單"           24 node9 14
rejects "24 node 名稱含空白"         24 "'node1 x'" 14
rejects "24 天數不是數字"           24 node1 abc
rejects "24 天數小於下限"           24 node1 3
rejects "23 服務不在清單"           23 node9:confluent-server 10
rejects "23 行數不是數字"           23 node1:confluent-server "'50 x'"
rejects "21 不是 broker 服務"       21 node1:confluent-control-center
accepts "23 合法輸入照常可用"       23 node1:confluent-server 5

echo "== 2 topic、consumer group、principal(14、32、33、36、41)"
rejects "14 topic 名稱含空白"       14 "'orders events'"
rejects "32 受保護的 topic(底線開頭)" 32 _optest 60000
rejects "32 受保護的 audit topic"   32 confluent-audit-log-events 60000
rejects "33 受保護的 topic"         33 __consumer_offsets
rejects "33 不符命名規範"           33 ORDERS
rejects "36 group 名稱含分隔符"     36 "'a|b'" earliest
rejects "36 重設位置格式錯"         36 demo-x tomorrow
rejects "41 principal 格式錯"             41 kafka-ops
accepts "41 合法 principal"               41 Group:cluster-admin

echo "== 3 授權與緊急(42、91)"
rejects "42 不允許指派 SystemAdmin" 42 add orders-read SystemAdmin
rejects "42 不允許指派 UserAdmin"   42 add orders-read UserAdmin
rejects "42 資源類型不在清單"       42 add orders-read DeveloperRead Cluster x
rejects "91 工具不在清單"           91 kafka-delete-records --help
rejects "91 動作不在允許清單"       91 kafka-acls --add
rejects "91 不允許覆寫連線設定"     91 kafka-topics --list --bootstrap-server x
accepts "91 允許的動作"             91 kafka-topics --list
out=$(docker exec -e OPMENU_PASS=gary-pw -e OPMENU_YES=1 -e OPMENU_TICKET=CHG-2026-0080 "$J" su -s /bin/bash -p gary -c "cd /tmp && /opt/opmenu/opmenu.sh --run 91 kafka-topics --list" </dev/null 2>&1)
echo "$out" | grep -q "必須填原因" && ok "91 沒有原因被擋" || bad "91 沒有原因被擋" "$(echo "$out" | tail -1 | cut -c1-80)"

echo "== 4 紀錄:每筆一行、欄位固定"
before=$(docker exec "$J" sh -c 'wc -l < /var/log/opmenu/opmenu.log')
run 14 "'bad name'" >/dev/null
after=$(docker exec "$J" sh -c 'wc -l < /var/log/opmenu/opmenu.log')
[ $((after - before)) -eq 1 ] && ok "一次執行只增加一行紀錄" || bad "紀錄行數" "增加了 $((after - before)) 行"
docker exec "$J" tail -1 /var/log/opmenu/opmenu.log | grep -q "sid=" && ok "紀錄含 session id" || bad "紀錄含 session id" ""

echo "== 5 帳密不出現在行程清單"
docker exec "$J" sh -c ': > /tmp/ps-sample; (end=$(( $(date +%s) + 20 )); while [ $(date +%s) -lt $end ]; do ps -eo args | grep -E "curl" | grep -v grep >> /tmp/ps-sample; done) >/dev/null 2>&1 &'
sleep 1; run 41 Group:cluster-admin >/dev/null; sleep 20
if docker exec "$J" grep -q "gary-pw\|Bearer" /tmp/ps-sample; then bad "curl 的帳密或 token 在 ps 可見" ""; else ok "curl 的帳密與 token 不在 ps(抓到 $(docker exec "$J" sh -c 'wc -l < /tmp/ps-sample') 次 curl)"; fi

echo "== 6 暫存檔:放記憶體檔案系統、強制終止後由下次啟動清掉"
docker exec "$J" su -s /bin/bash gary -c 'cd /tmp; (sleep 60 | OPMENU_PASS=gary-pw /opt/opmenu/opmenu.sh >/dev/null 2>&1 &); sleep 6; p=$(pgrep -n -u gary -f "^bash /opt/opmenu/opmenu.sh$"); n=$(ls /dev/shm/opmenu.$p.* 2>/dev/null | wc -l); kill -9 $p; sleep 1; r=$(ls /dev/shm/opmenu.$p.* 2>/dev/null | wc -l); echo "live=$n residue=$r"' > /tmp/sec6.txt 2>&1
cat /tmp/sec6.txt | grep -q "live=2 residue=2" && ok "session 中有 2 個暫存檔在 /dev/shm;KILL 後殘留(預期)" || bad "暫存檔位置" "$(cat /tmp/sec6.txt)"
run 11 >/dev/null
left=$(docker exec "$J" sh -c 'ls /dev/shm/opmenu.* 2>/dev/null | wc -l')
[ "$left" = 0 ] && ok "下次啟動後殘留已清掉" || bad "殘留清理" "還有 $left 個"

echo "== 7 正式設定(不允許環境變數覆寫)下,測試後門無效"
docker exec "$J" sh -c "grep -v ALLOW_ENV_OVERRIDE /etc/opmenu/opmenu.conf > /tmp/prod.conf"
out=$(docker exec -e OPMENU_CONF=/tmp/prod.conf -e OPMENU_PASS=gary-pw -e OPMENU_YES=1 -e OPMENU_TICKET=CHG-2026-0080 "$J" su -s /bin/bash -p gary -c "cd /tmp && /opt/opmenu/opmenu.sh --run 11" </dev/null 2>&1)
echo "$out" | grep -q "登入失敗\|AD 密碼" && ok "OPMENU_PASS 被忽略(要求輸入密碼)" || bad "OPMENU_PASS 被忽略" "$(echo "$out" | tail -1 | cut -c1-80)"

echo; echo "== 結果:PASS $pass / FAIL $fail"; [ "$fail" = 0 ]
