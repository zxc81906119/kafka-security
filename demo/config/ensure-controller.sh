#!/usr/bin/env bash
# 取代 cp-server 映像的 /etc/confluent/docker/ensure:
# KRaft controller 首次 format 時,以 --add-scram 預先建立 SCRAM 憑證(須在 broker 啟動前完成):
#   kafka-broker、kafka-controller = 內部通道。bootstrap 不建 SCRAM 帳號:只用 client 憑證(對 broker 先向 MDS 換 token)
. /etc/confluent/docker/bash-config

export KAFKA_DATA_DIRS=${KAFKA_DATA_DIRS:-"/var/lib/kafka/data"}
echo "===> Check if $KAFKA_DATA_DIRS is writable ..."
ub path "$KAFKA_DATA_DIRS" writable

ARGS=()
for v in $(env | grep '^SCRAM_BOOTSTRAP_' | cut -d= -f1 | sort); do ARGS+=(--add-scram "${!v}"); done
echo "===> Using provided cluster id $CLUSTER_ID (with ${#ARGS[@]} x --add-scram args) ..."
result=$(kafka-storage format --cluster-id=$CLUSTER_ID -c /etc/kafka/kafka.properties "${ARGS[@]}" 2>&1) || \
    echo $result | grep -i "already formatted" || \
    { echo $result && (exit 1) }
echo "$result" | grep -i -E "scram|Formatting|already" | cut -c1-120
