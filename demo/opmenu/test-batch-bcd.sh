#!/usr/bin/env bash
# 批 B、C、D 新功能的回歸測試(docker 後端;需要 demo 叢集、Alertmanager 在跑,AD 帳號 gary)。
# 用法:test-batch-bcd.sh            不含滾動重啟(27)
#       test-batch-bcd.sh --rolling  含滾動重啟(會真的依序重啟兩台 broker,約 4 到 6 分鐘)
cd "$(dirname "$0")"
export MSYS_NO_PATHCONV=1
pass=0; fail=0
ok()  { if [ "$2" = "$3" ]; then echo "  PASS  $1"; pass=$((pass+1)); else echo "  FAIL  $1(預期 [$3],實際 [$2])"; fail=$((fail+1)); fi; }
has() { if printf '%s' "$2" | grep -q -- "$3"; then echo "  PASS  $1"; pass=$((pass+1)); else echo "  FAIL  $1(找不到 [$3])"; fail=$((fail+1)); fi; }
hasnt() { if printf '%s' "$2" | grep -q -- "$3"; then echo "  FAIL  $1(不該出現 [$3])"; fail=$((fail+1)); else echo "  PASS  $1"; pass=$((pass+1)); fi; }
G=(OPMENU_USER=gary OPMENU_PASS=gary-pw OPMENU_YES=1 OPMENU_TICKET=CHG-2026-0200 OPMENU_REASON=test)
run() { env "${G[@]}" "$@" ; }
item() { local id="$1"; shift; env "${G[@]}" timeout 600 ./opmenu.sh --run "$id" "$@" </dev/null 2>&1; }
LOCK="$PWD/log/opmenu.lock.d"; rm -rf "$LOCK"

echo "== B1 變更時窗(單元,不連叢集)"
w() { OPMENU_HOME="$PWD" OPMENU_ALLOW_ENV_OVERRIDE=1 OPMENU_CHANGE_WINDOW="$1" OPMENU_NOW_OVERRIDE="$2" bash -c '. lib/defaults.sh; . lib/validate.sh; . lib/core.sh; core_window_ok && echo in || echo out' 2>/dev/null; }
W='Mon-Fri 22:00-06:00;Sat,Sun 00:00-23:59'
ok "週一 23:00 在時窗內" "$(w "$W" '1 23:00')" in
ok "週二 05:59 在時窗內(跨午夜)" "$(w "$W" '2 05:59')" in
ok "週二 06:01 不在" "$(w "$W" '2 06:01')" out
ok "週一 05:00 不在(前一天是週日,不屬 Mon-Fri 的夜間段)" "$(w "$W" '1 05:00')" out
ok "週六 12:00 在" "$(w "$W" '6 12:00')" in
ok "週五 21:59 不在" "$(w "$W" '5 21:59')" out
ok "週三 12:00 不在" "$(w "$W" '3 12:00')" out
ok "沒設時窗 = 不限制" "$(w '' '3 12:00')" in

echo "== B1 時窗擋變更、緊急模式不受限"
out=$(env "${G[@]}" OPMENU_ALLOW_ENV_OVERRIDE=1 OPMENU_CHANGE_WINDOW='Mon 00:00-00:01' OPMENU_NOW_OVERRIDE='3 12:00' ./opmenu.sh --run 25 broker1 1 </dev/null 2>&1)
has "時窗外:項目 25 被擋" "$out" "不在允許變更的時窗內"
out=$(env "${G[@]}" OPMENU_ALLOW_ENV_OVERRIDE=1 OPMENU_CHANGE_WINDOW='Mon 00:00-00:01' OPMENU_NOW_OVERRIDE='3 12:00' ./opmenu.sh --run 91 kafka-topics --list </dev/null 2>&1)
hasnt "時窗外:項目 91(緊急)不被時窗擋" "$out" "不在允許變更的時窗內"
out=$(env "${G[@]}" OPMENU_ALLOW_ENV_OVERRIDE=1 OPMENU_CHANGE_WINDOW='Mon 00:00-00:01' OPMENU_NOW_OVERRIDE='3 12:00' ./opmenu.sh --run 101 </dev/null 2>&1)
hasnt "時窗外:唯讀項目 11 不受限" "$out" "不在允許變更的時窗內"
grep -q 'BLOCKED' log/opmenu.log && echo "  PASS  紀錄有 BLOCKED" && pass=$((pass+1)) || { echo "  FAIL  紀錄沒有 BLOCKED"; fail=$((fail+1)); }

echo "== B2 並行鎖"
mkdir -p "$LOCK"; sleep 300 & HP=$!
echo "$HP otheruser 31 建立 topic | 2026-10-06 00:00:00" > "$LOCK/info"
out=$(item 25 broker1 1)
has "別人持有鎖(行程存活):被拒絕並顯示持有者" "$out" "目前有其他變更作業進行中(otheruser"
out=$(item 11)
hasnt "鎖被持有時,唯讀項目不受影響" "$out" "其他變更作業"
kill $HP 2>/dev/null; wait $HP 2>/dev/null
out=$(item 25 broker1 1)
has "持有者行程已不在(過期鎖):自動清掉並執行" "$out" "維護模式已開始"
[ ! -d "$LOCK" ] && echo "  PASS  執行完放掉鎖" && pass=$((pass+1)) || { echo "  FAIL  鎖沒放掉"; fail=$((fail+1)); rm -rf "$LOCK"; }
SID=$(printf '%s' "$out" | grep -o 'silence id=[0-9a-f-]*' | cut -d= -f2)

echo "== B3 維護模式 25/26"
has "25 建立 silence" "$out" "維護模式已開始:broker1"
out=$(item 25 broker1 999); has "25 超過上限被拒" "$out" "必須在 1 到"
out=$(item 25 evil.example.com 5); has "25 不在 node 清單被拒" "$out" "不在允許清單"
out=$(item 26 'x;y'); has "26 id 格式錯誤被拒" "$out" "silence id"
out=$(item 26 2c46f321-6c92-4577-bd80-f00a16d0bafa); has "26 不是 opmenu 建立的 silence 不處理" "$out" "不是由 opmenu 建立"
out=$(item 26 "$SID"); has "26 結束自己建的 silence" "$out" "維護模式已結束"
grep -v ALERTMANAGER_AUTH_FILE opmenu.conf > log/noauth.conf; out=$(env "${G[@]}" OPMENU_CONF=$PWD/log/noauth.conf ./opmenu.sh --run 25 broker1 1 </dev/null 2>&1); rm -f log/noauth.conf; has "25 Alertmanager 要帳密:沒帶帳密建立失敗" "$out" "建立 silence 失敗"
rm -rf "$LOCK"

echo "== B4 / C2 唯讀報告 11、10"
out=$(item 11); has "11 MDS 狀態" "$out" "正常("; has "11 broker 在線" "$out" "broker 在線:2 / 2"; has "11 token 剩餘" "$out" "剩約"
out=$(item 10); has "10 有 partition 總數" "$out" "partition 總數"; has "10 列出 broker 11" "$out" "^11 "

echo "== D1 權限覆核匯出 44"
out=$(item 44); has "44 匯出成功" "$out" "已匯出"
f=$(ls -t log/permission-review-*.csv 2>/dev/null | head -1)
has "44 CSV 表頭" "$(head -1 "$f")" "role,principal,resource_type"
has "44 含 SystemAdmin" "$(cat "$f")" '"SystemAdmin"'
echo "-- 沒有權限的人(ming)匯出 → 要被拒"
out=$(env OPMENU_USER=ming OPMENU_PASS=ming-pw OPMENU_YES=1 timeout 120 ./opmenu.sh --run 44 </dev/null 2>&1); has "44 沒權限被拒" "$out" "HTTP 403\|拒絕"

echo "== D2 audit 查詢 45"
out=$(item 45 120 gary); has "45 依主體篩選" "$out" "符合"; hasnt "45 篩選 gary 時沒有其他人" "$(printf '%s' "$out" | grep 'User:' | grep -vi 'User:gary')" "User:"
out1=$(item 45 120 gary | grep '符合'); out2=$(item 45 120 gary | grep '符合'); ok "45 連跑兩次結果一致(不漏讀)" "$out1" "$out2"
out=$(item 45 30 gary MAYBE); has "45 結果輸入錯誤被拒" "$out" "不在允許清單"
out=$(item 45 30 'x;y'); has "45 主體格式錯誤被拒" "$out" "輸入不接受"

if [ "${1:-}" = --rolling ]; then
  echo "== C1 滾動重啟 27(真的重啟兩台 broker)"
  out=$(item 27); has "27 兩台依序完成" "$out" "全部 2 台 broker 已完成滾動重啟"; has "27 第一台" "$out" "\[1/2\] 重啟 broker1"; has "27 第二台" "$out" "\[2/2\] 重啟 broker2"
  out=$(item 11); has "27 之後 broker 全在線" "$out" "broker 在線:2 / 2"
fi

echo; echo "== 結果:PASS $pass / FAIL $fail"; [ "$fail" = 0 ]
