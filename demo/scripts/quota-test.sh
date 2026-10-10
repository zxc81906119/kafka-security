#!/usr/bin/env bash
# ============================================================================
# quota-test.sh — 第 19 章實驗:client quota——帳號被偷後,攻擊者能灌多少流量?
# ----------------------------------------------------------------------------
# 白話:帳號一旦被偷,攻擊者可以用全速灌資料把叢集打爆。client quota(producer_byte_rate)能替每個帳號設流量上限。
#   這支腳本用臨時帳號 svc-quota 先不限速跑一次、再套用限速跑一次,比較兩次的吞吐量,證明限速有效。
# 前置條件:demo 環境已啟動(scripts/up.sh)。
# 用法:
#   scripts/quota-test.sh [位元組/秒]    限速值,預設 100000(約 100 KB/s);測試筆數可用環境變數 RECORDS 改(預設 2500 筆、每筆 1000 bytes)
# 會改動什麼:建立臨時 SCRAM 帳號 svc-quota,綁 DeveloperWrite 到 orders.events,對它設 producer_byte_rate,
#   並在 orders.events 寫入測試資料(兩輪各約 2500 筆)。結束時(含中途失敗,trap EXIT)會移除配額、解除角色,
#   並「停用」帳號:SCRAM 憑證覆寫成隨機密碼,**不刪除**(刪除 SCRAM 憑證會讓之後重啟 broker 失敗,見 scram-disable.sh)。
#   開始前也會先清掉上次中斷留下的配額與帳號,否則第一次測量就已經被限速。
# 怎麼判斷成功:最後一行「判定:限速後吞吐量降為原來的 1/N」(限速後至少慢 3 倍才算);
#   印「判定:不符合(沒有被限速)」代表配額沒生效。
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
D="$(pwd -W 2>/dev/null || pwd)"
RATE="${1:-100000}"; U=svc-quota; PW="quota-$RANDOM"
K="./scripts/k.sh kafka-configs --bootstrap-server broker1:9094 --command-config /clients/token-bootstrap.properties"
source scripts/rbac-lib.sh
cleanup() { $K --alter --entity-type users --entity-name "$U" --delete-config producer_byte_rate >/dev/null 2>&1 || true
            bash scripts/scram-disable.sh "$U" >/dev/null 2>&1 || true   # 不刪除:停用 SCRAM 憑證(覆寫成隨機密碼,不刪除)會讓之後重啟 broker 失敗(見 scram-disable.sh)
            rbac_unbind cert bootstrap "User:$U" DeveloperWrite Topic orders.events LITERAL >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup   # 先清掉上次中斷留下的配額 / 帳號(否則第一次測量就已經被限速)
bash scripts/create-service-account.sh "$U" "$PW" >/dev/null
rbac_bind cert bootstrap "User:$U" DeveloperWrite Topic orders.events LITERAL >/dev/null
perf() { # 密碼經 stdin 進容器,連線設定只放 /dev/shm
  printf '%s\n' "$PW" | docker run --rm -i --network cpsec_default -v "$D/certs:/etc/kafka/secrets:ro" -e KAFKA_OPTS="" -e KAFKA_HEAP_OPTS="-Xmx256m" -e U="$U" --entrypoint bash confluentinc/cp-server:8.3.2 -c '
    IFS= read -r PW
    printf "security.protocol=SASL_SSL\nsasl.mechanism=SCRAM-SHA-512\nsasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username=\"%s\" password=\"%s\";\nssl.truststore.location=/etc/kafka/secrets/truststore.p12\nssl.truststore.type=PKCS12\nssl.truststore.password=changeit\n" "$U" "$PW" > /dev/shm/c; unset PW
    kafka-producer-perf-test --topic orders.events --num-records "${RECORDS:-2500}" --record-size 1000 --throughput -1 --producer-props bootstrap.servers=broker1:9094 --producer.config /dev/shm/c 2>&1' | grep -E "records sent" | tail -1 | sed -E 's/^([0-9]+ records sent, [0-9.]+ records\/sec \([0-9.]+ MB\/sec\)).*/\1/'
}
A=$(perf); echo "① 不限速(帳號 $U 被偷,攻擊者全速寫入):"; echo "$A"
$K --alter --entity-type users --entity-name "$U" --add-config "producer_byte_rate=$RATE" 2>&1 | grep -v "^WARNING\|SLF4J" | tail -1
echo "② 套用 producer_byte_rate=$RATE(約 $((RATE/1000)) KB/s)後,同一個動作:"; B=$(perf); echo "$B"
echo "配額設定:$($K --describe --entity-type users --entity-name "$U" 2>&1 | grep -E "producer_byte_rate" | sed 's/^ *//')"
ra=$(echo "$A" | sed -E "s/.*, ([0-9.]+) records.*/\1/"); rb=$(echo "$B" | sed -E "s/.*, ([0-9.]+) records.*/\1/")
awk -v a="$ra" -v b="$rb" 'BEGIN{ if (b>0 && a/b>=3) printf "判定:限速後吞吐量降為原來的 1/%.0f(%.0f → %.0f 筆/秒)\n", a/b, a, b; else print "判定:不符合(沒有被限速)" }'
