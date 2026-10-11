#!/usr/bin/env bash
# 取代 cp-server 映像的 /etc/confluent/docker/ensure:KRaft controller 首次 format。
# 白話:這個叢集一開始就是「動態 quorum」(官方建議的正式環境做法):
#   · 前三台 controller 用同一份 --initial-controllers(id@host:port:directoryId,三台必須一模一樣)一次格式化成 voter;
#   · 之後要汰換 controller:新節點用 QUORUM_FORMAT_FLAG=--no-initial-controllers 格式化,再 add-controller(第 33 章)。
# 同時以 --add-scram 預先建立 SCRAM 憑證(須在 broker 啟動前完成):
#   kafka-broker、kafka-controller = 內部通道(內部通道已改 mTLS,不再使用;kafka-broker 仍給維運與測試用 CLIENT listener 的 SCRAM 登入)。
#   bootstrap 不建 SCRAM 帳號:只用 client 憑證(對 broker 先向 MDS 換 token)
. /etc/confluent/docker/bash-config

export KAFKA_DATA_DIRS=${KAFKA_DATA_DIRS:-"/var/lib/kafka/data"}
echo "===> Check if $KAFKA_DATA_DIRS is writable ..."
ub path "$KAFKA_DATA_DIRS" writable

# 已經格式化過就不再呼叫 format:動態 quorum 沒有 controller.quorum.voters 時,format 會先要求旗標才檢查「已格式化」,
# 重啟就失敗(實測:controller 重啟起不來)。VM 上 systemd 流程只在安裝時 format 一次,不會遇到;容器每次啟動都跑 ensure,所以要擋。
if [ -f "$KAFKA_DATA_DIRS/meta.properties" ]; then
  echo "===> $KAFKA_DATA_DIRS already formatted, skip format"
  exit 0
fi

ARGS=()
for v in $(env | grep "^SCRAM_BOOTSTRAP_" | cut -d= -f1 | sort); do [ -n "${!v}" ] && ARGS+=(--add-scram "${!v}"); done

FMT=()
if [ -n "${QUORUM_FORMAT_FLAG:-}" ]; then
  FMT=("$QUORUM_FORMAT_FLAG")                                     # 新加入的 controller:--no-initial-controllers
elif [ -n "${QUORUM_INITIAL_CONTROLLERS:-}" ]; then
  FMT=(--initial-controllers "$QUORUM_INITIAL_CONTROLLERS")       # 初始三台:同一份名單
fi
echo "===> Using provided cluster id $CLUSTER_ID (${FMT[*]:-no quorum flag}; ${#ARGS[@]} x --add-scram args) ..."
result=$(kafka-storage format --cluster-id=$CLUSTER_ID -c /etc/kafka/kafka.properties "${FMT[@]}" "${ARGS[@]}" 2>&1) || \
    echo $result | grep -i "already formatted" || \
    { echo $result && (exit 1) }
echo "$result" | grep -i -E "scram|Formatting|already" | cut -c1-120
