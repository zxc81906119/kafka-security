#!/usr/bin/env bash
# ============================================================================
# schema-lab.sh — 第 28 章:Schema 演進與資料契約(相容性、命名策略、規則)
# ----------------------------------------------------------------------------
# 白話:producer 與 consumer 是不同團隊、不同時間上線的程式,中間靠 schema 約定欄位。schema 怎麼改才不會讓
#   還沒更新的另一端壞掉?Schema Registry 用「相容性模式」把關:改壞了就拒絕註冊(HTTP 409)。
#   這支腳本實際試:哪些改法過、哪些被擋、三種模式差在哪、transitive 為什麼重要、
#   授權(誰能註冊)和相容性(能不能這樣改)是兩道獨立的關卡、命名策略如何影響授權、資料契約規則(CEL)能不能擋壞資料。
# 前置條件:HA 模式或基礎環境,且 Schema Registry 已啟動(scripts/sr-setup.sh);帳密沿用第 20 章(gary、yujie)
# 用法:
#   scripts/schema-lab.sh evolve      演進:加有預設值的欄位過、加必填欄位 409、改型別 409、相容性檢查 API
#   scripts/schema-lab.sh modes       BACKWARD / FORWARD / FULL 對同樣三種改法的結果(3×3 對照)
#   scripts/schema-lab.sh transitive  BACKWARD 只比最新版,BACKWARD_TRANSITIVE 比所有舊版
#   scripts/schema-lab.sh gates       授權(403)與相容性(409)是兩道獨立的關卡
#   scripts/schema-lab.sh naming      TopicNameStrategy 與 RecordNameStrategy:後者讓 subject 名稱脫離 topic,按前綴授權就失效
#   scripts/schema-lab.sh contract    資料契約規則(CEL):amount 不得為負,寫入端違反就被擋
# 會改動什麼:建立並刪除 subject sch.*、topic orders.strat 與 orders.contract(contract 與 naming 會寫入資料)。
# 怎麼判斷成功:最後一行印「判定:…」。
# 常見失敗:「Schema Registry 沒有在跑」→ scripts/sr-setup.sh;403 → 該 AD 帳號沒有該 subject 的角色(見第 20 章)
# ============================================================================
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/kafka.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR" || exit 1
need_container schema-registry1 "先執行:scripts/sr-setup.sh"
need_container schema-registry2 "先執行:scripts/sr-setup.sh"

SR=https://schema-registry:8081
JSON_TYPE='Content-Type: application/vnd.schemaregistry.v1+json'
SR_HOST_DIR="$(pwd -W 2>/dev/null || pwd)"
# topic 的副本數:叢集是 4 台 broker,預設副本 3
REPLICATION=3

# ---------- 小工具(這支腳本專用) ----------

# avro_body <欄位 JSON 陣列> [規則 JSON]:組出註冊用的請求內容(Avro record demo.Order)。
avro_body() {
  node -e 'const f=JSON.parse(process.argv[1]);const o={schemaType:"AVRO",schema:JSON.stringify({type:"record",name:"Order",namespace:"demo",fields:f})};if(process.argv[2])o.ruleSet=JSON.parse(process.argv[2]);console.log(JSON.stringify(o))' "$1" "${2:-}"
}

# 常用欄位(縮寫方便閱讀)。
F_ID='{"name":"id","type":"string"}'
F_AMOUNT='{"name":"amount","type":"int"}'
F_MEMO_DEFAULT='{"name":"memo","type":"string","default":""}'
F_BRANCH_REQUIRED='{"name":"branch","type":"string"}'

# register <subject> <帳密> <欄位陣列>:註冊一個版本,只印 HTTP 狀態與錯誤摘要。
register() {
  local out code
  out=$(dcurl -u "$2" -X POST -H "$JSON_TYPE" -d "$(avro_body "$3")" "$SR/subjects/$1/versions" 2>/dev/null)
  code=$(echo "$out" | tail -1)
  case "$code" in
    "[HTTP 200]") echo "$code 版本 $(echo "$out" | grep -o '"version":[0-9]*' | head -1 | cut -d: -f2)" ;;
    *)            echo "$code $(echo "$out" | grep -o '"message":"[^"]*"' | head -1 | cut -c1-170)" ;;
  esac
}

# is_compatible <subject> <欄位陣列> [versions 範圍,預設 latest]:做相容性檢查,印 true / false。
#   範圍 latest = 只對照最新版;範圍留空字串 = 對照所有版本(TRANSITIVE 模式才有意義:對 /versions/latest 檢查時,即使模式是 TRANSITIVE 也只比最新版,實測踩過)。
is_compatible() {
  local scope="${3-/latest}"
  dcurl -u gary:gary-pw -X POST -H "$JSON_TYPE" -d "$(avro_body "$2")" "$SR/compatibility/subjects/$1/versions$scope" 2>/dev/null     | grep -o '"is_compatible":[a-z]*' | cut -d: -f2
}

# set_mode <subject> <模式>:設定某 subject 的相容性模式。
set_mode() {
  dcurl -u gary:gary-pw -X PUT -H "$JSON_TYPE" -d "{\"compatibility\":\"$2\"}" "$SR/config/$1" >/dev/null 2>&1
}

# fresh_subject <subject> [初始欄位陣列]:刪除舊的(含永久刪除)後註冊 v1。
fresh_subject() {
  dcurl -u gary:gary-pw -X DELETE "$SR/subjects/$1" >/dev/null 2>&1
  dcurl -u gary:gary-pw -X DELETE "$SR/subjects/$1?permanent=true" >/dev/null 2>&1
  dcurl -u gary:gary-pw -X DELETE "$SR/config/$1" >/dev/null 2>&1
  register "$1" gary:gary-pw "${2:-[$F_ID,$F_AMOUNT]}" >/dev/null
}

cleanup_subjects() {
  local s
  for s in "$@"; do
    dcurl -u gary:gary-pw -X DELETE "$SR/subjects/$s" >/dev/null 2>&1
    dcurl -u gary:gary-pw -X DELETE "$SR/subjects/$s?permanent=true" >/dev/null 2>&1
    dcurl -u gary:gary-pw -X DELETE "$SR/config/$s" >/dev/null 2>&1
  done
}

# avro_produce <topic> <帳密> <JSON 一行> <schema 欄位陣列> [額外 --property…]:
#   用 kafka-avro-console-producer 寫一筆(寫入端用 svc-orders 的 SCRAM,Schema Registry 用指定的 AD 帳密);印出錯誤摘要或「已寫入」。
#   帳密從標準輸入進容器,不出現在指令列。
avro_produce() {
  local topic="$1" cred="$2" record="$3" fields="$4"; shift 4
  local schema; schema=$(node -e 'console.log(JSON.stringify({type:"record",name:"Order",namespace:"demo",fields:JSON.parse(process.argv[1])}))' "$fields")
  printf '%s\n' "${cred#*:}" | docker run --rm -i --network cpsec_default \
      -v "$SR_HOST_DIR/certs:/etc/kafka/secrets:ro" -v "$SR_HOST_DIR/config/clients:/clients:ro" -v "$SR_HOST_DIR/scripts/schema-produce.sh:/run.sh:ro" \
      -e KAFKA_OPTS="" -e KAFKA_HEAP_OPTS="-Xmx256m" -e TOPIC="$topic" -e SRUSER="${cred%%:*}" -e RECORD="$record" -e SCHEMA="$schema" -e EXTRA="$*" \
      --entrypoint bash confluentinc/cp-schema-registry:8.3.2 /run.sh 2>&1
}

# 建立實驗用的 topic,並讓應用程式帳號 svc-orders 能寫(Write + Describe 的 ACL;帳號本身是第 18 章建立的)。
prepare_topic() {
  kafka_topics --create --if-not-exists --topic "$1" --partitions 1 --replication-factor "$REPLICATION" | grep -E "Created|rror|already"
  kafka_acls --add --allow-principal User:svc-orders --operation Write --operation Describe --topic "$1" | grep -E "rror" || true
}

# ---------- 各個實驗 ----------

lab_evolve() {
  say "同一個 subject 連續註冊三種改法:加有預設值的欄位 → 加必填欄位 → 改型別。預設模式 BACKWARD(新 schema 要能讀舊資料)"
  local s=sch.evolve a b c d ok_check bad_check
  fresh_subject $s
  echo "全域相容性模式:$(dcurl -u gary:gary-pw "$SR/config" 2>/dev/null | grep -o '"compatibilityLevel":"[A-Z_]*"')"
  echo "v1 = {id, amount}"
  a=$(register $s gary:gary-pw "[$F_ID,$F_AMOUNT,$F_MEMO_DEFAULT]");                     echo "v2 加欄位 memo(有預設值):$a"
  b=$(register $s gary:gary-pw "[$F_ID,$F_AMOUNT,$F_MEMO_DEFAULT,$F_BRANCH_REQUIRED]");  echo "v3 加欄位 branch(必填、沒預設值):$b"
  c=$(register $s gary:gary-pw "[$F_ID,{\"name\":\"amount\",\"type\":\"string\"},$F_MEMO_DEFAULT]"); echo "v3' 把 amount 從 int 改成 string:$c"
  ok_check=$(is_compatible $s "[$F_ID,$F_AMOUNT,$F_MEMO_DEFAULT,{\"name\":\"tag\",\"type\":\"string\",\"default\":\"\"}]")
  bad_check=$(is_compatible $s "[$F_ID,$F_AMOUNT,$F_MEMO_DEFAULT,$F_BRANCH_REQUIRED]")
  echo "相容性檢查 API(不註冊,只問行不行):加有預設值的欄位 → $ok_check;加必填欄位 → $bad_check"
  d=$(register $s gary:gary-pw "[$F_ID,$F_AMOUNT]"); echo "重新註冊和 v1 一模一樣的 schema:$d(已存在的 schema 直接回傳原版本,不會新增版本)"
  cleanup_subjects $s
  echo "$a" | grep -q "HTTP 200" && echo "$b" | grep -q "HTTP 409" && echo "$c" | grep -q "HTTP 409" && [ "$ok_check" = true ] && [ "$bad_check" = false ] \
    && verdict "BACKWARD 下:加有預設值的欄位通過,加必填欄位與改型別被擋(409,訊息指出是哪個欄位);註冊前可用相容性檢查 API 先問"
}

lab_modes() {
  say "三種改法 × 三種模式:X=加有預設值的欄位、Y=刪掉欄位 amount、Z=加必填欄位。每個模式用獨立的 subject 檢查(不實際註冊)"
  local mode s x y z all_ok=1
  declare -A want=( [BACKWARD]="true true false" [FORWARD]="true false true" [FULL]="true false false" )   # X Y Z 的預期
  for mode in BACKWARD FORWARD FULL; do
    s=sch.modes.$mode
    fresh_subject $s; set_mode $s $mode
    x=$(is_compatible $s "[$F_ID,$F_AMOUNT,$F_MEMO_DEFAULT]")
    y=$(is_compatible $s "[$F_ID]")
    z=$(is_compatible $s "[$F_ID,$F_AMOUNT,$F_BRANCH_REQUIRED]")
    printf '  %-9s X 加預設欄位:%-5s  Y 刪欄位:%-5s  Z 加必填欄位:%-5s\n' "$mode" "$x" "$y" "$z"
    [ "$x $y $z" = "${want[$mode]}" ] || all_ok=0
    cleanup_subjects $s
  done
  echo "意義:BACKWARD = 新 schema 的 consumer 讀得懂舊資料(先升級 consumer);FORWARD = 舊 schema 的 consumer 讀得懂新資料(先升級 producer);FULL = 兩者都要"
  [ "$all_ok" = 1 ] && verdict "三種模式對同樣的改法結果不同:BACKWARD 擋『加必填欄位』外都過、FORWARD 擋『刪欄位』、FULL 兩者都擋——先升級哪一端,決定該用哪個模式"
}

lab_transitive() {
  say "v1={id},v2 加有預設值的 a,候選 v3 把 a 改成必填。BACKWARD 只對照最新版(v2,有 a),TRANSITIVE 對照全部舊版(含沒有 a 的 v1)"
  local s=sch.trans b t
  local F_A_DEFAULT='{"name":"a","type":"string","default":""}' F_A_REQUIRED='{"name":"a","type":"string"}'
  fresh_subject $s "[$F_ID]"
  register $s gary:gary-pw "[$F_ID,$F_A_DEFAULT]" >/dev/null
  set_mode $s BACKWARD;            b=$(is_compatible $s "[$F_ID,$F_A_REQUIRED]")
  set_mode $s BACKWARD_TRANSITIVE; t=$(is_compatible $s "[$F_ID,$F_A_REQUIRED]" "")
  echo "候選 v3(a 必填):BACKWARD → $b;BACKWARD_TRANSITIVE → $t"
  echo "為什麼要緊:topic 裡還留著 v1 寫的舊資料,新 consumer 從頭重讀(重播、新服務上線)時會遇到沒有 a 的資料而失敗"
  cleanup_subjects $s
  [ "$b" = true ] && [ "$t" = false ] \
    && verdict "BACKWARD 只比最新版,漏掉更早的版本;BACKWARD_TRANSITIVE 比全部舊版才擋得住。topic 會被重播的場合應該用 TRANSITIVE"
}

lab_gates() {
  say "yujie(orders-write)註冊:對 orders. 開頭的 subject 改壞 schema → 409(相容性擋);對 payments. 的 subject → 403(授權擋)。兩道關卡獨立"
  local s=orders.sch.gates p=payments.sch.gates a b c
  fresh_subject $s
  a=$(register $s yujie:yujie-pw "[$F_ID,{\"name\":\"amount\",\"type\":\"string\"}]"); echo "yujie 在 $s 改型別(有權限、但不相容):$a"
  b=$(register $s yujie:yujie-pw "[$F_ID,$F_AMOUNT,$F_MEMO_DEFAULT]");                 echo "yujie 在 $s 加有預設值的欄位(有權限、相容):$b"
  c=$(register $p yujie:yujie-pw "[$F_ID,$F_AMOUNT]");                                echo "yujie 在 $p 註冊(沒有權限):$c"
  cleanup_subjects $s $p
  echo "$a" | grep -q "HTTP 409" && echo "$b" | grep -q "HTTP 200" && echo "$c" | grep -q "HTTP 403" \
    && verdict "授權與相容性是兩道獨立的關卡:有權限也不能改壞(409),相容也不能越權(403);除錯時先看錯誤碼是哪一道"
}

lab_naming() {
  say "命名策略決定 producer 把 schema 註冊在哪個 subject。預設 TopicNameStrategy = <topic>-value(按 topic 前綴授權有效);RecordNameStrategy = 記錄的全名 demo.Order(和 topic 無關)"
  local a b
  prepare_topic orders.strat
  cleanup_subjects orders.strat-value demo.Order
  echo "yujie 的 producer(TopicNameStrategy,預設):"
  a=$(avro_produce orders.strat yujie:yujie-pw '{"id":"n1","amount":1}' "[$F_ID,$F_AMOUNT]" "--property auto.register.schemas=true")
  echo "$a" | grep -E "Exception|error_code|denied|Error" | head -2 | cut -c1-170 | sed 's/^/   /'; echo "   → 完成($(echo "$a" | grep -c "Exception\|error_code") 個錯誤);subject 列表:$(dcurl -u gary:gary-pw "$SR/subjects" 2>/dev/null | head -1 | grep -o '"orders.strat-value"\|"demo.Order"' | tr '\n' ' ')"
  echo "yujie 的 producer(RecordNameStrategy):"
  b=$(avro_produce orders.strat yujie:yujie-pw '{"id":"n2","amount":2}' "[$F_ID,$F_AMOUNT]" "--property auto.register.schemas=true --property value.subject.name.strategy=io.confluent.kafka.serializers.subject.RecordNameStrategy")
  echo "$b" | grep -E "Exception|error_code|denied|Error" | head -2 | cut -c1-170 | sed 's/^/   /'
  cleanup_subjects orders.strat-value demo.Order
  [ "$(echo "$a" | grep -c 'Exception\|error_code')" = 0 ] && echo "$b" | grep -q -i "denied\|403\|Forbidden" \
    && verdict "TopicNameStrategy 的 subject 跟著 topic 名稱,按 orders. 前綴授權有效;RecordNameStrategy 的 subject 是 demo.Order,前綴授權不涵蓋,yujie 被拒(403)——選了 RecordNameStrategy 就要改用依 subject 名稱的授權設計"
}

lab_contract() {
  say "在 schema 上掛資料契約規則(CEL):amount 不得為負。註冊成功與否看授權;寫入端違反規則時序列化器直接拒絕,壞資料進不了 topic"
  local reg good bad
  prepare_topic orders.contract
  cleanup_subjects orders.contract-value
  local rules='{"domainRules":[{"name":"amountNonNegative","kind":"CONDITION","type":"CEL","mode":"WRITE","expr":"message.amount >= 0","onFailure":"ERROR"}]}'
  reg=$(dcurl -u gary:gary-pw -X POST -H "$JSON_TYPE" -d "$(avro_body "[$F_ID,$F_AMOUNT]" "$rules")" "$SR/subjects/orders.contract-value/versions" 2>/dev/null | tail -1)
  echo "註冊帶規則的 schema(CEL 條件規則):$reg"
  good=$(avro_produce orders.contract yujie:yujie-pw '{"id":"c1","amount":100}' "[$F_ID,$F_AMOUNT]" "--property auto.register.schemas=false --property use.latest.version=true")
  echo "寫入 amount=100:$(echo "$good" | grep -c -i 'exception') 個錯誤"
  bad=$(avro_produce orders.contract yujie:yujie-pw '{"id":"c2","amount":-5}' "[$F_ID,$F_AMOUNT]" "--property auto.register.schemas=false --property use.latest.version=true")
  echo "寫入 amount=-5:"; echo "$bad" | grep -i -E "rule|exception" | head -3 | cut -c1-200 | sed 's/^/   /'
  cleanup_subjects orders.contract-value
  [ "$reg" = "[HTTP 200]" ] && [ "$(echo "$good" | grep -c -i 'exception')" = 0 ] && echo "$bad" | grep -q -i "amountNonNegative\|Rule failed\|RuleException" \
    && verdict "資料契約規則生效:amount=100 寫入成功,amount=-5 在寫入端就被擋(規則名 amountNonNegative);壞資料不進 topic"
}

case "${1:-}" in
  evolve)     lab_evolve ;;
  modes)      lab_modes ;;
  transitive) lab_transitive ;;
  gates)      lab_gates ;;
  naming)     lab_naming ;;
  contract)   lab_contract ;;
  *)          usage_from_header "$0"; exit 1 ;;
esac
