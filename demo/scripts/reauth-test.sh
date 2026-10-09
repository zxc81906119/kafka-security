#!/usr/bin/env bash
# 第 19 章實驗:SASL 重新認證(connections.max.reauth.ms)能不能切斷「帳號已停用、但還連著」的舊連線?
# 對照第 18 章的發現:預設 0(不重新認證)時只停用 SCRAM 憑證擋不住舊連線;這裡把 CLIENT listener 設成 30 秒重新認證,再做同一個實驗。
# 用法: scripts/reauth-test.sh run     (broker 已設定 CLIENT listener 每 60 秒重新認證:docker-compose.yml 的 KAFKA_LISTENER_NAME_CLIENT_CONNECTIONS_MAX_REAUTH_MS)
#   臨時帳號 svc-reauth 開長連線每 2 秒寫 1 筆(共 45 筆,約 90 秒),第 10 秒刪它的 SCRAM 憑證(角色保留),看之後還能寫幾筆。
#   注意:這個設定不能動態改(實測 kafka-configs 會拒絕 connections.max.reauth.ms;per-listener 寫法會被接受但不生效)
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
D="$(pwd -W 2>/dev/null || pwd)"
K="./scripts/k.sh kafka-configs --bootstrap-server broker1:9094 --command-config /clients/token-bootstrap.properties"
case "${1:-}" in
run)
  U=svc-reauth; PW="reauth-$RANDOM"; RID="ra$RANDOM"; N=45
  source scripts/rbac-lib.sh
  bash scripts/create-service-account.sh "$U" "$PW" >/dev/null
  rbac_bind cert bootstrap "User:$U" DeveloperWrite Topic orders.events LITERAL >/dev/null
  echo "起點:臨時帳號 $U(SCRAM)開長連線 producer,每 2 秒寫 1 筆、共 $N 筆(約 90 秒),標記 $RID"
  LOG=$(mktemp)
  ( printf '%s\n' "$PW" | docker run --rm -i --network cpsec_default -v "$D/certs:/etc/kafka/secrets:ro" -e KAFKA_OPTS="" -e KAFKA_HEAP_OPTS="-Xmx256m" -e U="$U" -e RID="$RID" -e N="$N" --entrypoint bash confluentinc/cp-server:8.3.2 -c '
    IFS= read -r PW
    printf "security.protocol=SASL_SSL\nsasl.mechanism=SCRAM-SHA-512\nsasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username=\"%s\" password=\"%s\";\nssl.truststore.location=/etc/kafka/secrets/truststore.p12\nssl.truststore.type=PKCS12\nssl.truststore.password=changeit\nmax.block.ms=5000\ndelivery.timeout.ms=8000\nrequest.timeout.ms=4000\n" "$U" "$PW" > /dev/shm/c; unset PW
    ( for i in $(seq 1 $N); do echo "$RID-$i"; sleep 2; done ) | kafka-console-producer --bootstrap-server broker1:9094 --producer.config /dev/shm/c --topic orders.events 2>&1' > "$LOG" 2>&1 ) &
  BG=$!
  sleep 10; echo "第 10 秒:停用 $U(SCRAM 憑證覆寫成隨機密碼、不刪除;角色保留)— 第 18 章的做法,當時擋不住舊連線"
  bash scripts/scram-disable.sh "$U" 2>&1 | tail -1
  wait "$BG" || true
  got=$(./scripts/k.sh kafka-console-consumer --bootstrap-server broker1:9094 --command-config /clients/token-bootstrap.properties --topic orders.events --group "raread-$RID" --from-beginning --timeout-ms 15000 2>/dev/null | grep -c "^$RID-" || true)
  echo "結果:$N 筆嘗試寫入,實際寫進 topic $got 筆(停用前約 5 筆;下一次重新認證在 60 秒內)"
  echo "producer 第一個錯誤:$(grep -m1 -iE "authentication|re-authentication|SaslAuthentication|Authentication failed" "$LOG" | sed -E 's/^\[[^]]*\] //' | cut -c1-160)"
  grep -m1 -iE "re-authenticat" "$LOG" >/dev/null && echo "(broker 要求重新認證時用已刪除的憑證 → 失敗 → 連線被切)"
  if [ "$got" -lt "$N" ]; then echo "判定:60 秒內舊連線被切斷(重新認證失敗),只寫進 $got/$N 筆"; else echo "判定:不符合(全部寫入,重新認證沒有生效)"; fi
  rbac_unbind cert bootstrap "User:$U" DeveloperWrite Topic orders.events LITERAL >/dev/null; rm -f "$LOG"
  ;;
*) sed -n 2,5p "$0"; exit 1;;
esac
