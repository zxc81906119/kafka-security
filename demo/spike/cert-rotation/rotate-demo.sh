#!/usr/bin/env bash
# 在「實際 demo 環境」演練 CA 換金鑰:依序換 controller / broker(含 MDS)/ REST Proxy / C3,看每個階段誰要重啟、混合狀態會不會中斷。
# 會先備份 demo/certs,演練完還原並重啟全部元件。結果寫入 rotate-demo.log。需要 demo 以 --with-restproxy --with-c3 啟動。
cd "$(dirname "$0")/../.."          # → demo/
export MSYS_NO_PATHCONV=1
DEMO="$(pwd)"; D="$(pwd -W 2>/dev/null || pwd)"
LOG="$DEMO/spike/cert-rotation/rotate-demo.log"; : > "$LOG"
say() { echo "$*" | tee -a "$LOG"; }
NET=cpsec_default
IMG=confluentinc/cp-server:8.3.2

# ───────── 工具 ─────────
curlc() { docker run --rm --network $NET -v "$D/certs:/certs:ro" --entrypoint curl curlimages/curl:latest -s "$@"; }
kcli() { docker run --rm --network $NET -v "$D/certs:/etc/kafka/secrets:ro" -v "$D/config/clients:/clients:ro" -e KAFKA_HEAP_OPTS=-Xmx128m --entrypoint bash $IMG -c "$1"; }

served() { # 各連接埠目前「出示」的憑證簽發者與序號(不經過任何信任檢查)
  docker run --rm --network $NET --entrypoint sh alpine/openssl -c '
for hp in controller1:9093 broker1:9094 broker1:8091 broker2:9094 restproxy:8086 control-center:9022; do
  r=$(echo | openssl s_client -connect $hp 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null | sed "s/.*CN *= *//")
  printf "   %-20s 簽發者:%s\n" "$hp" "${r:-(連不上)}"
done'
}
smoke() { # <ca 檔案> <標籤>
  local ca=$1 lbl=$2 r1 r2 mds rp lg c3
  r1=$(kcli "kafka-topics --bootstrap-server broker1:9094 --command-config /clients/plain-yujie.properties --list 2>&1 | grep -ciE 'exception|failed|PKIX'" | tr -d '\r\n ')
  r2=$(kcli "kafka-topics --bootstrap-server broker2:9094 --command-config /clients/plain-yujie.properties --list 2>&1 | grep -ciE 'exception|failed|PKIX'" | tr -d '\r\n ')
  mds=$(curlc --cacert /certs/$ca -u ming:ming-pw -o /dev/null -w '%{http_code}' https://broker1:8091/security/1.0/authenticate)
  rp=$(curlc --cacert /certs/$ca -u gary:gary-pw -o /dev/null -w '%{http_code}' -H 'Accept: application/vnd.kafka.v2+json' https://restproxy:8086/topics)
  lg=$(curlc --cacert /certs/$ca --cert /certs/client-legacy-orders.pem --key /certs/client-legacy-orders.key -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/vnd.kafka.json.v2+json' -d '{"records":[{"value":{"rot":1}}]}' https://restproxy:8086/topics/orders.events)
  c3=$(curlc --cacert /certs/$ca -o /dev/null -w '%{http_code}' https://control-center:9022/)
  say "   [$lbl] Kafka 人員登入 broker1/2 錯誤數=$r1/$r2 | MDS 人登入=$mds | REST Proxy(人 Basic)=$rp | REST Proxy(legacy 憑證寫入)=$lg | C3 網頁=$c3"
}
wait_up() { # 等 broker / REST Proxy / C3 都可用
  for i in $(seq 1 60); do
    ok=$(kcli "kafka-topics --bootstrap-server broker1:9094 --command-config /clients/token-bootstrap.properties --list >/dev/null 2>&1 && kafka-topics --bootstrap-server broker2:9094 --command-config /clients/token-bootstrap.properties --list >/dev/null 2>&1 && echo UP" | tr -d '\r\n ')
    [ "$ok" = UP ] && break; sleep 5
  done
}
wait_http() { for i in $(seq 1 60); do c=$(curlc -k -o /dev/null -w '%{http_code}' "$1"); case $c in 200|302|401|403) return;; esac; sleep 5; done; }
restart() { # 依序重啟指定元件並等待可用
  for c in "$@"; do
    say "   ↻ 重啟 $c"
    docker restart $c >/dev/null 2>&1
    case $c in
      broker1|broker2) wait_up;;
      restproxy) wait_http https://restproxy:8086/topics;;
      control-center) wait_http https://control-center:9022/;;
      controller1) sleep 25; wait_up;;
    esac
  done
}

source "$DEMO/scripts/rbac-lib.sh"

# ───────── 備份與產生新憑證 ─────────
say "== 備份 certs → certs.bak,並以「新根 CA2(新金鑰)」產生新 server / client 憑證"
rm -rf "$DEMO/certs.bak" "$DEMO/certs-new"; cp -a "$DEMO/certs" "$DEMO/certs.bak"; mkdir -p "$DEMO/certs-new"
cp "$DEMO/certs/san.cnf" "$DEMO/certs-new/"
docker run --rm -v "$D/certs-new:/w" --entrypoint sh alpine/openssl -c '
set -e; cd /w
openssl genrsa -out ca2.key 4096 2>/dev/null
openssl req -x509 -new -nodes -key ca2.key -sha256 -days 3650 -subj "/CN=Demo Private CA G2/O=Demo" -out ca2.pem
openssl genrsa -out server.key 2048 2>/dev/null
openssl req -new -key server.key -out server.csr -config san.cnf
openssl x509 -req -in server.csr -CA ca2.pem -CAkey ca2.key -CAcreateserial -out server.pem -days 825 -sha256 -extfile san.cnf -extensions v3 2>/dev/null
openssl pkcs12 -export -in server.pem -inkey server.key -certfile ca2.pem -name server -out server.keystore.p12 -passout pass:changeit
for n in c3 restproxy bootstrap legacy-orders; do
  openssl genrsa -out client-$n.key 2048 2>/dev/null
  openssl req -new -key client-$n.key -subj "/CN=$n/O=Demo" -out client-$n.csr
  openssl x509 -req -in client-$n.csr -CA ca2.pem -CAkey ca2.key -CAcreateserial -out client-$n.pem -days 825 -sha256 2>/dev/null
  openssl pkcs12 -export -in client-$n.pem -inkey client-$n.key -certfile ca2.pem -name $n -out client-$n.keystore.p12 -passout pass:changeit
done
cp /dev/null ca-bundle.pem; chmod 644 *'
cat "$DEMO/certs/ca.pem" "$DEMO/certs-new/ca2.pem" > "$DEMO/certs-new/ca-bundle.pem"
docker run --rm -v "$D/certs-new:/w" -v "$D/certs:/old:ro" --entrypoint bash $IMG -c '
cd /w
keytool -importcert -noprompt -alias ca1 -file /old/ca.pem -keystore ts_AB.p12 -storetype PKCS12 -storepass changeit >/dev/null
keytool -importcert -noprompt -alias ca2 -file /w/ca2.pem -keystore ts_AB.p12 -storetype PKCS12 -storepass changeit >/dev/null
keytool -importcert -noprompt -alias ca2 -file /w/ca2.pem -keystore ts_B.p12 -storetype PKCS12 -storepass changeit >/dev/null
chmod 644 *'
cp "$DEMO/certs/ca.pem" "$DEMO/certs/ca-old.pem"
cp "$DEMO/certs-new/ca-bundle.pem" "$DEMO/certs/ca-bundle.pem"; cp "$DEMO/certs-new/ca2.pem" "$DEMO/certs/ca2.pem"
# legacy-orders 要有 role binding,才能用「寫入成功(200)」證明憑證身分(CN)沒變
rbac_bind cert bootstrap User:legacy-orders DeveloperWrite Topic orders. PREFIXED >/dev/null; sleep 6

say ""; say "【起點】舊 CA1:各埠出示的憑證"; served; smoke ca.pem "起點"

# ───────── 階段 1:所有信任庫先放新舊兩個根 ─────────
say ""; say "【階段 1】所有信任庫先放「新舊兩個根」(憑證都還沒換)"
cp "$DEMO/certs-new/ts_AB.p12" "$DEMO/certs/truststore.p12"
say "   (信任庫檔案已換成 {CA1,CA2};尚未重啟:各元件仍在用舊信任庫)"; smoke ca-bundle.pem "尚未重啟"
restart controller1 broker1 broker2 restproxy control-center
smoke ca-bundle.pem "階段 1 完成"

# ───────── 階段 2:換 server 憑證(CA2 簽發) ─────────
say ""; say "【階段 2】換 server 憑證(CA2 簽發)"
cp "$DEMO/certs-new/server.keystore.p12" "$DEMO/certs/server.keystore.p12"
say "   (檔案已換,尚未重啟)各埠出示的憑證:"; served
say "   依序重啟,觀察混合狀態(部分元件已換、部分還沒)是否中斷:"
restart controller1; smoke ca-bundle.pem "controller 已換"
restart broker1;     smoke ca-bundle.pem "broker1 已換(broker2 還是舊憑證)"
restart broker2 restproxy control-center
say "   各埠出示的憑證:"; served; smoke ca-bundle.pem "階段 2 完成"

# ───────── 階段 3:重簽 client 憑證 ─────────
say ""; say "【階段 3】重簽 client 憑證(c3、restproxy、bootstrap、legacy-orders;CN 不變)"
for n in c3 restproxy bootstrap legacy-orders; do for e in pem key keystore.p12; do cp "$DEMO/certs-new/client-$n.$e" "$DEMO/certs/client-$n.$e"; done; done
say "   (檔案已換,尚未重啟;legacy-orders 與 bootstrap 是 curl 直接讀檔,立即生效)"; smoke ca-bundle.pem "client 憑證已換、元件未重啟"
restart broker1 broker2 restproxy control-center
smoke ca-bundle.pem "階段 3 完成"
say "   舊 CA1 簽發的 legacy-orders 憑證(階段 4 之前,新舊根並存):"
old=$(docker run --rm --network $NET -v "$D/certs.bak:/old:ro" -v "$D/certs:/certs:ro" --entrypoint curl curlimages/curl:latest -s --cacert /certs/ca-bundle.pem --cert /old/client-legacy-orders.pem --key /old/client-legacy-orders.key -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/vnd.kafka.json.v2+json' -d '{"records":[{"value":{"rot":0}}]}' https://restproxy:8086/topics/orders.events)
say "   → HTTP $old(仍被接受,因為信任庫還有 CA1)"

# ───────── 階段 4:移除舊根 ─────────
say ""; say "【階段 4】全部確認後,移除舊根(信任庫只留 CA2)"
cp "$DEMO/certs-new/ts_B.p12" "$DEMO/certs/truststore.p12"; cp "$DEMO/certs/ca2.pem" "$DEMO/certs/ca-bundle.pem"
restart controller1 broker1 broker2 restproxy control-center
smoke ca2.pem "階段 4 完成(只信任 CA2)"
old=$(docker run --rm --network $NET -v "$D/certs.bak:/old:ro" -v "$D/certs:/certs:ro" --entrypoint curl curlimages/curl:latest -s --cacert /certs/ca2.pem --cert /old/client-legacy-orders.pem --key /old/client-legacy-orders.key -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/vnd.kafka.json.v2+json' -d '{"records":[{"value":{"rot":0}}]}' https://restproxy:8086/topics/orders.events)
say "   舊 CA1 簽發的 legacy-orders 憑證 → HTTP $old(000 = TLS 握手被拒)"
oldca=$(curlc --cacert /certs/ca-old.pem -o /dev/null -w '%{http_code}' https://restproxy:8086/topics)
say "   client 仍只信任舊根 CA1(沒更新信任庫)→ HTTP $oldca(000 = 不信任新 server 憑證)"

# ───────── 還原 ─────────
say ""; say "== 還原原本的 certs 並重啟全部元件"
rm -f "$DEMO/certs/ca-bundle.pem" "$DEMO/certs/ca2.pem" "$DEMO/certs/ca-old.pem"
cp -a "$DEMO/certs.bak/." "$DEMO/certs/"
restart controller1 broker1 broker2 restproxy control-center
smoke ca.pem "還原後"
rbac_unbind cert bootstrap User:legacy-orders DeveloperWrite Topic orders. PREFIXED >/dev/null
rm -rf "$DEMO/certs-new"; say "(certs.bak 保留作為備份,確認無誤後可刪)"
