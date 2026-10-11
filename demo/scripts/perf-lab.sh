#!/usr/bin/env bash
# ============================================================================
# perf-lab.sh — 第 34 章:基準測試(寫入吞吐、壓縮、acks、分區數、讀取),產出可回填容量計算工具的數字
# ----------------------------------------------------------------------------
# 白話:要決定「要幾台 broker」,得先知道「一台能吃多少」。這支腳本用 Kafka 內建的 perf-test 量:
#   不同 acks(1 與 all)、不同壓縮(none、lz4、zstd)對寫入吞吐與延遲的影響,分區數對單一 producer 的影響,以及讀取吞吐。
#   結果會印成表格,並提示怎麼回填 tools/sizing.mjs。
# 重要限制:這是 docker 容器在一台筆電上跑出來的數字,資源互相搶(3 broker + 3 controller 共用同一台機器的 CPU 與磁碟),
#   **絕對值不能拿來決定正式環境台數**,只能看「比例」(壓縮省多少、acks=all 多花多少)與「方法」。
#   正式環境要在真實硬體與網路上,以同樣的腳本重測。
# 前置條件:叢集已啟動(scripts/up.sh),叢集健康
# 用法:
#   scripts/perf-lab.sh producer     寫入矩陣:acks(1、all)× 壓縮(none、lz4、zstd),每格 RECORDS 筆
#   scripts/perf-lab.sh partitions   分區數(1、3、6、12)對 acks=all 寫入吞吐的影響
#   scripts/perf-lab.sh consumer     讀取吞吐:先寫入 RECORDS 筆再從頭讀
#   scripts/perf-lab.sh all          依序全部執行並印出彙整與 sizing.mjs 的回填建議
# 環境變數:RECORDS=每格筆數(預設 300000)、SIZE=每筆 bytes(預設 1000)
# 會改動什麼:建立並刪除 topic perf.*;不改叢集設定。
# 怎麼判斷成功:最後一行印「判定:…」。
# 常見失敗:吞吐大幅低於預期 → 看 docker 是否被其他容器吃資源(docker stats)、Docker Desktop 記憶體與 CPU 配額
# ============================================================================
set -uo pipefail
PERF_OUT=/tmp/perf-lab.out
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/kafka.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR" || exit 1
need_ha_mode

RECORDS="${RECORDS:-300000}"
SIZE="${SIZE:-1000}"
RESULTS=/tmp/perf-lab-results.txt

# ---------- 小工具(這支腳本專用) ----------

# 重建 topic:perf_topic <名稱> <分區數>(副本 3、min.insync.replicas 2)。
perf_topic() {
  kafka_topics --delete --if-exists --topic "$1" >/dev/null; sleep 2
  kafka_topics --create --topic "$1" --partitions "$2" --replication-factor 3 --config min.insync.replicas=2 | grep -E "Created|rror"
}

# 跑一格寫入測試並印結果行:perf_cell <標籤> <topic> <acks> <額外 producer 參數>。
# 結果行格式:標籤 | records/s | MB/s | 平均延遲 | p99 延遲
perf_cell() {
  local label="$1" topic="$2" acks="$3" extra="$4" line rps mbs avg p99
  PRODUCER_EXTRA="$extra" RECORD_SIZE="$SIZE" PRODUCE_TIMEOUT=600 produce_test "$topic" "$RECORDS" "$acks" >/dev/null
  line=$(grep -a -E 'records sent, .* records/sec' "$PERF_OUT" | tail -1)
  rps=$(echo "$line" | grep -oE '[0-9.]+ records/sec' | awk '{print $1}')
  mbs=$(echo "$line" | grep -oE '\([0-9.]+ MB/sec\)' | grep -oE '[0-9.]+')
  avg=$(echo "$line" | grep -oE '[0-9.]+ ms avg latency' | awk '{print $1}')
  p99=$(echo "$line" | grep -oE '[0-9.]+ ms 99th' | awk '{print $1}')
  printf '%-28s | %9s | %7s | %8s | %8s\n' "$label" "${rps:-?}" "${mbs:-?}" "${avg:-?}" "${p99:-?}"
  printf '%s|%s|%s|%s|%s\n' "$label" "${rps:-0}" "${mbs:-0}" "${avg:-0}" "${p99:-0}" >> "$RESULTS"
}

hdr() { printf '%-28s | %9s | %7s | %8s | %8s\n' "設定" "筆/秒" "MB/秒" "平均 ms" "p99 ms"; }

# ---------- 各個實驗 ----------

lab_producer() {
  say "寫入矩陣:acks × 壓縮。topic 6 分區、副本 3、min.insync.replicas 2;每格 $RECORDS 筆、每筆 $SIZE bytes、不限速"
  perf_topic perf.matrix 6 | tail -1
  : > "$RESULTS"; hdr
  local acks comp
  for acks in 1 all; do
    for comp in none lz4 zstd; do
      perf_cell "acks=$acks 壓縮=$comp" perf.matrix "$acks" "compression.type=$comp linger.ms=5 batch.size=65536"
    done
  done
  local base best
  base=$(grep '^acks=all 壓縮=none' "$RESULTS" | cut -d'|' -f3)
  best=$(grep '^acks=all' "$RESULTS" | cut -d'|' -f3 | sort -rn | head -1)
  verdict "寫入矩陣完成(acks=all 不壓縮 ${base:-?} MB/s;acks=all 最佳 ${best:-?} MB/s)——絕對值只代表這台機器,看比例"
}

lab_partitions() {
  say "分區數(1、3、6、12)對 acks=all 寫入吞吐的影響:單一 producer、lz4、副本 3"
  : > "$RESULTS"; hdr
  local p
  for p in 1 3 6 12; do
    perf_topic "perf.p$p" "$p" >/dev/null
    perf_cell "分區=$p" "perf.p$p" all "compression.type=lz4 linger.ms=5 batch.size=65536"
    kafka_topics --delete --if-exists --topic "perf.p$p" >/dev/null
  done
  verdict "分區數測試完成:單一 producer 的吞吐受單連線與批次限制,不會隨分區數線性增加;分區要依『並行消費與整體吞吐』決定"
}

lab_consumer() {
  say "讀取吞吐:先寫入 $RECORDS 筆(lz4),再用新的 consumer group 從頭讀"
  perf_topic perf.read 6 >/dev/null
  PRODUCER_EXTRA="compression.type=lz4 linger.ms=5 batch.size=65536" RECORD_SIZE="$SIZE" PRODUCE_TIMEOUT=600 produce_test perf.read "$RECORDS" all >/dev/null
  local out line mbs msgs
  out=$("$DEMO_DIR/scripts/k.sh" kafka-consumer-perf-test --bootstrap-server "$KAFKA_BOOTSTRAP" --consumer.config "$KAFKA_ADMIN_CONFIG" \
          --topic perf.read --messages "$RECORDS" --group "perf-read-$RANDOM" --timeout 60000 2>&1)
  line=$(echo "$out" | grep -a -E '^[0-9]{4}-' | tail -1)
  mbs=$(echo "$line" | awk -F', ' '{print $4}'); msgs=$(echo "$line" | awk -F', ' '{print $6}')
  echo "讀取:${msgs:-?} 筆/秒、${mbs:-?} MB/秒"
  kafka_topics --delete --if-exists --topic perf.read >/dev/null
  [ -n "$mbs" ] && verdict "讀取吞吐 ${mbs} MB/s(${msgs} 筆/秒);讀取通常遠快於寫入(不需要複寫與 fsync 等待)"
}

lab_all() {
  lab_producer; echo
  lab_partitions; echo
  lab_consumer; echo
  say "回填 tools/sizing.mjs:--brokerMaxIngestMBps 用 acks=all 最佳值除以 broker 數(這台機器 3 台 broker 共用資源,所以只是下限參考);--partitionMBps 用單分區的 MB/s"
  echo "例:node tools/sizing.mjs --brokerMaxIngestMBps <壓測值> --partitionMBps <單分區壓測值>"
}

case "${1:-}" in
  producer)   lab_producer ;;
  partitions) lab_partitions ;;
  consumer)   lab_consumer ;;
  all)        lab_all ;;
  *)          usage_from_header "$0"; exit 1 ;;
esac
