#!/usr/bin/env bash
# ============================================================================
# ch27-observability.sh — 第 27 章:日誌與追蹤——經過 Kafka 進 Loki 與 Tempo(Grafana Alloy 搬運)
# ----------------------------------------------------------------------------
# 白話:指標只回答「有沒有問題」,回答不了「為什麼」。這一章補日誌(Loki)與追蹤(Tempo),且讓資料先經過 Kafka 當緩衝:下游停機時資料不掉,trace 還能跨過 Kafka 串起 producer 與 consumer。
# 前置條件:需要 Prometheus、Grafana:docker compose --profile c3 up -d prometheus alertmanager blackbox-exporter;scripts/grafana.sh on
# 用法:
#   ./demo.sh 27                  經由講解控制台跑這一章(DEMO_PAUSE=0 不暫停)
#   ./scenarios/ch27-observability.sh    直接跑
# 會改動什麼:建立 Kafka 帳號 alloy-producer / alloy-consumer、topic otel-logs / otel-traces 與 ACL;下載 OpenTelemetry Java agent;啟動 loki / tempo / alloy;buffer 實驗會停止再啟動 loki;重啟 grafana 載入資料來源。
# 怎麼判斷成功:每一步印「✔ 符合預期」,最後一行「第 27 章完成(失敗 0 項)」
# 實測結果摘要:
#   記憶體吃緊時先停 Control Center:docker stop control-center
#   實測結果摘要:
#   日誌:平台容器 → Alloy → Kafka(otel-logs)→ Alloy → Loki;Loki、Tempo 都是 mTLS
#   緩衝:Loki 停機期間產生的日誌,恢復後一筆不少(980 = 980)
#   trace:OpenTelemetry Java agent 掛在第 25 章的 Java 程式上,一個 trace 跨過 Kafka 串起 producer 與 consumer
#   稽核:被拒絕的存取留下稽核事件,經 Kafka 進 Loki;Kafka 帳號最小權限(寫與讀分開)
# ============================================================================
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch27 "日誌與追蹤經過 Kafka 進 Loki 與 Tempo"
OS="$DEMO_ROOT/scripts/observability.sh"
OL="$DEMO_ROOT/scripts/observe-lab.sh"

step obs-on "【啟動】備妥 Kafka 這一側(兩個專用帳號、兩個 topic、最小權限 ACL)、OpenTelemetry Java agent(校驗 SHA-256),啟動 Loki、Tempo、Alloy,讓 Grafana 載入 Loki 與 Tempo 資料來源" \
  "scripts/observability.sh on" \
  'bash "$OS" on 2>&1 | tail -3' '\[observability\] 完成'

step obs-flow "【日誌流向】平台容器 → Kafka(otel-logs)→ Loki;Loki 與 Tempo 要 mTLS" \
  "LogQL sum(count_over_time({job=\"kafka-platform\"}[10m]));kafka-get-offsets otel-logs" \
  'bash "$OL" flow 2>&1' '判定:平台日誌經 Kafka'

step obs-buffer "【Kafka 當緩衝】停掉 Loki,期間建 5 個 topic 製造日誌,恢復後比對 Loki 收到的行數與容器實際的日誌行數" \
  "docker stop loki;docker logs <容器> | grep <標記>;LogQL count_over_time" \
  'bash "$OL" buffer 2>&1' '判定:Loki 停機期間產生的日誌'

step obs-trace "【trace 跨過 Kafka】第 25 章的 Java 程式不改程式碼、掛上 OpenTelemetry agent:一個 trace 串起寫入端與讀取端" \
  "java -javaagent:otel-javaagent.jar …;Tempo /api/search" \
  'bash "$OL" trace 2>&1' '判定:一個 trace 跨過 Kafka'

step obs-audit "【稽核事件進 Loki】YUJIE 讀沒有權限的 topic 被拒,稽核事件經 Kafka 進 Loki" \
  "kafka-console-consumer(yujie);LogQL {job=\"kafka-audit\"}" \
  'bash "$OL" audit 2>&1' '判定:被拒絕的存取留下稽核事件'

step obs-acl "【最小權限】alloy-producer 只能寫 otel-*、alloy-consumer 只能讀;兩者都不能碰其他 topic" \
  "kafka-console-producer / consumer(以 alloy-producer、alloy-consumer 的 SCRAM 帳號)" \
  'bash "$OL" acl 2>&1' '判定:最小權限'

ch_end
