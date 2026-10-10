#!/usr/bin/env bash
# 第 23 章:憑證到期監控與不停機換憑證。需要 HA 模式、Prometheus、Alertmanager、blackbox-exporter
#   (scripts/ha.sh on;docker compose --profile c3 up -d prometheus alertmanager blackbox-exporter)。
#   scripts/cert-lab.sh baseline      現況:各端點「實際送出」的憑證 vs 檔案;OP menu 第 17 項(檔案巡檢,含剩餘時間分級)
#   scripts/cert-lab.sh monitor       blackbox 探測與 telemetry 指標:各端點剩餘天數,基準沒有憑證告警
#   scripts/cert-lab.sh expiring      把 CLIENT 埠換成「20 天效期」的憑證(模擬快到期)→ 到期告警觸發;MDS 不在動態重載範圍,仍是舊憑證
#   scripts/cert-lab.sh rotate        背景持續寫入時,不重啟換成 825 天的新憑證 → 序號變了、broker 沒重啟、寫入零失敗、告警解除
#   scripts/cert-lab.sh reject-san    新憑證的 SAN 與現有不同 → broker 拒絕這次動態更新
#   scripts/cert-lab.sh reject-ca     換成另一個 CA 簽的憑證:broker 接受,但 client 驗證失敗 → 立刻回退
#   scripts/cert-lab.sh persist       重啟 broker1 後仍是動態設定的憑證(動態設定存在叢集 metadata);靜態設定也要同步更新
#   scripts/cert-lab.sh cleanup       移除動態設定,回到靜態檔的憑證
# 作法與取捨見手冊 Lab 23:動態 keystore 重載(listener.name.<listener>.ssl.keystore.*)優於滾動重啟,但只涵蓋 Kafka 的 listener。
set -uo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
grep -q '^COMPOSE_FILE=.*docker-compose.ha.yml' .env 2>/dev/null || { echo "目前不是 HA 模式:先執行 scripts/ha.sh on"; exit 1; }
OSSL=alpine/openssl:latest
DC=./scripts/dcurl.sh
TOK=/clients/token-bootstrap.properties
BS=broker1:9094,broker2:9094,broker3:9094
D="$(pwd -W 2>/dev/null || pwd)"
KC() { timeout 90 ./scripts/k.sh kafka-configs --bootstrap-server $BS --command-config $TOK "$@" 2>&1 | grep -v -E "^WARNING|SLF4J"; }
ossl() { docker run --rm -v "$D/certs:/certs" --entrypoint sh $OSSL -c "cd /certs; $1"; }
served() { # served <host:port>:印「序號 到期日」(從 TLS 握手實際收到的憑證)
  local h="${1%%:*}"
  docker run --rm --network cpsec_default --entrypoint sh $OSSL -c "openssl s_client -connect $1 -servername $h </dev/null 2>/dev/null | openssl x509 -noout -serial -enddate 2>/dev/null | tr '\n' ' ' | sed 's/serial=//; s/notAfter=/到期 /'"
}
serial_of() { served "$1" | awk '{print $1}'; }
file_info() { ossl "openssl x509 -in $1 -noout -serial -enddate" | tr '\n' ' ' | sed 's/serial=//; s/notAfter=/到期 /'; }
mkcert() { # mkcert <名稱> <效期天數> [san.cnf 路徑,預設 san.cnf]:新 key、同 DN 與 SAN、行內 CA 簽發 → certs/<名稱>.keystore.p12(密碼 changeit)
  local n="$1" days="$2" cnf="${3:-san.cnf}"
  ossl "openssl genrsa -out $n.key 2048 2>/dev/null; openssl req -new -key $n.key -out $n.csr -config $cnf; openssl x509 -req -in $n.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out $n.pem -days $days -sha256 -extfile $cnf -extensions v3 2>/dev/null; openssl pkcs12 -export -in $n.pem -inkey $n.key -certfile ca.pem -name server -out $n.keystore.p12 -passout pass:changeit; chmod 644 $n.* " >/dev/null 2>&1
  [ -f "certs/$n.keystore.p12" ] && echo "   新憑證 $n:$(file_info $n.pem)"
}
apply() { # apply <名稱>:對所有 broker 的 CLIENT listener 動態換 keystore(不重啟)
  KC --entity-type brokers --entity-default --alter --add-config "listener.name.client.ssl.keystore.location=/etc/kafka/secrets/$1.keystore.p12,listener.name.client.ssl.keystore.type=PKCS12,listener.name.client.ssl.keystore.password=changeit,listener.name.client.ssl.key.password=changeit"
}
revert() { KC --entity-type brokers --entity-default --alter --delete-config "listener.name.client.ssl.keystore.location,listener.name.client.ssl.keystore.type,listener.name.client.ssl.keystore.password,listener.name.client.ssl.key.password" | grep -E "Completed|rror" | head -2; }
brokers_serial() { for b in broker1 broker2 broker3; do echo -n "$(serial_of $b:9094) "; done; echo; }
firing_cert() { bash $DC -u c3:prom-pw https://prometheus:9090/api/v1/alerts 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const i=s.indexOf("{");const j=JSON.parse(s.slice(i,s.lastIndexOf("}")+1));console.log(j.data.alerts.filter(a=>a.state==="firing"&&/^Kafka(Tls|Mtls)/.test(a.labels.alertname)).map(a=>a.labels.alertname+"@"+(a.labels.instance||"-")).sort().join(",")||"-")}catch(e){console.log("?")}})'; }
wait_cert_alert() { # wait_cert_alert <告警名> <instance> <present|absent> <秒>
  local t0=$(date +%s) f
  while [ $(( $(date +%s) - t0 )) -lt "$4" ]; do f=$(firing_cert); case ",$f," in *",$1@$2,"*) [ "$3" = present ] && { echo "   $(( $(date +%s) - t0 )) 秒後 $1@$2 觸發"; return 0; };; *) [ "$3" = absent ] && { echo "   $(( $(date +%s) - t0 )) 秒後 $1@$2 解除"; return 0; };; esac; sleep 10; done
  echo "   等了 $4 秒:$1@$2 仍${3/present/未觸發}${3/absent/未解除}(目前:$(firing_cert))"; return 1
}
days_left() { # days_left <instance>:從 Prometheus 讀剩餘天數
  bash $DC -u c3:prom-pw -G --data-urlencode "query=(probe_ssl_earliest_cert_expiry{instance=\"$1\"} - time()) / 86400" https://prometheus:9090/api/v1/query 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const i=s.indexOf("{");const j=JSON.parse(s.slice(i,s.lastIndexOf("}")+1));console.log(j.data.result.length?Number(j.data.result[0].value[1]).toFixed(1):"?")}catch(e){console.log("?")}})'
}

case "${1:-}" in
baseline)
  echo "各端點「實際送出」的憑證(TLS 握手收到的):"
  for e in broker1:9094 broker2:9094 broker3:9094 broker1:8091; do echo "  $e → $(served $e)"; done
  echo "磁碟上的檔案 certs/server.pem:$(file_info server.pem)"
  echo "OP menu 第 17 項(檔案巡檢)的前幾列:"
  ( cd opmenu && OPMENU_USER=gary OPMENU_PASS=gary-pw OPMENU_YES=1 ./opmenu.sh --run 17 2>&1 | grep -E "\.pem" | head -4 | sed 's/^/  /' )
  a=$(serial_of broker1:9094); b=$(serial_of broker1:8091); f=$(file_info server.pem | awk '{print $1}')
  [ -n "$a" ] && [ "$a" = "$b" ] && [ "$a" = "$f" ] && echo "判定:現況各端點送出的憑證與磁碟檔案是同一張(序號相同),OP menu 的檔案巡檢能看到剩餘時間分級"
  ;;
monitor)
  t0=$(date +%s); ok=0
  while [ $(( $(date +%s) - t0 )) -lt 180 ]; do
    n=$(bash $DC -u c3:prom-pw -G --data-urlencode 'query=count(probe_success{job="tls-expiry"} == 1)' https://prometheus:9090/api/v1/query 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const i=s.indexOf("{");const j=JSON.parse(s.slice(i,s.lastIndexOf("}")+1));console.log(j.data.result.length?j.data.result[0].value[1]:"0")}catch(e){console.log("0")}})')
    [ "$n" = 6 ] && { ok=1; break; }; sleep 10
  done
  for e in broker1:9094 broker2:9094 broker3:9094 broker1:8091 broker2:8092 broker3:8093; do echo "  $e → 剩 $(days_left $e) 天"; done
  echo "內部 mTLS 憑證(telemetry 指標)剩餘天數:$(bash $DC -u c3:prom-pw -G --data-urlencode 'query=min((io_confluent_kafka_server_raft_channel_mtls_earliest_cert_expiration_ms / 1000 - time()) / 86400)' https://prometheus:9090/api/v1/query 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const i=s.indexOf("{");const j=JSON.parse(s.slice(i,s.lastIndexOf("}")+1));console.log(j.data.result.length?Number(j.data.result[0].value[1]).toFixed(0):"沒有資料")}catch(e){console.log("?")}})')"
  echo "目前 firing 的憑證告警:$(firing_cert)"
  [ "$ok" = 1 ] && [ "$(firing_cert)" = "-" ] && echo "判定:6 個 TLS 端點的探測都成功並有剩餘天數,基準狀態沒有憑證告警"
  ;;
expiring)
  echo "簽一張只有 20 天效期的 server 憑證(同 DN、同 SAN),動態換到 CLIENT 埠:"; mkcert srv-short 20
  apply srv-short | grep -E "Completed|rror"; sleep 8
  echo "三台 broker CLIENT 埠送出的序號:$(brokers_serial)"; echo "MDS(8091)送出的序號(不在動態重載範圍):$(serial_of broker1:8091)"
  wait_cert_alert KafkaTlsCertExpiringSoon broker1:9094 present 240 && f1=1
  echo "到期告警目前:$(firing_cert)"
  echo "MDS 8091 的剩餘天數:$(days_left broker1:8091)(舊憑證,不告警)"
  ok2=0; case ",$(firing_cert)," in *",KafkaTlsCertExpiringSoon@broker1:8091,"*) ok2=1;; esac
  [ "${f1:-0}" = 1 ] && [ "$ok2" = 0 ] && echo "判定:CLIENT 埠換成 20 天效期的憑證後,到期告警觸發;MDS 仍是舊憑證(動態重載只涵蓋 Kafka 的 listener),沒有告警"
  ;;
rotate)
  echo "簽新憑證(825 天、同 DN 與 SAN):"; mkcert srv-new 825
  before=$(docker inspect -f '{{.State.StartedAt}}' broker1 broker2 broker3 | tr '\n' ' ')
  KT="./scripts/k.sh kafka-topics --bootstrap-server $BS --command-config $TOK"
  $KT --delete --if-exists --topic cert.roll >/dev/null 2>&1; sleep 3; $KT --create --topic cert.roll --partitions 3 --replication-factor 3 --config min.insync.replicas=2 2>&1 | grep -E "Created|rror"
  ./scripts/k.sh kafka-producer-perf-test --topic cert.roll --num-records 300 --throughput 5 --record-size 100 --command-config $TOK --producer-props bootstrap.servers=$BS acks=all enable.idempotence=true > /tmp/cert-roll.out 2>&1 &
  PP=$!; sleep 15
  echo "寫入進行中,動態換成新憑證(不重啟):"; apply srv-new | grep -E "Completed|rror"; sleep 8
  echo "三台 broker CLIENT 埠送出的序號:$(brokers_serial)"
  wait $PP
  sent=$(grep -oE '^[0-9]+ records sent' /tmp/cert-roll.out | tail -1 | awk '{print $1}'); have=$(./scripts/k.sh kafka-get-offsets --bootstrap-server $BS --command-config $TOK --topic cert.roll 2>/dev/null | awk -F: '{s+=$3} END {print s+0}')
  after=$(docker inspect -f '{{.State.StartedAt}}' broker1 broker2 broker3 | tr '\n' ' ')
  echo "producer 送出 ${sent:-?} 筆;topic 實際 $have 筆;broker 啟動時間 $([ "$before" = "$after" ] && echo 沒有變(沒重啟) || echo 變了(有重啟))"
  wait_cert_alert KafkaTlsCertExpiringSoon broker1:9094 absent 240 && f2=1
  new=$(serial_of broker1:9094); old=$(file_info server.pem | awk '{print $1}')
  $KT --delete --if-exists --topic cert.roll >/dev/null 2>&1
  [ "${sent:-}" = 300 ] && [ "$have" = 300 ] && [ "$before" = "$after" ] && [ "$new" != "$old" ] && [ "${f2:-0}" = 1 ] && echo "判定:不重啟換成新憑證:序號已變、broker 沒有重啟、寫入期間零失敗(300 = 300)、到期告警解除"
  ;;
reject-san)
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
  echo "$out" | grep -q -i -E "rror|invalid|validation" && [ "$before" = "$after" ] && echo "判定:SAN 與現有不同的憑證被 broker 拒絕,動態更新沒有生效(防止被塞進不同身分的憑證)"
  ;;
reject-ca)
  echo "建一個「別的 CA」,用它簽一張同 DN、同 SAN 的憑證:"
  ossl "openssl genrsa -out rogue-ca.key 2048 2>/dev/null; openssl req -x509 -new -key rogue-ca.key -sha256 -days 30 -subj '/CN=rogue-ca/O=Evil' -out rogue-ca.pem; openssl genrsa -out srv-rogue.key 2048 2>/dev/null; openssl req -new -key srv-rogue.key -out srv-rogue.csr -config san.cnf; openssl x509 -req -in srv-rogue.csr -CA rogue-ca.pem -CAkey rogue-ca.key -CAcreateserial -out srv-rogue.pem -days 30 -sha256 -extfile san.cnf -extensions v3 2>/dev/null; openssl pkcs12 -export -in srv-rogue.pem -inkey srv-rogue.key -certfile rogue-ca.pem -name server -out srv-rogue.keystore.p12 -passout pass:changeit; chmod 644 srv-rogue.* rogue-ca.*" >/dev/null 2>&1
  echo "   srv-rogue:$(file_info srv-rogue.pem)"
  echo -n "動態換上去:"; apply srv-rogue | grep -E "Completed|rror" | head -1; sleep 8
  echo "三台 broker 送出的序號:$(brokers_serial)"
  echo -n "client(只信任行內 CA)連 broker1:"; r=$(./scripts/k.sh kafka-topics --bootstrap-server broker1:9094 --command-config $TOK --list 2>&1 | grep -c -i -E "PKIX|unable to find valid certification|SSLHandshake|certificate"); [ "$r" -gt 0 ] && echo " 驗證失敗(PKIX / 握手錯誤)" || echo " 沒有失敗(異常)"
  echo "立刻回退(移除動態設定):"; revert; sleep 8
  echo "回退後序號:$(brokers_serial)"
  echo -n "client 再連:"; ./scripts/k.sh kafka-topics --bootstrap-server broker1:9094 --command-config $TOK --list 2>&1 | grep -c -E "^orders" | sed 's/^0$/ 失敗(異常)/; s/^[1-9].*$/ 成功/'
  [ "$r" -gt 0 ] && echo "判定:broker 接受了別的 CA 簽的憑證(它不檢查自己的鏈是否被信任),但所有 client 驗證失敗;所以換憑證前一定要先驗證鏈,並保留回退(移除動態設定)"
  ;;
persist)
  echo "目前是動態設定的新憑證 srv-new;重啟 broker1(靜態設定仍指向舊檔 server.keystore.p12):"
  apply srv-new | grep -E "Completed|rror" | head -1; sleep 6
  want=$(serial_of broker1:9094)
  docker restart broker1 >/dev/null; for i in $(seq 1 30); do docker ps --format '{{.Names}} {{.Status}}' | grep -q "^broker1 .*(healthy)" && break; sleep 5; done; sleep 5
  got=$(serial_of broker1:9094)
  echo "重啟前序號:$want;重啟後:$got"
  [ -n "$want" ] && [ "$want" = "$got" ] && echo "判定:重啟後仍是動態設定的憑證(動態設定存在叢集 metadata,會在啟動時套用);所以靜態設定檔也必須同步指向新檔,否則兩處不一致、日後有人移除動態設定會「換回舊憑證」"
  ;;
cleanup)
  revert; sleep 8; echo "序號:$(brokers_serial)"; echo "靜態檔 server.pem:$(file_info server.pem | awk '{print $1}')"
  ;;
*) sed -n 2,13p "$0"; exit 1;;
esac
