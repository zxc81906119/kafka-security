#!/usr/bin/env bash
# 維運選單「候選新項目」的可行性探測(2026-10-06):每個項目用 User:ming 暫綁一種 role 試跑,看 RBAC 下誰做得到;測完全部解除。
# 只用拋棄式的 topic / group / 帳號(名稱前綴 optest);不碰 _confluent-metadata-auth、__consumer_offsets 等真實內部 topic。
cd "$(dirname "$0")/../.."
source scripts/rbac-lib.sh
export MSYS_NO_PATHCONV=1
BOOT=broker1:9094; P=/clients/plain-ming.properties; B=/clients/token-bootstrap.properties
K() { scripts/k.sh "$@" 2>&1 | grep -v -E '^(WARNING|SLF4J)|^\s+at |^\s*$|KIP-848|deprecated' | cut -c1-200; }
sec() { echo; echo "===== $*"; }
asm() { K "$1" --bootstrap-server $BOOT --command-config $P "${@:2}"; }          # 以 ming 執行
asb() { K "$1" --bootstrap-server $BOOT --command-config $B "${@:2}"; }          # 以 bootstrap 執行
res() { # res <結果> —— 把輸出歸類成 通過 / 被拒 / 其他
  local o; o=$(cat); if echo "$o" | grep -q -i "AuthorizationException\|not authorized\|authorization failed\|Cluster authorization"; then echo "  → 被拒(授權)"; elif [ -z "$o" ]; then echo "  → (無輸出)"; else echo "$o" | head -${LINES_MAX:-3} | sed 's/^/  /'; echo "  → 有結果"; fi; }

# ---- 準備:拋棄式資源 ----
asb kafka-topics --create --if-not-exists --topic optest.a --partitions 1 --replication-factor 2 >/dev/null
asb kafka-topics --create --if-not-exists --topic _optest-guard --partitions 1 --replication-factor 2 >/dev/null
asb kafka-topics --create --if-not-exists --topic optest.b --partitions 1 --replication-factor 2 >/dev/null

probe() { # probe <role 說明> —— 目前 ming 綁著的 role 下,逐項試跑只讀/可還原的候選項目
  sleep 3
  echo "-- [$1]"
  echo "  1 KRaft quorum 狀態 (kafka-metadata-quorum describe --status)"; LINES_MAX=2 asm kafka-metadata-quorum describe --status | res
  echo "  2 各 topic 容量 (kafka-log-dirs --describe)";                    LINES_MAX=1 asm kafka-log-dirs --describe --topic-list optest.a | cut -c1-120 | res
  echo "  3 partition 搬移方案(只產生方案,不執行) kafka-reassign-partitions --generate"
    echo '{"topics":[{"topic":"optest.a"}],"version":1}' > /tmp/optest-topics.json
    docker run --rm -i --network cpsec_default -v "$PWD/certs:/etc/kafka/secrets:ro" -v "$PWD/config/clients:/clients:ro" -v /tmp/optest-topics.json:/t.json:ro -e KAFKA_OPTS="" -e KAFKA_HEAP_OPTS="-Xmx256m" --entrypoint kafka-reassign-partitions confluentinc/cp-server:8.3.2 --bootstrap-server $BOOT --command-config $P --topics-to-move-json-file /t.json --broker-list 11,12 --generate 2>&1 </dev/null | grep -v -E '^(WARNING|SLF4J)|^\s*$' | head -2 | cut -c1-120 | res
  echo "  4 preferred leader 選舉 (kafka-leader-election --election-type preferred --all-topic-partitions)"; LINES_MAX=2 asm kafka-leader-election --election-type preferred --all-topic-partitions | res
  echo "  5 增加分割區 (kafka-topics --alter --partitions 2 on optest.a)";  asm kafka-topics --alter --topic optest.a --partitions 2 | res
  echo "  6 client quota 設定 (producer_byte_rate on client optest)";       asm kafka-configs --alter --entity-type clients --entity-name optest --add-config producer_byte_rate=1048576 | res
  asb kafka-configs --alter --entity-type clients --entity-name optest --delete-config producer_byte_rate >/dev/null 2>&1
  echo "  7 broker log level 動態調整 (broker-loggers kafka.server.KafkaApis=DEBUG)"; asm kafka-configs --alter --entity-type broker-loggers --entity-name 11 --add-config kafka.server.KafkaApis=DEBUG | res
  asb kafka-configs --alter --entity-type broker-loggers --entity-name 11 --delete-config kafka.server.KafkaApis >/dev/null 2>&1
  echo "  8 刪除 consumer group (optest-g,拋棄式)"; asm kafka-consumer-groups --delete --group optest-g | res
  echo "  9 刪除底線開頭的非內部 topic (_optest-guard)";                     asm kafka-topics --delete --topic _optest-guard | res
  asb kafka-topics --create --if-not-exists --topic _optest-guard --partitions 1 --replication-factor 2 >/dev/null 2>&1
}

for r in "Operator|Operator" "ResourceOwner Topic*+Group*|RO" "ClusterAdmin|ClusterAdmin"; do
  name="${r%%|*}"; kind="${r##*|}"
  sec "ming = $name"
  case $kind in
    Operator)     rbac_bind cert bootstrap User:ming Operator >/dev/null;;
    RO)           rbac_bind cert bootstrap User:ming ResourceOwner Topic '*' LITERAL >/dev/null; rbac_bind cert bootstrap User:ming ResourceOwner Group '*' LITERAL >/dev/null;;
    ClusterAdmin) rbac_bind cert bootstrap User:ming ClusterAdmin >/dev/null;;
  esac
  probe "$name"
  case $kind in
    Operator)     rbac_unbind cert bootstrap User:ming Operator >/dev/null;;
    RO)           rbac_unbind cert bootstrap User:ming ResourceOwner Topic '*' LITERAL >/dev/null; rbac_unbind cert bootstrap User:ming ResourceOwner Group '*' LITERAL >/dev/null;;
    ClusterAdmin) rbac_unbind cert bootstrap User:ming ClusterAdmin >/dev/null;;
  esac
done

sec "SCRAM 密碼改用檔案傳入(避免出現在 ps):kafka-configs --add-config-file"
printf 'SCRAM-SHA-512=[password=optest-file-pw]\n' > /tmp/optest-scram.properties
docker run --rm -i --network cpsec_default -v "$PWD/certs:/etc/kafka/secrets:ro" -v "$PWD/config/clients:/clients:ro" -v /tmp/optest-scram.properties:/s.properties:ro -e KAFKA_OPTS="" -e KAFKA_HEAP_OPTS="-Xmx256m" --entrypoint kafka-configs confluentinc/cp-server:8.3.2 --bootstrap-server $BOOT --command-config $B --alter --add-config-file /s.properties --entity-type users --entity-name optest-svc 2>&1 </dev/null | grep -v -E '^(WARNING|SLF4J)|^\s*$' | head -3 | cut -c1-160
echo "  → 密碼是否真的設成功(用該帳號 SCRAM 連線列 topic):"
printf 'security.protocol=SASL_SSL\nsasl.mechanism=SCRAM-SHA-512\nsasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="optest-svc" password="optest-file-pw";\nssl.truststore.location=/etc/kafka/secrets/truststore.p12\nssl.truststore.password=changeit\n' > config/clients/scram-optest.properties
K kafka-topics --bootstrap-server $BOOT --command-config /clients/scram-optest.properties --list | head -2 | res
asb kafka-configs --alter --delete-config SCRAM-SHA-512 --entity-type users --entity-name optest-svc >/dev/null 2>&1

sec "MDS:依 role 反查有哪些主體(定期權限覆核用)"
scripts/mds.sh cert bootstrap POST "/security/1.0/lookup/role/DeveloperRead" "{\"clusters\":{\"kafka-cluster\":\"$KAFKA_CLUSTER_ID\"}}" | cut -c1-300 | head -3
scripts/mds.sh cert bootstrap POST "/security/1.0/lookup/role/SystemAdmin" "{\"clusters\":{\"kafka-cluster\":\"$KAFKA_CLUSTER_ID\"}}" | cut -c1-300 | head -3

sec "收尾:刪拋棄式資源"
for t in optest.a optest.b _optest-guard; do asb kafka-topics --delete --topic $t >/dev/null 2>&1; done
asb kafka-configs --alter --delete-config SCRAM-SHA-512 --entity-type users --entity-name optest-svc >/dev/null 2>&1
echo "ming 的 role(應為空):"; scripts/mds.sh cert bootstrap POST "/security/1.0/lookup/principals/User%3Aming/roleNames" "{\"clusters\":{\"kafka-cluster\":\"$KAFKA_CLUSTER_ID\"}}" | head -1
