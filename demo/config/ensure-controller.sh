#!/usr/bin/env bash
# 取代 cp-server 映像的 /etc/confluent/docker/ensure:
# KRaft controller 首次 format 時,以 --add-scram 預先建立 SCRAM 憑證(須在 broker 啟動前完成):
#   kafka-broker、kafka-controller = 內部通道。bootstrap 不建 SCRAM 帳號:只用 client 憑證(對 broker 先向 MDS 換 token)
. /etc/confluent/docker/bash-config

export KAFKA_DATA_DIRS=${KAFKA_DATA_DIRS:-"/var/lib/kafka/data"}
echo "===> Check if $KAFKA_DATA_DIRS is writable ..."
ub path "$KAFKA_DATA_DIRS" writable

ARGS=()
for v in $(env | grep "^SCRAM_BOOTSTRAP_" | cut -d= -f1 | sort); do [ -n "${!v}" ] && ARGS+=(--add-scram "${!v}"); done
echo "===> Using provided cluster id $CLUSTER_ID (with ${#ARGS[@]} x --add-scram args) ..."
# 動態 quorum(第 33 章):新加入的 controller 用 QUORUM_FORMAT_FLAG=--no-initial-controllers 格式化(不自己當初始成員,
# 由既有 quorum 的 leader 加入);沒設就維持原本做法(靜態 quorum 或 --add-scram 初始化)。
FMT=(); [ -n "${QUORUM_FORMAT_FLAG:-}" ] && FMT=("$QUORUM_FORMAT_FLAG")
# 已經格式化過就不再呼叫 format:動態 quorum 沒有 controller.quorum.voters 時,format 會先要求旗標才檢查「已格式化」,
# 重啟就失敗(實測:升級成動態後 controller 重啟起不來)。
if [ -f "$KAFKA_DATA_DIRS/meta.properties" ]; then
  echo "===> $KAFKA_DATA_DIRS already formatted, skip format"
  exit 0
fi
result=$(kafka-storage format --cluster-id=$CLUSTER_ID -c /etc/kafka/kafka.properties "${FMT[@]}" "${ARGS[@]}" 2>&1) || \
    echo $result | grep -i "already formatted" || \
    { echo $result && (exit 1) }
echo "$result" | grep -i -E "scram|Formatting|already" | cut -c1-120
