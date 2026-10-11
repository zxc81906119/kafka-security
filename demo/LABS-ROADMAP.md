# Lab 擴充路線圖(對照《Confluent Platform 銀行導入手冊》)

建立日期:2026-10-09。依據:手冊第 1 到 8 章與現有 Lab 0 到 20 的缺口分析。
原則:先測再寫;測不到的明確標「未驗證」;下載較大的映像前先列出名稱、來源與大小並詢問使用者。

## 進度(2026-10-10 更新)

| Lab | 內容 | 狀態 |
|---|---|---|
| 21 | HA 叢集停機行為與滾動重啟 | 完成(main) |
| 22 | 平台監控與告警(含監控端點保護、帳號分開) | 完成(main) |
| 23 | 憑證到期監控與不停機換憑證 | 完成(main) |
| 24 | 容量與再平衡(分區重新指派加限速) | 完成 |
| 25 | producer / consumer 可靠性(Java 單檔程式;依賴 HA) | 完成 |
| 26 | 指標與儀表板:Grafana + 官方 jmx-monitoring-stacks 儀表板;node_exporter、kafka_exporter(consumer lag);AD 登入。JMX exporter 擴到 Schema Registry、Connect 未做(使用者 2026-10-10 要求,C3 只看 broker 與 controller) | 完成|
| 27 | 日誌與追蹤:Loki + Grafana Alloy(broker/controller 日誌、稽核事件)、Tempo + OpenTelemetry Java agent(trace);日誌與 trace 以 Kafka 當傳輸緩衝(實測 TLS+SCRAM 可行,topic 最小權限) | 完成 |
| 28 | Schema 演進與資料契約 | 完成 |
| 29 | Connect:RBAC、連接器各用自己的身分、DLQ、config provider(用 Apache Kafka 自帶 connect-file,Maven Central 下載) | 完成 |
| 30 | 告警寄成信:Alertmanager 到自架郵件伺服器(使用者 2026-10-11 指定通道;demo 用 Mailpit 代替) | 完成 |
| 31 | Self-Balancing:自動搬分區(使用者 2026-10-11 指定):啟用(controller 也要設)、加空 broker、負載不均不觸發的條件、kafka-remove-brokers | 完成(授權範圍與 >20% 磁碟用量的重平衡未驗證) |
| 32 | Tiered Storage 到 MinIO(使用者 2026-10-11 指定):上傳、本機清理、從頭讀、重啟、存取保護 | 完成(物件儲存中斷、讀取效能、授權範圍未驗證) |
| 33 | 動態 quorum:靜態升級成動態、不停機汰換壞掉的 controller(使用者 2026-10-11「都做」清單) | 完成(自動加入、同時壞兩台、5 台 controller 未驗證) |

> 編號說明:原規劃 Lab 27–29 因批 B(升級與 DR)暫不做,改成連續編號 25–27;故事順序依「監控 → 憑證 → 容量 → 應用開發」。

## 已決定的範圍(使用者 2026-10-09 選定)

| 項目 | 決定 |
|---|---|
| 納入批次 | **批 A 平台韌性(Lab 21–24)**、**批 C 應用開發(Lab 27–29)** |
| 範圍外(本階段無預算,未來可能導入) | ksqlDB、Flink |
| 暫不做 | 批 B 升級與 DR(Lab 25–26,舊版映像與 Cluster Linking 授權風險)、批 D 事故演練(Lab 30) |
| HA 環境 | 新 compose profile `ha`(controller2、controller3、broker3),只在批 A 相關 Lab 啟用;Lab 0–20 維持現有輕量環境 |
| RHEL 手動安裝 | 在 Rocky 9 實測一次,寫成「實測紀錄 + 檢查清單」,不做成容器 Lab |
| 下載 | 每次下載前列名稱、來源、大小,等使用者同意 |

## 現有覆蓋與缺口(摘要)

| 手冊章節 | 現有 Lab | 狀態 |
|---|---|---|
| 3 安全(身分、授權、憑證、秘密、稽核、防線) | 1–4、6–15、17–20 | 完整 |
| 4 監控與告警 | 19.2(只有認證失敗一條) | 薄 → Lab 22 |
| 4 滾動重啟 | 16、18.25(2 台 broker) | 部分 → Lab 21 |
| 4 憑證不停機輪替 | 17(TLS) | 缺 → Lab 23 |
| 4 容量與再平衡 | 無 | 缺 → Lab 24 |
| 4 升級、DR、事故演練 | 無 | 暫不做(批 B、D) |
| 1–2 規劃與安裝 | 0(容器環境) | KRaft quorum → Lab 21;systemd、sysctl → Rocky 實測清單 |
| 5 應用開發 | 5、12(REST Proxy) | 缺 → Lab 27、28、29 |
| 5.5 CSFLE 加解密 | 20(只有授權) | **不可驗證**(缺授權),維持現狀 |

## 環境設計:`ha` profile

- 新增服務:`controller2`、`controller3`、`broker3`;controller 改為動態 quorum(3 台),broker 加到 3 台。
- 需要同步修改:`scripts/make-certs.sh`(server 憑證與內部憑證的 SAN 加 controller2、controller3、broker3)、`docker-compose.yml`(x-common 共用設定)、RBAC 的 MDS 設定(broker3 同樣要連 MDS 與 AD)、`scripts/up.sh`。
- 基礎環境(profile 預設)不變,避免整條回歸變慢;ha Lab 啟動前先 `docker compose --profile ha up`,結束後停掉。
- 風險:記憶體。ha 啟動時不要同時開 cyberark 與 sr profile;Lab 之間分開啟停。
- 預設副本與 min.isr:ha 內建立 topic 時明確指定 RF=3、min.insync.replicas=2。

## 批 A:平台韌性

### Lab 21 HA 叢集:3 controller、3 broker 的停機行為
| 步驟 | 內容 | 預期(測後才寫入手冊) |
|---|---|---|
| 21.1 | 啟動 ha;確認 quorum(`kafka-metadata-quorum describe --status`、`kafka-features describe`) | 3 個 voter、1 個 leader;kraft.version = 1 |
| 21.2 | 建 RF=3、min.isr=2 的 topic,寫入並讀取 | 成功,ISR 3 個 |
| 21.3 | 停 1 台 broker | 寫入仍成功(acks=all)、URP>0、ISR=2 |
| 21.4 | 再停 1 台 broker(剩 1 台) | acks=all 寫入失敗(NOT_ENOUGH_REPLICAS);讀取行為以實測為準 |
| 21.5 | 恢復 broker | ISR 追上、URP 回 0 |
| 21.6 | 停 1 台 controller | 叢集仍可管理(建 topic) |
| 21.7 | 停 2 台 controller(失去多數) | 實測:哪些操作失敗、既有資料面是否仍可讀寫 |
| 21.8 | 滾動重啟(依 4.3 的順序;active controller 最後) | 全程寫入零遺失(比對筆數) |

### Lab 22 監控與告警:官方列的告警真的被觸發
- 先探索:telemetry reporter 的 `metrics.include` 能否取得 UnderReplicatedPartitions、OfflinePartitionsCount、ActiveControllerCount;不足時才評估 jmx_exporter(**需下載,先問**)。
- 步驟:告警規則寫入 Prometheus → 停 broker 觸發 URP → 停多台觸發 Offline → 停 controller 觸發 ActiveController≠1 → 恢復後告警解除;附「磁碟用量」「憑證到期」兩條自訂規則(門檻標為自訂)。
- 手冊 4.1 的表格以實測可取得的指標為準,取不到的標未驗證。

### Lab 23 憑證:不停機換憑證與到期監控
- 步驟:建立短效期憑證 → 到期檢查腳本顯示剩餘天數與告警 → 以動態設定(`listener.name.<listener>.ssl.keystore.*`)換 keystore 不重啟 → 驗證服務憑證序號已變且既有連線不中斷 → 負面:不同 CA 簽發的新憑證導致 client 驗證失敗。
- 納入 OP menu 的「憑證到期檢查」項目(評估)。

### Lab 24 容量:分區重新指派加 throttle
- 步驟:建立多分區 topic 在 3 台 broker 上不均 → `--generate` 保存原指派 → `--execute --throttle` → `--verify` 並移除 throttle → 確認均衡;故意不移除 throttle 觀察殘留設定。
- Self-Balancing 與 Tiered Storage 不做(授權待確認)。

## 批 C:應用開發

### Lab 27 producer 與 consumer 可靠性
- 以 Java 單檔程式(`java Foo.java`,在 cp-server 映像內,classpath 帶 kafka-clients)做實驗;程式放 `demo/apps/`。
- 步驟:冪等 producer 在 broker 故障重試下不重複 → 關閉冪等對照 → consumer 手動提交與「處理後、提交前當機」造成重複(at-least-once)→ cooperative 與 eager rebalance 對照 → 靜態成員重啟不觸發 rebalance → 交易:abort 的訊息對 read_committed 不可見、read_uncommitted 可見。
- 交易需至少 3 台 broker,所以此 Lab 依賴 ha profile。

### Lab 28 Schema 演進與資料契約
- 步驟:BACKWARD 下加有預設值的欄位通過、加必填欄位被拒(409)→ 改欄位型別被拒 → 相容性檢查 API → 切換 FULL 與 TRANSITIVE 的差異 → subject 命名策略(TopicNameStrategy 與 RecordNameStrategy)→ 資料契約 CEL 規則(例如金額不得為負)是否可用及授權需求,**以實測為準**。
- 與 Lab 20(授權)銜接:以 yujie 的身分執行註冊,確認授權與相容性兩道關卡獨立。

### Lab 29 Connect:DLQ、設定檔祕密、RBAC
- 先探索:8.3 Connect 映像內建的 connector 是否足夠示範(source 與一個會失敗的 sink);若需另外安裝 connector,**列出名稱、來源與大小並先問使用者**。
- 步驟:Connect 加入 RBAC(worker 用 MDS token)→ connector 密碼用 config provider 從 Conjur 或 Secret Protection 取得 → DLQ:壞資料進 DLQ、errors.tolerance 設定對照 → 無權限的 connector 被拒。
- 地端 Connect 能否搭配 CSFLE:文件待核,不實測。

## 其他(不編 Lab)

- **Rocky 9 手動安裝實測**:systemd override、ulimit、sysctl、firewalld、RPM 套件來源;結果寫成手冊 2.3、1.4 的實測補充與檢查清單。需 Rocky 9 環境(先確認可用方式,若需下載映像先問)。
- **稽核設定補強**(Lab 10):開啟 produce 與 consume 記錄、路由、保留期。
- **ACL deny 補強**(Lab 19):以 `--deny-principal` 封鎖已入侵的 client。

## 每個新 Lab 的作業流程

1. 章節腳本 `scenarios/chNN-*.sh`(含 `ch_end`),在 `demo.sh` 與 `preflight.sh` 註冊。
2. 實跑 0 失敗;記錄實測結果(**以實測為準寫預期,不預設**)。
3. `labguide/labs-extra.mjs` 加 Lab 與 `ev`/`re` 判定;`labmap.mjs`、`story.mjs`、`build-story.mjs` 同步。
4. `node labguide/verify-doc.mjs chNN` 0 不符合;重產截圖與手冊(VERIFY_NOTE 如實寫)。
5. RUNBOOK、DESIGN-BASIS 加實測結果;更新手冊《銀行導入手冊》中對應段落(「未驗證」改「本案實測」)。
6. 提交 main,以暫存索引同步 labs-practice;使用者自行 push。

## 建議順序

1. `ha` profile 與憑證 SAN、動態 quorum(基礎建設)→ Lab 21。
2. Lab 22(監控)→ Lab 23(憑證)→ Lab 24(重新指派)。
3. Lab 27(依賴 ha)→ Lab 28 → Lab 29(最後,因下載與不確定性)。
4. Rocky 9 實測清單(可與上面並行,需另外環境)。

## 風險與待確認

| 項目 | 說明 |
|---|---|
| 記憶體與時間 | 3+3 叢集加其他服務可能吃不消;每個 Lab 分開啟停;整條回歸要把 ha Lab 獨立成第二條鏈 |
| 授權 | 開發者授權只能 1 台 broker,超過進 30 天試用且不能退回;ha 環境重建時要注意試用狀態 |
| 監控指標 | telemetry 可取得的指標未知,可能需要 jmx_exporter(下載) |
| Connect | 內建 connector 是否足夠示範未知,可能需要下載 connector 與映像 |
| CSFLE、Self-Balancing、Tiered Storage、Cluster Linking | 授權不明或缺授權,維持「未驗證」 |

## 腳本可讀性整理(2026-10-10 使用者要求)

目標:讓「會基本指令、不熟 bash 技巧的維運工程師」進來就看得懂,不必靠原作者維護。決定:白話說明模式預設開啟(`EXPLAIN=0` 可關);先套用在新寫的腳本當示範,**示範通過、使用者確認 OK 後,再推到前面的 Lab**。

| 階段 | 內容 | 驗證 |
|---|---|---|
| 0(已完成) | `scripts/lib/{common,prom,kafka}.sh`、`prom-value.mjs`、`prom-alerts.mjs`、`CONTRIBUTING.md`、`scripts/check.sh` | `check.sh` |
| 1 示範 | `ha-lab.sh`、`monitor-lab.sh`、`cert-lab.sh`、`ha.sh`、`jmx-setup.sh` 改成新風格(標頭樣板、`say`、共用函式、拆長行) | 第 21 到 23 章整章 0 失敗 |
| 2 | 前面所有舊腳本補標頭樣板與註解(不改行為) | `check.sh` |
| 3 | 第 1 到 14 章劇本與腳本:加白話說明、拆長行、換共用工具 | 每章整章 0 失敗 |
| 4 | 第 15 到 20 章(含 `secret-protection.sh`、`ch18`) | 每章整章 0 失敗 |
| 5 | OP menu | 安全回歸 31/31 |

原則:不重寫邏輯、一批一驗證、不一次改很多再一起測。新 Lab(24 起)從一開始就用新風格。
