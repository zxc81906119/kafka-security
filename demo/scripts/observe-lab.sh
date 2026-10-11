#!/usr/bin/env bash
# ============================================================================
# observe-lab.sh — 第 27 章:日誌與追蹤經過 Kafka 進 Loki 與 Tempo
# ----------------------------------------------------------------------------
# 白話:日誌和 trace 先寫進 Kafka 再送進 Loki / Tempo。這支腳本逐項驗證:資料真的有流過去、
#   Loki 停掉時資料留在 Kafka 不掉、一個 trace 能跨過 Kafka 把「寫入端」和「讀取端」串在一起、
#   稽核事件也能在 Loki 查到、各元件的 Kafka 帳號權限最小。
# 前置條件:叢集已啟動 + scripts/grafana.sh on + scripts/observability.sh on
# 用法:
#   scripts/observe-lab.sh flow     日誌流向:平台容器 → Kafka(otel-logs)→ Loki;Loki 與 Tempo 要 mTLS
#   scripts/observe-lab.sh buffer   Loki 停掉期間產生的日誌,恢復後一筆不少(Kafka 當緩衝)
#   scripts/observe-lab.sh trace    Java 程式掛 OpenTelemetry agent:一個 trace 串起寫入端與讀取端
#   scripts/observe-lab.sh audit    被拒絕的存取留下稽核事件,在 Loki 查得到
#   scripts/observe-lab.sh acl      alloy-producer / alloy-consumer 的權限邊界
# 會改動什麼:buffer 會停止再啟動 loki 容器、建立並刪除 topic bufx-*;trace 建立 topic app.trace;其餘只讀。
# 怎麼判斷成功:最後一行印「判定:…」。
# 常見失敗:「alloy 沒有在跑」→ scripts/observability.sh on;trace 查不到 → 從應用程式到 Tempo 可搜尋有延遲(實測約 1 到 2 分鐘),腳本最多等 240 秒
# ============================================================================
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/kafka.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/apps.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR" || exit 1
need_ha_mode
need_container alloy "先執行:scripts/grafana.sh on 與 scripts/observability.sh on"

MONITOR_CERT=(--cert /certs/client-monitor.pem --key /certs/client-monitor.key)
LOKI=https://loki:3100
TEMPO=https://tempo:3200
OTEL_OPTS="-javaagent:/otel/otel-javaagent.jar -Dotel.javaagent.enabled=true -Dotel.exporter.otlp.endpoint=http://alloy:4317 -Dotel.exporter.otlp.protocol=grpc -Dotel.metrics.exporter=none -Dotel.logs.exporter=none"

# ---------- 小工具(這支腳本專用) ----------

# 只取回應的 HTTP 狀態碼那一行,例如 [HTTP 200];連不上(握手被拒)是 [HTTP 000]。
http_code() { dcurl "$@" 2>/dev/null | tail -1; }

# loki_value '<LogQL>':執行即時查詢,印第一筆的值(沒有結果印「無」)。
loki_value() { dcurl "${MONITOR_CERT[@]}" -G --data-urlencode "query=$1" "$LOKI/loki/api/v1/query" 2>/dev/null | node "$LIB_DIR/prom-value.mjs"; }

# tempo_traces '<TraceQL>':搜尋 trace,每個印「id 服務清單 根 span」。
#   第二個參數(選用)是起始時間(epoch 秒):只看這個時間之後的 trace,避免撿到上一次實驗留下的。
tempo_traces() { dcurl "${MONITOR_CERT[@]}" -G --data-urlencode "q=$1" --data-urlencode limit=10 --data-urlencode "start=${2:-0}" --data-urlencode "end=$(( $(date +%s) + 60 ))" "$TEMPO/api/search" 2>/dev/null | node "$LIB_DIR/tempo-traces.mjs"; }

# 平台容器的日誌行數(含關鍵字):用 docker logs 當「真相」,和 Loki 比對。
truth_count() {
  local total=0 n c
  for c in broker1 broker2 broker3 controller1 controller2 controller3; do n=$(docker logs "$c" 2>&1 | grep -c "$1"); total=$((total + n)); done
  echo "$total"
}

# 用某個 Kafka 帳號(SCRAM)執行 kafka-* 指令:as_kafka_user <帳號> <指令> <參數…>。密碼取自 config/observability/secrets。
#   指令的標準輸入原樣傳進去(給 console-producer 用);設定檔寫在 /tmp,用檔案掛進容器。
as_kafka_user() {
  local user="$1" cmd="$2" cfg="$DEMO_DIR/config/observability/secrets/$1.properties"; shift 2
  printf 'security.protocol=SASL_SSL\nsasl.mechanism=SCRAM-SHA-512\nsasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="%s" password="%s";\nssl.truststore.location=/etc/kafka/secrets/truststore.p12\nssl.truststore.type=PKCS12\nssl.truststore.password=changeit\n' \
    "$user" "$(cat "config/observability/secrets/$user.pw")" > "$cfg"
  docker run --rm -i --network cpsec_default -v "$APP_HOST_DIR/certs:/etc/kafka/secrets:ro" -v "$APP_HOST_DIR/config/observability/secrets:/obs:ro" \
    -e KAFKA_OPTS="" -e KAFKA_HEAP_OPTS="-Xmx256m" --entrypoint "$cmd" confluentinc/cp-server:8.3.2 "$@" 2>&1 | grep -v -E '^WARNING|SLF4J'
}

# ---------- 各個實驗 ----------

lab_flow() {
  say "確認平台容器的日誌真的經 Kafka 進了 Loki,而且 Loki、Tempo 都要 mTLS"
  local c total off a b
  total=$(loki_value 'sum(count_over_time({job="kafka-platform"}[10m]))')
  echo "最近 10 分鐘 Loki 收到的平台日誌:$total 行"
  for c in broker1 broker2 broker3 controller1 controller2 controller3; do
    echo "  $c:$(loki_value "sum(count_over_time({job=\"kafka-platform\", container=\"$c\"}[10m]))") 行"
  done
  off=$("$DEMO_DIR/scripts/k.sh" kafka-get-offsets --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config "$KAFKA_ADMIN_CONFIG" --topic otel-logs 2>/dev/null | awk -F: '{s+=$3} END {print s+0}')
  echo "Kafka topic otel-logs 累計 $off 筆(日誌是先寫進這裡,再由 Alloy 讀出送進 Loki)"
  a=$(http_code "$LOKI/ready"); b=$(http_code "${MONITOR_CERT[@]}" "$LOKI/ready")
  echo "Loki 不帶 client 憑證 $a;帶 monitor 憑證 $b"
  [ "$a" = "[HTTP 000]" ] || a=bad
  a2=$(http_code "$TEMPO/ready"); b2=$(http_code "${MONITOR_CERT[@]}" "$TEMPO/ready")
  echo "Tempo 不帶 client 憑證 $a2;帶 monitor 憑證 $b2"
  [ "$total" != "無" ] && [ "$off" -gt 0 ] && [ "$a" = "[HTTP 000]" ] && [ "$a2" = "[HTTP 000]" ] \
    && verdict "平台日誌經 Kafka(otel-logs 累計 $off 筆)進了 Loki($total 行 / 10 分鐘);Loki 與 Tempo 都要 mTLS(無憑證握手被拒)"
}

lab_buffer() {
  say "把 Loki 停掉,期間製造日誌(建 5 個 topic 會在 broker 留下含 bufx 的日誌),恢復後比對 Loki 收到的行數和容器實際的日誌行數"
  local truth loki i marker
  marker="bufx$(date +%s)"      # 每次執行的標記不同,不會撿到上一次留在容器日誌裡的行
  docker stop loki >/dev/null; echo "Loki 已停止"
  for i in 1 2 3 4 5; do kafka_topics --create --topic "$marker-$i" --partitions 3 --replication-factor 3 | grep -E "Created|rror"; done
  sleep 30
  truth=$(truth_count "$marker"); echo "容器實際的日誌(含 $marker):$truth 行"
  docker start loki >/dev/null; echo "Loki 已啟動;等 Alloy 把留在 Kafka 的日誌補送進去"
  sleep 30
  for i in $(seq 1 24); do
    loki=$(loki_value 'sum(count_over_time({job="kafka-platform"} |= "'"$marker"'" [30m]))')
    [ "$loki" = "$truth" ] && break
    sleep 10
  done
  echo "Loki 收到:${loki:-無} 行"
  for i in 1 2 3 4 5; do kafka_topics --delete --topic "$marker-$i" >/dev/null; done
  [ "$truth" -gt 0 ] && [ "$loki" = "$truth" ] \
    && verdict "Loki 停機期間產生的日誌,恢復後補齊($truth 行 = $loki 行,一筆不少):資料留在 Kafka,Alloy 追上後送進去"
}

lab_trace() {
  say "兩支 Java 程式掛上 OpenTelemetry agent(不改程式碼):寫入端送 5 筆、讀取端處理 5 筆;trace 經 Alloy → Kafka(otel-traces)→ Tempo"
  local found="" i started
  started=$(( $(date +%s) - 5 ))
  apps_prepare
  [ -s config/observability/otel-javaagent.jar ] || die "沒有 OpenTelemetry agent:先執行 scripts/observability.sh on"
  kafka_topics --delete --if-exists --topic app.trace >/dev/null; sleep 3
  kafka_topics --create --topic app.trace --partitions 1 --replication-factor 3 --config min.insync.replicas=2 | grep -E "Created|rror"
  APP_JAVA_OPTS="$OTEL_OPTS -Dotel.service.name=orders-producer" run_app app-p Producer app.trace 5 5 true 2000 | tail -1
  APP_JAVA_OPTS="$OTEL_OPTS -Dotel.service.name=orders-consumer" run_app app-c AtLeastOnce app.trace "g-trace-$(date +%s)" 5 commit-after | tail -1
  # 查詢條件要同時涵蓋 publish 與 process 兩種 span,搜尋結果的『服務清單』才會列出兩個服務
  for i in $(seq 1 24); do
    found=$(tempo_traces '{ name =~ "app.trace.*" }' "$started" | grep "orders-consumer,orders-producer" | head -1)
    [ -n "$found" ] && break
    sleep 10
  done
  echo "Tempo 找到跨兩個服務的 trace(程式結束後約 $((i * 10)) 秒):${found:-沒有}"
  echo "(格式:trace-id  服務清單  根 span;根 span 是寫入端的 publish,讀取端的 process 掛在同一個 trace 底下)"
  [ -n "$found" ] && verdict "一個 trace 跨過 Kafka 串起寫入端(orders-producer)與讀取端(orders-consumer):context 隨訊息標頭傳遞,應用程式碼沒有改"
}

lab_audit() {
  say "用 YUJIE 的身分讀沒有權限的 topic(payments.events)→ 被拒;稽核事件經 Kafka 進了 Loki,查得到誰、對什麼、有沒有被允許"
  local i hits=0
  for i in 1 2 3; do
    "$DEMO_DIR/scripts/k.sh" kafka-console-consumer --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config /clients/plain-yujie.properties \
      --topic payments.events --from-beginning --max-messages 1 --timeout-ms 5000 >/dev/null 2>&1
  done
  for i in $(seq 1 9); do
    hits=$(dcurl "${MONITOR_CERT[@]}" -G --data-urlencode 'query={job="kafka-audit"} |= "payments.events" |= "User:YUJIE" |~ "granted.{1,4}:false"' --data-urlencode limit=1 \
            "$LOKI/loki/api/v1/query_range" 2>/dev/null | grep -c 'granted')
    [ "${hits:-0}" -ge 1 ] && break
    sleep 10
  done
  echo "Loki 查到 YUJIE 對 payments.events 被拒絕的稽核事件:$([ "${hits:-0}" -ge 1 ] && echo 有 || echo 沒有)"
  echo '查詢(在 Grafana Explore 選 Loki):{job="kafka-audit"} |= "payments.events" |= "User:YUJIE" |~ "granted.{1,4}:false"'
  [ "${hits:-0}" -ge 1 ] && verdict "被拒絕的存取留下稽核事件:稽核 topic → Kafka → Alloy → Loki,Grafana 查得到誰(User:YUJIE)對哪個 topic 被拒"
}

lab_acl() {
  say "alloy-producer 只能寫 otel-*,alloy-consumer 只能讀 otel-* 與稽核 topic;兩者都不能碰其他 topic"
  local p_write p_read p_other c_read c_write
  p_write=$(echo "acl-test" | as_kafka_user alloy-producer kafka-console-producer --bootstrap-server "$KAFKA_BOOTSTRAP" --producer.config /obs/alloy-producer.properties --topic otel-logs | grep -c -i "authorization")
  p_read=$(as_kafka_user alloy-producer kafka-console-consumer --bootstrap-server "$KAFKA_BOOTSTRAP" --consumer.config /obs/alloy-producer.properties --topic otel-logs --from-beginning --max-messages 1 --timeout-ms 8000 | grep -c -i "TopicAuthorizationException\|not authorized")
  p_other=$(echo "x" | as_kafka_user alloy-producer kafka-console-producer --bootstrap-server "$KAFKA_BOOTSTRAP" --producer.config /obs/alloy-producer.properties --topic orders.events | grep -c -i "authorization")
  c_read=$(as_kafka_user alloy-consumer kafka-console-consumer --bootstrap-server "$KAFKA_BOOTSTRAP" --consumer.config /obs/alloy-consumer.properties --topic otel-logs --group alloy-acltest --from-beginning --max-messages 1 --timeout-ms 8000 | grep -c "resourceLogs\|body")
  c_write=$(echo "x" | as_kafka_user alloy-consumer kafka-console-producer --bootstrap-server "$KAFKA_BOOTSTRAP" --producer.config /obs/alloy-consumer.properties --topic otel-logs | grep -c -i "authorization")
  echo "alloy-producer:寫 otel-logs 被拒 $p_write 次(預期 0);讀 otel-logs 被拒 $p_read 次(預期 ≥1);寫 orders.events 被拒 $p_other 次(預期 ≥1)"
  echo "alloy-consumer:讀 otel-logs 讀到內容 $c_read(預期 ≥1);寫 otel-logs 被拒 $c_write 次(預期 ≥1)"
  [ "$p_write" = 0 ] && [ "$p_read" -ge 1 ] && [ "$p_other" -ge 1 ] && [ "$c_read" -ge 1 ] && [ "$c_write" -ge 1 ] \
    && verdict "最小權限:alloy-producer 只能寫 otel-*(讀與寫其他 topic 都被拒);alloy-consumer 只能讀(寫被拒)"
}

case "${1:-}" in
  flow)   lab_flow ;;
  buffer) lab_buffer ;;
  trace)  lab_trace ;;
  audit)  lab_audit ;;
  acl)    lab_acl ;;
  *)      usage_from_header "$0"; exit 1 ;;
esac
