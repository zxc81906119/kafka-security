#!/usr/bin/env bash
# ============================================================================
# grafana-lab.sh — 第 26 章:Grafana 全元件監控(官方儀表板、主機指標、consumer lag、AD 登入)
# ----------------------------------------------------------------------------
# 白話:Control Center 只看得到 broker 與 controller;Grafana 把 Kafka、主機、consumer 放在同一個畫面。
#   這支腳本逐項檢查:Grafana 本身有沒有被保護好(HTTPS、AD 登入)、官方儀表板真的有資料嗎(不是只有匯入成功)、
#   主機磁碟指標、consumer 落後多少(故意讓 consumer 落後,看告警響不響)。
# 前置條件:HA 模式,且已執行 scripts/grafana.sh on(會啟動 Grafana、node_exporter、kafka_exporter)
# 用法:
#   scripts/grafana-lab.sh stack        Grafana 的 HTTPS、資料來源、儀表板都就緒
#   scripts/grafana-lab.sh dashboards   官方儀表板的每個查詢是否有資料(不是只有匯入成功)
#   scripts/grafana-lab.sh host         node_exporter:mTLS 保護、磁碟指標、磁碟告警規則已載入
#   scripts/grafana-lab.sh lag          kafka_exporter:最小權限、讓 consumer 落後 → 告警觸發 → 追上後解除
#   scripts/grafana-lab.sh login        用 AD 帳號登入 Grafana:群組對映角色、錯密碼與匿名被擋
# 會改動什麼:lag 會建立並刪除 topic mon.lag、用一個每次不同的 consumer group(g-lag-<時間>)讀資料;其餘只讀。
# 怎麼判斷成功:最後一行印「判定:…」。
# 常見失敗:「Grafana 沒有在跑」→ scripts/grafana.sh on;lag 的告警遲遲不來 → kafka_exporter 每 30 秒抓一次,告警要連續 2 分鐘,約 3 到 4 分鐘
# ============================================================================
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/prom.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/kafka.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR" || exit 1
need_ha_mode
need_container grafana "先執行:scripts/grafana.sh on"
need_container kafka-exporter "先執行:scripts/grafana.sh on"

GRAFANA_URL=https://grafana:3000
ADMIN_AUTH="admin:$(cat config/grafana/secrets/admin.pw)"
MONITOR_CERT=(--cert /certs/client-monitor.pem --key /certs/client-monitor.key)   # Prometheus 抓 exporter 用的 client 憑證
ROGUE_CERT=(--cert /certs/client-rogue.pem --key /certs/client-rogue.key)         # 不是行內 CA 簽的憑證

# 以本機 admin 呼叫 Grafana API。
gcurl() { dcurl -u "$ADMIN_AUTH" "$@"; }
# 只取 HTTP 狀態碼那一行(例如 [HTTP 200];連不上是 [HTTP 000])。
http_code() { dcurl "$@" 2>/dev/null | tail -1; }

# ---------- 各個實驗 ----------

lab_stack() {
  say "確認 Grafana 只收 HTTPS、資料來源(Prometheus,帳號 grafana)連得通、官方儀表板與自製儀表板都載入"
  local health plain ds titles n
  health=$(dcurl "$GRAFANA_URL/api/health" 2>/dev/null | grep -c '"database": "ok"')
  plain=$(http_code http://grafana:3000/api/health)
  echo "HTTPS /api/health:$([ "$health" = 1 ] && echo ok || echo 失敗);明文 http:$plain(不是 200 就是沒有提供明文服務;Grafana 對明文請求回 400)"
  ds=$(gcurl "$GRAFANA_URL/api/datasources/uid/Prometheus/health" 2>/dev/null | grep -o '"status": *"[A-Z]*"' | head -1)
  echo "資料來源 Prometheus 健康檢查:${ds:-沒有回應}"
  titles=$(gcurl "$GRAFANA_URL/api/search?type=dash-db" 2>/dev/null | grep -o '"title":"[^"]*"' | sed 's/"title"://; s/"//g')
  n=$(echo "$titles" | grep -c .)
  echo "已載入的儀表板($n 個):"; echo "$titles" | sed 's/^/  /'
  [ "$health" = 1 ] && [ "$plain" != "[HTTP 200]" ] && echo "$ds" | grep -q OK && [ "$n" -ge 6 ] \
    && verdict "Grafana 只收 HTTPS(明文請求被拒)、資料來源健康、$n 個儀表板已載入(5 個官方、1 個自製)"
}

lab_dashboards() {
  say "把每個儀表板的每個 PromQL 查詢都透過 Grafana 跑一次,數有幾個回傳資料——匯入成功不等於用得起來"
  local out total with_data
  local f files=()
  for f in config/grafana/dashboards/*.json; do [ "${f##*/}" = cp-host-lag.json ] || files+=("$f"); done   # 自製的不算在『官方儀表板』裡
  out=$(node "$LIB_DIR/dash-coverage.mjs" https://localhost:3000 "$ADMIN_AUTH" certs/ca.pem "${files[@]}")
  echo "$out"
  total=$(echo "$out" | sed -E 's/.*查詢 ([0-9]+) 個,有資料 ([0-9]+) 個.*/\1/' | awk '{s+=$1} END {print s}')
  with_data=$(echo "$out" | sed -E 's/.*查詢 ([0-9]+) 個,有資料 ([0-9]+) 個.*/\2/' | awk '{s+=$1} END {print s}')
  echo "合計:查詢 $total 個,有資料 $with_data 個"
  echo "$out" | grep -q "kafka-topics-kraft.json.*沒資料 0 個" && [ "$with_data" -ge $((total * 70 / 100)) ] \
    && verdict "官方儀表板不改一個字就能用:$total 個查詢中 $with_data 個有資料;沒資料的是環境沒有的功能(Tiered Storage、Schema Registry、Connect)與少數指標名稱不符,見手冊"
}

lab_host() {
  say "node_exporter 要求 mTLS(沒有憑證或不是行內 CA 簽的憑證,握手就被拒),再確認磁碟指標與磁碟告警規則"
  local a b c usage devices
  a=$(http_code https://node-exporter:9100/metrics)
  b=$(http_code "${ROGUE_CERT[@]}" https://node-exporter:9100/metrics)
  c=$(http_code "${MONITOR_CERT[@]}" https://node-exporter:9100/metrics)
  echo "不帶 client 憑證 $a;不是行內 CA 簽的 client 憑證 $b;Prometheus 的 monitor 憑證 $c"
  devices=$(prom_query 'count(count by (device) (node_filesystem_size_bytes{fstype=~"ext4|xfs"}))')
  usage=$(prom_query 'max(1 - node_filesystem_avail_bytes{fstype=~"ext4|xfs"} / node_filesystem_size_bytes{fstype=~"ext4|xfs"})')
  echo "Prometheus 看到 $devices 個 ext4 / xfs 裝置,最高用量 $(awk -v u="$usage" 'BEGIN {printf "%.1f", u * 100}')%"
  echo "磁碟與主機告警規則:"; prom_rules_list kafka-host
  [ "$a" = "[HTTP 000]" ] && [ "$b" = "[HTTP 000]" ] && [ "$c" = "[HTTP 200]" ] && [ "$(prom_rules_count kafka-host)" = "2 2" ] \
    && verdict "node_exporter 要求 mTLS(無憑證與外來憑證握手被拒),磁碟指標進了 Prometheus,磁碟告警規則已載入(目前用量低於 80%,沒有觸發)"
}

lab_lag() {
  say "先確認 kafka_exporter 的權限只有 Describe(看得到 offset、讀不到訊息),再故意讓 consumer 落後,看 lag 告警"
  local pw cfg denied listed sent f1=0 f2=0 group
  # group 名稱每次不同:舊的 group 會保留提交過的 offset,重複使用同名 group 會從上次的位置接著讀,lag 就不是預期的 4000
  LAG_GROUP="g-lag-$(date +%s)"; group=$LAG_GROUP
  pw=$(cat config/grafana/secrets/kafka-exporter.pw)
  cfg=/tmp/kafka-exporter.properties
  printf 'security.protocol=SASL_SSL\nsasl.mechanism=SCRAM-SHA-512\nsasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="kafka-exporter" password="%s";\nssl.truststore.location=/etc/kafka/secrets/truststore.p12\nssl.truststore.type=PKCS12\nssl.truststore.password=changeit\n' "$pw" > "$cfg"

  kafka_topics --delete --if-exists --topic mon.lag >/dev/null; sleep 3
  kafka_topics --create --topic mon.lag --partitions 3 --replication-factor 3 --config min.insync.replicas=2 | grep -E "Created|rror"
  sent=$(produce_test mon.lag 6000 all); echo "寫入 ${sent:-0} 筆"

  listed=$("$DEMO_DIR/scripts/k.sh" kafka-topics --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config /dev/stdin --list < "$cfg" 2>&1 | grep -c "mon.lag")
  denied=$("$DEMO_DIR/scripts/k.sh" kafka-console-consumer --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config /dev/stdin --topic mon.lag --from-beginning --max-messages 1 --timeout-ms 8000 < "$cfg" 2>&1 | grep -c -i "TopicAuthorizationException\|not authorized")
  echo "用 kafka-exporter 的身分:列出 topic 看得到 mon.lag($listed);讀訊息被拒絕($denied 次授權錯誤)"
  echo "ACL:$(kafka_acls --list --principal User:kafka-exporter | grep -c ResourcePattern) 個資源(topic *、group *、cluster),操作只有 Describe 與 DescribeConfigs"

  say "先替 group 的每個分區建立 offset(從頭開始)——沒提交過 offset 的分區,Kafka 與 kafka_exporter 都不會算 lag(實測踩過:資料集中在某個分區時,lag 只看到幾十筆)"
  "$DEMO_DIR/scripts/k.sh" kafka-consumer-groups --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config "$KAFKA_ADMIN_CONFIG"     --reset-offsets --to-earliest --topic mon.lag --group "$group" --execute 2>&1 | grep -c "mon.lag" | sed 's/^/   已建立 offset 的分區數:/'
  say "consumer group 只讀 2000 筆就停(提交 offset),所以落後約 4000 筆"
  "$DEMO_DIR/scripts/k.sh" kafka-console-consumer --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config "$KAFKA_ADMIN_CONFIG" \
    --topic mon.lag --group "$group" --from-beginning --max-messages 2000 --timeout-ms 20000 >/dev/null 2>&1
  wait_until "Prometheus 看到 $LAG_GROUP 落後超過 1000 筆" 180 lag_over_1000 || true
  echo "目前 $LAG_GROUP 的 lag:$(prom_query 'sum(kafka_consumergroup_lag{consumergroup="'$LAG_GROUP'"})')"
  wait_until "KafkaConsumerLagHigh 觸發" 300 alert_is_firing KafkaConsumerLagHigh '^Kafka' && f1=1

  say "再讀完剩下的,lag 回到 0,告警應該解除"
  "$DEMO_DIR/scripts/k.sh" kafka-console-consumer --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config "$KAFKA_ADMIN_CONFIG" \
    --topic mon.lag --group "$group" --from-beginning --max-messages 4000 --timeout-ms 20000 >/dev/null 2>&1
  wait_until "KafkaConsumerLagHigh 解除" 300 alert_is_cleared KafkaConsumerLagHigh '^Kafka' && f2=1
  kafka_topics --delete --if-exists --topic mon.lag >/dev/null
  [ "${sent:-0}" = 6000 ] && [ "$listed" -ge 1 ] && [ "$denied" -ge 1 ] && [ "$f1" = 1 ] && [ "$f2" = 1 ] \
    && verdict "kafka_exporter 只有 Describe 權限(看得到 offset、讀訊息被拒);consumer 落後時 lag 指標與告警觸發,追上後解除"
}

# 給 wait_until 用:$LAG_GROUP 的 lag 超過 1000 就回傳 0。
lag_over_1000() {
  local v; v=$(prom_query 'sum(kafka_consumergroup_lag{consumergroup="'$LAG_GROUP'"}) > 1000')
  [ "$v" != "無" ] && [ "$v" != "?" ]
}

lab_login() {
  say "用 AD 帳號登入 Grafana:群組對映角色(cluster-admin → Admin,其他 → Viewer);錯密碼、匿名、沒帶帳密的 /metrics 都被擋"
  local g y m bad anon metrics_no metrics_ok mpw
  g=$(http_code -u gary:gary-pw "$GRAFANA_URL/api/org/users")
  y=$(http_code -u yujie:yujie-pw "$GRAFANA_URL/api/org/users")
  m=$(http_code -u ming:ming-pw "$GRAFANA_URL/api/org/users")
  bad=$(http_code -u gary:wrong-pw "$GRAFANA_URL/api/user")
  anon=$(http_code "$GRAFANA_URL/api/search")
  mpw=$(cat config/grafana/secrets/metrics.pw)
  metrics_no=$(http_code "$GRAFANA_URL/metrics")
  metrics_ok=$(http_code -u "Prometheus:$mpw" "$GRAFANA_URL/metrics")
  echo "GARY(cluster-admin 群組)能管理使用者(Admin 才可):$g"
  echo "YUJIE(orders-write)$y;MING $m(Viewer 看得到儀表板,但不能管理使用者)"
  echo "錯密碼 $bad;匿名 $anon;/metrics 不帶帳密 $metrics_no、帶 Prometheus 帳號 $metrics_ok"
  echo "Grafana 知道的使用者與登入方式:"
  gcurl "$GRAFANA_URL/api/users" 2>/dev/null | grep -o '"login":"[^"]*"\|"authLabels":\[[^]]*\]' | paste -sd' ' | sed 's/"login"://g; s/"authLabels"://g' | fold -w 120 | sed 's/^/  /'
  [ "$g" = "[HTTP 200]" ] && [ "$y" = "[HTTP 403]" ] && [ "$m" = "[HTTP 403]" ] && [ "$bad" = "[HTTP 401]" ] \
    && [ "$anon" = "[HTTP 401]" ] && [ "$metrics_no" = "[HTTP 401]" ] && [ "$metrics_ok" = "[HTTP 200]" ] \
    && verdict "AD 帳號登入 Grafana:cluster-admin 群組是 Admin,其他人是 Viewer;錯密碼、匿名、沒帶帳密的 /metrics 都是 401"
}

case "${1:-}" in
  stack)      lab_stack ;;
  dashboards) lab_dashboards ;;
  host)       lab_host ;;
  lag)        lab_lag ;;
  login)      lab_login ;;
  *)          usage_from_header "$0"; exit 1 ;;
esac
