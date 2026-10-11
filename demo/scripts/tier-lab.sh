#!/usr/bin/env bash
# ============================================================================
# tier-lab.sh — 第 32 章:Tiered Storage(舊資料放到物件儲存 MinIO)
# ----------------------------------------------------------------------------
# 白話:一般 Kafka 的資料全放在 broker 本機磁碟,保留 30 天就要買 30 天的磁碟。開了 Tiered Storage,
#   寫滿的舊 segment 會上傳到物件儲存,broker 本機只留最近一段(hotset);讀舊資料時 broker 從物件儲存取回。
#   這支腳本實際驗證:資料真的上傳、本機真的變小、從頭讀還是讀得到全部、重啟後仍讀得到,以及物件儲存的存取保護。
# 前置條件:HA 模式,且已執行 scripts/tier-setup.sh on(MinIO 啟動、broker 載入 Tiered Storage 設定)
# 用法:
#   scripts/tier-lab.sh produce    建立啟用 tier 的 topic(小 segment、本機只留 60 秒)並寫入約 100 MB;記錄本機大小
#   scripts/tier-lab.sh archive    等資料上傳:物件儲存裡出現物件(用 MinIO 管理帳號數筆數與大小)
#   scripts/tier-lab.sh evict      等本機清掉已上傳的舊 segment:本機大小明顯變小
#   scripts/tier-lab.sh read       從頭讀全部資料(舊資料從物件儲存取回):筆數不變
#   scripts/tier-lab.sh restart    重啟 broker1 後從頭再讀:資料仍在(不靠本機也讀得到)
#   scripts/tier-lab.sh security   物件儲存的保護:匿名拒絕、專用帳號只能動這個 bucket、只收 HTTPS、密碼不在日誌
# 環境變數:RECORDS=寫入筆數(預設 100000,每筆約 1 KB)
# 會改動什麼:建立 topic tier.demo(produce 時重建);restart 會重啟 broker1(等回 healthy);不改叢集設定。
# 怎麼判斷成功:每個子命令最後一行印「判定:…」。
# 常見失敗:archive 一直沒有物件 → docker logs broker1 | grep -i tier(常見:憑證檔不存在、bucket 不存在、endpoint 不通、403)
# ============================================================================
set -uo pipefail
# shellcheck disable=SC2034  # produce_test(lib/kafka.sh)會讀
PERF_OUT=/tmp/tier-lab-perf.out
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/kafka.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR" || exit 1
need_ha_mode
need_container minio "先執行:scripts/tier-setup.sh on"

TOPIC=tier.demo
RECORDS="${RECORDS:-100000}"
RECORD_SIZE=1024
BUCKET=kafka-tier
TIER_DIR=config/tier
WIN_DIR="$(pwd -W 2>/dev/null || pwd)"
MC_IMAGE=quay.io/minio/mc:latest

# ---------- 小工具(這支腳本專用) ----------

# 用 MinIO 管理帳號執行 mc:mc_root <mc 參數…>。
mc_root() {
  docker run --rm --network cpsec_default --entrypoint mc -v "$WIN_DIR/certs/ca.pem:/root/.mc/certs/CAs/ca.crt:ro" \
    -e "MC_HOST_local=https://minio-root:$(cat "$TIER_DIR/secrets/root-password")@minio:9000" "$MC_IMAGE" "$@" 2>&1
}

# 用 Kafka 專用帳號執行 mc:mc_kafka <mc 參數…>。
mc_kafka() {
  docker run --rm --network cpsec_default --entrypoint mc -v "$WIN_DIR/certs/ca.pem:/root/.mc/certs/CAs/ca.crt:ro" \
    -e "MC_HOST_local=https://kafka-tier:$(cat "$TIER_DIR/secrets/kafka-secret")@minio:9000" "$MC_IMAGE" "$@" 2>&1
}

# bucket 裡的物件數(含各 segment、index、metadata)。
objects_count() { mc_root ls --recursive "local/$BUCKET" | grep -c ' STANDARD '; }

# bucket 裡物件的總大小(MB)。
objects_mb() { mc_root du "local/$BUCKET" | awk 'NR==1 {print $1}'; }

# topic 在所有 broker 本機磁碟上的實際資料總大小(MB,每個副本都算)。
# 為什麼不用 kafka-log-dirs:它回報的是「邏輯大小」,已上傳到物件儲存的部分也算進去(實測:本機檔案已清掉,數字不變);
# 要看真正佔用的磁碟,直接量 broker 容器裡該 topic 的目錄。
local_mb() {
  local b
  for b in broker1 broker2 broker3 broker4; do
    docker ps --format '{{.Names}}' | grep -qx "$b" || continue
    docker exec "$b" sh -c "du -sm /var/lib/kafka/data/$TOPIC-* 2>/dev/null" | cut -f1
  done | awk '{s+=$1} END {print s+0}'
}

# 給 wait_until 用:bucket 裡至少有 N 個物件。
objects_at_least() { [ "$(objects_count)" -ge "$1" ]; }

# 給 wait_until 用:本機大小小於 N MB。
local_below() { local m; m=$(local_mb); [ "$m" -ge 0 ] && [ "$m" -lt "$1" ]; }

# 從頭讀 topic 全部資料,印「讀到幾筆」(consumer-perf-test,用新的 consumer group)。
read_all() {
  "$DEMO_DIR/scripts/k.sh" kafka-consumer-perf-test --bootstrap-server "$KAFKA_BOOTSTRAP" --consumer.config "$KAFKA_ADMIN_CONFIG" \
    --topic "$TOPIC" --messages "$RECORDS" --group "tier-read-$RANDOM" --timeout 60000 --reporting-interval 5000 2>&1 \
    | grep -a -E '^[0-9]{4}-' | tail -1 | awk -F', ' '{print $5}' | cut -d. -f1
}

# ---------- 各個實驗 ----------

lab_produce() {
  say "建立 topic $TOPIC:啟用 tier、segment 5 MB(小,才會很快寫滿並上傳)、本機只保留 60 秒(hotset)、整體保留 7 天"
  kafka_topics --delete --topic "$TOPIC" >/dev/null 2>&1
  kafka_topics --create --topic "$TOPIC" --partitions 3 --replication-factor 3 \
    --config min.insync.replicas=2 --config confluent.tier.enable=true --config confluent.tier.local.hotset.ms=60000 \
    --config segment.bytes=5242880 --config retention.ms=604800000 | tail -1
  say "寫入 $RECORDS 筆(每筆約 1 KB,約 100 MB)"
  local sent; sent=$(RECORD_SIZE=$RECORD_SIZE produce_test "$TOPIC" "$RECORDS" all)
  local mb; mb=$(local_mb); echo "$mb" > /tmp/tier-lab-local-before
  echo "送出 $sent 筆;topic 筆數:$(topic_message_count "$TOPIC");各副本本機總大小:$mb MB(3 個副本各一份)"
  [ "$sent" = "$RECORDS" ] && verdict "寫入完成($sent 筆);接著用 archive 看資料是否上傳"
}

lab_archive() {
  say "每 5 MB 寫滿一個 segment 就可以上傳;等物件儲存裡出現物件(用 MinIO 管理帳號看,不是 Kafka 的專用帳號)"
  wait_until "bucket 出現物件(最多 5 分鐘)" 300 objects_at_least 1 || true
  sleep 20
  echo "物件數:$(objects_count);總大小:$(objects_mb)"
  mc_root ls --recursive "local/$BUCKET" | head -4 | sed 's/^/  /' | cut -c1-150
  [ "$(objects_count)" -ge 1 ] && verdict "舊 segment 已上傳到物件儲存($(objects_count) 個物件、$(objects_mb))"
}

lab_evict() {
  local before; before=$(cat /tmp/tier-lab-local-before 2>/dev/null || local_mb)
  say "hotset 是 60 秒:上傳完成且超過 60 秒的 segment,本機會在下一輪保留檢查(log.retention.check.interval.ms,預設 5 分鐘)被清掉;等本機大小變小"
  echo "清理前(寫入完成時),各副本本機總大小:$before MB"
  wait_until "本機大小降到一半以下(最多 12 分鐘)" 720 local_below "$(( before / 2 + 1 ))" || true
  local after; after=$(local_mb)
  echo "清理後,各副本本機總大小:$after MB(物件儲存 $(objects_mb))"
  [ "$after" -ge 0 ] && [ "$after" -lt "$before" ] && [ "$(topic_message_count "$TOPIC")" = "$RECORDS" ] \
    && verdict "本機從 $before MB 降到 $after MB,topic 筆數仍是 $RECORDS(舊資料在物件儲存,不在 broker 磁碟)"
}

lab_read() {
  say "從頭讀全部資料:本機已經沒有舊 segment,broker 要從物件儲存取回"
  local n; n=$(read_all)
  echo "讀到 ${n:-0} 筆(topic 筆數 $(topic_message_count "$TOPIC"));本機總大小:$(local_mb) MB"
  [ "${n:-0}" -ge "$RECORDS" ] && verdict "從頭讀到全部 $RECORDS 筆,舊資料從物件儲存取回,本機沒有因此變大"
}

lab_restart() {
  say "重啟 broker1,再從頭讀一次:資料在物件儲存,broker 重啟不會遺失、也不用從別的副本重新複製舊資料"
  docker restart broker1 >/dev/null
  wait_healthy broker1 >/dev/null || die "broker1 沒有 healthy"
  sleep 20
  local n; n=$(read_all)
  echo "讀到 ${n:-0} 筆;broker1 本機磁碟上這個 topic 的資料量:$(docker exec broker1 sh -c "du -sm /var/lib/kafka/data/$TOPIC-* 2>/dev/null" | cut -f1 | awk '{s+=$1} END {print s+0}') MB"
  [ "${n:-0}" -ge "$RECORDS" ] && verdict "broker1 重啟後仍讀到全部 $RECORDS 筆"
}

lab_security() {
  say "物件儲存的保護:① 匿名讀取被拒 ② 專用帳號不能建立別的 bucket、不能列出 bucket 清單 ③ 不接受明文 HTTP ④ 憑證檔權限與日誌"
  local a b c d
  a=$(docker run --rm --network cpsec_default -v "$WIN_DIR/certs/ca.pem:/ca.pem:ro" --entrypoint curl curlimages/curl:latest \
        -s -o /dev/null -w '%{http_code}' --cacert /ca.pem "https://minio:9000/$BUCKET/" 2>&1)
  echo "匿名 GET bucket:HTTP $a"
  b=$(mc_kafka mb local/other-bucket 2>&1 | head -1 | cut -c1-120); echo "專用帳號建立別的 bucket:$b"
  c=$(mc_kafka ls local 2>&1 | head -1 | cut -c1-120); echo "專用帳號列出 bucket 清單(只看得到被授權的):${c:-(空)}"
  d=$(docker run --rm --network cpsec_default --entrypoint curl curlimages/curl:latest -s -o /dev/null -w '%{http_code}' --max-time 8 "http://minio:9000/minio/health/live" 2>&1)
  echo "明文 HTTP 連 9000:HTTP $d(MinIO 在同一個埠用 TLS,明文請求會被拒或斷線)"
  local leak; leak=$(docker logs broker1 2>&1 | grep -c "$(cat "$TIER_DIR/secrets/kafka-secret")")
  echo "broker1 日誌出現 Kafka 專用帳號密碼的次數:$leak"
  local env_leak; env_leak=$(docker exec broker1 env | grep -c "$(cat "$TIER_DIR/secrets/kafka-secret")")
  echo "broker1 環境變數出現密碼的次數:$env_leak(密碼在唯讀掛載的檔案裡,以 confluent.tier.s3.cred.file.path 讀取)"
  [ "$a" = 403 ] && echo "$b" | grep -qi -E "denied|forbidden|not allowed|AccessDenied" && [ "$leak" = 0 ] && [ "$env_leak" = 0 ] \
    && verdict "物件儲存只收 HTTPS、匿名被拒(403)、專用帳號只能動 $BUCKET;密碼不在日誌與環境變數,走唯讀的憑證檔"
}

case "${1:-}" in
  produce)  lab_produce ;;
  archive)  lab_archive ;;
  evict)    lab_evict ;;
  read)     lab_read ;;
  restart)  lab_restart ;;
  security) lab_security ;;
  *)        usage_from_header "$0"; exit 1 ;;
esac
