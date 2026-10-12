#!/usr/bin/env bash
# ============================================================================
# chapter-start.sh — 把環境收斂到某一章的起點(冪等:已經正確的不動,重跑幾次結果都一樣)
# ----------------------------------------------------------------------------
# 白話:每一章都可以單獨從「環境已建好」開始,也可以接著前一章做,不必「跑 5 要先跑 4」。
#   這支腳本只確保那一章需要的狀態:AD 群組成員、角色綁定、topic、資料、服務帳號;已經是對的就略過。
#   章節腳本的第一步會呼叫它;照手冊手動操作時,從哪一章開始就先執行一次。
# 前置條件:環境已建好(scripts/up.sh)。
# 用法:
#   scripts/chapter-start.sh ch04      把環境收斂到第 4 章的起點
#   scripts/chapter-start.sh --list    列出有定義起點的章節
# 會改動什麼:依章節調整 AD 群組成員、角色綁定、建立 topic、寫入一筆起點資料、建立或停用示範用的服務帳號(見各章的說明)。
# 怎麼判斷成功:最後一行「[起點] chNN 就緒」;每一項印「已正確」或「已調整」。
# ============================================================================
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/kafka.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR" || exit 1
export MSYS_NO_PATHCONV=1
source scripts/rbac-lib.sh

BASE="dc=corp,dc=demo"
GROUP_CHANGED=0
ALL_GROUPS="orders-read orders-write ops topic-admin cluster-admin rbac-admin security breakglass"

ldap() { docker exec openldap "$@"; }
user_dn() { ldap ldapsearch -x -LLL -D "cn=admin,$BASE" -w adminpw -b "ou=users,$BASE" "(cn=$1)" dn 2>/dev/null | sed -n 's/^dn: //p' | head -1; }
# is_member <使用者> <群組>:群組的 member 是否含這個使用者的 DN(大小寫不分)
is_member() {
  local dn; dn=$(user_dn "$1")
  ldap ldapsearch -x -LLL -D "cn=admin,$BASE" -w adminpw -b "cn=$2,ou=groups,$BASE" member 2>/dev/null | tr -d '\r' | grep -qiF "member: $dn"
}
ensure_member() {
  if is_member "$1" "$2"; then echo "  $1 在 $2:已正確"
  else bash scripts/ldap-group.sh add "$1" "$2" >/dev/null && GROUP_CHANGED=1 && echo "  $1 加入 $2:已調整"; fi
}
ensure_not_member() {
  if is_member "$1" "$2"; then bash scripts/ldap-group.sh remove "$1" "$2" >/dev/null && GROUP_CHANGED=1 && echo "  $1 移出 $2:已調整"; fi
}
only_in() {   # only_in <使用者> <群組…>:使用者只屬於列出的群組(不在其他示範群組)
  local u="$1" g; shift
  for g in $ALL_GROUPS; do case " $* " in *" $g "*) ensure_member "$u" "$g" ;; *) ensure_not_member "$u" "$g" ;; esac; done
  [ $# -eq 0 ] && echo "  $u 不在任何示範群組:已確認"
}
# 角色綁定:MDS 新增同一條綁定是冪等的(已存在仍回 204),解除不存在的綁定也不會出錯
ensure_binding()    { rbac_bind   cert bootstrap "$@" >/dev/null 2>&1; echo "  綁定 $1 $2 $3:$4($5):已確保"; }
ensure_no_binding() { rbac_unbind cert bootstrap "$@" >/dev/null 2>&1; echo "  綁定 $1 $2 $3:$4($5):已確保不存在"; }
ensure_topic() {
  kafka_topics --create --if-not-exists --topic "$1" --partitions "${2:-3}" --replication-factor 3 --config min.insync.replicas=2 >/dev/null 2>&1
  echo "  topic $1:已確保存在"
}
# ensure_data <topic> <內容>:topic 是空的才寫一筆(以管理身分寫,不經過要示範的授權)
ensure_data() {
  if [ "$(topic_message_count "$1")" -gt 0 ]; then echo "  $1 有資料:已正確"
  else echo "$2" | "$DEMO_DIR/scripts/k.sh" kafka-console-producer --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config "$KAFKA_ADMIN_CONFIG" --topic "$1" >/dev/null 2>&1
       echo "  $1 寫入起點資料「$2」:已調整"; fi
}
# 示範用服務帳號:建立或重設成已知密碼(SCRAM 覆寫是冪等的);停用 = 覆寫成隨機密碼(不刪除,見 KAFKA-20774)
ensure_svc()      { bash scripts/create-service-account.sh "$1" "$2" >/dev/null 2>&1; echo "  服務帳號 $1:已確保(密碼為測試值)"; }
ensure_svc_off()  { bash scripts/scram-disable.sh "$1" >/dev/null 2>&1; echo "  服務帳號 $1:已確保停用"; }

# orders 的業務授權(第 3 章在 C3 建立的結果):orders-write 對 orders. 可讀寫
orders_write_granted() {
  ensure_binding Group:orders-write DeveloperWrite Topic orders. PREFIXED
  ensure_binding Group:orders-write DeveloperRead  Topic orders. PREFIXED
}

case "${1:-}" in
  --list) echo "每一章都可以執行;有特別起點的:ch01 ch02 ch03 ch04 ch05 ch06 ch07 ch09 ch10 ch11 ch12 ch14 ch15 ch16 ch18 ch27 ch33,其餘章節不需要額外準備"; exit 0 ;;
  ch01|ch02)
    # 起點:「還沒有任何授權」——清掉所有示範綁定與群組異動(scripts/reset.sh 本身就是冪等的)
    bash scripts/reset.sh >/dev/null 2>&1 && echo "  scripts/reset.sh:已回到還沒有任何授權的起點" ;;
  ch07)
    # 起點:svc-orders 還沒有任何示範綁定(要示範授權前被拒 → 在 C3 授權後成功)
    ensure_topic orders.events; ensure_topic payments.events
    ensure_no_binding User:svc-orders DeveloperWrite Topic orders. PREFIXED
    ensure_no_binding User:svc-orders DeveloperRead  Topic orders. PREFIXED ;;
  ch11)
    # 起點:ming 唯讀(只在 orders-read)、yujie 一般開發者(只在 orders-write)、三個維運群組都沒有人;上次的 infra 示範清掉
    ensure_topic orders.events
    only_in yujie orders-write
    only_in ming orders-read
    ensure_binding Group:orders-read DeveloperRead Topic orders. PREFIXED
    ensure_binding Group:orders-read  DeveloperRead Group demo- PREFIXED            # console consumer 要有 group 的讀取權
    ensure_binding Group:orders-write DeveloperRead Group demo- PREFIXED
    ensure_no_binding Group:orders-write DeveloperRead Topic infra. PREFIXED
    kafka_topics --delete --if-exists --topic infra.ops-demo >/dev/null 2>&1; echo "  topic infra.ops-demo:已確保不存在"
    ensure_data orders.events '{"order":"A-1001"}' ;;
  ch12)
    # 起點:legacy-orders 與 orders-write 都還沒有 orders. 的寫入權(本章在 C3 指派後才可寫)
    ensure_topic orders.events
    ensure_no_binding User:legacy-orders DeveloperWrite Topic orders. PREFIXED
    ensure_no_binding Group:orders-write  DeveloperWrite Topic orders. PREFIXED ;;
  ch14)
    # 起點:ming 沒有任何 role(本章用「已登入但沒授權」的人測 Admin REST);gary、yujie 照常
    ensure_topic orders.events
    orders_write_granted
    ensure_member yujie orders-write
    only_in ming ;;
  ch15)
    # 起點:yujie 在 orders-write,群組可讀寫 orders.(本章示範離職:移出群組後立刻失去權限)
    ensure_topic orders.events
    ensure_member yujie orders-write
    orders_write_granted ;;
  ch16)
    # 起點:OP menu 沒有殘留的鎖與上次維護模式的輸出
    rm -rf opmenu/log/opmenu.lock.d .maint.out; echo "  OP menu 的鎖與維護模式輸出:已清除" ;;
  ch18)
    # 起點:Conjur 在跑;svc-orders(第 7 章建立,這裡自己確保)與寫入授權存在;Conjur 裡「現在該用的帳號密碼」= svc-orders / 原密碼
    bash scripts/conjur.sh up >/dev/null 2>&1 || die "Conjur 啟動失敗:bash scripts/conjur.sh up"
    echo "  Conjur:已啟動"
    ensure_topic orders.events
    ensure_svc svc-orders orders-secret-v1
    ensure_binding User:svc-orders DeveloperWrite Topic orders. PREFIXED
    bash scripts/conjur.sh set opmenu/alertmanager-auth "opmenu:am-opmenu-pw" >/dev/null && echo "  Conjur 的 opmenu/alertmanager-auth:已設定"
    bash scripts/conjur.sh set-cred svc-orders svc-orders orders-secret-v1 >/dev/null && echo "  Conjur 的 svc-orders 帳密:已設定為原密碼"
    rm -rf opmenu/log/opmenu.lock.d ;;
  ch03)
    # 起點:「還沒授權」——要示範授權前被拒 → 在 C3 授權後成功;ming 不在任何群組(對照組)
    ensure_topic orders.events
    ensure_no_binding Group:orders-write DeveloperWrite Topic orders. PREFIXED
    ensure_no_binding Group:orders-write DeveloperRead  Topic orders. PREFIXED
    ensure_member yujie orders-write
    only_in ming ;;
  ch04)
    # 起點 = 第 3 章結束時:orders-write 可讀寫、ming 在 orders-write、orders.events 有資料;orders-read 還沒有唯讀授權
    ensure_topic orders.events
    orders_write_granted
    ensure_no_binding Group:orders-read DeveloperRead Topic orders. PREFIXED
    ensure_member yujie orders-write
    only_in ming orders-write
    ensure_data orders.events order-A-1001 ;;
  ch05|ch06)
    # 起點 = 第 4 章結束時:orders-write 可讀寫、orders-read 唯讀、ming 只在 orders-read
    ensure_topic orders.events; ensure_topic payments.events
    orders_write_granted
    ensure_binding Group:orders-read DeveloperRead Topic orders. PREFIXED
    ensure_no_binding Group:orders-write DeveloperRead Topic payments. PREFIXED     # 第 5 章 M.3 的對照:不能有這條
    ensure_member yujie orders-write
    only_in ming orders-read
    if [ "$1" = ch06 ]; then                                                         # 第 6 章的反面教材從乾淨的狀態開始
      ensure_no_binding User:shared-ops DeveloperWrite Topic orders. PREFIXED
      ensure_svc_off shared-ops
    fi ;;
  ch09)
    # 起點:svc-orders(第 7 章建立)與 orders-write 的寫入授權存在;上次輪替留下的 svc-orders-v2 清掉;AD 在線
    docker start openldap >/dev/null 2>&1 || true
    ensure_topic orders.events
    orders_write_granted
    ensure_member yujie orders-write
    ensure_svc svc-orders orders-secret-v1
    ensure_binding User:svc-orders DeveloperWrite Topic orders. PREFIXED
    ensure_no_binding User:svc-orders-v2 DeveloperWrite Topic orders. PREFIXED
    ensure_svc_off svc-orders-v2 ;;
  ch10)
    # 起點:本章要彙總的事件由本章自己製造(不依賴前面跑過哪些章):yujie 寫入被允許、ming 寫入被拒
    ensure_topic orders.events; ensure_topic payments.events
    orders_write_granted
    ensure_binding Group:orders-read DeveloperRead Topic orders. PREFIXED
    ensure_member yujie orders-write
    only_in ming orders-read ;;
  ch27)
    # 起點:Grafana 在跑(Lab 26 啟動的那一套)、應用程式用的 JDK 映像與 Kafka jar 資料卷已備妥(Lab 25 準備的那一份);不必先做 Lab 25、26
    if docker ps --format '{{.Names}}' | grep -qx grafana; then echo "  Grafana:已在跑"
    else bash scripts/grafana.sh on >/dev/null 2>&1 && echo "  Grafana:已啟動(scripts/grafana.sh on)" || die "Grafana 啟動失敗:bash scripts/grafana.sh on"; fi
    source scripts/lib/apps.sh; apps_prepare >/dev/null; echo "  JDK 映像與 Kafka jar 資料卷:已確保" ;;
  ch33)
    # 起點:voter 名單是 {1,2,3}(上次汰換留下的 controller4 移除、controller3 重新加入)
    bash scripts/quorum-lab.sh reset 2>&1 | grep -E "voter:|判定" | sed 's/^/  /'
    bash scripts/quorum-lab.sh status 2>/dev/null | grep -q "voter 3 個" || die "voter 名單沒有收斂成 {1,2,3}:bash scripts/quorum-lab.sh status;必要時 scripts/ha.sh on 重建" ;;
  ch[0-9][0-9])
    # 其餘章節:開頭不需要額外準備(需要的元件由該章第一步的 *-setup.sh 啟動,結束時還原)
    echo "  這一章不需要額外的起點準備" ;;
  *) usage_from_header "$0"; exit 1 ;;
esac

# 有改 AD 群組才等:MDS 讀 LDAP 群組有快取(demo 設定 5 秒,預設 60 秒)
if [ "$GROUP_CHANGED" = 1 ]; then echo "  (等 MDS 套用 AD 群組變更)"; sleep 15; fi
note "[起點] $1 就緒"
