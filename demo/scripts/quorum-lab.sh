#!/usr/bin/env bash
# ============================================================================
# quorum-lab.sh — 第 33 章:動態 quorum(KRaft controller 名單存在叢集裡,可以不停機增減與汰換 controller)
# ----------------------------------------------------------------------------
# 白話:這個叢集一開始就是動態 quorum(官方建議的正式環境做法):controller 名單存在叢集 metadata,不寫在每台設定檔。
#   換一台壞掉的 controller 只要「新的加進來、舊的移出去」兩個指令,不用改別台的設定、也不用重啟。
#   這支腳本模擬一台 controller 主機損壞,實際做一次汰換,並在汰換後再壞一台,驗證新名單仍能服務。
#   (從靜態 quorum 升級成動態的做法見 DESIGN-BASIS「動態 quorum」:kafka-features upgrade --feature kraft.version=1,再換設定並依序重啟。)
# 前置條件:全新環境(scripts/ha.sh on),叢集健康
# 用法:
#   scripts/quorum-lab.sh status     kraft.version、voter 名單與 directory id、誰是 leader
#   scripts/quorum-lab.sh replace    汰換:停 controller3(模擬主機損壞)→ 啟動全新的 controller4 → add-controller → remove-controller 3;
#                                    之後再停 controller1,驗證新的 quorum {1,2,4} 仍能服務
#   scripts/quorum-lab.sh reset      清掉 controller4(controller3 啟動回來不會重新加入,要用 scripts/ha.sh on 重建環境)
# 會改動什麼:replace 會永久改變 voter 名單(3 換成 4)並啟動 controller4(profile quorum)。實驗後建議 scripts/ha.sh on 重建。
# 怎麼判斷成功:每個子命令最後一行印「判定:…」。
# 常見失敗:add-controller 被拒 → 新節點尚未追上(describe --replication 看 lag)或沒用 --no-initial-controllers 格式化;
#   remove-controller 要同時給 controller id 與 directory id,從 describe --status 取;等不到 leader → docker logs controller1。
# ============================================================================
set -uo pipefail
PERF_OUT=/tmp/quorum-lab-perf.out
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/kafka.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR" || exit 1
need_ha_mode

CTRL_BOOT=controller1:9093,controller2:9093,controller3:9093       # 從哪裡找到 quorum(用於 --bootstrap-controller)
TOOL_CFG=/clients/internal.properties                               # mTLS 身分 CN=kafka-internal(super user)
TOPIC=quorum.t

# ---------- 小工具(這支腳本專用) ----------

# 在一次性容器裡執行 KRaft 相關工具,走 CONTROLLER 埠(mTLS):quorum_tool <命令> <參數…>。
quorum_tool() {
  local cmd="$1"; shift
  "$DEMO_DIR/scripts/k.sh" "$cmd" "$@" 2>&1 | grep -v -E 'SLF4J|^WARNING|WARN'
}

# kafka-metadata-quorum 對 controller 的查詢:quorum_md <bootstrap-controller 位址> <子命令…>。
quorum_md() {
  local bc="$1"; shift
  quorum_tool kafka-metadata-quorum --bootstrap-controller "$bc" --command-config "$TOOL_CFG" "$@"
}

# 目前還活著的第一個 controller(當查詢入口)。
live_controller() {
  local c
  for c in controller1 controller2 controller3 controller4; do
    docker ps --format '{{.Names}}' | grep -x "$c" >/dev/null && { echo "$c:9093"; return; }
  done
}

# kraft.version 的 finalized 等級(0 = 靜態,1 = 動態)。
kraft_version() {
  quorum_tool kafka-features --bootstrap-controller "$(live_controller)" --command-config "$TOOL_CFG" describe \
    | grep -E 'Feature: kraft.version' | grep -oE 'FinalizedVersionLevel: [0-9]+' | grep -oE '[0-9]+$' | head -1
}

# voter 名單:每行「節點 id  directoryId」。
voters() {
  quorum_md "$(live_controller)" describe --status | grep '^CurrentVoters' \
    | grep -oE '"id": [0-9]+(, "directoryId": "[^"]+")?' | sed -E 's/"id": ([0-9]+)(, "directoryId": "([^"]+)")?/\1 \3/'
}

# 名單中是否有某節點。
has_voter() { voters | awk '{print $1}' | grep -x "$1" >/dev/null; }   # 不用 grep -q:pipefail 下 grep 提早結束會讓上游吃 SIGPIPE,整條回傳非 0

# 給 wait_until 用:controller 名單(靜態版沒有 directoryId)有 N 個 voter。
voter_count_is() { [ "$(voters | wc -l)" -eq "$1" ]; }

# 給 wait_until 用:叢集有 leader。
has_leader() { quorum_md "$(live_controller)" describe --status | grep -E '^LeaderId:[[:space:]]+[0-9]+' >/dev/null; }

# 目前寫入測試:在背景持續寫 N 筆(每秒 R 筆),結果存 $PERF_OUT;回傳背景 pid 用 BG_PID。
start_writes() {
  : > "$PERF_OUT"
  ( PRODUCE_TIMEOUT=600 produce_test "$TOPIC" "$1" all "$2" > /tmp/quorum-lab-sent ) &
  BG_PID=$!
}

# 等 broker 與 controller 全部 healthy。
all_healthy() {
  local n
  for n in "$@"; do container_healthy "$n" || return 1; done
}

# ---------- 各個實驗 ----------

lab_status() {
  say "kraft.version 與 voter 名單(動態 quorum 的每個 voter 有 directory id,移除 controller 時要用)"
  echo "kraft.version = $(kraft_version)(0 = 靜態、1 = 動態)"
  quorum_md "$(live_controller)" describe --status | grep -E '^(ClusterId|LeaderId|LeaderEpoch|CurrentVoters|CurrentObservers)' | cut -c1-230 | sed 's/^/  /'
  verdict "目前是 $([ "$(kraft_version)" = 1 ] && echo 動態 || echo 靜態) quorum,voter $(voters | wc -l) 個,每個 voter 都有 directory id"
}

lab_replace() {
  [ "$(kraft_version)" = 1 ] || die "還不是動態 quorum。先執行:scripts/quorum-lab.sh upgrade"
  local before; before=$(voters | tr '\n' ';')
  echo "替換前 voter:$before"
  say "模擬 controller3 的主機損壞:停掉它(剩 2/3,仍有多數,叢集照常)"
  stop_containers controller3
  wait_until "剩下的 controller 仍有 leader" 60 has_leader || true
  say "在全新的節點 controller4 上以 --no-initial-controllers 格式化並啟動(它還不是 voter,只是 observer)"
  docker compose --profile quorum up -d controller4 >/dev/null 2>&1
  wait_healthy controller4 >/dev/null || die "controller4 沒有 healthy:docker logs controller4"
  sleep 10
  say "把 controller4 加進 quorum:在新節點上執行 add-controller(--command-config 用它自己的設定,工具從中讀 node.id 與 directory id)"
  docker exec controller4 bash -c "cp /etc/kafka/kafka.properties /tmp/add.properties; printf 'security.protocol=SSL\nssl.keystore.location=/etc/kafka/secrets/internal.keystore.p12\nssl.keystore.type=PKCS12\nssl.keystore.password=changeit\nssl.key.password=changeit\n' >> /tmp/add.properties" >/dev/null
  docker exec -e KAFKA_OPTS= controller4 kafka-metadata-quorum --bootstrap-controller controller1:9093 --command-config /tmp/add.properties add-controller 2>&1 \
    | grep -v -E 'SLF4J|^WARNING|WARN' | tail -3
  wait_until "controller4 成為 voter" 60 has_voter 4 || true
  local dir3; dir3=$(voters | awk '$1==3 {print $2}')
  say "把壞掉的 controller3 從名單移出:remove-controller --controller-id 3 --controller-directory-id <directory id>"
  quorum_md controller1:9093 remove-controller --controller-id 3 --controller-directory-id "$dir3" | tail -2
  wait_until "名單剩 3 個 voter(1、2、4)" 60 voter_count_is 3 || true
  echo "替換後 voter:$(voters | awk '{print $1}' | tr '\n' ' ')"
  say "再停掉 controller1(剩 2/3:controller2 與 controller4),新的 quorum 仍要能服務:寫入與建 topic"
  stop_containers controller1
  wait_until "新 quorum 選出 leader" 60 has_leader || true
  local sent; sent=$(produce_test "$TOPIC" 200 all)
  echo -n "停 controller1 後建立 topic:"; create_topic --topic quorum.after --partitions 1 --replication-factor 3
  start_containers controller1; wait_healthy controller1 >/dev/null
  [ "$(voters | awk '{print $1}' | sort | tr '\n' ' ')" = "1 2 4 " ] && [ "${sent:-0}" = 200 ] \
    && verdict "控制器汰換完成:3 換成 4,名單 {1,2,4};只改了 quorum 名單,沒有重啟 broker 或其他 controller;停 controller1 後仍可寫入與建 topic"
}

lab_reset() {
  docker compose --profile quorum stop controller4 >/dev/null 2>&1
  docker compose --profile quorum rm -f controller4 >/dev/null 2>&1
  note "controller4 已移除;要回到乾淨環境請執行 scripts/ha.sh on"
}

create_topic() { kafka_topics --create "$@" | grep -E "Created|rror" || echo "失敗"; }

case "${1:-}" in
  status)  lab_status ;;
  replace) lab_replace ;;
  reset)   lab_reset ;;
  *)       usage_from_header "$0"; exit 1 ;;
esac
