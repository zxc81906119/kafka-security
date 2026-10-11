# Lab 34–36 設計依據:官方文件查證(2026-10-11)

> 用途:第八週「最壞的情況」三個 Lab(34 看門狗、35 多機架、36 DR 與演練)的設計依據。
> 標「未查證」= 官方文件找不到;標「推論」= 由官方事實推導,要在 Lab 實測確認。CP 文件路徑皆為 `/platform/8.3/...`。

## Lab 36:DR(Cluster Linking,CP 對 CP)

### 連線方向
- destination-initiated(預設):DR 端主動連主站,主站要接受 inbound。最小指令:
  `kafka-cluster-links --bootstrap-server <dest> --create --link <name> --config-file <link.properties>`
  https://docs.confluent.io/platform/8.3/multi-dc-deployments/cluster-linking/topic-data-sharing.html
- source-initiated:主站主動往外連(`link.mode=SOURCE`、`connection.mode=OUTBOUND`;DR 端 `link.mode=DESTINATION`、`connection.mode=INBOUND`),主站不必開 inbound;source 端 CLI 使用者需明確綁 `ClusterAdmin`。
  https://docs.confluent.io/platform/8.3/multi-dc-deployments/cluster-linking/hybrid-cp.html
  https://docs.confluent.io/platform/8.3/multi-dc-deployments/cluster-linking/configs.html
- 推論:依客戶網路方向擇一;demo 用 destination-initiated(官方預設)。

### 認證與授權
- link 用一組 credential 連 source;官方範例有 PLAIN、mTLS(PEM),SCRAM 可參考 `local.sasl.*` 寫法。**OAUTHBEARER(MDS token)無官方範例(未查證)** → Lab 用 SCRAM 服務帳號當 link 身分。
  https://docs.confluent.io/platform/8.3/multi-dc-deployments/cluster-linking/security.html
- Source 端(destination-initiated):`DeveloperRead`(topics);offset 遷移 `DeveloperRead`(topics + groups);ACL sync `Operator`(Cluster)。
- Destination 端:建 mirror `DeveloperManage`(topics)、寫入 `DeveloperWrite`(topics)、commit offset `DeveloperWrite`(groups)+ `Operator`(Cluster)、同步 ACL `Operator`、刪同步 ACL `ClusterAdmin`;reverse 指令兩邊都要 ALTER Cluster;權限只在建立與重連時檢查。

### Mirror topic、offset、ACL
- `kafka-mirrors --create --mirror-topic <t> --link <l> --bootstrap-server <dest>`;mirror topic 唯讀。
- `auto.create.mirror.topics.enable` + `auto.create.mirror.topics.filters`(預設每 5 分鐘);`_confluent*`、`_schemas`、`confluent-audit-log-events` 不鏡像。
  https://docs.confluent.io/platform/8.3/multi-dc-deployments/cluster-linking/mirror-topics-cp.html
- `cluster.link.prefix` 設了就不能 reverse、不能配 ACL sync → DR 不設 prefix。
- offset:`consumer.offset.sync.enable`(預設 false)、`consumer.offset.sync.ms`(30000)、`consumer.offset.group.filters`;offset 大於 mirror LEO 時被 clamp → 切換後可能重複處理。
- ACL:`acl.sync.enable`、`acl.sync.ms`、`acl.filters`。**RBAC role binding 不會被同步(推論,未查證)** → DR 端 RBAC 要另外建好(演練清單必列)。

### 切換與切回
- `promote`:要求無 lag、source 在線(遷移用);`failover`:不論 lag 與 source 是否可達都會成功(災難用)。
- 已查到:`kafka-mirrors --promote --topics <t> --bootstrap-server <dest> --command-config <cfg>`;`kafka-mirrors --failover` 確切語法**未查證**(Lab 先 `kafka-mirrors --help`)。
- RPO ≈ 切換當下的 mirror lag;client 改連(bootstrap / DNS)官方 CP 未明文(未查證)。
- failback:`reverse-and-start` / `reverse-and-pause`(CP 7.7+);舊主站有分歧資料時先 `truncate-and-restore`;consumer group 要先搬,否則可能卡 `PENDING_STOPPED`。確切語法未查證。

### 量測與告警
- lag:`kafka.server.link:type=ClusterLinkFetcherManager,name=MaxLag,clientId=ClusterLink,link-name={linkName}`
- link 狀態:`kafka.server:type=cluster-link-metrics,...`(active / paused / unavailable);offset sync 錯誤:`link-task-count{task-name=consumer-offset-sync,state=in-error}`
- 建議告警:`broker-failed-link-count > 0`、MaxLag 超過依 RPO 訂的門檻。
  https://docs.confluent.io/platform/8.3/multi-dc-deployments/cluster-linking/metrics.html
- 官方無 DR 演練 SOP 或 RTO 數值(未查證)→ 演練機制由我們設計,寫明依據。

### 授權
- 「Confluent Server includes Cluster Linking at no licensing cost beyond the Enterprise license subscription」;30 天試用涵蓋。
  https://docs.confluent.io/platform/8.3/multi-dc-deployments/cluster-linking/index.html
  https://docs.confluent.io/platform/8.3/installation/license.html

## Lab 35:多機架(broker.rack)
- `broker.rack`:「used in rack aware replication assignment」;建立 topic 時每個分區橫跨 min(機架數, 副本數) 個機架;建議各機架 broker 數相同;改了要重啟。
  https://kafka.apache.org/43/configuration/broker-configs/、https://kafka.apache.org/43/operations/basic-kafka-operations/
- 既有 topic 不會自動重排:用 `kafka-reassign-partitions` 或 Self-Balancing(rack 是 SBC 的目標之一;無法達成均勻機架分布時 SBC 不做任何平衡)。
  https://docs.confluent.io/platform/8.3/clusters/sbc/index.html
- fetch-from-follower:broker `replica.selector.class=org.apache.kafka.common.replica.RackAwareReplicaSelector`(半查證)+ consumer `client.rack`。
  https://kafka.apache.org/43/configuration/consumer-configs/
- 推論(要實測):2 個機架時副本 3 必有一個機架放 2 份;該機架故障 → 只剩 1 份 < min.isr 2 → acks=all 寫入失敗;要撐過整個機架故障需 ≥ 3 個機架。KIP-1290(Rack-Aware min ISR)尚在討論。
- Multi-Region Clusters 官方建議 3 個以上機房(只簡述,不做)。https://docs.confluent.io/platform/8.3/multi-dc-deployments/multi-region.html

## Lab 34:看門狗(Watchdog / dead man's switch)
- kube-prometheus 規則:`alert: Watchdog`、`expr: vector(1)`、`severity: none`;「always firing … send a notification when this alert is not firing」。
  https://github.com/prometheus-operator/kube-prometheus/blob/main/manifests/kubePrometheus-prometheusRule.yaml
  https://runbooks.prometheus-operator.dev/runbooks/general/watchdog/
- 路由:Watchdog 子路由覆寫 `repeat_interval`(例如 1–5 分鐘)並送 webhook 到外部 heartbeat;`repeat_interval` 應為 `group_interval` 的倍數(會往上取),所以要一起調小。外部逾時 > repeat_interval + 緩衝(數值官方未給)。
  https://prometheus.io/docs/alerting/latest/configuration/
- Alertmanager HA(補充):`--cluster.listen-address`、`--cluster.peer`;Prometheus 要列出全部 Alertmanager,不要經負載平衡器。
  https://github.com/prometheus/alertmanager/blob/main/README.md
