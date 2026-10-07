#!/usr/bin/env bash
U="$1"; P="$2"; C=$(mktemp); trap 'rm -f $C' EXIT
cat > $C <<EOC
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="$U" password="$P";
ssl.truststore.location=/etc/kafka/secrets/truststore.p12
ssl.truststore.type=PKCS12
ssl.truststore.password=$(cat /etc/kafka/secrets/truststore_creds)
EOC
export KAFKA_HEAP_OPTS=-Xmx256m
echo "-- describe configs broker 11"; kafka-configs --bootstrap-server broker1:9094 --command-config $C --entity-type brokers --entity-name 11 --describe --all 2>&1 | grep -v '^SLF4J' | grep -E 'log.dirs|rror|uthoriz|xception' | head -3 | cut -c1-200
echo "-- describe cluster"; kafka-metadata-quorum --bootstrap-server broker1:9094 --command-config $C describe --status 2>&1 | grep -E 'rror|uthoriz|LeaderId' | head -2 | cut -c1-200
