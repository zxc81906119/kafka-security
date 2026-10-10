#!/usr/bin/env bash
# ============================================================================
# schema-produce.sh — 在 cp-schema-registry 映像「裡面」執行的小程式:用 kafka-avro-console-producer 寫一筆 Avro
# ----------------------------------------------------------------------------
# 白話:Avro 寫入要用映像內的 kafka-avro-console-producer。這支腳本由 schema-lab.sh 掛進容器後執行,
#   不是直接在主機上跑;帳密不放指令列,密碼從標準輸入讀入。
# 用法:(由 schema-lab.sh 呼叫,不手動執行)
#   輸入(環境變數):TOPIC、SRUSER(Schema Registry 的 AD 帳號)、RECORD(JSON 一行)、SCHEMA(Avro schema)、EXTRA(額外的 --property 參數)
#   標準輸入第一行:Schema Registry 帳號的密碼(不放在指令列)
#   寫入端連 Kafka 用 svc-orders 的 SCRAM(/clients/scram-svc-orders.properties)。
# 會改動什麼:對 TOPIC 寫入一筆 Avro 訊息(可能順帶註冊 schema,依 EXTRA 而定)。
# 怎麼判斷成功:沒有 Exception、結束碼 0;失敗時錯誤訊息直接印在輸出。
# ============================================================================
IFS= read -r PW
# shellcheck disable=SC2086
echo "$RECORD" | kafka-avro-console-producer --bootstrap-server broker1:9094 --producer.config /clients/scram-svc-orders.properties --topic "$TOPIC" \
  --property schema.registry.url=https://schema-registry:8081 \
  --property schema.registry.ssl.truststore.location=/etc/kafka/secrets/truststore.p12 --property schema.registry.ssl.truststore.type=PKCS12 \
  --property schema.registry.ssl.truststore.password=changeit \
  --property basic.auth.credentials.source=USER_INFO --property "basic.auth.user.info=$SRUSER:$PW" \
  --property "value.schema=$SCHEMA" $EXTRA
