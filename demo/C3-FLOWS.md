# Control Center(C3)所有流程與客戶環境限制

狀態標示:✅ 本專案實測 ｜ 📖 官方文件有寫 ｜ ❓ 未驗證/官方未明說

## 一、客戶環境限制(影響 C3 設計的部分)

| # | 限制 | 對 C3 的影響 |
|---|---|---|
| 1 | AD 只有 user/group,沒有服務帳號 | C3 自己連 MDS 不能用 AD 服務帳號。官方 C3 RBAC 頁的範例是帳密(`confluent.metadata.basic.auth.user.info`)📖;官方 mTLS RBAC 頁(7.8+)則提供 C3 用憑證的做法(Streams 用 `TokenCertificateLoginCallbackHandler`,C3→MDS 用 C3 的基本 TLS 設定)📖。本專案以 `confluent.metadata.ssl.*` 另設 client 憑證(CN=c3),屬性與官方範例不同,實測可行 ✅ |
| 2 | 不想管憑證,要共用一張 server 憑證 | 共用憑證只做加密(`ssl.client.auth=none`)。但「C3→MDS」用 client 憑證,等於多一張 CN=c3 的憑證要管;REST Proxy、bootstrap、每個 legacy app 也各要一張,**憑證總數會隨 app 增加**,須與客戶確認 |
| 3 | RHEL 9 VM、手動安裝、無 Ansible | C3 next-gen 需要 Prometheus + Alertmanager 另外部署(📖),都要手動裝、手動設定 |
| 4 | 正式環境人員只能唯讀,依 AD 群組分權 | C3 以登入者本人的 role 判斷;分權=readonly / ops / rbac-admins / admins ✅ |
| 5 | 人與機器並存 | 人走 AD(Basic→MDS→token);機器走憑證換 MDS token ✅ |
| 6 | 官方要求 C3 主體必須是 SystemAdmin | 官方理由:consumer lag 架構需要較高權限 📖。c3 憑證等同管理員:可建立/刪除 role binding ✅;拿掉權限 C3 無法運作 ✅ → 私鑰要嚴格保護 |
| 7 | 商用功能需 license | RBAC、audit、C3 都需對應授權 📖 |
| 8 | 沒有 Schema Registry | C3 預設去連 `localhost:8081`;`confluent.controlcenter.schema.registry.enable=false` 可關閉,連線錯誤消失 ✅(設定官方有列 📖,關閉後的行為官方未說明 ❓) |
| 9 | 客戶 Java 21(映像為 Java 25) | CP 8.3 支援 Java 17/21/25,建議 21 📖;已入 RUNBOOK 差異說明 |

## 二、人的流程(有人在瀏覽器前操作)

| 編號 | 流程 | 路徑 | 狀態 |
|---|---|---|---|
| H1 | 登入 | 瀏覽器 Basic(AD 帳密)→ C3 `GET /api/metadata/security/1.0/authenticate` → MDS → LDAP 驗證 → 回 `auth_token`(JWT RS256,3600 秒) | ✅ |
| H2 | 之後每個請求 | 同時帶 `Authorization: Bearer` 與 HttpOnly `auth_token` cookie;伺服器優先 Bearer,沒有才用 cookie | ✅ |
| H3 | C3 驗證 token | **C3 自己的 API**(如 `/2.0/clusters/kafka`):C3 本地驗章,偽造 / 去簽章的 token 直接 401,MDS 請求日誌(`io.confluent.rest-utils.requests`)沒有對應請求;有效請求再以使用者 token 呼叫 MDS `lookup/.../visibility`。**轉給 MDS 的路徑**(`/api/metadata/security/1.0/...`,例如在 C3 改 role binding):C3 不先驗章,偽造 token 被轉給 MDS,由 MDS 回 401。MDS 直接收到偽造 / 去簽章 token 也是 401。(2026-10-05 以 rest-utils 請求日誌重新驗證;先前「MDS 沒有 401 紀錄」是看錯日誌,`User Principal` 日誌只記認證成功的請求) | ✅ |
| H4 | token 續期 | 觀察到兩個 MDS 簽發的 JWT,最新的在 cookie | ✅ |
| H5 | 看/管 topic、consumer group | 瀏覽器 → C3 內建 REST(`/api/kafka-rest`)→ 以**使用者 token** 走 OAUTHBEARER 連 broker;audit 來源是 C3 IP、主體是使用者 | ✅ |
| H6 | 從 UI produce | 同 H5;ming 只有讀取權限 → Kafka 回 `ClusterAuthorizationException`(DeveloperRead 不含叢集層級 IdempotentWrite;僅 DeveloperWrite/ResourceOwner 含 📖,且 Kafka CLI 直連同樣被拒 ✅);加 DeveloperWrite 後成功 ✅。此拒絕在 audit 查不到(見第八節) | ✅ |
| H7 | 在 UI 管 role binding | 瀏覽器 → C3 → MDS(以使用者身分),MDS 日誌的呼叫者是使用者本人 | ✅ |
| H8 | Schema 相關頁面 | 本環境無 Schema Registry,已關閉 | ✅ |
| H9 | 人直接開 Prometheus/Alertmanager 頁 | 本 demo 未啟用認證 | ✅ |

## 三、機器的流程(無人值守)

| 編號 | 流程 | 路徑 | 狀態 |
|---|---|---|---|
| M1 | C3 自己連 MDS | client 憑證(CN=c3)→ MDS `GET /authenticate` → token(sub=c3),角色 SystemAdmin | ✅ |
| M2 | C3 自己連 broker(Streams、license) | 官方 c3-rbac 頁:C3 在 RBAC 下不支援 OAUTHBEARER 以外的 SASL 📖;實測 Streams 以 c3 憑證換 token 連 broker,拿掉 SystemAdmin 立即授權失敗 ✅ | 📖 ✅ |
| M3 | C3 → Prometheus / Alertmanager | 本 demo 未啟用認證(HTTP);官方支援 TLS + HTTP Basic(7.5+),另有 mTLS 設定頁 📖。**未驗證**實際啟用後的設定與效果 ❓ | ✅(未啟用)/ ❓(啟用) |
| M4 | 外部自動化(CI)呼叫 C3 API | 憑證換 MDS token → 帶 Bearer → 200;沒有 token → 401 | ✅ |
| M5 | 任何人連 Prometheus | 本 demo 未啟用認證,可讀指標 | ✅ |
| M6 | 任何人連 Alertmanager | 本 demo 未啟用認證,可建立/刪除靜音(能靜音告警) | ✅ |
| M7 | broker → Prometheus 指標傳遞 | 未在本次盤點逐項驗證 | ❓ |

## 四、風險彙整

1. **c3 憑證 = 管理員**(M1):外洩可改任何 role binding;拿掉權限 C3 就無法運作,只能靠保護私鑰與檔案權限。
2. **Prometheus、Alertmanager 預設無認證**(M3、M5、M6):官方支援 TLS+Basic 與 mTLS,正式環境應啟用(客戶不想管憑證時,共用 server 憑證做 TLS + Basic 帳密較貼合);未啟用時才以網路隔離補強。
3. **broker 內建 Admin REST(`/kafka/v3`,與 MDS 共用 8091 等埠)預設無認證**:匿名請求曾使 broker OOM 崩潰。**已處理**:依官方 `kafka.rest.` 設定(見第九節、ch14),匿名 401、依使用者身分授權 ✅。
4. **audit 查不到部分拒絕**(見第八節);c3 的事件在本 demo 為降噪而排除:稽核需求要另外盤點。
5. **restproxy 憑證可冒充未列入保護清單的使用者**:gary、c3、restproxy 等已列入保護清單;清單只認 `User:`,混入 `Group:` 會使整份失效(見第十節)。

## 五、驗證狀態
已驗證:偽造 token(OAuthBearerUnsecured,sub=gary)連 broker 被拒 ✅;Admin REST 官方設定可行 ✅;保護清單填群組的後果 ✅。
尚未驗證:簽章竄改過的真 token 直連 broker;M3 啟用 Basic/TLS 後的實測;M7;多 controller 環境。

## 六、各畫面的 API 與身分判斷(實測:`e2e/probe-c3-pages.mjs`,gary=管理員、ming=無任何 role)

| API 族群 | gary | ming | 判斷 |
|---|---|---|---|
| `/2.0/kafka/<id>/brokers`、`topics`、`topics-configs`、`topic-defaults`、`topic-default-config`、`/2.0/consumer/offsets/<id>` | 200 | 403 | 依**登入者身分**授權(Kafka 資料) |
| `/api/kafka-rest/<id>/kafka`(內建 REST) | 200 | 500(內部是 `must have cluster view access`) | 依登入者身分;C3 把拒絕包成 500 |
| `/2.0/clusters/kafka`、`.../display`、`/clusters/connect`、`/clusters/ksql`、`/clusters/schema-registry` | 200 | 200 | 叢集清單/設定類,**不受 ming 的 role 限制**;是 C3 自己的資料或不需授權,從外部無法判定 ❓ |
| `/2.0/feature/flags`、`/2.0/health/status`、`/api/permissions`、`/api/metadata/security/1.0` | 200 | 200 | 同上 |
| `/api/kafka-rest/<id>/v1` | 404 | 404 | 兩人皆 404(UI 探測用,不影響功能) |
| `/api/schema-registry//permissions` | 400 | 400 | 關閉 Schema Registry 後 UI 仍會探測(無害) |

C3 以**自己身分**(c3)的直接佐證:Streams 設定用 c3 憑證換 token、MDS 日誌的 `User Principal: c3`(authenticate/activenodes)、第七節的拿掉權限實驗。官方 C3 RBAC 頁**沒有**明說「C3 以自己或使用者身分查 Kafka」,只說明 SystemAdmin 的理由(consumer lag);因此「使用者操作帶使用者身分」是本專案的實測觀察,不是官方文字。各畫面中「ming 也看得到」的資料究竟是 c3 身分查的還是根本不需授權,本專案未能區分。

## 七、拿掉 C3 自己的權限會怎樣(實測,已還原)

| 動作 | 結果 |
|---|---|
| 暫時移除 `User:svc-c3` 的 SystemAdmin | **無任何影響**:gary 所有畫面仍 200、ming 結果不變、C3 日誌無相關錯誤。compose 內沒有任何地方使用 svc-c3,屬早期殘留的多餘高權限帳號,**已從專案移除**(腳本、audit router、保護清單、SCRAM 憑證) |
| 暫時移除 `User:c3` 的 SystemAdmin | C3 內部工作立刻失敗:`TopicAuthorizationException`(`_confluent-command`、`_confluent-alerts`,license 管理與 Streams)、`Failed to fetch MDS URLs`;約 1 分鐘後 **C3 容器退出(Exited 1)** |

結論:
- C3 的 Streams 與 license 是**以 c3 自己的身分**連 Kafka,且依賴 SystemAdmin;拿掉 C3 就無法運作。
- 因此 c3 憑證的管理員權限無法靠降權緩解,只能靠保護私鑰、限制檔案權限與網路隔離。
- 還原方式:`rbac_bind cert bootstrap User:c3 SystemAdmin` 後 `docker restart control-center`。
- 未回答:c3 失去權限時各畫面的對照(因 C3 整個退出而無法取得)。

## 八、audit log 的事實(官方 vs 本專案)

- 官方預設只擷取 Management 與 Authorize 兩類事件,同時含 allowed 與 denied;produce、consume、describe、interbroker、heartbeat 預設關閉 📖([audit-logs-concepts](https://docs.confluent.io/platform/current/security/compliance/audit-logs/audit-logs-concepts.html))。
- 官方:`kafka.InitProducerId`(idempotent/transactional 寫入初始化,也就是 IdempotentWrite 的檢查)屬 PRODUCE 類,預設不記 📖([auditable-events](https://docs.confluent.io/platform/current/security/compliance/audit-logs/auditable-events.html))。
- 本專案的 audit router(`config/audit-router.json`)是**自訂**的:針對 `orders.*`、`payments.*`、`infra.*` 開了 produce/consume/describe,並只排除 `kafka-broker`、`kafka-controller`;**C3 與 REST Proxy 不排除**,但 topic 前綴的 `consume` 路由不記錄「被允許」的事件(被拒仍記)。
- 實測:ming 只有 DeveloperRead 時 produce 被 Kafka 拒絕(Kafka CLI 直連、C3 皆然 ✅),但 audit 中**找不到**對應事件(即使 router 有叢集 produce 拒絕路由;原因未明 ❓)。
- **更正(先前說錯)與目前做法**:曾以為「c3 的背景操作不在預設 audit 範圍」。實測把 `User:c3` 移出排除清單後,C3 每隔幾秒就對 `orders.events` 產生 `kafka.ListOffsets`、`kafka.OffsetFetch` 的「被允許」事件,幾分鐘內數千筆,洗版審計 topic(連 `--timeout-ms 12000` 的讀取腳本都等不到靜止而卡住)。另一方面,**排除 c3 會讓 c3 憑證的授權變更完全不留紀錄**(實測:c3 改 role binding 無事件,bootstrap 同動作有 2 筆)。目前做法:不排除 c3,改為關閉 topic 前綴 `consume` 路由的「被允許」事件;實測 C3 活動加閒置 5 分鐘無洗版,且 c3 的 `mds.Authorize AlterAccess` 有被記錄。代價:看不到「誰成功讀了資料」,被拒的讀取仍記錄。
- 因此:**不能假設所有被拒的操作都能在 audit 查到**;稽核需求需另外盤點(或加 broker 端授權日誌)。

## 九、broker 內建 Admin REST 的保護(實測,已併入 compose;scenarios/ch14)

官方([Admin REST APIs security](https://docs.confluent.io/platform/current/kafka-rest/production-deployment/confluent-server/security.html))的 `kafka.rest.` 前綴設定:`rest.servlet.initializor.classes=InstallBearerOrBasicSecurityHandler`、`kafka.rest.resource.extension.class=KafkaRestSecurityResourceExtension`、`public.key.path`、`confluent.metadata.bootstrap.server.urls` 與 SSL、`client.security.protocol=SASL_SSL`。本專案另需 `kafka.rest.bootstrap.servers` 指向支援 OAUTHBEARER 的 CLIENT 埠(預設會連到只開 SCRAM 的內部埠,認證後回 `OAUTHBEARER not enabled`)。

| 呼叫 | 結果 |
|---|---|
| 匿名 `GET /kafka/v3/clusters` | 401(未設定時:直接成功,且曾導致 broker 崩潰) |
| 錯誤密碼 | 401 |
| gary(AD 帳密)列 topic、produce | 200,看得到全部、produce 成功 |
| ming(無 role)列 topic | 200,清單為空 |
| ming produce | **HTTP 200,內容 `error_code:40301`**——監控必須看內容的 error_code,不能只看 HTTP 狀態 |

## 十、保護清單(impersonation.protected.users)的陷阱(實測)

- 官方只示範 `User:` 格式(`User:<rp-principal>;User:<其他超級使用者>`),並建議一定要包含 super users 📖。
- 實測:在清單中放入 `Group:kafka-admins`,**整份清單失效**——連清單內的 `User:c3` 都能被 restproxy 憑證冒充(HTTP 200);還原後 gary、c3 恢復 403、一般使用者 200。結論:只能填 `User:`,不要混入群組;推論為清單解析失敗時 fail-open(原因為推論,未查證)。
- 清單是 broker 靜態設定,AD 新增管理員必須同步更新並重啟 broker(重啟為推論,未實測)。
