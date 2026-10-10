#!/usr/bin/env bash
# 第 22 章(進階):平台監控與告警——官方列的必設告警(URP、離線分區、active controller)真的被觸發,兩條收集路徑各測一次
# 需要 HA 模式與 Prometheus、Alertmanager:scripts/ha.sh on;docker compose --profile c3 up -d prometheus alertmanager
# 路徑 A:telemetry reporter → Prometheus(Confluent 為 Control Center 設計);路徑 B:JMX exporter → Prometheus(業界通用,不依賴 C3)。
# 實測偵測時間:A 約 150 到 250 秒(指標 60 秒送一次、規則 60 秒評估一次),B 約 35 秒(每 15 秒抓一次與評估);銀行自有監控建議走 B。
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch22 "平台監控與告警:URP、離線分區、active controller 的告警實際觸發"
MON="$DEMO_ROOT/scripts/monitor-lab.sh"

step mon-rules-tel "【路徑 A:telemetry】7 條平台告警規則已載入 Prometheus 並評估,基準狀態沒有告警(規則 config/c3/ops_rules.yml)" \
  "GET /api/v1/rules(Prometheus);GET /api/v1/alerts" \
  'bash "$MON" rules 2>&1' '判定:7 條平台告警規則已載入並評估'

step mon-urp-tel "【A:URP】停 1 台 broker → KafkaUnderReplicatedPartitions 觸發並送到 Alertmanager;恢復後解除。時間是這條路徑的特性:指標每 60 秒送一次、規則每 60 秒評估一次" \
  "docker stop broker3;等告警 firing;docker start broker3;等告警解除" \
  'bash "$MON" urp 2>&1' '判定:停 1 台 broker 觸發 URP'

step mon-offline-tel "【A:離線分區】只有 1 份副本的 topic,所在 broker 掉線 → KafkaOfflinePartitions 觸發(官方列為必設告警);恢復後解除" \
  "kafka-topics --create --replica-assignment 13;docker stop broker3;等告警" \
  'bash "$MON" offline 2>&1' '判定:單副本 topic 所在的 broker 掉線'

step mon-controller-tel "【A:controller】停 1 台 controller → KafkaControllerMissing;再停 1 台(失去多數)→ KafkaActiveControllerCountNotOne(官方列為必設告警);恢復後都解除" \
  "docker stop controller3;docker stop controller2;等告警;docker start" \
  'bash "$MON" controller 2>&1' '判定:controller 掉線觸發'

step mon-jmx-endpoint "【路徑 B:JMX exporter】Prometheus 官方的 Java agent(從 Maven Central 下載、校驗 SHA-1),每個 broker 與 controller 在 7778 埠開 /metrics。只匯出告警需要的 MBean(config/jmx/kafka.yml),不匯出全部" \
  "JVM 參數 -javaagent:…=7778:kafka.yml;curl <節點>:7778/metrics" \
  'bash "$MON" jmx-endpoint 2>&1' '判定:6 個節點都開了 JMX exporter'

step mon-rules-jmx "【B】同一組 7 條告警,指標換成 JMX 的名稱(config/c3/ops_rules_jmx.yml);另加「監控的監控」KafkaJmxScrapeDown(抓不到 exporter)。每 15 秒抓、每 15 秒評估" \
  "GET /api/v1/rules(kafka-platform-jmx)" \
  'SRC=jmx bash "$MON" rules 2>&1' '判定:7 條平台告警規則已載入並評估'

step mon-urp-jmx "【B:URP】同樣停 1 台 broker:這次約 35 秒就觸發(A 約 150 秒)" \
  "docker stop broker3;等 KafkaJmxUnderReplicatedPartitions" \
  'SRC=jmx bash "$MON" urp 2>&1' '判定:停 1 台 broker 觸發 URP'

step mon-offline-jmx "【B:離線分區】同樣的單副本 topic 實驗" \
  "docker stop broker3;等 KafkaJmxOfflinePartitions" \
  'SRC=jmx bash "$MON" offline 2>&1' '判定:單副本 topic 所在的 broker 掉線'

step mon-controller-jmx "【B:controller】同樣的 controller 實驗" \
  "docker stop controller3 controller2;等 KafkaJmxControllerMissing 與 KafkaJmxActiveControllerCountNotOne" \
  'SRC=jmx bash "$MON" controller 2>&1' '判定:controller 掉線觸發'

ch_end
