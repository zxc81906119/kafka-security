#!/usr/bin/env bash
# ============================================================================
# cert-lab.sh — 第 23 章:憑證到期監控,以及「不重啟 broker」換憑證
# ----------------------------------------------------------------------------
# 白話:憑證過期是銀行最常見的停機原因之一。這支腳本做兩件事:
#   (1) 監控:用 blackbox 探測各端點「實際送出」的憑證,算出剩幾天,快到期就告警;
#   (2) 換憑證:用 Kafka 的動態設定,一台一台換 broker 的對外憑證,不用重啟、寫入不中斷;
#       並故意做錯(SAN 不對、換成別的 CA 簽的)看 broker 怎麼反應,以及怎麼安全回退。
# 前置條件:叢集已啟動(scripts/up.sh),且 prometheus、alertmanager、blackbox-exporter 已啟動
#   (docker compose --profile c3 up -d prometheus alertmanager blackbox-exporter)
# 用法:
#   scripts/cert-lab.sh baseline      現況:各端點「實際送出」的憑證 vs 檔案;OP menu 第 17 項(檔案巡檢,含剩餘時間分級)
#   scripts/cert-lab.sh monitor       blackbox 探測(對外 TLS 與內部 mTLS 各 6 個端點):剩餘天數,基準沒有憑證告警
#   scripts/cert-lab.sh expiring      把 CLIENT 埠換成「20 天效期」的憑證(模擬快到期)→ 到期告警觸發;MDS 不在動態重載範圍,仍是舊憑證
#   scripts/cert-lab.sh rotate        背景持續寫入時,不重啟換成 825 天的新憑證 → 序號變了、broker 沒重啟、寫入零失敗、告警解除
#   scripts/cert-lab.sh reject-san    新憑證的 SAN 與現有不同 → broker 拒絕這次動態更新
#   scripts/cert-lab.sh reject-ca     換成另一個 CA 簽的憑證:broker 接受,但 client 驗證失敗 → 立刻回退
#   scripts/cert-lab.sh persist       重啟 broker1 後仍是動態設定的憑證(動態設定存在叢集 metadata);靜態設定也要同步更新
#   scripts/cert-lab.sh cleanup       移除動態設定,回到靜態檔的憑證
# 會改動什麼:在 certs/ 底下產生測試用的新憑證與 keystore(srv-*.、rogue-*,不進版本庫);
#   對 broker 設定動態 keystore(cleanup 會移除);rotate 建立並刪除 topic cert.roll;persist 會重啟 broker1。
# 怎麼判斷成功:最後一行印「判定:…」。
# 常見失敗:
#   動態更新被拒、訊息提到 SAN → 新憑證的 SAN 必須和現有的相同(KIP-226)
#   換完憑證後 client 連不上 → 立刻用 cleanup(走帶外的 INTERNAL mTLS 埠回退,不依賴剛弄壞的 CLIENT 埠)
# 作法與取捨見手冊 Lab 23:動態 keystore 重載(listener.name.<listener>.ssl.keystore.*)優於滾動重啟,但只涵蓋 Kafka 的 listener。
# ============================================================================
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/prom.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/kafka.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR" || exit 1
need_ha_mode

OPENSSL_IMAGE=alpine/openssl:latest
DOCKER_NET=cpsec_default
HOST_DIR="$(pwd -W 2>/dev/null || pwd)"          # 給 docker -v 用的主機路徑(Windows 要 C:/… 格式)
BROKER_IDS="${CERT_BROKER_IDS:-11 12 13 14}"     # broker 的 node id(broker1~4 = 11~14)
CERT_ALERTS='^Kafka(Tls|Mtls)'                   # 憑證相關的告警名稱

# ---------- 憑證小工具(在容器裡用 openssl,不必在本機裝) ----------

# ossl "<shell 指令>":在 certs/ 目錄裡執行指令(用 openssl 映像)。
ossl() { docker run --rm -v "$HOST_DIR/certs:/certs" --entrypoint sh "$OPENSSL_IMAGE" -c "cd /certs; $1"; }

# served <host:port>:印「序號 到期日」——從 TLS 握手實際收到的憑證(不是磁碟上的檔案)。
served() {
  local host="${1%%:*}"
  docker run --rm --network "$DOCKER_NET" --entrypoint sh "$OPENSSL_IMAGE" -c \
    "openssl s_client -connect $1 -servername $host </dev/null 2>/dev/null | openssl x509 -noout -serial -enddate 2>/dev/null | tr '\n' ' ' | sed 's/serial=//; s/notAfter=/到期 /'"
}
serial_of() { served "$1" | awk '{print $1}'; }

# file_info <檔名>:印 certs/ 底下憑證檔的「序號 到期日」。
file_info() { ossl "openssl x509 -in $1 -noout -serial -enddate" | tr '\n' ' ' | sed 's/serial=//; s/notAfter=/到期 /'; }

# mkcert <名稱> <效期天數> [san 設定檔,預設 san.cnf]:用行內 CA 簽一張同 DN、同 SAN 的新憑證,
#   產生 certs/<名稱>.keystore.p12(密碼 changeit,測試值)。
mkcert() {
  local name="$1" days="$2" cnf="${3:-san.cnf}"
  ossl "openssl genrsa -out $name.key 2048 2>/dev/null; \
        openssl req -new -key $name.key -out $name.csr -config $cnf; \
        openssl x509 -req -in $name.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out $name.pem -days $days -sha256 -extfile $cnf -extensions v3 2>/dev/null; \
        openssl pkcs12 -export -in $name.pem -inkey $name.key -certfile ca.pem -name server -out $name.keystore.p12 -passout pass:changeit; \
        chmod 644 $name.*" >/dev/null 2>&1
  [ -f "certs/$name.keystore.p12" ] && echo "   新憑證 $name:$(file_info "$name.pem")"
}

# precheck <名稱>:套用前先離線驗證——鏈是否由行內 CA 簽發且未過期、SAN 是否與現有相同。通過回傳 0。
precheck() {
  local name="$1" chain san_new san_cur
  chain=$(ossl "openssl verify -CAfile ca.pem $name.pem 2>&1" | tail -1)
  san_new=$(ossl "openssl x509 -in $name.pem -noout -ext subjectAltName 2>/dev/null | tail -n +2" | tr -d ' \r\n')
  san_cur=$(ossl "openssl x509 -in server.pem -noout -ext subjectAltName 2>/dev/null | tail -n +2" | tr -d ' \r\n')
  echo "   預檢 $name:鏈驗證 → $chain;SAN $([ "$san_new" = "$san_cur" ] && echo 與現有相同 || echo 與現有不同)"
  echo "$chain" | grep -q ": OK" && [ "$san_new" = "$san_cur" ]
}

# verify_served <host:port>:用行內 CA 驗證該端點實際送出的憑證鏈(站在 client 的角度)。
verify_served() {
  docker run --rm --network "$DOCKER_NET" -v "$HOST_DIR/certs/ca.pem:/ca.pem:ro" --entrypoint sh "$OPENSSL_IMAGE" -c \
    "openssl s_client -connect $1 -servername ${1%%:*} -CAfile /ca.pem -verify_return_error </dev/null 2>&1 | grep -E 'Verify return code|verify error' | head -1"
}

# brokers_serial:每台 broker CLIENT 埠(9094)目前送出的憑證序號。
brokers_serial() { local b; for b in broker1 broker2 broker3 broker4; do echo -n "$(serial_of "$b:9094") "; done; echo; }

# ---------- 動態換憑證 ----------

# apply <名稱> [broker id…]:對 CLIENT listener 動態換 keystore(不重啟)。
#   Kafka 規定 keystore 設定只能設在單一 broker(不能設叢集預設),所以一台一台換:先換一台驗證(金絲雀),再換其他台。
apply() {
  local name="$1" ids id; shift; ids="${*:-$BROKER_IDS}"
  for id in $ids; do
    kafka_configs --entity-type brokers --entity-name "$id" --alter --add-config \
      "listener.name.client.ssl.keystore.location=/etc/kafka/secrets/$name.keystore.p12,listener.name.client.ssl.keystore.type=PKCS12,listener.name.client.ssl.keystore.password=changeit,listener.name.client.ssl.key.password=changeit"
  done
}

# revert:移除動態設定,回到靜態檔的憑證。一律走帶外路徑(INTERNAL mTLS 埠),
#   因為 CLIENT 埠的憑證正是可能被換壞的那一個——回退不能依賴剛弄壞的連線。
revert() {
  local id
  for id in $BROKER_IDS; do
    kafka_configs_oob --entity-type brokers --entity-name "$id" --alter --delete-config \
      "listener.name.client.ssl.keystore.location,listener.name.client.ssl.keystore.type,listener.name.client.ssl.keystore.password,listener.name.client.ssl.key.password" \
      | grep -E "Completed|rror" | head -1
  done
}

# ---------- 告警與剩餘天數(查 Prometheus) ----------

cert_firing() { alerts_firing "$CERT_ALERTS"; }

# wait_cert_alert <告警名> <instance> <present|absent> <最多秒數>:等某個憑證告警出現(present)或消失(absent)。
wait_cert_alert() {
  local name="$1" instance="$2" want="$3" max="$4" t0 firing
  t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt "$max" ]; do
    firing=$(cert_firing)
    case ",$firing," in
      *",$name@$instance,"*) [ "$want" = present ] && { note "$(( $(date +%s) - t0 )) 秒後 $name@$instance 觸發"; return 0; } ;;
      *)                     [ "$want" = absent ]  && { note "$(( $(date +%s) - t0 )) 秒後 $name@$instance 解除"; return 0; } ;;
    esac
    sleep 10
  done
  note "等了 $max 秒:$name@$instance 仍未$([ "$want" = present ] && echo 觸發 || echo 解除)(目前:$(cert_firing))"
  return 1
}

# days_left <instance>:從 Prometheus 讀該端點憑證的剩餘天數(小數 1 位)。
days_left() {
  local v; v=$(prom_query "(probe_ssl_earliest_cert_expiry{instance=\"$1\"} - time()) / 86400")
  case "$v" in 無|"?") echo "?";; *) printf '%.1f' "$v";; esac
}

# ---------- 各個實驗 ----------

lab_baseline() {
  say "看各端點『實際送出』的憑證序號,和磁碟上 certs/server.pem 比對——監控要看實際送出的,不是只看檔案"
  local e a b f
  echo "各端點「實際送出」的憑證(TLS 握手收到的):"
  for e in broker1:9094 broker2:9094 broker3:9094 broker4:9094 broker1:8091; do echo "  $e → $(served $e)"; done
  echo "磁碟上的檔案 certs/server.pem:$(file_info server.pem)"
  echo "OP menu 第 17 項(檔案巡檢)的前幾列:"
  ( cd opmenu && OPMENU_USER=gary OPMENU_PASS=gary-pw OPMENU_YES=1 ./opmenu.sh --run 17 2>&1 | grep -E "\.pem" | head -4 | sed 's/^/  /' )
  a=$(serial_of broker1:9094); b=$(serial_of broker1:8091); f=$(file_info server.pem | awk '{print $1}')
  [ -n "$a" ] && [ "$a" = "$b" ] && [ "$a" = "$f" ] \
    && verdict "現況各端點送出的憑證與磁碟檔案是同一張(序號相同),OP menu 的檔案巡檢能看到剩餘時間分級"
}

lab_monitor() {
  say "等 blackbox 探測到 22 個 TLS 端點(最多 180 秒),列出每個端點憑證的剩餘天數,確認目前沒有憑證告警"
  local t0 ok=0 n e
  t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 180 ]; do
    n=$(prom_query 'count(probe_success{job=~"tls-expiry.*"} == 1) or vector(0)')
    [ "$n" = 22 ] && { ok=1; break; }
    sleep 10
  done
  for e in broker1:9094 broker2:9094 broker3:9094 broker4:9094 broker1:8091 broker2:8092 broker3:8093 broker4:8094 \
           restproxy1:8086 restproxy2:8086 schema-registry1:8081 schema-registry2:8081 connect1:8083 connect2:8083 control-center:9022; do
    echo "  $e → 剩 $(days_left $e) 天"; done
  for e in broker1:9092 broker2:9092 broker3:9092 broker4:9092 controller1:9093 controller2:9093 controller3:9093; do echo "  $e(內部 mTLS)→ 剩 $(days_left $e) 天"; done
  echo "目前 firing 的憑證告警:$(cert_firing)"
  [ "$ok" = 1 ] && [ "$(cert_firing)" = "-" ] \
    && verdict "22 個 TLS 端點(15 個對外、7 個內部 mTLS)的探測都成功並有剩餘天數,基準狀態沒有憑證告警"
}

lab_expiring() {
  say "簽一張只有 20 天效期的憑證(模擬快到期),動態換到 CLIENT 埠,看到期告警會不會響"
  local f1=0 mds_alarmed=0
  echo "簽一張只有 20 天效期的 server 憑證(同 DN、同 SAN),動態換到 CLIENT 埠:"; mkcert srv-short 20
  precheck srv-short || { echo "預檢未過,不套用"; exit 1; }
  apply srv-short | grep -E "Completed|rror"; sleep 8
  echo "4 台 broker CLIENT 埠送出的序號:$(brokers_serial)"
  echo "MDS(8091)送出的序號(不在動態重載範圍):$(serial_of broker1:8091)"
  wait_cert_alert KafkaTlsCertExpiringSoon broker1:9094 present 240 && f1=1
  echo "到期告警目前:$(cert_firing)"
  echo "MDS 8091 的剩餘天數:$(days_left broker1:8091)(舊憑證,不告警)"
  case ",$(cert_firing)," in *",KafkaTlsCertExpiringSoon@broker1:8091,"*) mds_alarmed=1;; esac
  [ "$f1" = 1 ] && [ "$mds_alarmed" = 0 ] \
    && verdict "CLIENT 埠換成 20 天效期的憑證後,到期告警觸發;MDS 仍是舊憑證(動態重載只涵蓋 Kafka 的 listener),沒有告警"
}

lab_rotate() {
  say "背景持續寫入 300 筆,同時不重啟換成 825 天的新憑證:先換一台當金絲雀驗證,再換其餘 3 台"
  local before after sent have pp f2=0 new old
  echo "簽新憑證(825 天、同 DN 與 SAN):"; mkcert srv-new 825
  before=$(docker inspect -f '{{.State.StartedAt}}' broker1 broker2 broker3 broker4 | tr '\n' ' ')
  kafka_topics --delete --if-exists --topic cert.roll >/dev/null 2>&1; sleep 3
  kafka_topics --create --topic cert.roll --partitions 3 --replication-factor 3 --config min.insync.replicas=2 | grep -E "Created|rror"
  "$DEMO_DIR/scripts/k.sh" kafka-producer-perf-test --topic cert.roll --num-records 300 --throughput 5 --record-size 100 \
      --command-config "$KAFKA_ADMIN_CONFIG" \
      --producer-props bootstrap.servers="$KAFKA_BOOTSTRAP" acks=all enable.idempotence=true > /tmp/cert-roll.out 2>&1 &
  pp=$!; sleep 15
  precheck srv-new || { echo "預檢未過,不套用"; exit 1; }
  echo "寫入進行中,動態換成新憑證(不重啟)。先換一台當金絲雀(broker1 = id 11),用 client 的角度驗證通過,再換其他台:"
  apply srv-new 11 | grep -E "Completed|rror"; sleep 6
  echo "   金絲雀 broker1 實際送出的鏈驗證:$(verify_served broker1:9094)"
  case "$(verify_served broker1:9094)" in
    *"(ok)"*) apply srv-new 12 13 14 | grep -E "Completed|rror" ;;
    *)        echo "   金絲雀驗證失敗,停止並回退"; revert; exit 1 ;;
  esac
  sleep 8
  echo "4 台 broker CLIENT 埠送出的序號:$(brokers_serial)"
  wait "$pp"
  sent=$(grep -aoE '^[0-9]+ records sent' /tmp/cert-roll.out | tail -1 | awk '{print $1}')
  have=$(topic_message_count cert.roll)
  after=$(docker inspect -f '{{.State.StartedAt}}' broker1 broker2 broker3 broker4 | tr '\n' ' ')
  echo "producer 送出 ${sent:-?} 筆;topic 實際 $have 筆;broker 啟動時間 $([ "$before" = "$after" ] && echo "沒有變(沒重啟)" || echo "變了(有重啟)")"
  wait_cert_alert KafkaTlsCertExpiringSoon broker1:9094 absent 240 && f2=1
  new=$(serial_of broker1:9094); old=$(file_info server.pem | awk '{print $1}')
  kafka_topics --delete --if-exists --topic cert.roll >/dev/null 2>&1
  [ "${sent:-}" = 300 ] && [ "$have" = 300 ] && [ "$before" = "$after" ] && [ "$new" != "$old" ] && [ "$f2" = 1 ] \
    && verdict "不重啟換成新憑證:序號已變、broker 沒有重啟、寫入期間零失敗(300 = 300)、到期告警解除"
}

lab_reject_san() {
  say "簽一張 SAN 不同的憑證(多了 evil.example.com、少了所有 broker 名稱),broker 應該拒絕這次動態更新"
  local before after out
  cat > certs/srv-san.cnf <<'EOF'
[req]
distinguished_name=dn
req_extensions=v3
prompt=no
[dn]
CN=kafka.demo.local
O=Demo
[v3]
subjectAltName=DNS:kafka.demo.local,DNS:evil.example.com
extendedKeyUsage=serverAuth,clientAuth
EOF
  before=$(brokers_serial)
  echo "簽一張 SAN 不同的憑證(多了 evil.example.com、少了所有 broker 名稱):"; mkcert srv-san 825 srv-san.cnf
  out=$(apply srv-san); echo "$out" | grep -E "rror|Invalid|Validation|SAN|Subject" | head -3 | cut -c1-200 | sed 's/^/   /'
  after=$(brokers_serial)
  echo "換之前的序號:$before;之後:$after"
  echo "$out" | grep -q -i -E "rror|invalid|validation" && [ "$before" = "$after" ] \
    && verdict "SAN 與現有不同的憑證被 broker 拒絕,動態更新沒有生效(防止被塞進不同身分的憑證)"
}

lab_reject_ca() {
  say "建一個『別的 CA』簽一張同 DN、同 SAN 的憑證——broker 不會擋,但 client 會全部驗證失敗;練習怎麼限制影響面並回退"
  local v r
  echo "建一個「別的 CA」,用它簽一張同 DN、同 SAN 的憑證:"
  ossl "openssl genrsa -out rogue-ca.key 2048 2>/dev/null; \
        openssl req -x509 -new -key rogue-ca.key -sha256 -days 30 -subj '/CN=rogue-ca/O=Evil' -out rogue-ca.pem; \
        openssl genrsa -out srv-rogue.key 2048 2>/dev/null; \
        openssl req -new -key srv-rogue.key -out srv-rogue.csr -config san.cnf; \
        openssl x509 -req -in srv-rogue.csr -CA rogue-ca.pem -CAkey rogue-ca.key -CAcreateserial -out srv-rogue.pem -days 30 -sha256 -extfile san.cnf -extensions v3 2>/dev/null; \
        openssl pkcs12 -export -in srv-rogue.pem -inkey srv-rogue.key -certfile rogue-ca.pem -name server -out srv-rogue.keystore.p12 -passout pass:changeit; \
        chmod 644 srv-rogue.* rogue-ca.*" >/dev/null 2>&1
  echo "   srv-rogue:$(file_info srv-rogue.pem)"
  precheck srv-rogue && echo "   預檢通過(異常)" || echo "   → 預檢攔下了:鏈不是行內 CA 簽的。正常流程到這裡就停"

  say "為了看後果,故意不理預檢,只換 broker1 一台(金絲雀),其他台不動"
  echo "為了看後果,故意不理預檢,只換一台當金絲雀(broker1 = id 11):"
  apply srv-rogue 11 | grep -E "Completed|rror" | head -1; sleep 8
  echo "4 台 broker 送出的序號:$(brokers_serial)"
  v=$(verify_served broker1:9094); echo "從 client 角度驗證 broker1 送出的鏈:$v"
  echo -n "client(只信任行內 CA)連 broker1:"
  r=$("$DEMO_DIR/scripts/k.sh" kafka-topics --bootstrap-server broker1:9094 --command-config "$KAFKA_ADMIN_CONFIG" --list 2>&1 \
        | grep -c -i -E "PKIX|unable to find valid certification|SSLHandshake|certificate")
  [ "$r" -gt 0 ] && echo " 驗證失敗(PKIX / 握手錯誤)" || echo " 沒有失敗(異常)"
  echo -n "同一個 client 連沒換的 broker2:"
  "$DEMO_DIR/scripts/k.sh" kafka-topics --bootstrap-server broker2:9094 --command-config "$KAFKA_ADMIN_CONFIG" --list 2>&1 \
    | grep -c -E "^orders" | sed 's/^0$/ 失敗/; s/^[1-9].*$/ 成功(只有金絲雀受影響,影響面被限制在一台)/'

  say "回退:走帶外路徑(INTERNAL mTLS 埠)——CLIENT 埠的憑證正是被換壞的那個,回退不能靠它"
  echo "回退:走帶外路徑(INTERNAL mTLS 埠),因為 CLIENT 埠的憑證正是被換壞的那一個——回退不能依賴剛弄壞的連線:"
  revert; sleep 8
  echo "回退後序號:$(brokers_serial)"
  echo -n "client 再連 broker1:"
  "$DEMO_DIR/scripts/k.sh" kafka-topics --bootstrap-server broker1:9094 --command-config "$KAFKA_ADMIN_CONFIG" --list 2>&1 \
    | grep -c -E "^orders" | sed 's/^0$/ 失敗(異常)/; s/^[1-9].*$/ 成功/'
  [ "$r" -gt 0 ] \
    && verdict "別的 CA 簽的憑證通得過 broker 的動態更新驗證(它不檢查自己送出的鏈是否被 client 信任),但 client 全部驗證失敗;所以要先離線預檢、先換一台金絲雀、並用不經 CLIENT 埠的帶外路徑回退"
}

lab_persist() {
  say "動態設定的憑證存在叢集 metadata,重啟後仍然有效;所以靜態設定檔也必須同步更新"
  local want got
  echo "目前是動態設定的新憑證 srv-new;重啟 broker1(靜態設定仍指向舊檔 server.keystore.p12):"
  apply srv-new | grep -E "Completed|rror" | head -1; sleep 6
  want=$(serial_of broker1:9094)
  docker restart broker1 >/dev/null; wait_healthy broker1 >/dev/null; sleep 5
  got=$(serial_of broker1:9094)
  echo "重啟前序號:$want;重啟後:$got"
  [ -n "$want" ] && [ "$want" = "$got" ] \
    && verdict "重啟後仍是動態設定的憑證(動態設定存在叢集 metadata,會在啟動時套用);所以靜態設定檔也必須同步指向新檔,否則兩處不一致、日後有人移除動態設定會「換回舊憑證」"
}

lab_cleanup() {
  say "移除動態設定(走帶外路徑),讓4 台 broker 回到靜態檔 certs/server.pem 的憑證"
  local serials static matched
  revert; sleep 8
  serials=$(brokers_serial); static=$(file_info server.pem | awk '{print $1}')
  echo "序號:$serials"; echo "靜態檔 server.pem:$static"
  matched=$(echo "$serials" | tr ' ' '\n' | grep -c "^$static$")
  [ "$matched" = 4 ] && verdict "已回到靜態檔的憑證(4 台 broker 送出的序號都與 certs/server.pem 相同)"
}

case "${1:-}" in
  baseline)   lab_baseline ;;
  monitor)    lab_monitor ;;
  expiring)   lab_expiring ;;
  rotate)     lab_rotate ;;
  reject-san) lab_reject_san ;;
  reject-ca)  lab_reject_ca ;;
  persist)    lab_persist ;;
  cleanup)    lab_cleanup ;;
  *)          usage_from_header "$0"; exit 1 ;;
esac
