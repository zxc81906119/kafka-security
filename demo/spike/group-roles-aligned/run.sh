#!/usr/bin/env bash
# 對齊後的 7 組:臨時加入各群組後,實際能做什麼?(第 11 章劇情依據)。在 demo/ 目錄執行。
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/../.."
source scripts/rbac-lib.sh
BOOT=broker1:9094
CLJ='{"clusters":{"kafka-cluster":"XyZBQ3-GTvKH2qNfP7X33A"}}'
BIND='{"scope":{"clusters":{"kafka-cluster":"XyZBQ3-GTvKH2qNfP7X33A"}},"resourcePatterns":[{"resourceType":"Topic","name":"infra.","patternType":"PREFIXED"}]}'
sec() { echo; echo "===== $*"; }
kt() { ./scripts/k.sh kafka-topics --bootstrap-server $BOOT --command-config "/clients/plain-$1.properties" "${@:2}" 2>&1 | grep -v '^SLF4J\|^WARNING\|is deprecated' | head -${LINES_MAX:-3} | cut -c1-170; }
cons() { ./scripts/k.sh kafka-console-consumer --bootstrap-server $BOOT --command-config "/clients/plain-$1.properties" --topic "$2" --group "demo-$1-x" --from-beginning --max-messages 1 --timeout-ms 8000 2>&1 | grep -v '^SLF4J\|^WARNING' | head -2 | cut -c1-170; }
mdsb() { ./scripts/mds.sh basic "$1:$1-pw" POST /security/1.0/principals/Group%3Aorders-write/roles/DeveloperRead/bindings "$BIND" 2>&1 | tail -1 | cut -c1-120; }
g() { ./scripts/ldap-group.sh "$@" >/dev/null 2>&1; }

bash scripts/reset.sh >/dev/null 2>&1
# 先放一筆資料到 infra.exp-data(gary = topic-admin + …),讓「讀不讀得到」只取決於權限
./scripts/k.sh kafka-topics --bootstrap-server $BOOT --command-config /clients/plain-gary.properties --create --if-not-exists --topic infra.exp-data --partitions 1 --replication-factor 2 >/dev/null 2>&1
echo '{"d":"secret-1"}' | ./scripts/k.sh kafka-console-producer --bootstrap-server $BOOT --command-config /clients/plain-gary.properties --topic infra.exp-data >/dev/null 2>&1
sleep 6

sec "E1 yujie 加入 ops(Operator)"
g add yujie ops; sleep 12
echo "-- 建 topic:";           kt yujie --create --topic infra.exp1 --partitions 1 --replication-factor 2
echo "-- 列出 topic:";         LINES_MAX=3 kt yujie --list
echo "-- 看 under-replicated:"; LINES_MAX=3 kt yujie --describe --under-replicated-partitions; echo "(exit $?)"
echo "-- 讀 infra.exp-data:";  cons yujie infra.exp-data
echo "-- 改授權(MDS):";        mdsb yujie
g remove yujie ops; sleep 8

sec "E2 yujie 加入 topic-admin(ResourceOwner Topic*、Group*)"
g add yujie topic-admin; sleep 12
echo "-- 建 topic:";           kt yujie --create --topic infra.exp2 --partitions 1 --replication-factor 2
echo "-- 讀 infra.exp-data:";  cons yujie infra.exp-data
echo "-- 改授權(MDS,範圍在她的 Topic* 內):"; mdsb yujie
echo "-- 清掉她剛綁的:"; ./scripts/mds.sh cert bootstrap DELETE /security/1.0/principals/Group%3Aorders-write/roles/DeveloperRead/bindings "$BIND" 2>&1 | tail -1 | cut -c1-80
echo "-- 刪 topic:";           kt yujie --delete --topic infra.exp2
g remove yujie topic-admin; sleep 8

sec "E3 ming 加入 rbac-admin(UserAdmin)"
g add ming rbac-admin; sleep 12
echo "-- 改授權(MDS):";        mdsb ming
echo "-- 清掉:"; ./scripts/mds.sh cert bootstrap DELETE /security/1.0/principals/Group%3Aorders-write/roles/DeveloperRead/bindings "$BIND" 2>&1 | tail -1 | cut -c1-80
echo "-- 建 topic:";           kt ming --create --topic infra.exp3 --partitions 1 --replication-factor 2
echo "-- 讀 infra.exp-data:";  cons ming infra.exp-data
g remove ming rbac-admin; sleep 5

sec "收尾"
./scripts/k.sh kafka-topics --bootstrap-server $BOOT --command-config /clients/plain-gary.properties --delete --topic infra.exp-data 2>&1 | tail -1 | cut -c1-100
bash scripts/reset.sh >/dev/null 2>&1; echo done
