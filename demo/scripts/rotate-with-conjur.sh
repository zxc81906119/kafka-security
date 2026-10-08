#!/usr/bin/env bash
# 服務帳號的「新舊並行」輪替,帳密由 CyberArk(Conjur)交付:零中斷、失敗可回滾。正式環境由 CPM 自訂平台或排程呼叫同樣的步驟。
# 用法:
#   scripts/rotate-with-conjur.sh start <舊帳號> <新帳號>      建新帳號 → 複製角色(逐筆檢查)→ 驗證新帳號真的連得上且看得到同樣的 topic → 才把新帳密寫進 Conjur;任何一步失敗就回滾新帳號、Conjur 不動
#   scripts/rotate-with-conjur.sh quarantine <舊帳號>          隔離舊帳號:先解除全部角色(可逆),SCRAM 憑證還留著;若還有人在用,audit 會出現被拒(DENIED)
#   scripts/rotate-with-conjur.sh check <舊帳號> [分鐘]        看舊帳號的 audit:允許幾筆、被拒幾筆(隔離過就只看隔離之後;否則看最近 N 分鐘);被拒 = 還有人在用,先 rollback
#   scripts/rotate-with-conjur.sh rollback <舊帳號>            有人還在用:把角色綁回去
#   scripts/rotate-with-conjur.sh finish <舊帳號>              確認沒人用後停用:刪除 SCRAM 憑證(要先 quarantine)
#   scripts/rotate-with-conjur.sh restore                      demo 還原:svc-orders(原密碼與原角色)回來、Conjur 指回它、移除 svc-orders-v2
# Conjur 的變數:kafka/<host>/credential(JSON {"u":帳號,"p":密碼};一個變數放整組,寫入與讀取都是單一操作)
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
CID=XyZBQ3-GTvKH2qNfP7X33A
HOST=svc-orders                               # Conjur 的機器身分(應用的身分不變,帳號才換)
Q=config/conjur                               # 隔離時保存舊角色的地方(忽略檔)
D="$(pwd -W 2>/dev/null || pwd)"
K() { ./scripts/k.sh "$@"; }
CFG=/clients/token-bootstrap.properties       # demo 用 bootstrap;正式環境用 cluster-admin + rbac-admin 的身分
mds_boot() { ./scripts/dcurl.sh --cert /certs/client-bootstrap.pem --key /certs/client-bootstrap.key -H "Content-Type: application/json" -H "Accept: application/json" "$@"; }
roles_of() { mds_boot -X POST "https://broker1:8091/security/1.0/lookup/principal/User:$1/resources" -d "{\"clusters\":{\"kafka-cluster\":\"$CID\"}}" | head -1; }
# 角色清單(每行:角色 資源範圍JSON),排序後可直接比較
role_lines() { roles_of "$1" | node -e '
  let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{ let j={}; try{j=JSON.parse(s||"{}")}catch(e){} const r=j["User:"+process.argv[1]]||{};
    console.log(Object.entries(r).map(([role,res])=>role+" "+JSON.stringify(res)).sort().join("\n")); })' "$1"; }
bind_lines() { # bind_lines <user>(stdin:role_lines 格式);任何一筆不是 2xx 就回傳失敗
  local rc=0 role res code
  while read -r role res; do
    [ -n "$role" ] || continue
    code=$(mds_boot -o /dev/null -X POST "https://broker1:8091/security/1.0/principals/User:$1/roles/$role/bindings" -d "{\"scope\":{\"clusters\":{\"kafka-cluster\":\"$CID\"}},\"resourcePatterns\":$res}" | tail -1)
    echo "  綁定 $role → User:$1 $code"
    case "$code" in *"HTTP 20"*) ;; *) rc=1 ;; esac
  done
  return $rc
}
unbind_all() { # unbind_all <user>
  local role res code
  role_lines "$1" | while read -r role res; do
    [ -n "$role" ] || continue
    code=$(mds_boot -o /dev/null -X DELETE "https://broker1:8091/security/1.0/principals/User:$1/roles/$role/bindings" -d "{\"scope\":{\"clusters\":{\"kafka-cluster\":\"$CID\"}},\"resourcePatterns\":$res}" | tail -1)
    echo "  解除 $role $code"
  done
}
scram_set() { K kafka-configs --bootstrap-server broker1:9094 --command-config $CFG --alter --add-config "SCRAM-SHA-512=[password=$2]" --entity-type users --entity-name "$1" 2>&1 | grep -E "Completed|Error" | sed 's/^/  /'; }
scram_del() { K kafka-configs --bootstrap-server broker1:9094 --command-config $CFG --alter --delete-config SCRAM-SHA-512 --entity-type users --entity-name "$1" 2>&1 | grep -E "Completed|Error" | sed 's/^/  /'; }
# 用某個 SCRAM 帳密列出可見的 topic(帳密由 stdin 進容器,不放環境變數);認證失敗時印 AUTH-FAILED
list_as() { # list_as <帳號> <密碼>
  printf 'security.protocol=SASL_SSL\nsasl.mechanism=SCRAM-SHA-512\nsasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="%s" password="%s";\nssl.truststore.location=/etc/kafka/secrets/truststore.p12\nssl.truststore.type=PKCS12\nssl.truststore.password=changeit\n' "$1" "$2" \
  | docker run --rm -i --network cpsec_default -v "$D/certs:/etc/kafka/secrets:ro" -e KAFKA_OPTS="" -e KAFKA_HEAP_OPTS="-Xmx256m" --entrypoint bash confluentinc/cp-server:8.3.2 -c \
    'cat > /dev/shm/c; kafka-topics --bootstrap-server broker1:9094 --command-config /dev/shm/c --list 2>&1' \
  | { out=$(cat); if echo "$out" | grep -qi "Authentication failed"; then echo AUTH-FAILED; else echo "$out" | grep -vE "^(WARNING|SLF4J)|^\[20|^$|deprecated" | sort; fi; }
}
cred_field() { node -e 'try{console.log(JSON.parse(process.argv[1])[process.argv[2]])}catch(e){}' "$1" "$2"; }

case "${1:-}" in
start)
  old="$2"; new="$3"
  pw=$(openssl rand -hex 12 2>/dev/null || echo "pw-$RANDOM$RANDOM$RANDOM")
  fail() { echo "✘ $1"; echo "  回滾:移除 $new(Conjur 沒有被動過,舊帳號照常)"; unbind_all "$new" >/dev/null 2>&1 || true; scram_del "$new" >/dev/null 2>&1 || true; exit 1; }
  want=$(role_lines "$old"); [ -n "$want" ] || { echo "✘ 舊帳號 $old 沒有任何角色,不知道要複製什麼,中止(沒有改任何東西)"; exit 1; }
  echo "① 建立新帳號 $new(密碼隨機,只存進 Conjur)"; scram_set "$new" "$pw" | grep -q Completed || fail "建立 SCRAM 失敗"
  echo "② 複製 $old 的角色給 $new(逐筆檢查)"; printf '%s\n' "$want" | bind_lines "$new" || fail "角色複製有失敗的"
  [ "$(role_lines "$new")" = "$want" ] || fail "複製後的角色與舊帳號不一致"
  echo "③ 驗證新帳號:真的連得上,而且看得到和舊帳號同樣的 topic"
  oldcred=$(bash scripts/conjur.sh get-as "$HOST" "$HOST/credential" 2>/dev/null || true)
  newtopics=$(list_as "$new" "$pw")
  [ "$newtopics" != AUTH-FAILED ] && [ -n "$newtopics" ] || fail "新帳號連不上或看不到任何 topic"
  if [ -n "$oldcred" ] && [ "$(cred_field "$oldcred" u)" = "$old" ]; then
    oldtopics=$(list_as "$old" "$(cred_field "$oldcred" p)")
    [ "$oldtopics" = "$newtopics" ] || fail "新舊帳號看到的 topic 不同(舊:$(echo "$oldtopics" | wc -l) 個,新:$(echo "$newtopics" | wc -l) 個)"
    echo "  新舊帳號看到同樣的 $(echo "$newtopics" | wc -l) 個 topic"
  else echo "  (Conjur 目前不是 $old 的帳密,略過與舊帳號比較;新帳號可連線、看到 $(echo "$newtopics" | wc -l) 個 topic)"; fi
  echo "④ 驗證通過,新帳密才一次寫進 Conjur(kafka/$HOST/credential,單一變數、原子)"
  bash scripts/conjur.sh set-cred "$HOST" "$new" "$pw" >/dev/null || fail "寫入 Conjur 失敗"
  unset pw
  echo "結果:$new 已建立並綁定相同角色;Conjur 已指向 $new;$old 仍可用(新舊並行中)"
  ;;
quarantine)
  old="$2"; mkdir -p "$Q"
  role_lines "$old" > "$Q/quarantine-$old.txt"; date -u +%H:%M:%S > "$Q/quarantine-$old.since"   # 隔離時刻:check 只看這之後的事件
  [ -s "$Q/quarantine-$old.txt" ] || { echo "✘ $old 沒有角色可隔離"; exit 1; }
  echo "⑤ 隔離 $old:先解除全部角色(已保存到 $Q/quarantine-$old.txt,可 rollback),SCRAM 憑證還留著"; unbind_all "$old"
  [ -z "$(role_lines "$old")" ] || { echo "✘ 角色沒有解除乾淨"; exit 1; }
  echo "結果:$old 已隔離(角色已解除、憑證仍在);還在用它的人會被拒,audit 會看到 DENIED"
  ;;
check)
  old="$2"; mins="${3:-5}"
  if [ -s "$Q/quarantine-$old.since" ]; then since=$(cat "$Q/quarantine-$old.since"); label="隔離( UTC)之後"; else since=$(date -u -d "-$mins minutes" +%H:%M:%S); label="最近 $mins 分鐘"; fi
  rows=$(K kafka-console-consumer --bootstrap-server broker1:9094 --command-config $CFG --topic confluent-audit-log-events --from-beginning --timeout-ms 12000 2>/dev/null \
      | node scripts/audit-fmt.mjs --last 600 | awk -v p="User:$old" -v since="$since" '$2==p && $1>=since')
  a=$(printf '%s\n' "$rows" | grep -c ALLOWED || true); d=$(printf '%s\n' "$rows" | grep -c DENIED || true)
  echo "舊帳號 $old $label的 audit:允許 $a 筆、被拒 $d 筆"
  if [ "$a" -eq 0 ] && [ "$d" -eq 0 ]; then echo "判定:沒有人在用 → 可以 finish(注意:audit 不記錄 orders.* 讀取成功,所以要先 quarantine 讓還在用的人變成被拒,才看得到)"
  else echo "判定:還有人在用 $old(被拒表示有人在隔離後還在嘗試)→ 先 rollback,找出是誰"; fi
  ;;
rollback)
  old="$2"; [ -s "$Q/quarantine-$old.txt" ] || { echo "✘ 沒有 $old 的隔離紀錄"; exit 1; }
  echo "回復 $old 的角色"; bind_lines "$old" < "$Q/quarantine-$old.txt" && echo "結果:$old 的角色已回復" || { echo "✘ 有角色沒綁回去"; exit 1; }
  ;;
finish)
  old="$2"; [ -s "$Q/quarantine-$old.txt" ] || { echo "✘ $old 還沒隔離(先 quarantine 並確認 check 沒有被拒),不直接停用"; exit 1; }
  echo "⑥ 停用 $old:刪除 SCRAM 憑證"; scram_del "$old"; rm -f "$Q/quarantine-$old.txt" "$Q/quarantine-$old.since"
  echo "結果:舊帳號 $old 已停用"
  ;;
restore)
  echo "demo 還原:svc-orders(原密碼與原角色)回來,Conjur 指回它,移除 svc-orders-v2"
  scram_set svc-orders orders-secret-v1
  printf 'DeveloperWrite [{"resourceType":"Topic","name":"orders.","patternType":"PREFIXED"}]\n' | bind_lines svc-orders >/dev/null || true
  bash scripts/conjur.sh set-cred "$HOST" svc-orders orders-secret-v1 >/dev/null
  unbind_all svc-orders-v2 >/dev/null 2>&1 || true; scram_del svc-orders-v2 >/dev/null 2>&1 || true
  rm -f "$Q"/quarantine-svc-orders*
  echo "結果:svc-orders 已還原;svc-orders-v2 已移除"
  ;;
*) sed -n 2,11p "$0"; exit 1 ;;
esac
