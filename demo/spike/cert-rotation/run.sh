#!/usr/bin/env bash
# 憑證更換實驗(單節點 Kafka SSL listener,要求 client 憑證)。結果寫入 evidence.log
cd "$(dirname "$0")"
export MSYS_NO_PATHCONV=1
D="$(pwd -W 2>/dev/null || pwd)"
mkdir -p work
LOG=evidence.log; : > "$LOG"
say() { echo "$*" | tee -a "$LOG"; }

gen() { docker run --rm -v "$D/work:/w" -w /w --entrypoint sh alpine/openssl -c "$1"; }
jks() { docker run --rm -v "$D/work:/w" -w /w --entrypoint keytool confluentinc/cp-server:8.3.2 "$@" >/dev/null 2>&1; }

if [ ! -f work/.done ]; then
  say "== 產生憑證:CA1(舊根)、CA2(換金鑰的新根)、CA1b(同金鑰重新簽發的根)"
  gen '
set -e
printf "subjectAltName=DNS:kafka,DNS:localhost\n" > srv.ext
printf "extendedKeyUsage=clientAuth\n" > cli.ext
openssl req -x509 -newkey rsa:2048 -nodes -keyout ca1.key -out ca1.pem -days 365 -subj "/CN=Corp Root CA" 2>/dev/null
openssl req -x509 -newkey rsa:2048 -nodes -keyout ca2.key -out ca2.pem -days 365 -subj "/CN=Corp Root CA G2" 2>/dev/null
openssl req -x509 -new -key ca1.key -out ca1b.pem -days 730 -subj "/CN=Corp Root CA" 2>/dev/null
issue() { n=$1; ca=$2; cn=$3; ext=$4
  openssl req -newkey rsa:2048 -nodes -keyout $n.key -out $n.csr -subj "/CN=$cn" 2>/dev/null
  openssl x509 -req -in $n.csr -CA $ca.pem -CAkey $ca.key -CAcreateserial -out $n.pem -days 365 -extfile $ext 2>/dev/null
  openssl pkcs12 -export -in $n.pem -inkey $n.key -certfile $ca.pem -name $n -out $n.p12 -passout pass:changeit; }
issue S1 ca1 kafka srv.ext
issue S2 ca1 kafka srv.ext
issue S3 ca2 kafka srv.ext
issue C1 ca1 client-app cli.ext
issue C2 ca2 client-app cli.ext
chmod 644 *'
  for t in "A ca1" "B ca2" "C ca1b" "AB ca1 ca2"; do
    set -- $t; name=$1; shift
    for c in "$@"; do jks -importcert -noprompt -alias $c -file /w/$c.pem -keystore /w/ts_$name.p12 -storetype PKCS12 -storepass changeit; done
  done
  for n in A B C AB; do cp work/ts_$n.p12 work/ts_srv_$n.p12; done
  chmod 644 work/*; touch work/.done
fi

printf changeit > work/creds; docker compose -p crtest down -v >/dev/null 2>&1
say "== 啟動 Kafka(server 憑證 S1 ← CA1;server 信任庫 {CA1};要求 client 憑證)"
docker compose -p crtest up -d >/dev/null 2>&1
for i in $(seq 1 40); do docker exec cr-kafka kafka-broker-api-versions --bootstrap-server kafka:9092 >/dev/null 2>&1 && break; sleep 3; done

NET=crtest_default
cli() { # <name> <keystore> <truststore>  → OK 或 錯誤摘要
  printf 'security.protocol=SSL\nssl.truststore.location=/certs/%s.p12\nssl.truststore.type=PKCS12\nssl.truststore.password=changeit\nssl.keystore.location=/certs/%s.p12\nssl.keystore.type=PKCS12\nssl.keystore.password=changeit\nssl.key.password=changeit\n' "$3" "$2" > work/client-$1.properties
  out=$(docker run --rm --network $NET -v "$D/work:/certs:ro" -e KAFKA_HEAP_OPTS=-Xmx128m --entrypoint kafka-topics confluentinc/cp-server:8.3.2 --bootstrap-server kafka:9093 --command-config /certs/client-$1.properties --list 2>&1)
  if echo "$out" | grep -qiE "exception|failed|PKIX|handshake"; then
    for p in 'PKIX path building failed' 'unable to find valid certification path' 'certificate_unknown' 'bad_certificate' 'unknown_ca' 'certificate_required' 'SSL handshake failed' 'failed authentication'; do echo "$out" | grep -qi "$p" && { echo "拒絕:$p"; break; }; done
  else echo "OK"; fi
}
serial() { docker run --rm --network $NET --entrypoint sh alpine/openssl -c "echo | openssl s_client -connect kafka:9093 2>/dev/null | openssl x509 -noout -serial -issuer" 2>/dev/null | tr '\n' ' '; }
cfg() { docker exec cr-kafka kafka-configs --bootstrap-server kafka:9092 --alter --entity-type brokers --entity-name 1 --add-config "$1" 2>&1 | tail -1; }

say ""; say "【T0 基準】server=S1(CA1),client=C1(CA1)+信任庫{CA1}"; say "  → $(cli t0 C1 ts_A)"
say "  server 憑證:$(serial)"

say ""; say "【T1 只換 server 憑證,CA 不變】動態換 keystore → S2(同 CA1、新金鑰、新序號),client 完全不動"
say "  $(cfg 'listener.name.ssl.ssl.keystore.location=/certs/S2.p12')"; sleep 3
say "  server 憑證:$(serial)"; say "  → client(C1 + 信任庫{CA1},未改):$(cli t1 C1 ts_A)"

say ""; say "【T4 CA 根憑證用「同一把金鑰」重新簽發(CA1b)】client 信任庫只放 CA1b"
say "  → client(C1 + 信任庫{CA1b}):$(cli t4 C1 ts_C)"
say "  server 信任庫也換成 {CA1b}(動態):$(cfg 'listener.name.ssl.ssl.truststore.location=/certs/ts_srv_C.p12')"; sleep 3
say "  → client(C1 + 信任庫{CA1b}):$(cli t4b C1 ts_C)"
say "  還原 server 信任庫 {CA1}:$(cfg 'listener.name.ssl.ssl.truststore.location=/certs/ts_srv_A.p12')"; sleep 3

say ""; say "【T2 CA 換金鑰:錯誤順序】先換 server 憑證到 S3(CA2),client 信任庫還是 {CA1}"
say "  $(cfg 'listener.name.ssl.ssl.keystore.location=/certs/S3.p12')"; sleep 3
say "  → client(C1 + 信任庫{CA1}):$(cli t2 C1 ts_A)"
say "  還原 S2:$(cfg 'listener.name.ssl.ssl.keystore.location=/certs/S2.p12')"; sleep 3
say "  → client(C1 + 信任庫{CA1}):$(cli t2r C1 ts_A)"

say ""; say "【T3 CA 換金鑰:正確順序】"
say " ① 所有信任庫先加入新根(server 與 client 都變成 {CA1,CA2})"
say "    server 信任庫:$(cfg 'listener.name.ssl.ssl.truststore.location=/certs/ts_srv_AB.p12')"; sleep 3
say "    → client(C1 + 信任庫{CA1,CA2}):$(cli t3a C1 ts_AB)"
say " ② 換 server 憑證到 S3(CA2)"
say "    $(cfg 'listener.name.ssl.ssl.keystore.location=/certs/S3.p12')"; sleep 3
say "    server 憑證:$(serial)"
say "    → client(舊 client 憑證 C1 + 信任庫{CA1,CA2}):$(cli t3b C1 ts_AB)"
say " ③ 重簽 client 憑證 → C2(CA2)"
say "    → client(C2 + 信任庫{CA1,CA2}):$(cli t3c C2 ts_AB)"
say " ④ 全部確認後移除舊根(server 信任庫 {CA2},client 信任庫 {CA2})"
say "    server 信任庫:$(cfg 'listener.name.ssl.ssl.truststore.location=/certs/ts_srv_B.p12')"; sleep 3
say "    → client(C2 + 信任庫{CA2}):$(cli t3d C2 ts_B)"
say "    → 還沒換的舊 client 憑證(C1 + 信任庫{CA2}):$(cli t3e C1 ts_B)"

say ""; say "(收尾)docker compose -p crtest down -v"
docker compose -p crtest down -v >/dev/null 2>&1
