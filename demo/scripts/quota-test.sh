#!/usr/bin/env bash
# 第 19 章實驗:client quota(帳號被偷後,攻擊者能灌多少流量?)。臨時帳號 svc-quota 先不限速跑一次、再套用 producer_byte_rate 跑一次,比較吞吐量。
# 用法: scripts/quota-test.sh [位元組/秒,預設 100000]      (做完會移除配額、帳號與角色)
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
