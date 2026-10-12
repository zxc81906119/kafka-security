#!/usr/bin/env bash
# ============================================================================
# ch26-grafana.sh — 第 26 章:Grafana 全元件監控——官方儀表板、node_exporter(主機)、kafka_exporter(consumer lag)、AD 登入
# ----------------------------------------------------------------------------
# 白話:Control Center 只看得到 broker 與 controller。這一章接上 Grafana 看全部:官方儀表板、主機磁碟(node_exporter)、consumer lag(kafka_exporter),並讓這些元件自己也受保護(HTTPS、AD 登入、mTLS、最小權限帳號)。
# 前置條件:需要 Prometheus、Alertmanager:docker compose --profile c3 up -d prometheus alertmanager blackbox-exporter
# 冪等:是。第一步 scripts/chapter-start.sh 確認起點(本章不需要前面的章節),重跑結果相同。
# 用法:
#   ./demo.sh 26                  經由講解控制台跑這一章(DEMO_PAUSE=0 不暫停)
#   ./scenarios/ch26-grafana.sh    直接跑
# 會改動什麼:產生密碼檔、下載官方儀表板、在模擬 AD 新增唯讀查詢帳號、在 Kafka 建立 SCRAM 帳號 kafka-exporter 與 ACL、啟動 grafana / node-exporter / kafka-exporter 容器、重啟 prometheus;建立並刪除 topic mon.lag。
# 怎麼判斷成功:每一步印「✔ 符合預期」,最後一行「第 26 章完成(失敗 0 項)」
# 實測結果摘要:
#   Grafana 只收 HTTPS、AD(LDAPS)登入並依群組對映角色;資料來源用只讀的 grafana 帳號連 Prometheus
#   官方 jmx-monitoring-stacks 的 8 個儀表板(KRaft 5 個 + Schema Registry、Connect、REST Proxy)不改一個字匯入(抓取 job 用官方慣例的名稱與 env 標籤):245 個查詢 171 個有資料
#   node_exporter、kafka_exporter 走 mTLS;kafka_exporter 的 Kafka 帳號只有 Describe(讀不到訊息);lag 告警實測觸發與解除
# ============================================================================
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch26 "Grafana 全元件監控:官方儀表板、主機指標、consumer lag"
GS="$DEMO_ROOT/scripts/grafana.sh"
GL="$DEMO_ROOT/scripts/grafana-lab.sh"

step prepare "【起點準備】這一章不需要額外準備,確認環境可直接開始(冪等:可單獨從這一章開始,也可重跑)" \
  "scripts/chapter-start.sh ch26" \
  'bash "$DEMO_ROOT/scripts/chapter-start.sh" ch26 2>&1' '\[起點\] ch26 就緒'

step grafana-on "【啟動】備妥密碼、官方儀表板(固定 commit、校驗 SHA-256)、AD 的唯讀查詢帳號、kafka_exporter 專用的 Kafka 帳號(只有 Describe),啟動 Grafana、node_exporter、kafka_exporter" \
  "scripts/grafana.sh on" \
  'bash "$GS" on 2>&1 | tail -3' '\[grafana\] 完成'

step grafana-stack "【Grafana 就緒】只收 HTTPS;資料來源 Prometheus(帳號 grafana)連得通;8 個官方儀表板(含 Schema Registry、Connect、REST Proxy)與 1 個自製儀表板都載入" \
  "curl https://grafana:3000/api/health;/api/datasources/uid/Prometheus/health;/api/search" \
  'bash "$GL" stack 2>&1' '判定:Grafana 只收 HTTPS'

step grafana-dash "【官方儀表板用得起來嗎】把每個儀表板的每個 PromQL 查詢都跑一次,數有幾個有資料" \
  "node scripts/lib/dash-coverage.mjs(經 Grafana 的資料來源代理查詢)" \
  'bash "$GL" dashboards 2>&1' '判定:官方儀表板不改一個字就能用'

step grafana-host "【主機指標】node_exporter 要求 mTLS;磁碟用量進了 Prometheus;磁碟告警規則已載入" \
  "curl --cert … https://node-exporter:9100/metrics;PromQL node_filesystem_*" \
  'bash "$GL" host 2>&1' '判定:node_exporter 要求 mTLS'

step grafana-lag "【consumer lag】kafka_exporter 的帳號只有 Describe;讓 consumer 落後 4000 筆 → KafkaConsumerLagHigh 觸發 → 追上後解除" \
  "kafka-console-consumer --group g-lag --max-messages 2000;PromQL kafka_consumergroup_lag" \
  'bash "$GL" lag 2>&1' '判定:kafka_exporter 只有 Describe 權限'

step grafana-login "【AD 登入】GARY(cluster-admin 群組)是 Admin,YUJIE、MING 是 Viewer;錯密碼、匿名、沒帶帳密的 /metrics 都是 401" \
  "curl -u gary:… https://grafana:3000/api/org/users" \
  'bash "$GL" login 2>&1' '判定:AD 帳號登入 Grafana'

step grafana-diskrule "【磁碟告警規則單元測試】合成時間序列:70% 不告警、85% 持續 5 分鐘後告警、降到 60% 解除、tmpfs 不算" \
  "promtool test rules config/c3/ops_rules_host.test.yml" \
  'bash "$GL" diskrule 2>&1' '判定:磁碟規則單元測試通過'

ch_end
