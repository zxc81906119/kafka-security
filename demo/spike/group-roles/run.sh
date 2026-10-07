#!/usr/bin/env bash
# 群組與 role 自檢的實測(2026-10-06):
#  T0 lookup roleNames 是否會把 AD 群組的 role 一併算進去(第二人資格檢查要用)
#  T1 AuditAdmin 能不能讀 audit topic;加 DeveloperRead(Topic + Group)後能不能
#  T2 ResourceOwner(Topic *、Group *)能做哪些 topic 作業;能不能建 SCRAM;ClusterAdmin 能不能建 SCRAM
#  T3 元件主體(c3、restproxy)現有的 role binding
# 全程用 User:ming(沒有其他 role),測完解除。
cd "$(dirname "$0")/../.."
source scripts/rbac-lib.sh
BOOT=broker1:9094; K() { scripts/k.sh "$@" 2>&1 | grep -v -E '^(WARNING|SLF4J)|^\s+at |^\s*$' | cut -c1-220; }
CL="{\"clusters\":{\"kafka-cluster\":\"$KAFKA_CLUSTER_ID\"}}"
sec() { echo; echo "===== $*"; }
lookup() { scripts/mds.sh cert bootstrap POST "/security/1.0/lookup/principals/$1/roleNames" "$CL"; }
AUD=confluent-audit-log-events

sec "T0 roleNames:gary(經 Group:kafka-admins 拿 SystemAdmin)/ ming(應為空)"
lookup User%3Agary; lookup User%3Aming
sec "T0b 用 ming 自己的 token 查自己(第二人檢查會這樣查)"
scripts/mds.sh basic ming:ming-pw POST "/security/1.0/lookup/principals/User%3Aming/roleNames" "$CL"

sec "T1a ming 只有 AuditAdmin → 讀 audit topic"
rbac_bind cert bootstrap User:ming AuditAdmin
sleep 3
K kafka-console-consumer --bootstrap-server $BOOT --command-config /clients/plain-ming.properties --topic $AUD --from-beginning --max-messages 1 --timeout-ms 12000 --group audit-ming | tail -3
sec "T1b 加 DeveloperRead Topic $AUD + Group audit- → 讀 audit topic"
rbac_bind cert bootstrap User:ming DeveloperRead Topic $AUD LITERAL
rbac_bind cert bootstrap User:ming DeveloperRead Group audit- PREFIXED
sleep 3
K kafka-console-consumer --bootstrap-server $BOOT --command-config /clients/plain-ming.properties --topic $AUD --from-beginning --max-messages 1 --timeout-ms 12000 --group audit-ming | cut -c1-120 | tail -3
rbac_unbind cert bootstrap User:ming AuditAdmin
rbac_unbind cert bootstrap User:ming DeveloperRead Topic $AUD LITERAL
rbac_unbind cert bootstrap User:ming DeveloperRead Group audit- PREFIXED

sec "T2a ming = ResourceOwner Topic * + Group *"
rbac_bind cert bootstrap User:ming ResourceOwner Topic '*' LITERAL
rbac_bind cert bootstrap User:ming ResourceOwner Group '*' LITERAL
sleep 3
P=/clients/plain-ming.properties
echo "-- 建 topic";   K kafka-topics --bootstrap-server $BOOT --command-config $P --create --topic spk.ro --partitions 1 --replication-factor 1 | tail -2
echo "-- 改設定";     K kafka-configs --bootstrap-server $BOOT --command-config $P --alter --entity-type topics --entity-name spk.ro --add-config retention.ms=3600000 | tail -2
echo "-- 讀設定";     K kafka-configs --bootstrap-server $BOOT --command-config $P --describe --entity-type topics --entity-name spk.ro | tail -2
echo "-- 重設 offset";K kafka-consumer-groups --bootstrap-server $BOOT --command-config $P --group spk-g --topic spk.ro --reset-offsets --to-earliest --execute | tail -2
echo "-- 刪 group";   K kafka-consumer-groups --bootstrap-server $BOOT --command-config $P --delete --group spk-g | tail -2
echo "-- 刪 topic";   K kafka-topics --bootstrap-server $BOOT --command-config $P --delete --topic spk.ro | tail -2
echo "-- 建 SCRAM(預期被拒)"; K kafka-configs --bootstrap-server $BOOT --command-config $P --alter --add-config 'SCRAM-SHA-512=[password=x]' --entity-type users --entity-name svc-spk | tail -2
echo "-- 改 broker 動態設定(預期被拒)"; K kafka-configs --bootstrap-server $BOOT --command-config $P --alter --entity-type brokers --entity-default --add-config log.cleaner.threads=1 | tail -2
rbac_unbind cert bootstrap User:ming ResourceOwner Topic '*' LITERAL
rbac_unbind cert bootstrap User:ming ResourceOwner Group '*' LITERAL

sec "T2b ming = ClusterAdmin"
rbac_bind cert bootstrap User:ming ClusterAdmin
sleep 3
echo "-- 建 SCRAM";  K kafka-configs --bootstrap-server $BOOT --command-config $P --alter --add-config 'SCRAM-SHA-512=[password=x]' --entity-type users --entity-name svc-spk | tail -2
echo "-- 刪 SCRAM";  K kafka-configs --bootstrap-server $BOOT --command-config $P --alter --delete-config SCRAM-SHA-512 --entity-type users --entity-name svc-spk | tail -2
echo "-- 建 topic";  K kafka-topics --bootstrap-server $BOOT --command-config $P --create --topic spk.ca --partitions 1 --replication-factor 1 | tail -2
echo "-- 刪 topic";  K kafka-topics --bootstrap-server $BOOT --command-config $P --delete --topic spk.ca | tail -2
echo "-- 讀 audit topic(預期被拒)"; K kafka-console-consumer --bootstrap-server $BOOT --command-config $P --topic $AUD --from-beginning --max-messages 1 --timeout-ms 10000 --group audit-ming | tail -2
rbac_unbind cert bootstrap User:ming ClusterAdmin

sec "T3 元件主體的 binding"
for p in User%3Ac3 User%3Arestproxy; do echo "-- $p"; lookup $p; scripts/mds.sh cert bootstrap POST "/security/1.0/lookup/rolebindings/principal/$p" "$CL" | cut -c1-400; done

sec "收尾:ming 應沒有任何 role"
lookup User%3Aming
