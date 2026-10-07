# Demo 自檢:對照官方最佳實踐,作法不同時是否合理

> **2026-10-04 起以 [DESIGN-BASIS.md](DESIGN-BASIS.md) 為準**(依「客戶前提 + 官方限制」分類,不以實測有沒有通為依據)。本檔保留作為歷史紀錄。

整理自三份唯讀審查(Kafka 本體、周邊組件、授權與營運)加上我自己的核實。
**證據等級**:✅ 我在本機實測或直接讀檔確認 ｜ 📖 官方文件有寫(審查 agent 的摘要,重要項請對原頁複核)｜ ❓ 無法判斷。
**分類**:S 與官方相同 ｜ D1 與官方不同但合理 ｜ D2 與官方不同且應改 ｜ U 無法判斷。

## 一、我自己核實過的 4 項(都屬 D2)

| # | 發現 | 核實方式 | 風險 | 建議 |
|---|---|---|---|---|
| 1 | **audit 排除 `User:c3`,所以用 c3 憑證改 role binding 完全不留紀錄** | 用 c3 憑證建立再刪除 binding(皆 204)→ audit 無事件;用 bootstrap 做同樣動作 → audit 有 2 筆(`mds.Authorize AlterAccess`)✅ | c3 憑證等於管理員,最需要被稽核的身分反而最不被記錄 | 不要整個排除 c3;排除是「整個主體」層級,要保留 Management/Authorize 類事件需改用 routes 試驗,可行性待測 |
| 2 | **CA 私鑰與所有私鑰放同一目錄、權限 644、整個目錄掛進 5 個容器** | `ls -l certs`:`ca.key`、`server.key`、`keypair.pem`、`client-bootstrap.key` 皆 `-rw-r--r--`;compose 有 5 處 `./certs:/etc/kafka/secrets:ro` ✅ | 任一容器被攻破 → 可簽出 CN=bootstrap 的憑證;MDS 對 client 憑證為 REQUESTED 且信任同一 CA,該憑證對應 super user。keypair.pem 是 MDS token 簽章私鑰,外洩可偽造任意使用者 token。restproxy、c3 其實只需要 public.pem | 正式環境:CA 私鑰離線;私鑰 0600/0640、owner 為 kafka 帳號;只把 public.pem 給非 MDS 元件;MDS 的 truststore 限縮到專用(子)CA |
| 3 | **`User:bootstrap` 是永久 super user,有 SCRAM 與憑證兩個入口,且被當日常工具** | `KAFKA_SUPER_USERS` 含 bootstrap;`reset.sh`、`up.sh`、`create-service-account.sh` 日常使用 `scram-bootstrap.properties`(明文密碼)✅ | 兩個進入點、無輪替;日常用途讓 break-glass 帳號失去意義 | 完成第一批授權後,日常管理改用專用 RBAC 身分;bootstrap 只留一種入口、密碼封存、使用時告警。專用身分能否由 RBAC 涵蓋 `AlterUserScramCredentials`:❓ 需實測 |
| 4 | **`mds-users.txt` 是殘留** | compose 內無任何 MDS 屬性引用它(只被 `cp` 到 /tmp)✅ | 讓人誤以為有 FILE user store;檔內有明文密碼 | 刪除 |

## 二、與官方不同,但目前做法合理(D1)

| 項目 | demo 做法 | 官方 | 為什麼合理 / 正式環境怎麼做 |
|---|---|---|---|
| 共用 server 憑證 | 一組 PK+憑證給所有元件 | 官方建議每節點各一張(摘要,❓) | **客戶限制**。共用只做加密、不當身分(實測);外洩 = 可偽裝伺服器。正式環境要有金鑰保護與輪替計畫,並請客戶簽認 |
| Kafka listener `ssl.client.auth=none` | 不要求 client 憑證 | 若啟用 mTLS 建議 required 📖 | Kafka 資料埠用 SASL 認證,不用 mTLS,none 合理 |
| MDS / REST Proxy `ssl.client.authentication=REQUESTED` | 人 Basic、機器憑證並存 | 官方範例是 REQUIRED(純 mTLS);REQUESTED 是官方列出的合法值,官方遷移頁說明可與 LDAP 並存 📖;「人機同一 REST Proxy 並存」官方未明述 ❓ | 人沒有憑證,REQUIRED 會在握手就擋掉。**風險**:信任整個 CA、身分取自 CN → 若企業 CA 會發憑證給很多人,必須限縮 truststore 或用專用子 CA |
| REST Proxy 對映規則 `RULE:^.*CN=([^,]*).*$/$1/` | 吃 DN 中任意位置的 CN | 官方範例 `^CN=(.*?)$` | Java 的 DN 是反序,官方範例對不上 demo 憑證(實測);正式環境用客戶 CA 的實際 DN 重驗 |
| controller 用 SASL_SSL + PLAIN 靜態 JAAS | 內部帳號 | SCRAM overview 說 controller 間不能用 SCRAM;PLAIN 為官方範例 📖 | 官方允許。**限制**:demo 只有 1 個 controller,controller 間 PLAIN 從未被執行,多 controller 須實測 |
| CLIENT listener 合併 PLAIN+LDAP / SCRAM / OAUTHBEARER | 同一個 listener | 官方範例常把 token listener 獨立;合併官方未明說 ❓ | 實測可行;正式環境可分開,方便獨立防火牆控管 |
| `ldap.refresh.interval.ms=5000` | 5 秒 | 預設 60000 📖 | demo 為了展示群組異動數秒生效。正式環境用預設,會對 AD 造成較少查詢 |
| `ldap://` + simple bind | 明文 | 官方:正式環境用 `ldaps://`,simple 僅適合開發 📖 | OpenLDAP demo 沒開 TLS。**客戶 AD 必須 ldaps**(也要列多台 DC) |
| 1 controller、2 broker、RF=2、min ISR=1、heap 768m/256m、Java 25 | demo 資源限制 | 正式環境 3 controller、3 broker、RF 3、min ISR 2、Java 21 📖 | 資源限制,合理。**單一 controller 已造成過一次 metadata 毀損事故** |
| audit 保留 7 天、排除 kafka-broker / kafka-controller | 降噪 | 官方預設 90 天 📖(但 AUDIT-P 摘要寫 30 天,❓ 兩頁矛盾)| demo 省空間。正式環境依法遵調整,且 retention 只在 audit 自己建 topic 時生效,既有 topic 要另外用 kafka-configs 改 |
| 明文密碼放 compose 環境變數 | changeit、broker-secret、ldap-bind-pw… | Secret Protection 或 0600 設定檔 📖 | demo 可接受;**正式環境不可** |
| SCRAM 密碼走命令列參數建立 | `--add-config "SCRAM-SHA-512=[password=…]"` | 機制與官方一致 📖 | 密碼會留在 shell history / process list;正式環境改從檔案或 stdin、隨機密碼 |
| 輪替方式:新帳號名並行再停舊 | `svc-orders-v2` | 官方:同一使用者可新增憑證而不移除舊的 📖(摘要)| 可行,但換名要重綁 role、audit 主體改名。同帳號並存兩組密碼是否可行:❓ 未實測,值得測 |
| C3 保留 HTTP 9021 listener | demo 方便 | 官方 mTLS 範例只有 HTTPS 9021 📖 | **正式環境必須移除 HTTP**,否則登入時 AD 密碼明文傳輸 |
| Prometheus / Alertmanager 未認證 | 空的 web-config | 官方支援 TLS+Basic(7.5+)、mTLS(7.9.1+)📖 | demo 可接受。**未認證的 Alertmanager 可被用來靜音告警**。客戶要減少憑證 → 用共用 server 憑證做 TLS + Basic |
| REST Proxy 自訂 ensure 略過 kafka-ready | 因內部用 SCRAM | 官方未提略過 | demo 可接受;正式環境不應略過健康檢查 |
| `kafka.rest.bootstrap.servers` 指向 CLIENT 埠 | 實測補丁 | 官方頁未列 | 由「INTERNAL 只開 SCRAM、CLIENT 才有 OAUTHBEARER」這個設計造成,合理且已實測 |
| ops 分權:Operator + DeveloperManage(`infra.`) | 不能讀寫資料、不能改授權 | DeveloperManage 無 AlterConfigs;ClusterAdmin 無讀寫 📖 | 符合分權。**缺口**:要改 retention 需 ClusterAdmin(全叢集範圍);ops 只管 `infra.*`,業務 topic 由 SystemAdmin 建 |
| 臨時提權靠 AD 群組加入/移出 | Kafka 端零變更 | 官方未規範 ❓ | 好處是不動 Kafka;**證據分散在兩處**:Kafka audit 只看得到「用了權限」,看不到「誰把他加進群組」,要靠 AD 稽核與單據對應 |

## 三、與官方不同且應改(D2)——扣掉第一節已列的 4 項

| # | 項目 | 證據等級 | 說明與建議 |
|---|---|---|---|
| 5 | **Admin REST 借用 restproxy 的憑證身分** | 📖 + 推論 | `User:restproxy` 是 impersonation 超級使用者,Admin REST 與 REST Proxy 共用同一組私鑰,擴大了 `/impersonate` 能力的暴露面。Admin REST 的 Basic/Bearer 流程是否真的需要 impersonation 權限:❓(推論不需要)。**建議另發專用憑證、不列入 impersonation super users,並實測最小需求** |
| 6 | **REST Proxy 內部用 SCRAM `svc-restproxy`** | 📖(摘要)| 官方 mTLS 範例是 OAUTHBEARER + 憑證(`TokenCertificateLoginCallbackHandler`)。我們多一組密碼要管,與「憑證與密碼最小化」不符,且為此略過 kafka-ready。**建議評估改成憑證式 OAUTHBEARER 並實測**(未測,官方 handler 屬性值需對原頁確認)|
| 7 | **`protected.users` 是靜態名單** | ✅(混入 Group: 失效已實測)| AD 新增管理員沒進清單就能被冒充。正式環境盤點所有高權限 User 主體,新增管理員納入變更流程;用 restproxy 私鑰保護與 `/impersonate` 監控補償 |
| 8 | **UserAdmin 自授權沒有偵測** | 📖 + 觀察 | demo 只有事後查詢、沒有告警。建議對 `mds.Authorize AlterAccess` 且主體非 bootstrap/kafka-admins 的事件告警 |
| 9 | **SystemAdmin 綁整個 AD 群組** | 📖(官方建議 1–2 人)| 群組成員無上限。正式環境約束 `kafka-admins` 人數,日常改用細分角色 |
| 10 | **明文密碼 / 同名重複使用** | ✅ | PLAIN 與 SCRAM 的 `kafka-broker` 密碼同為 broker-secret;正式環境各通道獨立強密碼、Secret Protection |
| 11 | **audit 與提權的可稽核性** | ✅ + 📖 | audit 在同一叢集、RF=2、7 天;官方建議長期保存(SIEM/獨立叢集);AD 群組異動事件要納入客戶 SIEM |

## 四、無法判斷(U)——需要實測或向 Confluent 確認

- controller 為什麼需要 `ldap.*`、以及補上官方的 `kraft.controller.enabled=true` 後是否可移除(**這是我一直沒做的實驗**)
- C3→MDS 用 `confluent.metadata.ssl.*` 與官方「用 C3 基本 TLS 設定」哪個才是推薦;官方摘要前後矛盾,需開原頁(基本 TLS 設定若指 C3 的 REST keystore,就是共用 server 憑證,會讓 C3 在 MDS 的身分變成共用憑證的 CN,與我們的需求衝突)
- IdempotentWrite 被拒為何在 audit 查不到
- AD 帳號**停用**(非收回群組)後,已簽發 token 與 PLAIN 長連線多久失效
- SCRAM 同帳號並存兩組密碼是否可行
- AD 掛掉時群組快取是否保留;persistent search 在 AD 是否可用
- audit 預設保留天數(90 或 30 天,官方兩頁矛盾)
- Secret Protection 是否涵蓋 JAAS 與 LDAP 密碼

## 五、這份審查本身的限制

- 官方內容來自 WebFetch/WebSearch 的摘要,**不是逐字閱讀**;標 📖 的結論重要者請對原頁複核。
- 官方「Security best practices」總頁沒抓到,金鑰檔權限、CA 私鑰存放沒有官方專頁依據,只能引用個別頁面與一般實務。
- **第 15 章(離職情境)腳本我寫好但從未執行**;審查報告中把它的預期結果當成已驗證結果引用,不可採信。

## 六、處理結果(2026-10-04)

| 項目 | 處理 | 實測結果 |
|---|---|---|
| 殘留的 `mds-users.txt` | 已刪除檔案,並移除 broker 的自訂 command 與掛載 | 叢集重建後正常啟動 ✅ |
| audit 排除 `User:c3` | 取消排除 c3;topic 前綴的 `consume` 路由不記錄「被允許」事件(被拒仍記) | c3 改 role binding 有 `mds.Authorize AlterAccess` 紀錄 ✅;C3 活動加閒置 5 分鐘無洗版 ✅。**代價:看不到「誰成功讀了資料」** |
| Admin REST 借用 restproxy 憑證 | 不設 client 憑證(實測不需要;MDS 為 REQUESTED 時) | ch14 全數通過 ✅;拿掉專用憑證後行為不變 ✅ |
| REST Proxy 連 Kafka 用 SCRAM | 改為憑證式 OAUTHBEARER(官方 mTLS RBAC 範例做法),移除 `svc-restproxy` 與自訂 ensure | ch12 全數通過 ✅;`kafka-ready` 直接通過 ✅(不再需要略過) |
| controller 的 LDAP 設定 | 依官方改設 `kraft.controller.enabled=true` + token key,**移除 ldap.\***| ✅ **推翻了先前「controller 需要 ldap.*」的結論**:三種組合手動測試皆成功、對照使用者被拒;ch11 在無 LDAP 的 controller 下 0 失敗 |

**尚未處理(仍列在上方第三節)**:`bootstrap` 永久 super user 的雙入口、私鑰與 CA 私鑰權限/存放(demo 容器需要讀取,正式環境才能修)、`protected.users` 靜態名單、UserAdmin 自授權告警、SystemAdmin 綁整個群組、明文密碼、audit 保留與長期保存、C3 HTTP listener。這些要嘛是 demo 受限(容器需讀取金鑰)、要嘛屬正式環境才適用的做法,已在文件說明。
