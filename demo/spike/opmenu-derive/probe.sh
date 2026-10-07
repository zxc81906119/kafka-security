#!/usr/bin/env bash
# 探測:哪些設定可以從叢集本身推算出來。在 rocky-jump 容器內執行:  probe.sh <AD 帳號> <密碼>
# 只做唯讀查詢。用不同權限的帳號跑,看哪些探測在最低權限下仍然可行。
U="$1"; P="$2"
CA=/etc/kafka/secrets/ca.pem
TS=/etc/kafka/secrets/truststore.p12
TSP=$(cat /etc/kafka/secrets/truststore_creds)
BS=broker1:9094,broker2:9094
CONF=$(mktemp)
trap 'rm -f "$CONF"' EXIT
cat > "$CONF" <<EOC
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="$U" password="$P";
ssl.truststore.location=$TS
ssl.truststore.type=PKCS12
ssl.truststore.password=$TSP
EOC
export KAFKA_HEAP_OPTS=-Xmx256m
q() { "$@" 2>&1 | grep -v '^SLF4J\|^WARNING\|is deprecated'; }

echo "== [1] cluster id(MDS,不帶帳密)"
curl -s -m 10 --cacert "$CA" https://broker1:8091/v1/metadata/id; echo

echo "== [2] broker 清單(kafka-broker-api-versions)"
q kafka-broker-api-versions --bootstrap-server "$BS" --command-config "$CONF" | grep -E '^[^ ]+:[0-9]+ \(id:' | cut -c1-80

echo "== [3] controller 清單(kafka-metadata-quorum --describe --status)"
q kafka-metadata-quorum --bootstrap-server "$BS" --command-config "$CONF" describe --status | grep -E 'LeaderId|CurrentVoters|CurrentObservers' | cut -c1-200

echo "== [4] broker 設定 log.dirs(kafka-configs --describe --all)"
IDS=$(q kafka-broker-api-versions --bootstrap-server "$BS" --command-config "$CONF" | grep -o '(id: [0-9]*' | grep -o '[0-9]*$')
for id in $IDS; do
  echo "-- broker $id"
  q kafka-configs --bootstrap-server "$BS" --command-config "$CONF" --entity-type brokers --entity-name "$id" --describe --all | grep -E '^ *log\.dirs|^ *advertised\.listeners|^ *node\.id' | cut -c1-200
done
