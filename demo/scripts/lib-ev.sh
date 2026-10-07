#!/usr/bin/env bash
# 取證與講解共用函式庫:每一步執行指令 → 顯示 → 存成 evidence/<章>/NN-xxx.log(之後轉成終端風格截圖)。
# 每個 step 可附上「預期」(expect),preflight 會檢查實際輸出是否符合預期。
# 環境變數 DEMO_PAUSE=1 時,每步執行前顯示講稿並等待 Enter(現場講解用)。
DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEMO_ROOT_W="$(cd "$DEMO_ROOT" && pwd -W 2>/dev/null || echo "$DEMO_ROOT")"
EV_ROOT="$DEMO_ROOT/evidence"
export MSYS_NO_PATHCONV=1
EV_FAIL=0

C_RESET=$'\033[0m'; C_G=$'\033[32m'; C_R=$'\033[31m'; C_Y=$'\033[33m'; C_B=$'\033[36m'

ch_begin() { # ch_begin <chapter-id> "<chapter title>"
  CH="$1"; CHDIR="$EV_ROOT/$CH"; N=0
  rm -rf "$CHDIR"; mkdir -p "$CHDIR"
  echo; echo "${C_B}══ 第 ${CH#ch} 章:$2 ══${C_RESET}"
  printf '%s\n' "$2" > "$CHDIR/_title.txt"
}

# 過濾 JVM/Kafka 工具的雜訊,只留有意義的行
_ev_filter() {
  grep -v -E '^(WARNING|SLF4J)|^\s+at |Option .* is deprecated|--(producer|consumer)\.config is deprecated|KIP-848|^Warning: --|AppInfoParser|^\s*$|Caused by: .*TimeoutException|Error in kafka producer I/O thread|ErrorLoggingCallback|UnknownTopicOrPartition|Transactional method invoked' \
  | sed -E 's/^\[20[0-9-]+ [0-9:,]+\] //' \
  | grep -v -E 'AdminMetadataManager|^ ?\(org\.apache\.kafka\.tools|^ ?\(org\.apache\.kafka\.clients' \
  | sed -E 's/ \(org\.apache\.kafka\.[a-zA-Z.]+\)$//' | cut -c1-200
}

# step <slug> "<標題/講稿>" "<顯示用指令>" <實際執行的 shell 字串> [expect-regex]
step() {
  local slug="$1" title="$2" shown="$3" cmd="$4" expect="${5:-}"
  N=$((N+1)); local id; id=$(printf '%02d' "$N"); local f="$CHDIR/$id-$slug.log"
  if [ "${DEMO_PAUSE:-0}" = 1 ]; then echo; echo "${C_Y}▶ [$id] $title${C_RESET}"; read -r -p "   (Enter 執行) " _; fi
  local out rc
  out=$(eval "$cmd" 2>&1 | _ev_filter); rc=${PIPESTATUS[0]}
  {
    printf '# %s\n' "$title"
    printf '$ %s\n' "$shown"
    printf '%s\n' "$out"
  } > "$f"
  echo "${C_G}[$id]${C_RESET} $title"; echo "    \$ $shown"; printf '%s\n' "$out" | sed 's/^/    /' | head -${EV_SHOW:-12}
  if [ -n "$expect" ]; then
    if printf '%s' "$out" | grep -q -E "$expect"; then echo "    ${C_G}✔ 符合預期 (/$expect/)${C_RESET}"; echo "PASS" > "$f.result"
    else echo "    ${C_R}✘ 不符合預期 (/$expect/)${C_RESET}"; echo "FAIL" > "$f.result"; EV_FAIL=$((EV_FAIL+1)); fi
  fi
}

# ---------- 友善包裝(顯示成客戶看得懂的指令) ----------
BOOT="broker1:9094"
K() { "$DEMO_ROOT/scripts/k.sh" "$@"; }
as_produce() { # as_produce <user> <topic> <message>   (人:SASL/PLAIN + AD 帳密)
  echo "$3" | K kafka-console-producer --bootstrap-server $BOOT --command-config "/clients/plain-$1.properties" --topic "$2"
}
as_consume() { # as_consume <user> <topic> [group]
  K kafka-console-consumer --bootstrap-server $BOOT --command-config "/clients/plain-$1.properties" --topic "$2" --group "${3:-demo-$1}" --from-beginning --max-messages 3 --timeout-ms 15000
}
as_list() { K kafka-topics --bootstrap-server $BOOT --command-config "/clients/plain-$1.properties" --list; }
svc_produce() { # svc_produce <props-name> <topic> <message>  (服務:SCRAM)
  echo "$3" | K kafka-console-producer --bootstrap-server $BOOT --command-config "/clients/$1.properties" --topic "$2"
}
rp() { "$DEMO_ROOT/scripts/rp.sh" "$@"; }
mds() { "$DEMO_ROOT/scripts/mds.sh" "$@"; }
ldapg() { "$DEMO_ROOT/scripts/ldap-group.sh" "$@"; }

wait_group_effect() { # 等待 LDAP 群組異動被 MDS 套用(快取 5 秒);最多 40 秒
  local i; for i in $(seq 1 10); do sleep 4; done; }

ch_end() { echo "${C_B}── 第 ${CH#ch} 章完成(失敗 $EV_FAIL 項)──${C_RESET}"; return $EV_FAIL; }

as_script() { "$DEMO_ROOT/scripts/as-user.sh" "$@"; }

# audit_events [audit-fmt.mjs 參數...] —— 讀 audit log,整理成一行一事件(用 node 解析 JSON,避免大量子行程)
audit_events() {
  K kafka-console-consumer --bootstrap-server $BOOT --command-config /clients/token-bootstrap.properties     --topic confluent-audit-log-events --from-beginning --timeout-ms 12000 2>/dev/null | node "$DEMO_ROOT_W/scripts/audit-fmt.mjs" "$@"
}

# send_result <指令...> —— 執行指令並在最後印出明確的結果行(成功 / 被拒絕),避免「指令回傳碼為 0 但其實被拒」的誤判
send_result() {
  local out; out=$("$@" 2>&1); printf '%s\n' "$out"
  if printf '%s' "$out" | grep -q -i -E "not authorized|TopicAuthorization|authorization failed|Authentication failed|FAILED"; then echo "→ 結果:被拒絕"; else echo "→ 結果:成功"; fi
}
