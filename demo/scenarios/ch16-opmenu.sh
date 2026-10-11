#!/usr/bin/env bash
# ============================================================================
# ch16-opmenu.sh — 第 16 章:OP menu:日常維運選單(登入、查看、維護模式、權限覆核、audit、時窗與並行鎖、滾動重啟)
# ----------------------------------------------------------------------------
# 白話:示範 demo/opmenu/ 的日常維運選單(docker 後端):選單分四層,編號第一位是層級。
#   選單本身不判斷權限,一律交給 Kafka RBAC(沒權限的人用同一個選單會被拒);變更類項目還有變更時窗與並行鎖保護。
# 前置條件:環境已建好;Alertmanager 已啟用(維護模式要建靜音)
# 用法:
#   ./demo.sh 16                  經由講解控制台跑這一章
#   ./scenarios/ch16-opmenu.sh      直接跑(DEMO_PAUSE=0 不暫停)
# 會改動什麼:開頭刪除 opmenu 的並行鎖目錄與 demo/.maint.out。
#   維護模式:對 broker1 建立 Alertmanager 靜音再結束它;匯出權限清單 CSV 到 opmenu/log/;並行鎖那步暫時建立鎖目錄與背景 sleep(結束前清掉)。
#   滾動重啟(項目 27)會真的依序重啟 4 台 broker(整章約 11.5 分鐘);不想跑時設 CH16_SKIP_ROLLING=1。
#   結束前刪除 .maint.out。
# 怎麼判斷成功:每一步印『✔ 符合預期』,最後一行『第 16 章完成(失敗 0 項)』
# 實測結果摘要:取證用:以環境變數帶入帳密與核准單號(OPMENU_USER、OPMENU_PASS、OPMENU_TICKET 等),僅在 demo 設定檔 OPMENU_ALLOW_ENV_OVERRIDE=1 時有效,正式環境一律忽略
#   項目 11 一次看完 partition、broker、MDS、token 剩餘時間、controller quorum;項目 19 顯示每個設定值的來源(conf / derived / default)
#   項目 25/26:維護模式 = Alertmanager silence,只能結束 opmenu 自己建的
#   ming(唯讀)匯出權限清單被 Kafka RBAC 拒絕
#   變更時窗:模擬週三中午嘗試變更被擋(唯讀項目與緊急模式不受限);另一人持有鎖時變更被拒並顯示是誰在做什麼
#   項目 27 滾動重啟:一次一台,每台重啟後先等 45 秒,再連續兩次確認全部 broker 在線且 under-replicated 與 offline 為 0 才換下一台
# ============================================================================
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch16 "OP menu:日常維運選單(登入、查看、維護模式、權限覆核、audit、時窗與並行鎖)"
OPDIR="$DEMO_ROOT/opmenu"
opm() { ( cd "$OPDIR" && env OPMENU_YES=1 OPMENU_TICKET=CHG-2026-0001 OPMENU_REASON=demo "$@" ); }   # opm OPMENU_USER=... OPMENU_PASS=... ./opmenu.sh --run N ...
G=(OPMENU_USER=gary OPMENU_PASS=gary-pw)
LOCK="$OPDIR/log/opmenu.lock.d"; rm -rf "$LOCK"
rm -f "$DEMO_ROOT/.maint.out"

step list "【項目清單】選單分四層;編號第一位是層級" \
  "./opmenu.sh --list" \
  'opm "${G[@]}" ./opmenu.sh --list | cut -f1,2,5' '27'

step health "【11 cluster 與身分鏈健康】partition、broker、MDS 各台、token 剩餘時間、controller quorum 一次看完" \
  "./opmenu.sh --run 11" \
  'opm "${G[@]}" ./opmenu.sh --run 11 | grep -v "^$" | tail -14' 'broker 在線'

step effconf "【19 生效設定】每個值用了什麼、來源是 conf(設定檔)、derived(推算)還是 default(預設)" \
  "./opmenu.sh --run 19" \
  'opm "${G[@]}" ./opmenu.sh --run 19 | grep -v "^$" | tail -17' 'derived'

step maint-on "【25 開始維護模式】對 broker1 靜音告警 30 分鐘(Alertmanager silence;記錄操作者與核准單號)" \
  "./opmenu.sh --run 25 broker1 30" \
  'opm "${G[@]}" ./opmenu.sh --run 25 broker1 30 | grep -v "^$" | tail -3 | tee "$DEMO_ROOT/.maint.out"' '維護模式已開始'

step maint-off "【26 結束維護模式】維護做完,提前結束這個 silence(只能結束 opmenu 自己建的)" \
  "./opmenu.sh --run 26 <silence id>" \
  'ID=$(grep -o "silence id=[0-9a-f-]*" "$DEMO_ROOT/.maint.out" | cut -d= -f2); opm "${G[@]}" ./opmenu.sh --run 26 "$ID" | grep -v "^$" | tail -2' '維護模式已結束'

step review "【44 匯出權限清單】依 role 列出所有 principal 與資源範圍(CSV),交給定期權限覆核" \
  "./opmenu.sh --run 44;head 權限清單.csv" \
  'opm "${G[@]}" ./opmenu.sh --run 44 | grep -v "^$" | tail -1; f=$(ls -t "$OPDIR"/log/permission-review-*.csv | head -1); head -8 "$f"' '已匯出'

step ming-denied "【沒有權限的人】明(唯讀)用同一個選單匯出權限清單 → 被 Kafka RBAC 拒絕;選單本身不判斷權限" \
  "OPMENU_USER=ming ./opmenu.sh --run 44" \
  'opm OPMENU_USER=ming OPMENU_PASS=ming-pw ./opmenu.sh --run 44 | grep -v "^$" | tail -3' '403|拒絕'

step audit "【45 查詢 audit】最近 4 小時被拒絕(DENIED)的事件,依主體與資源列出" \
  "./opmenu.sh --run 45 240 '' DENIED" \
  'O=$(opm "${G[@]}" ./opmenu.sh --run 45 240 "" DENIED | grep -v "^$"); echo "$O" | grep "符合"; echo "$O" | tail -6' '符合'

step window "【變更時窗】只允許週一 00:00 到 00:01 變更;現在(模擬週三中午)嘗試開始維護模式 → 被擋;唯讀項目與緊急模式不受限" \
  "OPMENU_CHANGE_WINDOW='Mon 00:00-00:01' ./opmenu.sh --run 25 broker1 5" \
  'opm "${G[@]}" OPMENU_CHANGE_WINDOW="Mon 00:00-00:01" OPMENU_NOW_OVERRIDE="3 12:00" ./opmenu.sh --run 25 broker1 5 | grep -v "^$" | tail -2' '不在允許變更的時窗內'

step lock "【並行鎖】另一個人正在做變更(持有鎖的行程還活著)→ 我的變更被拒,並顯示是誰在做什麼" \
  "(另一人持有鎖)./opmenu.sh --run 25 broker1 5" \
  'mkdir -p "$LOCK"; sleep 120 & HP=$!; echo "$HP gary 27 滾動重啟所有 broker | $(date "+%F %T")" > "$LOCK/info"; opm "${G[@]}" ./opmenu.sh --run 25 broker1 5 | grep -v "^$" | tail -2; kill $HP 2>/dev/null; rm -rf "$LOCK"' '其他變更作業進行中'

if [ "${CH16_SKIP_ROLLING:-0}" != 1 ]; then
  step rolling "【27 滾動重啟所有 broker】一次一台;每台重啟後先等 45 秒,再連續兩次確認「全部 broker 在線、under-replicated 與 offline 為 0」才換下一台" \
    "./opmenu.sh --run 27" \
    'opm "${G[@]}" ./opmenu.sh --run 27 | grep -v "^$" | tail -14' '完成滾動重啟'
fi

rm -f "$DEMO_ROOT/.maint.out"
ch_end
