#!/usr/bin/env bash
# 滾動輪替期間 producer 有沒有受影響:背景持續寫入(acks=all,冪等),同時執行資料金鑰輪替 → 兩台 broker 依序一台一台重啟。
#   比對「producer 回報送出幾筆」與「topic 實際有幾筆」,並看 producer 有沒有報錯。
#   條件:兩台 broker 都已套用 Secret Protection(scripts/secret-protection.sh join-broker1);topic 副本數 2、min.insync.replicas=1(demo 預設)。
# 用法: scripts/rolling-rotate-test.sh [筆數,預設 1200;每秒 5 筆]
set -uo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
N="${1:-1200}"; T=zdt.test
ADMIN="--bootstrap-server broker1:9094 --command-config /clients/token-bootstrap.properties"
OUT=$(mktemp)
./scripts/k.sh kafka-topics $ADMIN --delete --topic $T >/dev/null 2>&1; sleep 2
./scripts/k.sh kafka-topics $ADMIN --create --topic $T --partitions 3 --replication-factor 2 2>&1 | grep -E "Created|rror"
echo "① 背景 producer:$N 筆、每秒 5 筆、acks=all、冪等;同時輪替資料金鑰並滾動重啟 broker1 → broker2"
./scripts/k.sh kafka-producer-perf-test --topic $T --num-records "$N" --throughput 5 --record-size 100 --producer.config /clients/token-bootstrap.properties \
  --producer-props bootstrap.servers=broker1:9094,broker2:9094 acks=all enable.idempotence=true > "$OUT" 2>&1 &
PP=$!
sleep 15
bash scripts/secret-protection.sh rotate-data 2>&1 | grep -E "重啟|登入|變動行數|判定" | sed 's/^/   /'
echo "② 等 producer 寫完…"; wait $PP
sent=$(grep -oE '^[0-9]+ records sent' "$OUT" | tail -1 | awk '{print $1}')
warns=$(grep -ciE "WARN|Connection to node|NOT_LEADER|disconnected" "$OUT" || true)
fails=$(grep -cE "ERROR|Expiring|expired|Failed to send" "$OUT" || true)
echo "   producer 的警告(重試、換 leader、斷線重連,屬正常)前幾種:"
grep -iE "WARN|Connection to node|NOT_LEADER|disconnected" "$OUT" | sed -E 's/^\[[^]]*\] //' | cut -c1-120 | sort | uniq -c | sort -rn | head -3 | sed 's/^/     /'
have=$(./scripts/k.sh kafka-get-offsets $ADMIN --topic $T 2>/dev/null | awk -F: '{s+=$3} END {print s+0}')
echo "   producer 回報送出 ${sent:-?} 筆;topic 實際 ${have} 筆;送出失敗 ${fails} 筆;警告行 ${warns}"
./scripts/k.sh kafka-topics $ADMIN --delete --topic $T >/dev/null 2>&1; rm -f "$OUT"
if [ -n "${sent:-}" ] && [ "$sent" = "$N" ] && [ "$have" = "$N" ] && [ "$fails" = 0 ]; then
  echo "判定:滾動重啟期間 producer 零送出失敗、零遺失(送出 $N 筆 = topic $N 筆)"
else
  echo "判定:不符合(送出 ${sent:-?}、topic ${have}、送出失敗 ${fails})"
fi
