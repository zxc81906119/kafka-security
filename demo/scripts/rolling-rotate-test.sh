#!/usr/bin/env bash
# ============================================================================
# rolling-rotate-test.sh — 測試「滾動輪替」期間 producer 有沒有受影響
# ----------------------------------------------------------------------------
# 白話:Secret Protection 輪替資料金鑰後,4 台 broker 要依序一台一台重啟。這支腳本在背景持續寫入(acks=all、冪等)的同時
#   執行輪替與滾動重啟,比對「producer 回報送出幾筆」與「topic 實際有幾筆」,並看 producer 有沒有報錯,
#   證明滾動重啟期間零中斷、零遺失。
# 前置條件:4 台 broker 都已套用 Secret Protection(scripts/secret-protection.sh join-others);
#   topic 副本 3、min.insync.replicas 2(叢集預設):一次重啟一台時仍有 2 份同步副本,acks=all 寫得進去。
# 用法:
#   scripts/rolling-rotate-test.sh [筆數]    預設 2400,每秒 5 筆(約 8 分鐘)
# 會改動什麼:建立 topic zdt.test(3 分區、副本 3;開始前先刪掉舊的),寫入測試資料,結束時刪除該 topic;
#   並執行 scripts/secret-protection.sh rotate-data(資料金鑰重新輪替、certs/security.properties 被換成新檔、
#   broker1~4 依序重啟)。輪替本身不會還原。
# 怎麼判斷成功:最後一行「判定:滾動重啟期間 producer 零送出失敗、零遺失」;
#   印「判定:不符合(送出 …、topic …、送出失敗 …)」代表有遺失或失敗。
#   producer 的警告(重試、換 leader、斷線重連)屬正常,不代表失敗。
# ============================================================================
set -uo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
N="${1:-2400}"; T=zdt.test   # 每秒 5 筆約 8 分鐘,涵蓋 4 台依序重啟的時間
ADMIN="--bootstrap-server broker1:9094,broker2:9094,broker3:9094,broker4:9094 --command-config /clients/token-bootstrap.properties"
OUT=$(mktemp)
./scripts/k.sh kafka-topics $ADMIN --delete --topic $T >/dev/null 2>&1; sleep 2
./scripts/k.sh kafka-topics $ADMIN --create --topic $T --partitions 3 --replication-factor 3 2>&1 | grep -E "Created|rror"
echo "① 背景 producer:$N 筆、每秒 5 筆、acks=all、冪等;同時輪替資料金鑰並滾動重啟 broker1 → broker2 → broker3 → broker4"
./scripts/k.sh kafka-producer-perf-test --topic $T --num-records "$N" --throughput 5 --record-size 100 --producer.config /clients/token-bootstrap.properties \
  --producer-props bootstrap.servers=broker1:9094,broker2:9094,broker3:9094,broker4:9094 acks=all enable.idempotence=true > "$OUT" 2>&1 &
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
