#!/usr/bin/env bash
# run.sh 裡兩項因掛載路徑錯誤而無效的探測,修正後重跑:partition 搬移方案(--generate)、SCRAM 密碼用檔案傳入(--add-config-file)
cd "$(dirname "$0")/../.."
source scripts/rbac-lib.sh
export MSYS_NO_PATHCONV=1
D="$(pwd -W 2>/dev/null || pwd)"; W="$D/spike/ops-items/work"; mkdir -p spike/ops-items/work
BOOT=broker1:9094; P=/clients/plain-ming.properties; B=/clients/token-bootstrap.properties
echo '{"topics":[{"topic":"optest.a"}],"version":1}' > spike/ops-items/work/topics.json
printf 'SCRAM-SHA-512=[password=optest-file-pw]\n' > spike/ops-items/work/scram.properties
KW() { docker run --rm --network cpsec_default -v "$D/certs:/etc/kafka/secrets:ro" -v "$D/config/clients:/clients:ro" -v "$W:/w:ro" -e KAFKA_OPTS="" -e KAFKA_HEAP_OPTS="-Xmx256m" --entrypoint "$1" confluentinc/cp-server:8.3.2 "${@:2}" 2>&1 </dev/null | grep -v -E '^(WARNING|SLF4J)|^\s*$|KIP-848|deprecated' | cut -c1-170; }

scripts/k.sh kafka-topics --bootstrap-server $BOOT --command-config $B --create --if-not-exists --topic optest.a --partitions 1 --replication-factor 2 >/dev/null 2>&1

echo "===== partition 搬移方案(kafka-reassign-partitions --generate,只產生不執行)"
for r in "Operator|Operator" "ResourceOwner Topic*+Group*|RO" "ClusterAdmin|ClusterAdmin"; do
  name="${r%%|*}"; kind="${r##*|}"
  case $kind in Operator) rbac_bind cert bootstrap User:ming Operator >/dev/null;; RO) rbac_bind cert bootstrap User:ming ResourceOwner Topic '*' LITERAL >/dev/null;; ClusterAdmin) rbac_bind cert bootstrap User:ming ClusterAdmin >/dev/null;; esac
  sleep 3; echo "-- [ming = $name]"
  KW kafka-reassign-partitions --bootstrap-server $BOOT --command-config $P --topics-to-move-json-file /w/topics.json --broker-list 11,12 --generate | head -3
  case $kind in Operator) rbac_unbind cert bootstrap User:ming Operator >/dev/null;; RO) rbac_unbind cert bootstrap User:ming ResourceOwner Topic '*' LITERAL >/dev/null;; ClusterAdmin) rbac_unbind cert bootstrap User:ming ClusterAdmin >/dev/null;; esac
done

echo; echo "===== SCRAM 密碼用檔案傳入(--add-config-file;密碼不會出現在 ps 的命令列)"
KW kafka-configs --bootstrap-server $BOOT --command-config $B --alter --add-config-file /w/scram.properties --entity-type users --entity-name optest-svc | head -3
printf 'security.protocol=SASL_SSL\nsasl.mechanism=SCRAM-SHA-512\nsasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="optest-svc" password="optest-file-pw";\nssl.truststore.location=/etc/kafka/secrets/truststore.p12\nssl.truststore.password=changeit\n' > config/clients/scram-optest.properties
echo "-- 用檔案設的密碼登入(通過 = 沒有 Authentication failed 字樣):"
out=$(scripts/k.sh kafka-topics --bootstrap-server $BOOT --command-config /clients/scram-optest.properties --list 2>&1); if echo "$out" | grep -q -i "Authentication failed"; then echo "  ✘ 登入失敗"; else echo "  ✔ 登入成功(帳號沒有 role,清單為空是正常的)"; fi
echo "-- 用錯的密碼登入(應失敗):"
sed -i 's/optest-file-pw/wrong-pw/' config/clients/scram-optest.properties
out=$(scripts/k.sh kafka-topics --bootstrap-server $BOOT --command-config /clients/scram-optest.properties --list 2>&1); if echo "$out" | grep -q -i "Authentication failed"; then echo "  ✔ 被拒(Authentication failed)"; else echo "  ✘ 竟然成功"; fi

echo; echo "===== 收尾"
scripts/k.sh kafka-configs --bootstrap-server $BOOT --command-config $B --alter --delete-config SCRAM-SHA-512 --entity-type users --entity-name optest-svc >/dev/null 2>&1
scripts/k.sh kafka-topics --bootstrap-server $BOOT --command-config $B --delete --topic optest.a >/dev/null 2>&1
echo "ming 的 role(應為空):"; scripts/mds.sh cert bootstrap POST "/security/1.0/lookup/principals/User%3Aming/roleNames" "{\"clusters\":{\"kafka-cluster\":\"$KAFKA_CLUSTER_ID\"}}" | head -1
