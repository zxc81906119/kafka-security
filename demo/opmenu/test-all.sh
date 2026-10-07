#!/usr/bin/env bash
# 非互動的功能測試:逐項執行,印出每項最後幾行與紀錄結果。需要 demo 的 AD 帳號 gary(管理員)。
cd "$(dirname "$0")"
G=(OPMENU_USER=gary OPMENU_PASS=gary-pw OPMENU_YES=1 OPMENU_TICKET=CHG-2026-0010 OPMENU_REASON=test)
run(){ local n="$1"; shift; echo; echo "===== $*"; env "${G[@]}" timeout 180 ./opmenu.sh --run "$@" </dev/null 2>&1 | grep -v "^$" | tail -"$n"; }
run 1 18
run 3 13 demo-
run 1 13 zzz
run 2 34 svc-opmtest opm.
run 6 41 User:svc-opmtest
run 1 35 svc-opmtest
run 1 35 gary
run 1 31 opm.events 1
run 2 36 opmenu-nogroup earliest
run 2 33 opm.events
echo; echo "===== 41 沒有權限的人(ming,應 DENIED)"; env OPMENU_USER=ming OPMENU_PASS=ming-pw timeout 120 ./opmenu.sh --run 41 User:svc-orders </dev/null 2>&1 | grep -v "^$" | tail -1
run 1 42 add orders-read DeveloperRead Topic opm.
run 3 41 Group:orders-read
run 1 42 remove orders-read DeveloperRead Topic opm.
run 1 43 50
run 1 22 restproxy
run 1 22 broker1
run 1 23 restproxy 5
run 1 24 broker1 14
run 1 24 broker1 3
run 3 91 kafka-topics --list
run 1 91 kafka-delete-records --help
echo; echo "===== 收尾:刪測試帳號與 binding(用 bootstrap)"; env "${G[@]}" timeout 120 ./opmenu.sh --run 91 kafka-configs --alter --delete-config SCRAM-SHA-512 --entity-type users --entity-name svc-opmtest </dev/null 2>&1 | tail -1
echo; echo "===== 紀錄"; tail -22 log/opmenu.log
