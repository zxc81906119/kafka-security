#!/usr/bin/env bash
# 第 20 章:上線前的檢查習慣——欄位到底有沒有被加密?不要只看 producer 沒報錯,直接讀 topic 的原始位元組。
#   ① 以 svc-orders(SCRAM,不受前面章節的 role 變動影響;Schema Registry 的帳密用 yujie)用 Avro(Schema Registry 的 orders.events-value v1)寫一筆含卡號的訂單;
#   ② 以 bootstrap 身分用一般 console consumer 讀原始位元組,找卡號字串。
#   在這個環境(CSFLE 沒有授權、schema 沒有加密規則)會看到明文——這就是「規則沒生效」時 topic 裡的樣子。
# 用法: scripts/sr-raw-check.sh [卡號,預設 5500-0000-0000-0004]
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
D="$(pwd -W 2>/dev/null || pwd)"
CARD="${1:-5500-0000-0000-0004}"; ID="raw-$RANDOM"
echo "① svc-orders(SCRAM)以 Avro 寫入(schema 註冊資訊用 yujie 讀) orders.events:{id:$ID, card_no:$CARD}"
# 帳密從 stdin 進容器;連線設定只放 /dev/shm
printf 'yujie-pw\n' | docker run --rm -i --network cpsec_default -v "$D/certs:/etc/kafka/secrets:ro" -v "$D/config/clients:/clients:ro" -e KAFKA_OPTS="" -e KAFKA_HEAP_OPTS="-Xmx256m" -e ID="$ID" -e CARD="$CARD" --entrypoint bash confluentinc/cp-schema-registry:8.3.2 -c '
  IFS= read -r PW
  echo "{\"id\":\"$ID\",\"amount\":250,\"card_no\":\"$CARD\"}" | kafka-avro-console-producer --bootstrap-server broker1:9094 --producer.config /clients/scram-svc-orders.properties --topic orders.events \
    --property schema.registry.url=https://schema-registry:8081 \
    --property schema.registry.ssl.truststore.location=/etc/kafka/secrets/truststore.p12 --property schema.registry.ssl.truststore.type=PKCS12 --property schema.registry.ssl.truststore.password=changeit \
    --property basic.auth.credentials.source=USER_INFO --property basic.auth.user.info=yujie:$PW \
    --property auto.register.schemas=false --property use.latest.version=true \
    --property value.schema="{\"type\":\"record\",\"name\":\"Order\",\"namespace\":\"demo\",\"fields\":[{\"name\":\"id\",\"type\":\"string\"},{\"name\":\"amount\",\"type\":\"int\"},{\"name\":\"card_no\",\"type\":\"string\",\"confluent:tags\":[\"PII\"]}]}" > /tmp/out.txt 2>&1 \
    && { echo "   寫入完成(producer 沒有報錯)"; grep -E "Exception|Error|error" /tmp/out.txt | head -4 | cut -c1-200 | sed "s/^/   [producer] /"; } || { echo "   寫入失敗:"; grep -E "Exception|error_code" /tmp/out.txt | head -3; exit 1; }'
echo "② 用一般 console consumer(bootstrap 身分)讀 orders.events 的原始位元組,找這一筆:"
raw=$(./scripts/k.sh kafka-console-consumer --bootstrap-server broker1:9094 --command-config /clients/token-bootstrap.properties --topic orders.events --group "raw-$RANDOM" --from-beginning --timeout-ms 10000 2>/dev/null | grep -a "$ID" | head -1 | tr -d "\0")
printf '%s' "$raw" | od -c | head -3 | sed 's/^/   /'
if printf '%s' "$raw" | grep -aq "$CARD"; then echo "判定:topic 裡的卡號是明文(欄位沒有被加密)—— 這個環境沒有 CSFLE 授權,規則不存在;正式環境若看到明文,代表加密規則沒生效"; else echo "判定:topic 裡找不到明文卡號(欄位已加密或這筆沒寫入)"; fi
