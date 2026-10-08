#!/usr/bin/env bash
# 示範「應用程式啟動時向 CyberArk(Conjur)取帳密」:帳號與密碼放在 Conjur 的「同一個變數」(JSON),一次取、一次換,不會取到不配對的帳密。
# 密碼只進記憶體(容器內的 tmpfs)。輪替時應用不用改設定。
# 用法: scripts/app-with-conjur.sh <host 身分> <topic> <訊息>
#   例: scripts/app-with-conjur.sh svc-orders orders.events hello-from-conjur
# 流程:① 以 host 的 API key 向 Conjur 換 token → ② 取 kafka/<host>/credential(例 {"u":"svc-orders","p":"…"})→ ③ 在容器的 /dev/shm 組出連線設定 → ④ 寫入 topic → 容器結束,設定隨之消失
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
HOST="$1"; TOPIC="$2"; MSG="${3:-hello}"
D="$(pwd -W 2>/dev/null || pwd)"
echo "① ② 向 Conjur 取帳密(身分 host/kafka/$HOST;一個變數、一次取得)"
CRED=$(bash scripts/conjur.sh get-as "$HOST" "$HOST/credential") || { echo "取帳密失敗:$CRED"; exit 1; }
echo "③ ④ 在記憶體組連線設定並寫入 $TOPIC"
# 帳密與訊息都從 stdin 進容器(第一行是帳密 JSON,第二行起是訊息):不放環境變數,docker inspect 與行程清單都看不到
printf '%s\n%s\n' "$CRED" "$MSG" | docker run --rm -i --network cpsec_default -v "$D/certs:/etc/kafka/secrets:ro" -e KAFKA_OPTS="" -e KAFKA_HEAP_OPTS="-Xmx256m" \
  -e TOPIC="$TOPIC" --entrypoint bash confluentinc/cp-server:8.3.2 -c '
  IFS= read -r CRED
  APP_USER=$(python3 -c "import sys,json;print(json.loads(sys.argv[1])[\"u\"])" "$CRED")
  APP_PW=$(python3 -c "import sys,json;print(json.loads(sys.argv[1])[\"p\"])" "$CRED"); unset CRED
  echo "   使用帳號 $APP_USER;取得密碼(長度 ${#APP_PW} 字元;不顯示)"
  cfg=/dev/shm/client.properties                        # tmpfs:只在記憶體
  {
    echo "security.protocol=SASL_SSL"
    echo "sasl.mechanism=SCRAM-SHA-512"
    echo "sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username=\"$APP_USER\" password=\"$APP_PW\";"
    echo "ssl.truststore.location=/etc/kafka/secrets/truststore.p12"
    echo "ssl.truststore.type=PKCS12"
    echo "ssl.truststore.password=changeit"
  } > "$cfg"; chmod 600 "$cfg"; unset APP_PW
  out=$(kafka-console-producer --bootstrap-server broker1:9094 --command-config "$cfg" --topic "$TOPIC" 2>&1)   # 訊息從 stdin 的第二行起讀
  echo "$out" | grep -iE "authentication failed|authorization failed|not authorized|Exception" | grep -v "^\s*at " | head -3
  if echo "$out" | grep -qiE "authentication failed|authorization failed|not authorized"; then echo "結果:被拒絕"; exit 1; fi
  echo "結果:成功寫入 $TOPIC(以 $APP_USER 身分;連線設定只存在 /dev/shm,容器結束即消失)"'
