# 要向 Confluent 確認的事項(授權、支援範圍、已知問題)

> 用途:導入前一次問清楚,避免做完才發現授權或支援範圍不符。每一題都寫了「為什麼要問」與「測試時看到什麼」,方便對方直接回答。
> 狀態欄由我們在收到回覆後填寫。本專案測試版本:Confluent Platform 8.3.2(Kafka 4.3.x)、RHEL 9 / Rocky 9、Java 21。

## A. 授權與功能範圍(最優先:決定哪些功能能用)

| # | 問題 | 為什麼要問 | 測試時看到什麼 | 狀態 |
|---|---|---|---|---|
| A1 | 我們的訂閱涵蓋哪些功能?請逐項確認:RBAC / MDS、稽核日誌、Control Center、Self-Balancing、Tiered Storage、Cluster Linking、Schema Registry 的資料契約規則、REST Proxy 安全外掛 | 官方各功能頁大多沒寫授權範圍 | demo 用 30 天試用,功能全開;無法從試用得知正式授權的差異 | |
| A2 | 欄位級加密(CSFLE)是否需要加購?授權如何計算? | 註冊帶加密規則的 schema 回 402「Both enterprise and add-on CSFLE licenses are required」 | Lab 20:加密與解密因此未驗證 | |
| A3 | CEL 資料契約規則(Lab 28)是否含在 Enterprise 授權內?在 Schema Registry 與 client 端的授權範圍各是什麼? | 規則只在 client 端序列化器強制執行,要確認客戶端使用是否需要額外授權 | 已驗證功能行為,授權範圍未知 | |
| A4 | Self-Balancing 與 `kafka-remove-brokers` 的授權範圍?官方只寫「Enterprise 版本含 kafka-remove-brokers」 | 要不要用它取代人工搬分區(Lab 24)取決於此 | Lab 31 | |
| A5 | Tiered Storage 的授權範圍?官方「認證的物件儲存清單」中,客戶行內物件儲存(請填廠牌型號)是否在內? | 不在清單內的物件儲存不保證支援 | Lab 32 用 MinIO 測試 | |
| A6 | Cluster Linking 含在 Enterprise 授權內嗎?(文件寫「no licensing cost beyond the Enterprise license」)目的端必須是 Confluent Server,是否有額外限制? | 跨站災難復原的方案選擇 | 未測 | |

## B. 平台與支援範圍

| # | 問題 | 為什麼要問 | 測試時看到什麼 | 狀態 |
|---|---|---|---|---|
| B1 | 8.3 在 RHEL 9 的正式支援組合:Java 21(建議)、JDK 發行版(OpenJDK / Temurin / Oracle)、檔案系統(XFS)、核心版本 | 手動安裝要照這個準備主機 | Rocky 9.8 + OpenJDK 21 測試通過;SELinux enforcing 未測 | |
| B2 | 銀行環境若要求 FIPS 140:CP 8.3 是否支援 FIPS 模式的 JDK 與加密套件?支援哪個 JDK? | 影響 TLS 套件與憑證演算法選擇 | 未測 | |
| B3 | SELinux enforcing 下的支援狀況與官方建議的標籤(是否有官方 policy 模組) | 銀行主機通常 enforcing | 容器環境無法驗證 | |
| B4 | 8.3 的支援期限(EOL)、patch 發佈節奏、8.3.x 之間滾動升級的建議流程 | 維運計畫與升級窗口 | 官方升級頁:7.7.1 以上 KRaft 可直接升 8.3 | |
| B5 | `Health+` / telemetry 是否會對外送資料?在不連外的環境應如何完整關閉? | 銀行環境不能對外 | demo 設 `confluent.telemetry.remoteconfig.confluent.enabled=false`,只送到內部 Prometheus | |

## C. 已知問題與修補時程

| # | 問題 | 為什麼要問 | 測試時看到什麼 | 狀態 |
|---|---|---|---|---|
| C1 | KAFKA-20774(刪除 SCRAM 憑證後重啟 broker 失敗):CP 8.3.x 的修補版本與時程?是否有 patch? | 目前以「覆寫成隨機密碼、不刪除」繞過 | 全新叢集 100% 重現 | |
| C2 | JMX exporter 對 mTLS 的支援:官方是否有建議的監控端點保護方式(1.0.1 只支援 TLS + Basic) | 監控端點的保護強度 | Lab 22 | |
| C3 | Schema Registry 用 `InstallCompositeSecurityHandler`(client 憑證與 Token / Basic 並存)是否在支援範圍內?(安全外掛裡有此類別,SR 文件只寫 `InstallBearerOrBasicSecurityHandler` 與 `auth.mechanism=SSL`)另:C3 對 SR 的健康檢查能否改打 `/v1/metadata/id`(Connect 有 `connect.healthcheck.endpoint`)? | C3 的背景健康檢查固定打 SR 的 `/` 且沒有使用者身分;只用 BearerOrBasic 時 401、C3 判定 SR 全掛;不想為 C3 開 AD 帳號 | 採組合認證 + C3 `schema.registry.schema.registry.alias.name=c3`:健康檢查以 CN=c3 通過、使用者操作仍用各自 token(gary 5 / yujie 1 / ming 0) | |

## D. 設計確認

| # | 問題 | 為什麼要問 | 測試時看到什麼 | 狀態 |
|---|---|---|---|---|
| D1 | 共用單一 server 憑證(單一 DN、多 SAN)只做傳輸加密、身分另用 client 憑證:是否有官方不建議的理由? | 客戶要求憑證最小化 | Lab 8 對照 | |
| D2 | AD 大型目錄(巢狀群組、上萬使用者)的建議 LDAP 設定與效能注意事項(`ldap.group.search.*`、快取) | 模擬 AD 規模小,真實 AD 的行為未知 | OpenLDAP 模擬 | |
| D3 | 動態 quorum:正式環境建議 3 還是 5 台 controller?`controller.quorum.auto.join.enable` 的預設與建議 | 官方文件說 8.2 起新叢集預設啟用,實測沒設時不會自動加入 | Lab 33 | |
| D4 | 稽核日誌(audit log)的保存與匯出:是否有官方建議的 SIEM 整合方式與事件過濾做法 | 銀行稽核要求 | Lab 10 | |
| D5 | CSFLE 在地端 KMS 的支援清單(AWS / Azure / GCP / Vault 之外,是否支援 HSM 或 CyberArk) | 客戶有 CyberArk,沒有雲端 KMS | 官方文件無 Conjur 型態 | |
| D6 | Cluster Linking 在 RBAC 下,來源端 link 帳號的最小權限:官方 RBAC 表只寫 `DeveloperRead`(Topic、Group),但建鏡像時被拒 `Denied Operation = DescribeConfigs`(Topic)。本案補一條 ACL(Topic DescribeConfigs,PREFIXED),沒用 DeveloperManage。這是官方建議做法嗎?另 link 對 `Cluster:kafka-cluster` 的 Describe 也被拒(不影響鏡像與 offset 同步),是否需要給? | DR 設計要最小權限,且 RBAC 與 ACL 並用會增加管理項目 | Lab 36(CP 8.3.2):只有 DeveloperRead 時 `kafka-mirrors --create` 回 `TopicAuthorizationException: While fetching configuration for topic`;補 ACL 後鏡像 300 = 300、offset 同步 200 = 200 | |
