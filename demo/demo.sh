#!/usr/bin/env bash
# 現場講解控制台:選單列出章節;每步先印講稿、按 Enter 再執行(DEMO_PAUSE=1)。
# 用法:
#   ./demo.sh            互動選單
#   ./demo.sh 3          直接跑第 3 章(逐步按 Enter)
#   ./demo.sh all        依序跑第 1~19 章
#   ./demo.sh reset      重置到第 0 章起始狀態
cd "$(dirname "$0")"
declare -A CH=(
  [1]="ch01-no-identity.sh|沒有身分就進不來(預設全拒絕)"
  [2]="ch02-c3-login.sh|人用 AD 帳號登入 C3(三個人看到的不同)"
  [3]="ch03-rbac-ad-group.sh|RBAC 與 AD 群組:授權跟著群組走(C3 + LDAP 介面 + MDS API)"
  [4]="ch04-readonly.sh|生產環境人只能唯讀"
  [5]="ch05-postman.sh|工具/Postman 用同一份 AD 身分(newman 實跑)"
  [6]="ch06-scripts.sh|維運腳本:腳本共用、憑證各人各自"
  [7]="ch07-service.sh|機器(不在 AD):服務帳號 SCRAM + RBAC"
  [8]="ch08-shared-cert.sh|(選修)為什麼不用共用憑證做 mTLS 身分"
  [9]="ch09-rotate-internal.sh|(選修)輪替、內部通道、AD 故障"
  [10]="ch10-audit-summary.sh|收尾:audit log 彙整"
  [11]="ch11-separation.sh|(進階)維運分權:唯讀 / 維運 / 授權管理,臨時提權與收回"
  [12]="ch12-legacy-app.sh|(進階)legacy app 經 REST Proxy:機器用憑證、人用 Basic,並存"
  [13]="ch13-c3-inventory.sh|(進階)Control Center 身分盤點:人與機器各走哪條路"
  [14]="ch14-admin-rest.sh|(進階)broker 內建 Admin REST 的保護:匿名擋下、依使用者授權"
  [17]="ch17-transport-hardening.sh|(進階)傳輸加密補強:AD 走 LDAPS、監控 HTTPS + Basic、C3 HTTPS"
  [18]="ch18-cyberark.sh|(進階)與行內 CyberArk 整合:應用程式取密碼、輪替、OP menu 取帳密、設定檔密碼不落地(Conjur)"
  [19]="ch19-stolen-account.sh|(進階)帳號被偷之後:限速、失效、告警(重新認證、連線上限、配額、認證失敗告警、AD 鎖定)"
  [20]="ch20-schema-registry.sh|(進階)Schema Registry 納入同一套授權:subject 與 KEK 的權限;欄位級加密(CSFLE)的授權前提與授權限制"
  [21]="ch21-ha.sh|(進階)HA 叢集:3 controller、3 broker 的停機行為與滾動重啟(需先 scripts/ha.sh on;不在 all 內)"
  [22]="ch22-monitoring.sh|(進階)平台監控與告警:URP、離線分區、active controller 的告警實際觸發(需 HA 模式與 Prometheus;不在 all 內)"
)
run_ch() {
  local n="$1"; local f="${CH[$n]%%|*}"
  if [ "$f" = "__c3_login__" ]; then
    echo "第 2 章(C3 登入)為瀏覽器操作:請開 https://localhost:9022 以 gary / yujie / ming 各登入一次(密碼見 RUNBOOK)。"
    echo "需要自動截圖:  (cd e2e && node ch02.mjs)"; return
  fi
  DEMO_PAUSE=${DEMO_PAUSE:-1} ./scenarios/"$f"
}
case "${1:-menu}" in
  reset) ./scripts/reset.sh ;;
  all) for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 17 18 19 20; do run_ch "$n"; done ;;
  [0-9]|1[0-9]|2[0-2]) run_ch "$1" ;;
  *)
    while true; do
      echo; echo "═══ Confluent 安全方案 Demo ═══"
      for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 17 18 19 20 21 22; do printf "  %2s) %s\n" "$n" "${CH[$n]#*|}"; done
      echo "   r) 重置   q) 離開"
      read -r -p "選擇章節: " c
      case "$c" in q) break ;; r) ./scripts/reset.sh ;; [0-9]|1[0-9]|2[0-2]) run_ch "$c" ;; esac
    done ;;
esac
