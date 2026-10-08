# Demo 操作腳本與講稿(RUNBOOK)

> 所有輸出與截圖皆來自實際執行(`evidence/`)。環境:CP **8.3.2**(KRaft)、C3 next-gen **2.6.1**、REST Proxy 8.3.2、OpenLDAP(**模擬** AD,非真 AD)。官方映像為 Java 25;客戶現場建議 Java 21(8.3 官方 Recommended)。

## 0. 啟動 / 自檢 / 重置
```bash
cd demo
bash scripts/up.sh --with-restproxy --with-c3   # 首次建置(含憑證、LDAP、RBAC 初始化)
./preflight.sh                                  # 開場前自檢(容器、端點、登入、記憶體)
./preflight.sh --full                           # 全章實跑確認「全部符合預期」
./demo.sh                                       # 現場控制台(選單;每步先印講稿,按 Enter 才執行)
./demo.sh reset                                 # 回到第 0 章起點
```
Docker Desktop 建議記憶體 ≥ 10GB(實測全部啟動約 3.5GB;controller×1 + broker×2)。

### 身分與密碼(demo 專用)
| 身分 | 類型 | 帳號 / 密碼 | 說明 |
|---|---|---|---|
| gary(CN=GARY) | 人(AD) | gary / gary-pw | 組長;群組 `cluster-admin`、`topic-admin`、`rbac-admin`、`security`(沒有 SystemAdmin;SystemAdmin 只給 `breakglass`,平常是空的) |
| yujie(CN=YUJIE) | 人(AD) | yujie / yujie-pw | 組員;群組 `orders-write`(demo 示範用,正式環境人只能唯讀) |
| ming | 人(AD) | ming / ming-pw | 新進組員,起初無群組 |
| svc-orders | 服務(Kafka SCRAM) | svc-orders / orders-secret-v1 | 不在 AD |
| kafka-broker | 內部(Kafka SCRAM) | kafka-broker / broker-secret | INTERNAL 埠(9092)broker↔broker;super user;防火牆限制來源 |
| kafka-controller | 內部(Kafka SCRAM + CONTROLLER 埠 PLAIN 靜態帳號) | kafka-controller / controller-secret | controller→broker(9092):授權 provider 讀 RBAC 資料、audit 匯出;super user;與 kafka-broker 分開,audit 與撤銷才分得清 |
| bootstrap | 平台(對 MDS 用憑證 CN=bootstrap;對 Kafka 先用同一張憑證向 MDS 換 token,以 OAUTHBEARER 連線;不另建 SCRAM 帳號,設定檔 config/clients/token-bootstrap.properties) | — | super user,MDS 初始管理員與 kafka-configs/topic 管理用,MDS 無法簽發 token 時改用內部帳號 kafka-broker(SCRAM,super user)直連 broker |
| c3、restproxy | 平台(憑證 CN=c3 / restproxy) | — | 向 MDS 認證用,不是 AD 帳號;連 Kafka 也用憑證換 token |

入口:C3 `https://localhost:9022`(瀏覽器要信任 demo CA;自動化略過驗證)、LDAP 管理介面 `http://localhost:8081`(登入 DN `cn=admin,dc=corp,dc=demo` / `adminpw`)、REST Proxy `https://localhost:8086`、MDS `https://localhost:8091`。

### 畫面配置(建議)
左半:瀏覽器(C3 / Postman)・右上:終端機(`./demo.sh`)・右下:audit log(`scripts/lib-ev.sh` 的 `audit_events`)。gary / yujie / ming 各開一個瀏覽器 profile(或無痕視窗)預先登入。

---
## 第 0 章 身分地圖(3 分,投影片)
**講**:「AD 管人,Kafka 管機器。」人 → AD 帳號 + AD 群組;機器 → Kafka 內的服務帳號;平台元件(C3、REST Proxy)→ 自己的身分。**證據**:簡報「身分地圖」頁。

## 第 1 章 沒有身分就進不來(`./demo.sh 1`)
| 操作 | 預期 |
|---|---|
| 無帳密打 REST Proxy | 401 |
| AD 帳號密碼錯 | 401 / Authentication failed |
| 帳密正確但未授權 | 可見業務 topic = 0 |
**一句結論**:預設全拒絕,先有身分、再談授權。證據 `evidence/ch01/`。

## 第 2 章 人用 AD 登入 C3(`./demo.sh 2`)
gary / yujie / ming 各登入 C3(帳密 = AD)。**看**:gary 有 Brokers、Cluster settings、全部 topics;ming 只看到「not configured for management」。**講**:C3 自己有最高權限(SystemAdmin),但使用者只看得到「自己」被授權的。證據 `evidence/ch02/*.png`(每人 5 張)。

## 第 3 章 RBAC 與 AD 群組(`./demo.sh 3`)★核心
1. yujie 寫入 → 被拒(他在群組,但還沒有 role)。
2. **C3**:gary → Administration → Manage role assignments → Topic → Add role assignment(Group / `orders-write` / DeveloperWrite、DeveloperRead / Prefixed `orders.`)。**注意**:Principal name 下拉直接列出 AD 使用者與群組。
3. Postman/MDS API 印證同一份資料(`lookup/principal/Group:orders-write/resources`)。
4. yujie 寫入成功;ming 被拒。
5. **LDAP 管理介面**把 ming 加進 `orders-write` → 數秒後 ming 寫入成功(群組變更最長約一個刷新間隔:demo 設 `ldap.refresh.interval.ms=5000`,實測 4–7 秒;**官方預設 60000 即 60 秒**,實機需預留約 1 分鐘)。Kafka 端零變更。
6. ming 重新整理 C3:看得到 `orders.*`。
證據 `evidence/ch03/`(C3 表單與列表、LDAP 前/後、終端)。
**Q&A**:Q 為什麼 RBAC 不用 ACL?A 集中管理、C3 UI 指派、元件整合;僅需 broker 層群組授權時 Confluent Server Authorizer 搭配 LDAP group provider 的 ACL 也能用 `Group:`。Q 群組巢狀?A 需向客戶確認(建議平面群組)。Q 即時嗎?A 取決於刷新間隔(預設 60 秒),不是即時。

## 第 4 章 生產環境人只能唯讀(`./demo.sh 4`)
gary 在 C3 指派 `orders-read` → DeveloperRead;LDAP 介面把 ming 從 developers 移到 readonly。**預期**:ming 可讀、寫入被拒(`Cluster authorization failed`:唯讀無 IdempotentWrite)、建立 topic 被拒;yujie 不受影響。證據 `evidence/ch04/`。

## 第 5 章 Postman / REST Proxy(`./demo.sh 5`)
匯入 `postman/demo.postman_collection.json` + `demo-humans.postman_environment.json`(並匯入 `certs/ca.pem` 為 Postman 受信 CA)。requests 以編號命名,描述欄即講稿,Tests 顯示綠/紅。newman 實跑 10 requests / 14 assertions 全過。
**⚠ 必講的陷阱**:MDS 驗證成功後會設定 `auth_token` cookie,**cookie 優先於 Basic Auth**。同一個 Postman session 換身分(例如從 gary 換成 yujie)時,後續請求仍以 gary 執行(實測 yujie 竟新增 role binding)。collection 已加 pre-request 清 cookie;手動測試時請清除 `localhost` cookie。證據 `evidence/ch05/postman-*.png`。

## 第 6 章 維運腳本(`./demo.sh 6`)
腳本共用(`scripts/ops/orders-heartbeat.sh` 無帳密),憑證各人各自(`~/.kafka/client.properties`)。yujie 成功、ming(唯讀)失敗;反例:全組共用 `shared-ops` → audit log 只見 `User:shared-ops`,看不出是 yujie 還是 ming(連唯讀的 ming 都能寫了)。**規範**:腳本由手動轉排程/CI → 必須改服務身分,不可借用人的帳號(AD 密碼到期/鎖定會讓排程失敗甚至鎖帳號)。證據 `evidence/ch06/`。

## 第 7 章 機器不在 AD(`./demo.sh 7`)
建立 SCRAM 帳號 `svc-orders` → 授權前被拒 → **C3** 指派 `User:svc-orders` DeveloperWrite(Principal name 輸入名稱,選 `Create "svc-orders"`:C3 允許不在 AD 的主體)→ 可寫 `orders.*`、碰 `payments.*` 被拒;密碼錯 → 認證失敗;用 AD 方式(PLAIN→LDAP)驗證 → 失敗。**關鍵畫面**:C3 role assignment 同一張表同時有 AD 群組與服務帳號(`evidence/ch07/c7-1-svc-saved.png`)。

## 第 8 章(選修)為什麼不用共用憑證做 mTLS 身分(`./demo.sh 8`)
共用憑證 DN = `kafka.demo.local`:C3 與 REST Proxy 出示同一張,MDS 都看成 `kafka.demo.local`(同一個人,無法分權);各自憑證則為 `c3` / `restproxy`。**結論**:共用 server 憑證只做加密;服務身分用 SCRAM;平台元件需各自 client 憑證。

## 第 9 章(選修)輪替、內部通道、AD 故障(`./demo.sh 9`)
- **輪替**:建立 `svc-orders-v2` 並給同樣 role → 新舊並行 → 停舊 → 舊密碼立即失效。
- **內部通道**:CONTROLLER 埠只有 TLS 無 SASL → 拒絕;用 AD 帳密連 CONTROLLER → 拒絕(controller 只認內部靜態帳號,不查 AD)。**誠實說明**:INTERNAL 埠只是另一個 SASL 埠,任何有效 SCRAM 帳號都能「認證」進去,但授權仍生效(svc-orders 建立 topic 被拒)→ **必須以防火牆限制只有 broker/controller 節點可連 9092/9093**。
- **AD 故障**(停 openldap):SCRAM 服務照常;人的新登入失敗;AD 恢復後恢復。

## 第 10 章 收尾:audit log(`./demo.sh 10`)
彙總整場:被拒絕(ming/yujie/svc-orders 的 Metadata/Produce)、被允許(誰寫了什麼)、權限變更嘗試(yujie 嘗試改授權 → DENIED)。**注意**:官方預設 audit 擷取 Management 與 Authorize 兩類事件(含 allowed 與 denied);produce、consume、describe、interbroker、heartbeat 預設關閉。本 demo 的 `config/audit-router.json` 是**自訂**的(針對 `orders.*`/`payments.*`/`infra.*` 開啟 produce/consume/describe,只排除 kafka-broker、kafka-controller;C3 與 REST Proxy **不排除**,所以用 c3 憑證改 role binding 這類動作會被記錄(實測)。為避免 C3 輪詢 offset 洗版(實測:不處理時 C3 幾分鐘內產生數千筆 ListOffsets / OffsetFetch),針對 topic 前綴的 `consume` 路由**不記錄「被允許」的事件**,被拒絕的仍記——代價是看不到「誰成功讀了資料」)。未授權者多半在 Describe(`kafka.Metadata`)就被擋。**限制(實測)**:並非所有拒絕都查得到——例如只有 DeveloperRead 的使用者 produce 被擋(叢集層級 IdempotentWrite,官方歸在 PRODUCE 類 `kafka.InitProducerId`),audit 中找不到對應事件,原因未明;稽核需求要另外盤點。

---
## 第 11 章(進階)維運分權:唯讀 / ops / topic-admin / rbac-admin(`./demo.sh 11`)
**問題**:正式環境人只能唯讀,但總要有人看叢集、管 topic、管授權,怎麼分?**做法**:權限放在 Kafka(RBAC + AD 群組);維運選單/腳本只是操作介面,以「操作者本人」身分執行;三個維運群組的 role 在 bootstrap 時就綁好、日常群組是空的,需要時經核准臨時加入、做完移出。
| AD 群組 | 能做什麼(實測) | role |
|---|---|---|
| orders-read | 讀資料、看 topic | DeveloperRead |
| ops | 只能列出 topic;**建 topic、讀資料、改授權都被拒,連 `kafka-topics --describe` 也被拒** | Operator |
| topic-admin | 建/刪 topic、讀資料、**在自己的 Topic\* 範圍內還能改授權(204)**——強角色 | ResourceOwner(Topic\*、Group\*) |
| rbac-admin | 只管授權;不能建 topic、不碰資料 | UserAdmin |
| breakglass | 全權,平常是空的 | SystemAdmin |
流程:角色對照(MDS 查詢與 C3 檢視)→ ming 唯讀可讀 → yujie 建 topic 被拒 → **AD 把 yujie 加進 ops** → 仍建不了 topic、改不了授權 → 收回 → **加進 topic-admin** → 可建 topic、讀得到資料、能改授權(示範後收掉)→ 收回 → **AD 把 ming 加進 rbac-admin** → 可替 orders-write 開 infra.* 讀取權、但不能建 topic → 授權生效 → **收回**後再操作皆被拒 → audit 看得到誰被拒、誰改了授權。證據 `evidence/ch11/`。依據實測:`spike/group-roles-aligned/run.log`。
**不建議**:選單背後用一個共用高權限帳號再由選單判斷誰能按什麼 → audit 只剩共用帳號(同第 6 章反例)。若客戶堅持閘道式選單:sudo + AD 群組(SSSD)限制執行者、憑證只給專用系統使用者、選單自己記錄操作者。
**Q&A**:Q 為什麼 ops(Operator)連 describe 都不行?A 實測 Operator 只能列出 topic 清單,`--describe` 回 TopicAuthorizationException;所以 OP menu 的項目 10、11、27 需要 topic-admin 級權限。Q topic-admin 為什麼是強角色?A ResourceOwner 包含該資源的讀寫與授權;在自己的範圍內能改授權,所以只在需要時臨時加入、事後收回,並由 audit 追蹤。Q 要改 topic 設定(retention 等)可以只給 ops 嗎?A 不行;要用 ResourceOwner,或 **ClusterAdmin**(官方:叢集範圍,Topic 的 Create/Delete/Alter/AlterConfigs/Describe,**無 Read/Write**;實測可改 retention.ms、不能讀寫資料),但 ClusterAdmin 是叢集範圍、不能限定前綴。Q 把群組最後一個成員移掉會怎樣?A demo 的 OpenLDAP 的 groupOfNames 至少要有一個 member,所以每個群組放一個不存在的 NOBODY 佔位(真實 AD 沒有這個限制)。Q UserAdmin 會不會自己給自己權限?A 理論上可,所以人數最小化並用 audit 追蹤。

## 第 12 章(進階)legacy app 只能用 HTTP:經 REST Proxy,機器用憑證、人用 Basic 並存(`./demo.sh 12`)
**問題**:legacy app 不能用 Kafka client(無法 SCRAM),只能 HTTP 丟資料;但 REST Proxy 的 Basic 帳密是交給 MDS 查 AD,AD 又沒有服務帳號 → 服務帳號進 REST Proxy 是 401(實測)。**做法**:REST Proxy 改用官方的多協定處理器 `AuthenticationHandler`,**人**走 Basic(經 MDS 查 AD)、**機器**走 client 憑證(CN = 主體)。
| 設定(REST Proxy) | 值 | 說明 |
|---|---|---|
| `rest.servlet.initializor.classes` | `io.confluent.common.security.jetty.initializer.AuthenticationHandler` | 取代原本的 InstallBearerOrBasicSecurityHandler;同時支援 Basic / 憑證 |
| `ssl.client.authentication` | `REQUESTED` | 官方列有 NONE/REQUESTED/REQUIRED 三值;官方 AuthenticationHandler 範例是 REQUIRED(純 mTLS)。人沒有憑證,所以人機並存**必須**用 REQUESTED(有帶憑證才驗)——此組合為本專案實測,官方文件未明述 |
| `auth.ssl.principal.mapping.rules` | `RULE:^.*CN=([^,]*).*$/$1/,DEFAULT` | 憑證 DN → 主體。**屬性名稱以官方 AuthenticationHandler 頁為準**(`auth.ssl.principal.mapping.rules`);REST Proxy 另一頁的 `confluent.rest.auth.ssl.principal.mapping.rules` 屬於另一種傳遞模式——實測改用該前綴後對映失效(主體變成 `O=Demo,CN=legacy-orders`)。DN 在 Java 內為反序(實測觀察),規則不能假設 CN 在最前面 |
流程:app --HTTPS+client 憑證--> REST Proxy --mTLS(CN=restproxy,impersonation)--> MDS 取得 `User:legacy-orders` 的 token --OAUTHBEARER--> broker --RBAC--> 允許/拒絕。證據:`evidence/ch12/`:授權前 403、授權後 200、寫 payments 403、無憑證 401、有效但無授權 403、自簽憑證 TLS 被拒、人 Basic 照常 200、audit 主體為 `User:legacy-orders`。
**兩條路徑的實測差異(MDS 請求日誌)**:
- **人(Basic)**:REST Proxy 把使用者的 Basic 帳密轉給 MDS `GET /security/1.0/authenticate`(MDS 看到的主體是 `yujie`)→ MDS 以 LDAP simple bind 驗證 → 回 `auth_token`(JWT,存活約 1 小時)→ REST Proxy 以該 token 用 OAUTHBEARER 連 broker。**沒有** `/impersonate` 呼叫。
- **機器(client 憑證)**:REST Proxy 以自己的憑證(MDS 看到 `restproxy`)呼叫 `POST /security/1.0/impersonate`,代 `legacy-orders` 取得 token → 之後以該 token 連 broker。這一步才用到 REST Proxy 自己的 client 憑證與 MDS 的 impersonation 超級使用者設定(`User:restproxy`)。
**注意**:憑證身分**只能用 `User:` 綁 role,不支援群組**(官方明載);每個 legacy app 一張憑證(客戶 CA 簽發,需追蹤到期);REST Proxy 要有 `public.key.path` 與 impersonation 設定(同第 5 章)。
**風險與對策(實測)**:REST Proxy 的 client 憑證能呼叫 MDS `/impersonate` 代「任何不在受保護清單的使用者」。修正前只保護 bootstrap / kafka-broker / kafka-controller,實測 gary、c3(皆 SystemAdmin)都可被代(200)→ 拿到 REST Proxy 私鑰即可升為管理員。已把 `User:gary;User:c3;User:restproxy` 加進 `confluent.metadata.server.impersonation.protected.users`,實測全部 403;gary 本人登入與 C3 不受影響。**清單只認 `User:`**(官方範例格式,並建議一定要含 super users):**實測在清單中混入 `Group:kafka-admins`,整份清單失效**(連 `User:c3` 都能被代,HTTP 200),所以管理員個人帳號必須逐一以 `User:` 列入,AD 新增管理員要同步更新清單(為 broker 靜態設定)。限制:audit log 的 `actingPrincipal` 為空,看不出請求經過 REST Proxy。
**Q&A**:Q REST Proxy 的憑證被偷會怎樣?A 攻擊者可代「不在受保護清單」的任何人;所以特權身分一律列入清單、保護私鑰權限、監看 /impersonate 呼叫。
**不可行的備案**:MDS 的帳號密碼檔(`confluent.metadata.server.user.store=FILE`)——官方允許值只有 LDAP(預設)、OAUTH、LDAP_WITH_OAUTH、FILE,**沒有 FILE+LDAP 並存**,選 FILE 會取代 LDAP,人的 AD 登入就壞了。
**Q&A**:Q 為什麼不用共用 server 憑證當 app 身分?A 同第 8 章:同一個 DN 會被視為同一個人。Q 憑證到期怎麼辦?A 到期前換新憑證,RBAC 綁定的是 CN,CN 不變則不用重綁。

## 第 13 章(進階)Control Center(C3)身分盤點:人與機器各走哪條路(`./demo.sh 13`)
| 連線 | 人 / 機器 | 怎麼認證 | 證據 |
|---|---|---|---|
| 瀏覽器 → C3 → MDS | 人 | 登入時 C3 把使用者 Basic 帳密轉給 MDS `/authenticate`(經 `/api/metadata` 代理),MDS 向 AD 驗證後回 token;之後瀏覽器全部帶 **Bearer** | 瀏覽器請求紀錄:第一個呼叫 [Basic],其餘 [Bearer] |
| C3 → MDS(看使用者能看什麼) | 人 | 用**使用者本人的 token**:`lookup/principals/User:ming/visibility`、`PUT /authorize` | MDS 日誌主體=ming |
| C3 → broker(使用者操作) | 人 | **帶使用者本人的身分**(OAUTHBEARER) | audit:來自 C3 IP 的 ListOffsets / FetchConsumer / CreateTopics,主體 `User:ming` / `User:gary` |
| C3 自己 → MDS / broker(背景串流、內部 topic) | 機器 | client 憑證(CN=c3)向 MDS `GET /authenticate` 換 token(約每小時續期),OAUTHBEARER 連 broker;主體 `User:c3`,**必須是 SystemAdmin**(官方) | MDS 日誌 `c3 GET /authenticate`;token sub=c3 |
| 自動化 → C3 API | 機器 | 憑證向 MDS 換 token → 帶 Bearer 呼叫 C3 API | 實測 200;無 token 401 |
| C3 / broker → Prometheus、Alertmanager | 機器 | **HTTPS + HTTP Basic**(官方支援 TLS + Basic〔7.5+〕與 mTLS;demo 自 2026-10-08 起啟用,見第 17 章) | 無帳密讀 Prometheus 401、Alertmanager 建立靜音 401;帶 Basic 帳密 200 |
**官方 vs 實測**:官方 C3 RBAC 頁說明 C3 主體必須是 SystemAdmin(理由:consumer lag 架構),且 C3 在 RBAC 下只能用 OAUTHBEARER;但**沒有明說** C3 以自己或使用者身分查 Kafka。**實測**使用者操作在 broker 端的主體是使用者本人(audit 可證,屬本專案觀察,非官方文字),C3 自己的 `User:c3` 用於背景串流(Streams、license;拿掉 SystemAdmin 即授權失敗、C3 退出)。C3 用憑證:官方 mTLS RBAC 頁(7.8+)**有** C3 範例(Streams 用 `TokenCertificateLoginCallbackHandler`;C3→MDS 用 C3 的基本 TLS 設定);本專案 C3→MDS 則用 `confluent.metadata.ssl.*` 另設 client 憑證(CN=c3),屬性與官方範例不同,實測可行。官方 C3 RBAC 頁的 MDS 認證範例仍是帳密(`confluent.metadata.basic.auth.user.info`)。
**風險(實測)**:1) `client-c3` 憑證換到的 token = 管理員(能建/刪 role binding,204)→ 嚴控 keystore 權限;2) Prometheus、Alertmanager 已啟用 TLS + Basic(第 17 章),但 Basic 沒有細部授權,有帳密就能寫 Alertmanager → 帳密分開(C3 一組、OP menu 維護模式一組)、日誌要保護;3) REST Proxy 憑證可代 c3 → 已列入 protected.users(第 12 章)。
**Q&A**:Q 能不能把 C3 的權限降低?A 官方要求 C3 主體必須 SystemAdmin(要看全部 consumer group 與 lag)。Q 能不能不用憑證?A 官方 C3 RBAC 頁的範例是 MDS 帳密(需 AD 之外的服務帳號),客戶 AD 沒有服務帳號,故用憑證(官方 mTLS RBAC 頁也有憑證做法)。

## 第 14 章(進階)broker 內建 Admin REST 的保護:匿名擋下、依使用者授權(`./demo.sh 14`)
**問題**:Confluent Server 的 broker 內建一組 Admin REST(`/kafka/v3`,與 MDS 共用 8091 等埠),**未設定安全擴充時完全無認證**(日誌:REST security extensions are not configured)。實測不帶任何身分的 `GET /kafka/v3/clusters` 會成功進入 AdminClient,並曾使 broker 記憶體耗盡而崩潰(2 次,首次原因未確認)。8091 同時是 MDS 埠,必須對使用者與元件開放,**不能靠防火牆整個擋掉**。
**做法(依官方 [Admin REST APIs security](https://docs.confluent.io/platform/current/kafka-rest/production-deployment/confluent-server/security.html),`kafka.rest.` 前綴,已併入 compose 的 `x-broker-env`)**:
| 設定(broker) | 值 |
|---|---|
| `kafka.rest.rest.servlet.initializor.classes` | `io.confluent.common.security.jetty.initializer.InstallBearerOrBasicSecurityHandler` |
| `kafka.rest.kafka.rest.resource.extension.class` | `io.confluent.kafkarest.security.KafkaRestSecurityResourceExtension` |
| `kafka.rest.public.key.path` | MDS token 公鑰 |
| `kafka.rest.confluent.metadata.bootstrap.server.urls` + `...metadata.ssl.*` | MDS 位址與信任庫。**不設 client 憑證**:實測拿掉 adminrest 專用憑證後,匿名 401、錯誤密碼 401、gary 列全部 topic、ming 空清單、ming produce 被拒(40301)全部照舊,保護不靠這張憑證(MDS `ssl.client.authentication=REQUESTED` 時);若 MDS 改成 REQUIRED,則需要再給 Admin REST 一張 client 憑證(未驗證) |
| `kafka.rest.bootstrap.servers` | 指向 **CLIENT 埠(9094)**——本專案實測:未設定時它連到只開 SCRAM 的內部埠,認證後回 `OAUTHBEARER not enabled` |
| `kafka.rest.client.security.protocol` / `...ssl.truststore.*` | `SASL_SSL` 與 truststore |
**實測結果(ch14)**:匿名 401(未設定時:成功且可使 broker 崩潰)、錯誤密碼 401、gary(AD 帳密)列 topic 200 且 produce 成功、ming(無 role)列 topic 200 但**清單為空**、ming produce 回 **HTTP 200,內容 `error_code:40301`**(監控與腳本必須看內容的 error_code,不能只看 HTTP 狀態)。
**注意**:先前嘗試只加 `kafka.rest.client.*` 固定 SCRAM 身分(沒有安全擴充)會使所有請求變成超級使用者——**必須成組設定**。


---
## 第 17 章(進階)傳輸加密補強:AD 走 LDAPS、監控 HTTPS + Basic、C3 HTTPS(`./demo.sh 17`)
**問題**:前面章節處理「誰能做什麼」,這章處理「線上傳輸有沒有被看光」。AD 連線若是明文 LDAP,登入密碼與群組查詢會在網路上明文流動;Prometheus、Alertmanager 若不設認證,任何連得到的人都能讀指標,甚至靜音告警;C3 若有 HTTP 入口,登入時的 AD 密碼明文。
**做法**(都已併入主 compose;共用同一張 server 憑證,SAN 補 `prometheus`、`alertmanager`,**同一把 key、同一個 CA 重簽**):
| 對象 | 設定 | 說明 |
|---|---|---|
| broker → AD | `ldap.java.naming.provider.url=ldaps://…:636`、`ldap.java.naming.security.protocol=SSL`、`ldap.ssl.truststore.*` | 只有連 AD 的 JVM(兩台 broker)需要信任庫;controller 不連 AD |
| Prometheus、Alertmanager | `web-config-prom.yml`、`web-config-am.yml`:`tls_server_config` + `basic_auth_users`(bcrypt) | 啟動參數 `--web.config.file`;demo 帳密 c3 / prom-pw、c3 / am-pw(測試值) |
| Prometheus → Alertmanager | `prometheus.yml` 的 `alerting.alertmanagers` 加 `scheme: https`、`basic_auth`、`tls_config.ca_file` | **官方 TLS + Basic 頁沒寫、實測必要**:沒設時告警送不到(`bad response status 400`) |
| C3 → Prometheus / Alertmanager | `confluent.controlcenter.prometheus.url` 與 `alertmanager.url` 改 https;`.ssl.truststore.*`;`.basic.auth.user.info` | |
| broker → Prometheus(指標推送) | `confluent.telemetry.exporter.<名稱>.client.base.url` 改 https;`api.key` / `api.secret` 即 Basic 帳密;`…https.ssl.truststore.*` | |
| 使用者 → C3 | `https://…:9022`(共用 server 憑證) | demo 另留 HTTP 9021 只給容器內健康檢查;正式環境不要開 |
| OP menu 維護模式(25、26) | `OPMENU_ALERTMANAGER_URL=https://…`、`OPMENU_ALERTMANAGER_AUTH_FILE` | 用專用帳號(demo:`opmenu` / am-opmenu-pw),不與 C3 共用 |
**實測結果(ch17,9 項)**:broker 連 AD 全在 636、389 沒有 broker;不信任 CA 就連不上 LDAPS;AD 帳密登入(MDS Basic、Kafka PLAIN)不受影響;Prometheus 無帳密 401、錯密碼 401、正確 200、明文 HTTP 400;Alertmanager 不帶帳密連建立靜音都 401;broker 指標持續進來;C3 對 Prometheus、Alertmanager 的連線狀態 ONLINE;C3 憑證驗證通過、不信任 CA 時 curl 錯誤 60。
**注意與未驗證**:① Windows 的 curl(schannel)連 HTTPS 要加 `--ssl-no-revoke`,否則因無法檢查憑證撤銷而連不上(不是憑證問題);瀏覽器要信任 demo CA,自動化腳本略過驗證。② 健康檢查用 TCP 探測,Prometheus 日誌會有 `TLS handshake error … EOF`,屬探測連線,可忽略。③ C3 的 INFO 日誌會印出 Authorization 標頭(Base64),日誌檔要保護。④ 真實 AD 的 LDAPS 憑證鏈(含中繼 CA)、Alertmanager mTLS、F5 終止 C3 的 TLS,皆未驗證。

---
---
## 第 18 章(進階)與行內 CyberArk 整合:應用程式取密碼、輪替、OP menu 取帳密、設定檔密碼不落地(`./demo.sh 18`)
**範圍**:CyberArk 分兩塊。**秘密管理**(商業版 CCP / Conjur)這條路用 CyberArk 的開源版 **Conjur OSS** 實做(API 與商業版一致);**PAM**(PSM 代登入與錄影、CPM 輪替主機帳號、PVWA 依單借出)無法在本機重現,只在簡報與 DESIGN-BASIS 說明,要在客戶環境 PoC。
**元件**(profile `cyberark`;`scripts/conjur.sh up` 一鍵):`conjur-db`(postgres)、`conjur-server`、`conjur`(nginx TLS 入口,共用 server 憑證,SAN 含 conjur)、`conjur-cli`(管理用)。policy 在 `config/conjur/policy/kafka.yml`:host(機器身分)svc-orders、legacy-orders、rogue-app、opmenu、broker;variable(秘密)各自的密碼、帳密、主金鑰;permit 只給自己的。API key 與資料金鑰在 `config/conjur/`(忽略檔),admin API key 在 `admin.key`。
| 步驟 | 證明 | 指令 |
|---|---|---|
| 應用取密碼 | host API key → token(8 分鐘)→ 取秘密 200;沒被授權 404;錯 key 401 | `scripts/conjur.sh probe-as svc-orders svc-orders/credential`、`probe-as rogue-app …`、`probe-bad svc-orders` |
| 應用啟動 | 取密碼後在容器 tmpfs 組 SCRAM 設定寫入 orders.events;主機與映像無密碼檔 | `scripts/app-with-conjur.sh svc-orders svc-orders orders.events msg` |
| 輪替(改密碼) | kafka-configs 改密碼 + `conjur.sh set`;應用重啟跟上、舊設定檔 Authentication failed(有短暫中斷) | ch18 步驟 7、8(會還原) |
| 輪替(新舊並行,零中斷) | `scripts/rotate-with-conjur.sh start svc-orders svc-orders-v2`:建 v2(密碼隨機只存 Conjur)→ 複製舊帳號全部角色並逐筆檢查 → **驗證新帳號連得上且看到同樣的 topic(失敗就回滾新帳號,Conjur 不動)** → Conjur 的 `svc-orders/credential`(JSON `{"u":帳號,"p":密碼}`,帳號與密碼放同一個變數:寫入與讀取都是單一操作,不會取到不配對的帳密)一次改指 v2;應用逐批重啟自動改用 v2(`app-with-conjur.sh` 連帳號都從 Conjur 取);**不直接刪舊帳號**:`quarantine` 先解除角色(存檔、可 `rollback`)→ `check` 只看隔離之後的 audit(DENIED = 還有人在用)→ 沒人用才 `finish` 刪 SCRAM;`restore` 還原 demo。正式環境由 CPM 自訂平台或排程呼叫 | ch18 步驟 9 到 15 |
| 舊連線實驗 | 長連線 producer 寫到一半:**只刪 SCRAM 憑證 → 14 筆全寫完(擋不住已連著的連線)**;先解除角色 → 只寫進約 6 筆,之後每個請求授權失敗、認證失敗 0 次 | `scripts/old-connection-test.sh both / scram-only`;ch18 步驟 16、17 |
| OP menu | `OPMENU_ALERTMANAGER_AUTH_CMD`(優先於 AUTH_FILE)執行時取帳密;rogue-app 身分取不到 → 開不了維護模式 | ch18 步驟 9 |
| 設定檔密碼不落地 | Confluent Secret Protection:`confluent secret` 加密 AD 查詢密碼 → `certs/security.properties`;主金鑰存 Conjur;broker2 以 `docker-compose.cyberark.yml` 覆蓋,啟動前 `config/conjur/fetch-secret.py` 取主金鑰進環境變數(= systemd 的包裝腳本;ExecStartPre 的環境變數不會傳給 ExecStart);生效設定只有佔位符、環境無明文、gary 經 broker2 登入 200 | `scripts/secret-protection.sh setup / apply / show / revert` |
| 同上,改用 CyberArk 官方工具 summon | `summon -p summon-conjur -f secrets.yml <啟動程式>`:summon-conjur 以 `/etc/conjur.conf` + `/etc/conjur.identity`(netrc)向 Conjur 取 `config/conjur/secrets-broker.yml` 列的秘密,注入成子程序環境變數後執行啟動程式;取不到(401)就不執行。實測 broker2(`docker-compose.cyberark-summon.yml`):PID 1 = summon → java;master key 只在 java 程序環境、docker inspect 與 /tmp 都沒有;gary 登入 200。正式環境 systemd 只要 `ExecStart=/usr/local/bin/summon -p summon-conjur -f /etc/kafka/secrets.yml /usr/bin/kafka-server-start /etc/kafka/server.properties`,不必 ExecStartPre 或包裝腳本。踩坑:Docker Desktop 單檔 bind mount 時 summon-conjur 讀不到 netrc(改掛目錄 + `netrc_path`) | `scripts/secret-protection.sh summon-setup / apply-summon`(summon v0.13.1、summon-conjur v0.9.3 自 GitHub 下載並校驗 SHA256,放 `config/conjur/bin/`,不進版本庫) |
| 稽核 | Conjur 日誌:`demo:host:kafka/rogue-app tried to fetch …: Forbidden`、`… fetched …` | ch18 步驟 13 |
**實測結果(ch18)**:13 項全過。**注意**:取不到主金鑰 broker 就不啟動(刻意),Conjur 的可用性要與 broker 同級;Kafka 的 SCRAM 輪替沒有現成 CyberArk 平台,靠腳本,由 CPM 自訂平台或排程觸發;CLI 是 `conjur init oss`(v9),docker exec 要 `MSYS_NO_PATHCONV=1`。**未驗證**:商業版 CCP 的 AppID 認證、Conjur 高可用、PAM 側全部。

## 第 19 章(進階)帳號被偷之後:失效、告警、限速、限連線、鎖定(`./demo.sh 19`)

**起點**:第 18 章實驗發現「只刪 SCRAM 憑證,已連著的舊連線不會斷」。這一章假設帳號已被偷,逐項補上平台能做的限制。全部在 docker 實測(2026-10-08)。

| 項目 | 證明 | 設定 / 指令 |
|---|---|---|
| SASL 重新認證 | 停用「連著的」帳號(只刪 SCRAM):45 筆嘗試只寫進 27 筆,producer 第一個錯誤是 `Authentication failed during re-authentication`(第 18 章同樣動作 14/14 全寫入) | `KAFKA_LISTENER_NAME_CLIENT_CONNECTIONS_MAX_REAUTH_MS=60000`(demo 值;正式建議 1 小時);`scripts/reauth-test.sh run`。**不能動態改**:`connections.max.reauth.ms` 被 kafka-configs 拒絕;`listener.name.client.…` 寫法會被接受但實測不生效(30/30 全寫入)→ 要改只能重啟 |
| 認證失敗告警 | 5 次錯誤登入 → `KafkaAuthFailuresBurst` firing(listener CLIENT)→ Alertmanager 收到 | broker telemetry 加 `socket.server.failed.authentication.total` 等指標;規則 `config/c3/security_rules.yml`(5 分鐘增量 > 3);Prometheus 每 60 秒評估,約 2 到 4 分鐘出現 |
| TLS 套件 | `ECDHE-RSA-AES256-GCM-SHA384` 與 TLS 1.3 接受;`ECDHE-RSA-AES128-SHA`(CBC + SHA-1)、`AES128-SHA` 拒絕。**未設定前 Kafka listener 接受 CBC + SHA-1**;MDS(Jetty)本來就拒絕 | `KAFKA_SSL_ENABLED_PROTOCOLS=TLSv1.3,TLSv1.2`、`KAFKA_SSL_CIPHER_SUITES`(只列 GCM / ChaCha20),在 `x-common-ssl`。只設 Kafka listener,其他元件未設 |
| 連線數上限 | 單一來源 IP 上限 2:開 4 條,日誌 `Rejected connection … maximum of 2.0 connections` | `kafka-configs --entity-type brokers --entity-default --add-config max.connections.per.ip=2`(動態;`--entity-type ips` 只收連線速率配額,不收這個) |
| client quota | 同一動作(2500 筆 × 1 KB):不限速 約 2700 筆/秒;`producer_byte_rate=100000` 後 約 167 筆/秒(1/16) | `scripts/quota-test.sh`。**寫入量太小看不出效果**(400 筆不被限速) |
| AD 帳戶鎖定 | 對 GARY 連續 6 次錯誤 → 用對的密碼也 401(MDS、Kafka PLAIN 同時失敗);bootstrap 憑證(緊急路徑)與 SCRAM 機器帳號不受影響;管理員解鎖後 200 | OpenLDAP ppolicy overlay 模擬(`ldap-config/ppolicy-*.ldif`,`up.sh` 載入,鎖定預設關);`scripts/ad-lockout.sh on / off / status / unlock` |

**踩坑**:(1) telemetry 的 `metrics.include` 用萬用字元或沒排除 delta 型態 → Prometheus 對整批回 500(`invalid temporality and type combination`),連原本的監控指標也被丟;每個名稱後面要加 `(?!.*delta).*`。(2) `python3` 在這台 Windows 是空殼,腳本編輯改用 node / perl。

**未解的問題(重要,待查)**:使用了一段時間、做過很多實驗的叢集,**重啟 broker 會失敗**:broker 啟動時 authorizer 的 client(`_confluent-metadata-coordinator`、cluster-link admin、telemetry producer)連自己的 INTERNAL listener(`broker1:9092`),被自己拒絕 `invalid credentials with SASL mechanism SCRAM-SHA-512`,broker 以 fatal exit 結束,重試與清掉本機 metadata 都沒用。重現 3 次;全新叢集連續重啟 5 次都正常;逐項排除:SCRAM 帳號新增與刪除、user quota、max.connections.per.ip、AD 鎖定、role binding、consumer group 讀取、連著的帳號被刪憑證、metadata 快照存在、metadata 日誌膨脹到 11000 筆。**尚未找到觸發條件**。推測與「inter-broker listener 用存在 metadata 裡的 SCRAM 憑證,啟動時自我認證要等 metadata 載入」有關,**未驗證**。正式環境的含意:在客戶環境滾動重啟 broker 前要在測試環境確認;inter-broker 認證考慮改用不依賴 metadata 的方式(例如 mTLS),需另外驗證。

## 第 20 章(進階)Schema Registry 與欄位級加密(CSFLE):同一套授權,與授權限制(`./demo.sh 20`)

**範圍**:把 Schema Registry(SR)納入同一套身分與授權(MDS / AD 群組),並檢查欄位級加密(CSFLE)在這個環境能驗證到哪裡。2026-10-09 在 docker 實測。**結論先講**:SR 的 RBAC(subject、KEK)可以驗證;**CSFLE 的加密與解密不能驗證**——需要企業版加上 CSFLE 加購授權,試用授權註冊帶 ENCRYPT 規則的 schema 會回 `402 Both enterprise and add-on CSFLE licenses are required`。

**元件**:profile `sr` 的一個容器 `schema-registry`(`confluentinc/cp-schema-registry:8.3.2`,約 1.5 GB 映像、768 MB 記憶體);對外 HTTPS:8081(主機埠 8085,因為 8081 被 phpLDAPadmin 用);`scripts/sr-setup.sh` 補授權並啟動。

| 步驟 | 證明 | 設定 / 指令 |
|---|---|---|
| 認證 | 不帶帳密 401、密碼錯 401、AD 帳密 200;SR 不存帳號,Basic 交給 MDS 驗 | `InstallBearerOrBasicSecurityHandler`;`confluent.metadata.bootstrap.server.urls`、`public.key.path` |
| SR 連 Kafka | 與 REST Proxy 同做法:client 憑證(CN=schema-registry)向 MDS 換 token,OAUTHBEARER | `TokenCertificateLoginCallbackHandler`;`client-schema-registry.keystore.p12`(`make-certs.sh` 產生,server 憑證 SAN 補 schema-registry) |
| subject 授權 | gary(topic-admin)可註冊 payments.;yujie(orders-write)可註冊 orders.、註冊 payments. 403;yujie 列 subject 只看到 `["orders.events-value"]`;ming(無群組)看到 `[]` | `scripts/sr-setup.sh` 的 `srbind`:scope 要多 `schema-registry-cluster` |
| KEK 授權 | gary(security 群組,ResourceOwner `Kek:*`)可建 orders-kek;yujie(DeveloperRead `Kek:orders-kek`)建別的 403、讀 200;ming 讀 403 | `dek.registry.rbac.enable=true`;資源名稱 `Kek:<名稱>` |
| CSFLE | 註冊帶 ENCRYPT 規則的 schema → **402 需要企業版 + CSFLE 加購授權**;加密、解密、金鑰輪替**未驗證** | `RuleSetResourceExtension`(沒開時規則被默默丟掉) |

**踩坑(逐一實測,都已處理在 compose 與 sr-setup.sh)**:
1. 只開 HTTPS 時要 `SCHEMA_REGISTRY_INTER_INSTANCE_PROTOCOL=https`,否則啟動失敗(`No listener configured with requested scheme http`)。
2. 啟動前檢查(cub)要 `CUB_CLASSPATH` 含 `/usr/share/java/confluent-security/schema-registry/*`,否則找不到 `TokenCertificateLoginCallbackHandler`。
3. DEK Registry 要自己的 topic `_dek_registry_keys`,SR 身分要有 `_dek_registry` 開頭的 ResourceOwner,否則啟動失敗(`TopicAuthorizationException`)。
4. 沒設 `dek.registry.rbac.enable=true` 時,KEK 端點對所有人 403(日誌:`Couldn't find a corresponding operation to authorize`)。
5. SR 的身分要有 **SR 叢集範圍的 SecurityAdmin**(依官方文件)才能代使用者向 MDS 查授權;沒有時 KEK 端點回 500(日誌:`Authorization request for principal … is not permitted for requestor principal User:schema-registry`、broker 日誌 `Denied Operation = DescribeAccess on resource = Kek:…`)。曾試過把 `User:schema-registry` 加進 `impersonation.super.users`,**沒有用**,已還原。
6. **靜默失敗(測試時觀察到,未納入自動腳本)**:SR 沒開 `RuleSetResourceExtension` 時,註冊帶 ruleSet 的 schema 不報錯,規則被丟掉(`GET /subjects/.../versions/latest` 沒有 ruleSet);producer 用 `use.latest.version=true` 或帶 `value.rule.set` 照常寫入,**卡號以明文落在 topic**,用一般 console consumer 讀原始位元組可見。上線前要用讀原始位元組的方式確認欄位是密文,不能只看 producer 沒報錯。
7. 官方文件:KEK 的 RBAC 只管「誰能建、改、讀 KEK」;**解密能力由 KMS 控制,不是 RBAC**。文件列出的 KMS 型態是 AWS / Azure / GCP / HashiCorp Vault,另有 local-kms(僅供測試);地端沒有看到 CyberArk Conjur 等內建型態,需用自訂 KMS driver 或 Vault。

**未驗證 / 要和客戶確認**:CSFLE 授權的商務與取得方式;地端 KMS(Vault 或自訂 driver)對接;機器(不在 AD)如何向 SR 認證(SR 的 REST 只認 AD 帳密或 MDS token);SR 的高可用與多執行個體(`schema.registry.group.id`);加密對效能與 schema 演進的影響。

## 對應到客戶 RHEL 9 VM 的位置與步驟(手動部署)
| demo | RHEL 9 VM |
|---|---|
| docker-compose 的 `KAFKA_*` 環境變數 | `/etc/kafka/server.properties`(broker)、`controller.properties`;同名小寫句點(`KAFKA_LISTENER_NAME_CLIENT_...` → `listener.name.client....`) |
| `certs/` | `/etc/kafka/secrets/`(權限 600、owner `cp-kafka`);AD CS 根憑證同時放系統信任(`update-ca-trust`)與 Java truststore |
| 各元件 SCRAM 密碼 | Secret Protection / 檔案權限 600 + systemd 獨立使用者;Vault 為後續 |
| `ensure-controller.sh`(`--add-scram`) | 每個 controller 節點首次啟動前:`kafka-storage format --cluster-id <id> -c controller.properties --add-scram '...'`(**順序錯誤需重新 format**) |
| `.env`(audit router) | `server.properties`:`confluent.security.event.router.config=<JSON 單行>` |
| 防火牆 | 9092(INTERNAL)、9093(CONTROLLER)只開放給 broker/controller 節點;Prometheus(9090)、Alertmanager(9093,另一台主機時)只開放給 C3 與必要的監控來源,除非已啟用其 TLS + Basic 認證;8091 為 MDS 與 Admin REST 共用,需對使用者與元件開放,保護靠第 14 章的安全擴充 |

## 已知限制與如實說明
1. OpenLDAP **不是** AD:屬性以 AD 慣例仿造(`member`、`groupOfNames`),巢狀群組/UPN/大小寫行為需以客戶 AD 實測。
2. 群組變更非即時(demo 5 秒;預設 60 秒)。
3. C3 / REST Proxy 向 MDS 認證需**各自一張 client 憑證**(CN=c3 / restproxy);C3 在 RBAC 下與 broker 之間只能走 OAUTHBEARER(以 `TokenCertificateLoginCallbackHandler` 憑證換 token);REST Proxy 連 Kafka 也改用 client 憑證換 token(`TokenCertificateLoginCallbackHandler`,身分 `User:restproxy`,官方 mTLS RBAC 範例做法),不再有 SCRAM 帳號 `svc-restproxy`;`kafka-ready` 健康檢查實測可直接通過,不需要略過。
4. RBAC、LDAP、audit log、REST Proxy security plugin 為商用功能(demo 為 30 天試用)。
5. KRaft 分離 controller + RBAC:依官方 MDS 設定頁,controller 設 `confluent.metadata.server.kraft.controller.enabled=true` 與 token key(`confluent.metadata.server.token.key.path`),使用 `ConfluentServerAuthorizer`,並設定 MDS / audit 連線;**controller 不需要 `ldap.*`**(官方:只有 MDS writer broker 連 LDAP)。**更正**:本專案先前曾記錄「controller 不設 ldap.* 則群組型 role 的 CreateTopics 不生效」,但在重建後的環境重測:controller 在「無 LDAP + 有旗標與 token key」「無 LDAP + 只有 token key」「無 LDAP、無旗標、無 token key」三種設定下,靠 AD 群組取得權限的建立 topic 都成功,沒有群組的對照使用者被拒,ch11 完整章節在最後一種設定下 0 失敗——先前結論重現不了(當時為何失敗未查明,可能是當時別的設定不完整)。目前採官方設定。
6. Postman 證據截圖為 newman 結果渲染(非 Postman 桌面視窗);終端截圖為真實輸出渲染。
