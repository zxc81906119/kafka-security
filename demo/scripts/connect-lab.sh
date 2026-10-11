#!/usr/bin/env bash
# ============================================================================
# connect-lab.sh — 第 29 章:Kafka Connect 的安全與可靠性(RBAC、連接器身分、壞資料、密碼不落地)
# ----------------------------------------------------------------------------
# 白話:連接器是「長期在背景搬資料」的程式,出事的方式和一般應用不同。這支腳本逐項驗證:
#   誰能建立與看到連接器(RBAC)、連接器用自己的最小權限身分而不是 worker 的大權限、
#   壞資料不會拖垮整個連接器(DLQ)、連接器的密碼不會寫在設定裡被人從 REST 或 topic 讀走。
#   連接器用 Apache Kafka 自帶的 FileStreamSink(寫進檔案),只為了示範 Connect 本身的行為。
# 前置條件:HA 模式 + scripts/connect-setup.sh on
# 用法:
#   scripts/connect-lab.sh rbac       AD 群組決定誰能建立、看到、刪除連接器
#   scripts/connect-lab.sh identity   連接器用自己的服務帳號(最小權限);用 worker 身分或讀沒授權的 topic 會失敗
#   scripts/connect-lab.sh dlq        壞資料:沒有容錯時連接器停擺;有容錯加 DLQ 時好的繼續、壞的進 DLQ 並附錯誤原因
#   scripts/connect-lab.sh secrets    密碼用 config provider 引用:REST 與 connect-configs topic 都看不到密碼;直接寫進設定就看得到
# 會改動什麼:建立並刪除連接器 orders-*、topic orders.sink 的測試資料(寫入)與 DLQ;其餘只讀。
# 怎麼判斷成功:最後一行印「判定:…」。
# 常見失敗:REST 回 403 → 角色綁定未生效(等 1 分鐘);連接器 FAILED → 看 /connectors/<名稱>/status 的 trace
# ============================================================================
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/kafka.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR" || exit 1
need_ha_mode
need_container connect1 "先執行:scripts/connect-setup.sh on"
need_container connect2 "先執行:scripts/connect-setup.sh on"

CONNECT=https://connect:8083
JSON_TYPE='Content-Type: application/json'

# ---------- 小工具(這支腳本專用) ----------

# 只取 HTTP 狀態碼那一行。
http_code() { dcurl "$@" 2>/dev/null | tail -1; }

# create_connector <帳密> <連接器名稱> <topic> [connector-json.mjs 的選項…]:建立連接器,印 HTTP 狀態碼。
create_connector() {
  local cred="$1" name="$2" topic="$3"; shift 3
  dcurl -u "$cred" -X POST -H "$JSON_TYPE" -d "$(node "$LIB_DIR/connector-json.mjs" "$name" "$topic" "$@")" "$CONNECT/connectors" 2>/dev/null | tail -1
}

# connector_state <名稱>:連接器與第一個 task 的狀態(例如 RUNNING/RUNNING);不存在印 NONE。
connector_state() {
  local out; out=$(dcurl -u gary:gary-pw "$CONNECT/connectors/$1/status" 2>/dev/null)
  echo "$out" | grep -q '"state"' || { echo NONE; return; }
  echo "$(echo "$out" | grep -o '"connector":{"state":"[A-Z]*"' | grep -o '[A-Z]*"$' | tr -d '"')/$(echo "$out" | grep -o '"tasks":\[{"id":0,"state":"[A-Z]*"' | grep -o '[A-Z]*"$' | tr -d '"')"
}

# state_is <名稱> <期望狀態>:連接器狀態等於期望值就回傳 0(給 wait_until 用)。
state_is() { [ "$(connector_state "$1")" = "$2" ]; }

# wait_state <名稱> <期望狀態,例如 RUNNING/RUNNING> [最多秒數]
wait_state() { wait_until "$1 = $2" "${3:-90}" state_is "$1" "$2"; }

# 刪除連接器(用 gary,topic-admin 群組可管全部);不存在也不算錯。
delete_connector() { for n in "$@"; do dcurl -u gary:gary-pw -X DELETE "$CONNECT/connectors/$n" >/dev/null 2>&1; done; sleep 2; }

# 把訊息寫進 orders.sink(一行一筆)。
produce_lines() { "$DEMO_DIR/scripts/k.sh" kafka-console-producer --bootstrap-server "$KAFKA_BOOTSTRAP" --producer.config "$KAFKA_ADMIN_CONFIG" --topic orders.sink 2>&1 | grep -v -E 'WARN|SLF4J|deprecated'; }

# 重建 topic(清掉資料、保留角色綁定):reset_topics <topic…>。
reset_topics() {
  local t
  for t in "$@"; do kafka_topics --delete --if-exists --topic "$t" >/dev/null; done
  sleep 3
  for t in "$@"; do kafka_topics --create --topic "$t" --partitions 1 --replication-factor 3 --config min.insync.replicas=2 | grep -E "rror" || true; done
}

# 連接器第一個 task 失敗時的錯誤摘要(trace 的第一行)。
task_error() { dcurl -u gary:gary-pw "$CONNECT/connectors/$1/status" 2>/dev/null | grep -o '"trace":"[^"]*' | head -1 | cut -c10-190; }

# ---------- 各個實驗 ----------

lab_rbac() {
  say "AD 群組決定誰能做什麼:yujie(orders-write)只能管 orders- 開頭的連接器;ming 什麼都看不到;gary(topic-admin)管全部;沒帳密 401"
  local a b c d e f
  delete_connector orders-rbac payments-rbac
  a=$(create_connector yujie:yujie-pw orders-rbac orders.sink);   echo "yujie 建立 orders-rbac:$a"
  b=$(create_connector yujie:yujie-pw payments-rbac orders.sink); echo "yujie 建立 payments-rbac(名稱不在她的範圍):$b"
  c=$(create_connector ming:ming-pw orders-rbac2 orders.sink);    echo "ming 建立連接器:$c"
  d=$(dcurl -u ming:ming-pw "$CONNECT/connectors" 2>/dev/null | head -1); echo "ming 列出連接器:$d(空清單 = 授權過濾掉了,連名稱都看不到)"
  e=$(http_code -u ming:ming-pw "$CONNECT/connectors/orders-rbac/status"); echo "ming 讀 orders-rbac 的狀態:$e"
  f=$(http_code "$CONNECT/connectors"); echo "不帶帳密:$f"
  echo "gary 列出連接器:$(dcurl -u gary:gary-pw "$CONNECT/connectors" 2>/dev/null | head -1)"
  delete_connector orders-rbac payments-rbac orders-rbac2
  echo "$a" | grep -q "201" && echo "$b" | grep -q "403" && echo "$c" | grep -q "403" && [ "$d" = "[]" ] && echo "$e" | grep -q "403" && echo "$f" | grep -q "401" \
    && verdict "連接器的建立、查看依 AD 群組授權:yujie 只能管 orders- 開頭的(201 / 403)、ming 看不到也建不了、沒帳密 401"
}

lab_identity() {
  say "連接器用自己的 AD 服務帳號 SVC-ORDERS-SINK(只能讀 orders.sink);對照:用 worker 身分、或去讀沒授權的 topic,都會失敗"
  local ok err_worker err_wide
  delete_connector orders-own orders-worker orders-wide
  create_connector gary:gary-pw orders-own orders.sink --dlq >/dev/null     # 帶 --dlq:topic 裡留有前面實驗的壞資料,這個實驗只看身分,不要被壞資料干擾
  wait_state orders-own RUNNING/RUNNING >/dev/null; ok=$(connector_state orders-own); echo "orders-own(自己的服務帳號,讀 orders.sink):$ok"
  create_connector gary:gary-pw orders-worker orders.sink --principal=none >/dev/null
  wait_state orders-worker RUNNING/FAILED 120 >/dev/null; echo "orders-worker(沒覆寫身分 = 用 worker 的身分讀 orders.sink):$(connector_state orders-worker)"
  err_worker=$(task_error orders-worker); echo "   錯誤:${err_worker:-無}"
  create_connector gary:gary-pw orders-wide payments.events >/dev/null
  wait_state orders-wide RUNNING/FAILED 120 >/dev/null; echo "orders-wide(自己的服務帳號,但去讀沒授權的 payments.events):$(connector_state orders-wide)"
  err_wide=$(task_error orders-wide); echo "   錯誤:${err_wide:-無}"
  delete_connector orders-own orders-worker orders-wide
  [ "$ok" = "RUNNING/RUNNING" ] && echo "$err_worker" | grep -qi "authorization\|not authorized" && echo "$err_wide" | grep -qi "authorization\|not authorized" \
    && verdict "連接器各用自己的最小權限身分:有授權的 topic 正常;worker 身分沒有資料 topic 的讀取權,越權的 topic 讀不到(TopicAuthorizationException)"
}

lab_dlq() {
  say "寫 8 筆進 orders.sink(5 筆好的 JSON、3 筆壞的)。對照:沒有容錯的連接器遇到壞資料就停;有容錯加 DLQ 的好的繼續、壞的進 DLQ"
  local strict_state tol_file dlq_n header
  delete_connector orders-sink orders-strict orders-dlq      # orders-sink 是手動試過的舊連接器,它也會把壞資料寫進同一個 DLQ,先刪掉
  for w in connect1 connect2; do docker exec "$w" sh -c 'rm -f /tmp/orders-dlq.out /tmp/orders-strict.out' 2>/dev/null; done   # 連接器的 task 會跑在任一台 worker,兩台都清
  reset_topics orders.sink orders.sink.dlq      # 清掉前面實驗留下的資料,數字才是這一次的
  create_connector gary:gary-pw orders-strict orders.sink >/dev/null
  create_connector gary:gary-pw orders-dlq orders.sink --dlq >/dev/null
  wait_state orders-strict RUNNING/RUNNING >/dev/null; wait_state orders-dlq RUNNING/RUNNING >/dev/null
  printf '{"id":1}\n{"id":2}\nnot-json-a\n{"id":3}\nnot-json-b\n{"id":4}\n{"id":5}\nnot-json-c\n' | produce_lines
  wait_state orders-strict RUNNING/FAILED 90 >/dev/null; strict_state=$(connector_state orders-strict)
  echo "orders-strict(errors.tolerance=none,預設):$strict_state"
  echo "   錯誤:$(task_error orders-strict)"
  sleep 10
  tol_file=$( { docker exec connect1 cat /tmp/orders-dlq.out 2>/dev/null; docker exec connect2 cat /tmp/orders-dlq.out 2>/dev/null; } | grep -c '^{id=')   # task 在哪一台 worker 不固定,兩台的檔案合併計算
  echo "orders-dlq(errors.tolerance=all + DLQ):狀態 $(connector_state orders-dlq);寫進檔案的好資料 $tol_file 筆"
  dlq_n=$("$DEMO_DIR/scripts/k.sh" kafka-get-offsets --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config "$KAFKA_ADMIN_CONFIG" --topic orders.sink.dlq 2>/dev/null | awk -F: '{s+=$3} END {print s+0}')
  echo "DLQ topic orders.sink.dlq 共 $dlq_n 筆(壞資料 3 筆)"
  header=$("$DEMO_DIR/scripts/k.sh" kafka-console-consumer --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config "$KAFKA_ADMIN_CONFIG" --topic orders.sink.dlq --from-beginning --max-messages 1 --timeout-ms 8000 --property print.headers=true 2>&1 \
            | grep -o '__connect.errors.stage:[A-Z_]*\|__connect.errors.exception.class.name:[a-zA-Z.]*' | tr '\n' ' ')
  echo "DLQ 訊息的錯誤標頭:${header:-沒讀到}"
  delete_connector orders-strict orders-dlq
  [ "$strict_state" = "RUNNING/FAILED" ] && [ "$tol_file" = 5 ] && [ "$dlq_n" = 3 ] && echo "$header" | grep -q "VALUE_CONVERTER" \
    && verdict "沒有容錯的連接器遇到第一筆壞資料就 FAILED;有容錯加 DLQ 的 5 筆好資料照寫、3 筆壞資料進 DLQ 並附錯誤階段與原因"
}

lab_secrets() {
  say "同一個連接器,密碼寫法兩種:用 \${file:…} 引用密碼檔,或直接寫進設定。比較 REST 與 connect-configs topic(設定實際存放處)讀得到什麼"
  local pw=connector-orders-sink-pw prov_hit inline_hit rest_prov rest_inline
  delete_connector orders-prov orders-inline
  create_connector gary:gary-pw orders-prov orders.sink >/dev/null
  CONNECTOR_PASSWORD="$pw" create_connector gary:gary-pw orders-inline orders.sink --principal=inline >/dev/null
  sleep 5
  configs=$("$DEMO_DIR/scripts/k.sh" kafka-console-consumer --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config "$KAFKA_ADMIN_CONFIG" --topic connect-configs --from-beginning --timeout-ms 10000 2>/dev/null)
  prov_hit=$(echo "$configs" | grep '"orders-prov"\|connector-orders-prov' | grep -c "$pw")
  inline_hit=$(echo "$configs" | grep 'orders-inline' | grep -c "$pw")
  echo "connect-configs topic(連接器設定實際存放處)裡找密碼:用 provider 的連接器 $prov_hit 筆;直接寫進設定的連接器 $inline_hit 筆"
  echo "用 provider 的連接器,設定裡存的是:$(echo "$configs" | grep 'orders-prov' | grep -o '\${file:[^}]*}' | head -1)"
  rest_prov=$(dcurl -u gary:gary-pw "$CONNECT/connectors/orders-prov/config" 2>/dev/null | grep -c "$pw")
  rest_inline=$(dcurl -u gary:gary-pw "$CONNECT/connectors/orders-inline/config" 2>/dev/null | grep -c "$pw")
  echo "REST 讀連接器設定(gary):provider 版出現密碼 $rest_prov 次、直接寫版 $rest_inline 次(sasl.jaas.config 這類標示為密碼的設定,REST 會遮成 ••••)"
  echo "connect-configs 是普通 topic:誰能讀它,誰就拿得到寫在裡面的密碼——所以密碼不能寫進設定"
  delete_connector orders-prov orders-inline
  [ "$prov_hit" = 0 ] && [ "$inline_hit" -ge 1 ] \
    && verdict "用 config provider 引用密碼檔:connect-configs topic 裡只有 \${file:…} 的引用,沒有密碼;直接寫進設定的密碼以明文存在 connect-configs(REST 雖然遮罩,topic 沒有)"
}

case "${1:-}" in
  rbac)     lab_rbac ;;
  identity) lab_identity ;;
  dlq)      lab_dlq ;;
  secrets)  lab_secrets ;;
  *)        usage_from_header "$0"; exit 1 ;;
esac
