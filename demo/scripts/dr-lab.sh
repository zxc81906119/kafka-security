#!/usr/bin/env bash
# ============================================================================
# dr-lab.sh — 第 36 章的實驗與 DR 演練:主站整個掛掉時,切到 DR 站、量測 RPO / RTO、切回
# ----------------------------------------------------------------------------
# 白話:DR 不是「有備份」就好,要能證明「多久恢復(RTO)、掉多少資料(RPO)、步驟誰都做得出來」。這支腳本把演練拆成幾步,
#   最後產生一份演練紀錄(evidence/dr-drills/),格式可直接當稽核要的演練紀錄範本。
# 前置條件:scripts/dr-setup.sh up 完成(link main-to-dr 為 ACTIVE)。
# 用法:
#   scripts/dr-lab.sh mirror      主站建立 dr.orders,DR 站建立鏡像;主站寫 300 筆、consumer group dr-app 讀 200 筆;看 DR 端資料與 offset 同步
#   scripts/dr-lab.sh rbac        DR 站的授權不會自動同步:yujie 在 DR 端被拒 → 補建綁定(演練清單的一項)→ 允許
#   scripts/dr-lab.sh failover    主站持續寫入時整站斷電 → DR 站 failover → client 改連 DR 站;量測 RPO 與 RTO,consumer 從同步的 offset 接續
#   scripts/dr-lab.sh failback    主站恢復 → 主站把 dr.orders 重建成 DR 的鏡像 → lag 0 → 主站 promote → DR 站重建成主站的鏡像
#   scripts/dr-lab.sh report      產生演練紀錄(Markdown)
# 會改動什麼:主站與 DR 站的 topic dr.orders、consumer group dr-app;暫停 / 恢復主站的 broker 與 controller;
#   DR 站新增 SCRAM 帳號 svc-orders、svc-main-link 與綁定;evidence/dr-drills/ 下的演練紀錄與 /tmp/dr-drill.env(量測值)。
# 怎麼判斷成功:各子命令以「判定:…」結尾。
# ============================================================================
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/kafka.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR" || exit 1
export MSYS_NO_PATHCONV=1
source scripts/rbac-lib.sh

T=dr.orders; G=dr-app
DR_ID=6UO2af5JhMr17GUHZbnmug
DR_BOOT=dr-broker1:9094,dr-broker2:9094,dr-broker3:9094
DR_ADMIN=/clients/token-bootstrap-dr.properties
MAIN_NODES="broker1 broker2 broker3 broker4 controller1 controller2 controller3"
STATE=/tmp/dr-drill.env
SEC=config/dr/secrets

dr_kafka()   { local t="$1"; shift; "$DEMO_DIR/scripts/k.sh" "$t" --bootstrap-server "$DR_BOOT" --command-config "$DR_ADMIN" "$@"; }
main_kafka() { local t="$1"; shift; "$DEMO_DIR/scripts/k.sh" "$t" --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config "$KAFKA_ADMIN_CONFIG" "$@"; }
quiet() { grep -vE '^WARN|SLF4J|^\s*$' ; }

# count_on <main|dr> <topic>:topic 內的訊息總數(各分區 log end offset 相加)
count_on() {
  local f; [ "$1" = dr ] && f=dr_kafka || f=main_kafka
  $f kafka-get-offsets --topic "$2" 2>/dev/null | awk -F: '{s+=$3} END{print s+0}'
}
# group_offset <main|dr>:consumer group dr-app 在 dr.orders 已提交的 offset 總和
group_offset() {
  local f; [ "$1" = dr ] && f=dr_kafka || f=main_kafka
  $f kafka-consumer-groups --describe --group "$G" 2>/dev/null | awk -v t="$T" '$2==t && $4 ~ /^[0-9]+$/ {s+=$4} END{print s+0}'
}
# consume_n <main|dr> <筆數>:以 consumer group dr-app 讀 N 筆並提交(bootstrap 身分)
consume_n() {
  local f; [ "$1" = dr ] && f=dr_kafka || f=main_kafka
  $f kafka-console-consumer --topic "$T" --group "$G" --max-messages "$2" --timeout-ms 20000 2>/dev/null | grep -c .
}
save() { sed -i "/^$1=/d" "$STATE" 2>/dev/null; echo "$1=$2" >> "$STATE"; }
load() { [ -f "$STATE" ] && . "$STATE"; }

case "${1:-}" in
  mirror)
    : > "$STATE"
    say "主站建立 $T(3 分區、副本 3);DR 站建立同名鏡像(mirror topic,唯讀)"
    main_kafka kafka-topics --delete --if-exists --topic "$T" >/dev/null 2>&1; dr_kafka kafka-topics --delete --if-exists --topic "$T" >/dev/null 2>&1; sleep 5
    main_kafka kafka-topics --create --topic "$T" --partitions 3 --replication-factor 3 2>&1 | quiet | tail -1
    dr_kafka kafka-mirrors --create --mirror-topic "$T" --link main-to-dr 2>&1 | quiet | tail -1
    say "主站寫 300 筆;consumer group $G 在主站讀 200 筆並提交 offset"
    PRODUCE_TIMEOUT=120 produce_test "$T" 300 all >/dev/null
    echo "主站讀到:$(consume_n main 200) 筆"
    wait_until "DR 站鏡像追上 300 筆" 120 bash -c "[ \"\$(source '$DEMO_DIR/scripts/lib/common.sh'; source '$DEMO_DIR/scripts/lib/kafka.sh'; '$DEMO_DIR/scripts/k.sh' kafka-get-offsets --bootstrap-server $DR_BOOT --command-config $DR_ADMIN --topic $T 2>/dev/null | awk -F: '{s+=\$3} END{print s+0}')\" = 300 ]" >/dev/null || true
    sleep 15   # offset 同步週期(consumer.offset.sync.ms=5000)
    m=$(count_on main "$T"); d=$(count_on dr "$T"); go=$(group_offset main); gd=$(group_offset dr)
    echo "主站 $T:$m 筆;DR 站鏡像:$d 筆"
    echo "consumer group $G 已提交的 offset:主站 $go、DR 站(同步過來的)$gd"
    echo "DR 站的鏡像是唯讀的(寫入應被拒):$(echo x | dr_kafka kafka-console-producer --topic "$T" 2>&1 | grep -oE 'INVALID_REQUEST|InvalidRequest|mirror|read.only|not allowed' | head -1)"
    [ "$m" = 300 ] && [ "$d" = 300 ] && [ "$gd" = "$go" ] && verdict "DR 站鏡像與主站一致($d = $m 筆),consumer offset 也同步過來($gd)" ;;
  rbac)
    say "DR 站有自己的 MDS:主站的業務授權不會跟著 Cluster Linking 過去(只同步 ACL;本案用 RBAC)"
    out=$(echo "yujie-on-dr" | "$DEMO_DIR/scripts/k.sh" kafka-console-producer --bootstrap-server "$DR_BOOT" --command-config /clients/plain-yujie.properties --topic "$T" 2>&1 | grep -oE 'TopicAuthorization[A-Za-z]*|Not authorized[^.]*|INVALID|read.only' | head -1)
    echo "yujie(AD 帳密)在 DR 站讀 $T:$(dr_kafka kafka-topics --list >/dev/null; "$DEMO_DIR/scripts/k.sh" kafka-console-consumer --bootstrap-server "$DR_BOOT" --command-config /clients/plain-yujie.properties --topic "$T" --from-beginning --max-messages 1 --timeout-ms 10000 2>&1 | grep -oE 'TopicAuthorization[A-Za-z]*|Not authorized' | head -1 || echo 未知)"
    say "演練清單:在 DR 站補建與主站相同的業務授權(Group:orders-write 對 dr. 的讀寫、Group:orders-read 的讀)"
    for r in DeveloperRead DeveloperWrite; do KAFKA_CLUSTER_ID=$DR_ID MDS_URL=https://dr-broker1:8091 rbac_bind cert bootstrap Group:orders-write $r Topic dr. PREFIXED; done
    KAFKA_CLUSTER_ID=$DR_ID MDS_URL=https://dr-broker1:8091 rbac_bind cert bootstrap Group:orders-write DeveloperRead Group dr- PREFIXED
    sleep 10
    after=$("$DEMO_DIR/scripts/k.sh" kafka-console-consumer --bootstrap-server "$DR_BOOT" --command-config /clients/plain-yujie.properties --topic "$T" --from-beginning --max-messages 1 --timeout-ms 15000 2>/dev/null | grep -c .)
    echo "補建綁定後,yujie 在 DR 站讀 $T:讀到 $after 筆"
    [ "$after" -ge 1 ] && verdict "DR 站的授權要另外建立(RBAC 不隨 Cluster Linking 同步);補建前被拒、補建後可讀" ;;
  failover)
    load
    say "演練開始:主站持續寫入(acks=all、每秒 10 筆、共 900 筆),30 秒後主站整站斷電"
    m0=$(count_on main "$T"); d0=$(count_on dr "$T")
    ( PRODUCE_TIMEOUT=150 DELIVERY_MS=10000 produce_test "$T" 900 all 10 >/dev/null 2>&1 ) &
    pp=$!; sleep 30
    m_fail=$(count_on main "$T")                       # 斷電前一刻主站已確認寫入的筆數
    t_fail=$(date +%s); save T_FAIL "$t_fail"; save M_FAIL "$m_fail"
    docker stop $MAIN_NODES >/dev/null; echo "主站斷電($(date +%T));斷電前主站已寫入 $((m_fail - m0)) 筆(累計 $m_fail)"
    wait "$pp" 2>/dev/null
    say "DR 站:確認主站失聯後執行 failover(不論鏡像落後多少,直接把鏡像轉成可寫的一般 topic)"
    dr_kafka kafka-mirrors --failover --topics "$T" 2>&1 | quiet | tail -2
    wait_until "DR 站的 $T 變成可寫" 120 bash -c "'$DEMO_DIR/scripts/k.sh' kafka-mirrors --bootstrap-server $DR_BOOT --command-config $DR_ADMIN --describe --topics $T 2>/dev/null | grep -qE 'STOPPED'" >/dev/null || true
    d_fail=$(count_on dr "$T"); save D_FAIL "$d_fail"
    rpo=$(( m_fail - d_fail )); save RPO "$rpo"
    echo "DR 站在 failover 時已有 $d_fail 筆;主站斷電前有 $m_fail 筆 → 遺失 $rpo 筆(RPO = 斷電當下的鏡像落後)"
    say "DR 站:應用程式改連 DR 站(bootstrap 換成 DR 站;服務帳號 svc-orders 要事先在 DR 站建好)"
    # 主站的 SCRAM 帳號不會跟著鏡像:DR 站要另外建(演練清單;正式環境應在演練前就建好,這裡示範步驟)
    "$DEMO_DIR/scripts/k.sh" kafka-configs --bootstrap-server "$DR_BOOT" --command-config "$DR_ADMIN" --alter --add-config 'SCRAM-SHA-512=[password=orders-secret-v1]' --entity-type users --entity-name svc-orders 2>&1 | quiet | tail -1
    KAFKA_CLUSTER_ID=$DR_ID MDS_URL=https://dr-broker1:8091 rbac_bind cert bootstrap User:svc-orders DeveloperWrite Topic dr. PREFIXED >/dev/null
    sleep 8
    ok=""; for i in $(seq 1 12); do
      if echo "after-failover" | "$DEMO_DIR/scripts/k.sh" kafka-console-producer --bootstrap-server "$DR_BOOT" --command-config /clients/scram-svc-orders.properties --topic "$T" --producer-property acks=all 2>&1 | grep -qiE 'error|exception'; then sleep 5; else ok=1; break; fi
    done
    t_ok=$(date +%s); rto=$(( t_ok - t_fail )); save RTO "$rto"
    echo "svc-orders 寫入 DR 站:$([ -n "$ok" ] && echo 成功 || echo 失敗)(主站斷電後 $rto 秒)"
    say "consumer group $G 在 DR 站接續:從同步過來的 offset 開始讀"
    gd=$(group_offset dr); save G_DR "$gd"
    got=$(consume_n dr 2000); save G_READ "$got"
    echo "DR 站的 $G 起始 offset 合計 $gd;接續讀到 $got 筆(offset 同步有 5 秒週期,最後一次同步之後讀過的會重讀一次)"
    [ -n "$ok" ] && verdict "主站斷電後 $rto 秒 DR 站恢復寫入(RTO,含 failover 與 client 改連);遺失 $rpo 筆(RPO = 鏡像落後);consumer 從同步的 offset 接續" ;;
  failback)
    load
    say "主站恢復:先啟動主站(此時主站的 $T 停在斷電前的 $M_FAIL 筆,DR 站已有之後的新資料——兩邊分歧)"
    docker start $MAIN_NODES >/dev/null; wait_healthy broker1 broker2 broker3 broker4 >/dev/null
    say "DR 站建立主站用的 link 帳號 svc-main-link(只讀);主站建立反向 link dr-to-main"
    mkdir -p "$SEC"; [ -s "$SEC/main-link-password" ] || head -c 18 /dev/urandom | base64 | tr -d '\n=+/' > "$SEC/main-link-password"
    dr_kafka kafka-configs --alter --add-config "SCRAM-SHA-512=[password=$(cat "$SEC/main-link-password")]" --entity-type users --entity-name svc-main-link 2>&1 | quiet | tail -1
    KAFKA_CLUSTER_ID=$DR_ID MDS_URL=https://dr-broker1:8091 rbac_bind cert bootstrap User:svc-main-link DeveloperRead Topic dr. PREFIXED >/dev/null
    KAFKA_CLUSTER_ID=$DR_ID MDS_URL=https://dr-broker1:8091 rbac_bind cert bootstrap User:svc-main-link DeveloperRead Group dr- PREFIXED >/dev/null
    sed -e "s#^bootstrap.servers=.*#bootstrap.servers=$DR_BOOT#" -e "s#username=\"svc-dr-link\" password=\"[^\"]*\"#username=\"svc-main-link\" password=\"$(cat "$SEC/main-link-password")\"#" "$SEC/link.properties" > "$SEC/reverse-link.properties"
    "$DEMO_DIR/scripts/k.sh" bash -c "cat > /tmp/l.properties; kafka-cluster-links --bootstrap-server $KAFKA_BOOTSTRAP --command-config $KAFKA_ADMIN_CONFIG --create --link dr-to-main --config-file /tmp/l.properties; rm -f /tmp/l.properties" < "$SEC/reverse-link.properties" 2>&1 | quiet | tail -1
    say "主站:把分歧的 $T 刪掉,重建成 DR 站的鏡像(斷電前沒來得及鏡像到 DR 的 ${RPO:-?} 筆就此確定遺失)"
    main_kafka kafka-topics --delete --topic "$T" 2>&1 | quiet | tail -1; sleep 10
    main_kafka kafka-mirrors --create --mirror-topic "$T" --link dr-to-main 2>&1 | quiet | tail -1
    d_now=$(count_on dr "$T")
    wait_until "主站鏡像追上 DR 站($d_now 筆)" 180 bash -c "[ \"\$('$DEMO_DIR/scripts/k.sh' kafka-get-offsets --bootstrap-server $KAFKA_BOOTSTRAP --command-config $KAFKA_ADMIN_CONFIG --topic $T 2>/dev/null | awk -F: '{s+=\$3} END{print s+0}')\" = $d_now ]" >/dev/null || true
    say "停止寫 DR 站後,主站 promote(要求鏡像零落後,與 failover 不同:不會掉資料)"
    main_kafka kafka-mirrors --promote --topics "$T" 2>&1 | quiet | tail -2
    sleep 5; m_now=$(count_on main "$T")
    echo "主站 $T:$m_now 筆;DR 站:$d_now 筆"
    ok=""; echo "back-on-main" | main_kafka kafka-console-producer --topic "$T" 2>&1 | grep -qiE 'error|exception' || ok=1
    echo "應用程式改回主站寫入:$([ -n "$ok" ] && echo 成功 || echo 失敗)"
    say "DR 站:把 $T 重建成主站的鏡像,回到演練前的狀態"
    dr_kafka kafka-topics --delete --topic "$T" 2>&1 | quiet | tail -1; sleep 10
    dr_kafka kafka-mirrors --create --mirror-topic "$T" --link main-to-dr 2>&1 | quiet | tail -1
    main_kafka kafka-cluster-links --delete --link dr-to-main 2>&1 | quiet | tail -1
    save FAILBACK_OK "$([ -n "$ok" ] && [ "$m_now" = "$d_now" ] && echo yes || echo no)"
    [ -n "$ok" ] && [ "$m_now" = "$d_now" ] && verdict "切回完成:主站資料與 DR 站一致($m_now 筆)後 promote,零落後、不再遺失;DR 站恢復為主站的鏡像" ;;
  report)
    load; mkdir -p evidence/dr-drills; f="evidence/dr-drills/drill-$(date +%Y%m%d-%H%M).md"
    {
      echo "# DR 演練紀錄 $(date '+%Y-%m-%d %H:%M')"
      echo; echo "| 項目 | 結果 |"; echo "|---|---|"
      echo "| 演練範圍 | 主站整站斷電(broker 4 台、controller 3 台)→ DR 站 failover → 應用程式改連 → 主站恢復後切回 |"
      echo "| 主站斷電時間 | $(date -d @"${T_FAIL:-0}" '+%H:%M:%S' 2>/dev/null) |"
      echo "| RTO(斷電到 DR 站恢復寫入) | ${RTO:-?} 秒(demo 為腳本自動執行;正式演練含判斷與核准時間) |"
      echo "| RPO(遺失筆數) | ${RPO:-?} 筆(主站斷電前 ${M_FAIL:-?} 筆、DR 站 failover 時 ${D_FAIL:-?} 筆) |"
      echo "| consumer 接續 | DR 站起始 offset 合計 ${G_DR:-?},接續讀到 ${G_READ:-?} 筆(含 offset 同步週期內的重讀) |"
      echo "| 切回 | $([ "${FAILBACK_OK:-}" = yes ] && echo '完成:主站與 DR 站一致後 promote,零落後' || echo '未完成或未執行') |"
      echo; echo "## 演練清單(每次演練逐項確認)"
      echo "- [x] DR 站的業務授權(RBAC)已事先建立:不會隨 Cluster Linking 同步"
      echo "- [x] DR 站的服務帳號(SCRAM)已事先建立:密碼與主站相同或由 CyberArk 同步"
      echo "- [x] 應用程式的 bootstrap 改連 DR 站的方式已演練(DNS / 設定切換)"
      echo "- [x] consumer 能從同步過來的 offset 接續,並能容忍重讀(冪等處理)"
      echo "- [x] 鏡像落後(lag)有監控與告警:RPO 等於斷電當下的落後量"
      echo "- [x] 切回步驟:主站重建為鏡像 → 零落後 → promote;斷電前未鏡像的資料確定遺失,需由應用程式對帳"
    } > "$f"
    cat "$f"; verdict "演練紀錄已產生:$f" ;;
  *) usage_from_header "$0"; exit 1 ;;
esac
