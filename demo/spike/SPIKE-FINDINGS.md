# M0 Spike 實測結果(CP 8.3.2、KRaft、MDS RBAC、LDAP)

> 以下皆為在本機 docker compose 實際跑過的結果(非文件推論)。環境:`confluentinc/cp-server:8.3.2`(Java 25)、C3 next-gen 2.6.1、openldap(模擬 AD)。

## 已驗證可行
| # | 項目 | 結果 |
|---|---|---|
| 1 | **LDAP 人員登入 MDS**(`bind DN` 唯讀查詢帳號 + simple bind) | ✅ gary/yujie/ming 可登入;錯誤密碼 401 |
| 2 | **CLIENT listener 同時啟用 PLAIN+LDAP / SCRAM-SHA-512 / OAUTHBEARER** | ✅ 同一個 listener 三種機制並存(人用 LDAP,服務用 SCRAM) |
| 3 | **AD 群組 → RBAC role binding**(`Group:kafka-developers`) | ✅ yujie 可 produce/consume,ming 被拒(TopicAuthorizationException) |
| 4 | **加入 AD 群組後 Kafka 端零變更即生效** | ✅ 實測 4–7 秒(`ldap.refresh.interval.ms=5000`;官方預設 60000 即 60 秒,實機需預留約 1 分鐘) |
| 5 | **broker→controller 用 SASL/PLAIN、broker↔broker 用 SCRAM** | ✅ `kafka-storage format --add-scram` 預建 SCRAM 憑證有效。**限制**:本 demo 只有 1 個 controller,**controller 之間的 PLAIN 連線從未被執行過**(官方:controller 間不支援 SCRAM;官方文件之間寫法不一致,kraft-security 頁與 SCRAM overview 頁不同),多 controller 環境需另行實測 |
| 6 | **服務帳號 SCRAM 不在 AD**,以 RBAC `User:svc-orders` 授權 | ✅ 可寫 `orders.*`,碰 `payments.*` 被拒 |
| 7 | **MDS 同時接受 LDAP basic 與 client 憑證(mTLS)**(`ssl.client.authentication=REQUESTED`,user store 仍為 LDAP) | ✅ **FILE 與 LDAP 並存不需要** — mTLS 憑證可直接當平台元件身分(官方 migrate-ldap-to-mtls 頁也說明 MDS 加 HTTPS listener 並將 client 憑證認證設為 REQUESTED,可與既有 LDAP 並存 📖);`CN=bootstrap` 憑證建立第一批 binding |
| 8 | **REST Proxy RBAC + 身分傳遞** | ✅ 人以 Basic(AD 帳密)進入,身分傳到 Kafka:yujie produce 成功、ming/未授權 topic 403、錯誤密碼 401 |
| 9 | **C3 next-gen 2.6.1 + RBAC**,gary(AD 群組 kafka-admins)登入 | ✅ 登入成功,顯示 CP 8.3.2 叢集、topics 14 |
| 10 | **C3 自身以 `TokenCertificateLoginCallbackHandler` 用 client 憑證(CN=c3)取得 MDS token** | ✅ 免 AD 帳號、免密碼檔 |
| 11 | audit log 預設內容 | ⚠ 官方預設:Management + Authorize 類(含 allowed/denied);produce/consume/describe 等預設關閉(見下) |

## 對原計畫的修正(重要)
1. **MDS FILE+LDAP 並存 spike 結論改變**:不需要驗證 FILE。實測 **MDS 可同時接受 LDAP basic 與 mTLS 憑證**,所以 C3、REST Proxy、bootstrap 這類「平台元件身分」用 **各自一張 client 憑證(CN=c3 / restproxy / bootstrap)** 即可,不碰 AD、不放密碼檔。**代價**:這 3 個平台元件需要各自不同 DN 的憑證(共 3 張),與客戶「全部共用一張」衝突 → 簡報須明講:共用 server 憑證只能做加密,平台元件身分需獨立憑證。
2. **C3 自身連 Kafka 不能用 SCRAM**:RBAC 模式下 C3 強制使用 OAUTHBEARER(實測出現 `Unexpected SASL mechanism: SCRAM-SHA-512`;官方 c3-rbac 頁有原句:C3 不支援 OAUTHBEARER 以外的 SASL 機制 📖)。`TokenUserLoginCallbackHandler` 要求 username/password;改用 `TokenCertificateLoginCallbackHandler`(keystore 憑證)才能免帳密。
3. **KRaft 分離 controller + RBAC:controller 也必須用 `ConfluentServerAuthorizer`**,否則 CreateTopics 等需 controller 授權的操作看不到 RBAC role binding(實測:gary 為 SystemAdmin 仍被拒)。controller 需設 `confluent.authorizer.access.rule.providers`、`confluent.metadata.bootstrap.servers` 與連線設定(本 demo 用內部 SCRAM `kafka-broker`)。官方 MDS 設定頁另寫:RBAC 下 controller 節點應設 `confluent.metadata.server.kraft.controller.enabled=true` 並提供 token key,且只有 MDS writer broker 連 LDAP;已依官方設定 controller(旗標與 token key,不給 ldap.*),實測見最後一節「自檢第三輪」。**原計畫 §3「controller 使用 StandardAuthorizer」不正確,已修正。**
4. **TOKEN 與 CLIENT 合併成一個 listener**:不需獨立 TOKEN listener(原計畫 §4 表可簡化)。
5. **REST Proxy 自身的 Kafka 連線**:原本用 SCRAM `svc-restproxy` 且以自訂 ensure 略過 `kafka-ready`;已改為官方 mTLS RBAC 範例的做法(client 憑證換 token、OAUTHBEARER),`kafka-ready` 可直接通過(見「自檢第三輪」)。
6. **audit log**:官方預設擷取 Management 與 Authorize 類事件(含 denied);produce/consume/describe/interbroker/heartbeat 預設關閉。展示資料面的「誰在何時被拒」需自訂 `confluent.security.event.router.config`(已做,見下)。
7. **OpenLDAP 需額外 ACL**:讓 bind DN 唯讀查詢 users/groups,同時 userPassword 不可讀。真實 AD 對應為「唯讀查詢帳號」權限。
8. 映像:`cp-kafka-rest:8.3.2` 存在(前稿誤判),但映像為 Java 25(客戶為 Java 21)。

## 待辦(後續章節驗證)
- audit log 資料面事件設定、群組異動後 C3 UI 顯示變化、C3 RBAC UI 操作、MDS API/Postman、情境 8/9。

## 追加實測(audit log)
- 官方預設 audit 只擷取 Management 與 Authorize 類(本環境預設實際看到的是 `mds.Authorize` 等)。要看到資料面事件,需自訂 `confluent.security.event.router.config`(本 demo:`config/audit-router.json`,以 `.env` 注入):`produce`/`consume`(allowed+denied)與 `describe`(僅 denied),並排除平台雜訊 principal(kafka-broker、kafka-controller、svc-restproxy)。
- **未授權的使用者通常在 Metadata/Describe 就被擋**(`kafka.Metadata`,`granted:false`),不會走到 Produce;因此 `describe` denied 必須納入路由,否則看不到「ming 被拒」。
- **controller 也要設 audit exporter 連線**(`confluent.security.event.logger.exporter.kafka.*`),否則 `Audit log provider could not be started`(controller 沒有 inter-broker listener 可預設使用)。
- 實測事件:`kafka.Produce`(yujie,granted=true)、`kafka.Metadata`(ming/svc-orders,granted=false,operation=Describe)。

## 追加實測(Postman / newman)
- **MDS 驗證成功後會回傳 `Set-Cookie: auth_token=...`,且 cookie 優先於 Basic Auth**。同一個 Postman/newman session 先用 gary 登入,之後「換成 yujie 的 Basic」的請求仍以 gary 身分執行(實測:yujie 竟新增了 role binding,HTTP 204)。對策:collection 層級 pre-request 以「解析變數後的 URL」呼叫 `pm.cookies.jar().clear()`;現場使用 Postman 桌面版換身分前須清除 cookie。簡報/RUNBOOK 須明載。
- Basic 對 REST Proxy 無此問題(REST Proxy 每次請求以 Basic 驗證)。
- `GET /topics/{topic}`(REST v2)對僅有 DeveloperRead 的使用者回 403(需 DescribeConfigs);唯讀者可用 `GET /topics`(列出)確認可見性,或建 consumer 讀取。
- MDS 要求 `Accept: application/json`(否則 406)。

## 追加實測(C3 token 流程、broker 內建 REST)
- **瀏覽器 → C3**:登入時前端以 Basic 呼叫 `/api/metadata/security/1.0/authenticate`(C3 轉給 MDS),回應含 auth_token(JWT,iss=Confluent,3600 秒,用 MDS 公鑰驗章通過)。之後 C3 API 請求**同時帶 `Authorization: Bearer` 與 `auth_token` cookie(HttpOnly、Secure、SameSite=Lax)**;C3 伺服器**優先看 Bearer,沒有 Bearer 才用 cookie**(實測:只帶 cookie=200;cookie 有效+Bearer 亂碼=401;Bearer 有效+cookie 亂碼=200)。token 會續期(用舊 token 呼叫 authenticate 取得新 token,新值寫回 cookie);不在 localStorage / sessionStorage。另有一個非 JWT 的 Bearer 值只用於 /api/metadata 與 /api/kafka-rest(用途未確認)。
- **C3 驗 token**:竄改 sub、竄改 exp、用別把私鑰重簽、alg=none 全部 401;期間 MDS 只記到 1 筆 401(對照:直接送壞 token 給 MDS 會留下 401 紀錄),表示 C3 在本地以 MDS 公鑰驗章(官方:public.key.path 必須與 MDS 相同)。**但每個有效請求 C3 仍會以該使用者 token 呼叫 MDS `lookup/principals/User:xxx/visibility`**(6 次請求≈6~7 次),這是授權/可見範圍,不是驗章。
- **C3 → Kafka(使用者操作)**:`/api/kafka-rest` 由 **C3 內建的 REST** 處理(audit 來源 IP=C3,不是 broker),把使用者的 token 當 SASL/OAUTHBEARER 憑證連 broker;audit:來自 C3 IP 的 kafka.Produce / FetchConsumer / ListOffsets 等主體是 User:gary / User:ming,授權由 broker 判定(例如 role=SystemAdmin)。ming 從 C3 produce 目前回 500(C3 日誌顯示它在連 Schema Registry 預設位址 localhost:8081 被拒),**後續已查明**:C3 預設 Schema Registry 位址為 `localhost:8081`,設 `confluent.controlcenter.schema.registry.enable=false` 後該連線消失;ming 無 role 時 500 的內部原因是 `must have cluster view access`(C3 的 RBAC),給 ming DeveloperRead 後 produce 被 Kafka 以 `ClusterAuthorizationException` 拒絕(缺叢集層級 IdempotentWrite,Kafka CLI 直連結果相同),加 DeveloperWrite 後成功。
- **broker 內建 Admin REST(8090 HTTP / 8091 與 MDS 共用)未設定時沒有認證(已修正,見下方「自檢第二輪」與 ch14)**:broker 日誌 "REST security extensions are not configured";未設定 `kafka.rest.client.*` 時,不帶 token 的 `GET /kafka/v3/clusters` 回 500 "AdminClient thread has exited",broker1 隨即因 OutOfMemoryError(`kafka-producer-network-thread | producer-1`)崩潰(觀察到 2 次:11:04、11:06;日誌顯示該 client 以 Kafka client 的預設協定(PLAINTEXT)去連 SASL_SSL 的 9092,TLS 位元組被誤判為超大訊息長度)。**曾嘗試**以 `kafka.rest.client.security.protocol=SASL_SSL`+固定 SCRAM(kafka-broker)修正 → 匿名、垃圾 token、唯讀使用者全部 200 且能看全部 topic(請求變成以超級使用者執行,更糟),**已撤回**。官方 Admin REST + RBAC 的設定(`kafka.rest.` 前綴)後來已實測可行(見下)。C3 在本 demo 中對 broker REST 只呼叫 `GET /v1/metadata/id` 與 MDS 端點。首次 broker1 崩潰(10:59:22,約 C3 produce 後 1 分鐘)原因未能確認。
- demo 的 broker heap 由 512MB 調為 768MB(穩定性);重啟過的容器要 `docker restart` 才會重新取得 Docker 網路 IP,否則其他容器解析不到。

## 追加實測(第 13 章:C3 身分盤點)
- **人**:瀏覽器登入 → C3 以 `/api/metadata/security/1.0/authenticate` 代轉使用者 Basic 到 MDS 換 token(請求紀錄:僅第一個呼叫是 Basic,其後全為 Bearer);MDS 日誌主體為使用者本人(authenticate / lookup visibility / PUT authorize)。**C3 對 broker 的使用者操作帶使用者身分**:audit 中來自 C3 IP 的 ListOffsets、FetchConsumer、CreateTopics、DescribeConfigs 主體為 User:ming / User:gary。
- **機器**:C3 自己用 client 憑證(CN=c3)向 MDS `GET /authenticate` 換 token(MDS 日誌 `c3 GET /authenticate`;不呼叫 /impersonate;c3 憑證呼叫 /impersonate 為 403),OAUTHBEARER 連 broker(Streams 內部 topic)。(audit router 排除 User:c3 是刻意降噪:實測移出排除清單後,C3 每隔幾秒產生 ListOffsets / OffsetFetch(Describe)事件,幾分鐘內數千筆並洗版審計 topic,已恢復排除。)
- **c3 憑證=管理員**:用 c3 憑證換到的 token 可建立與刪除 role binding(204、204)。官方要求 C3 主體必須 SystemAdmin。
- **機器 → C3 API**:憑證換 MDS token 後帶 Bearer 呼叫 /2.0/clusters/kafka 回 200;無 token 401。
- **Prometheus / Alertmanager 本 demo 未啟用認證**:無憑證讀 Prometheus 200;Alertmanager 可建立與刪除靜音(200)。官方支援 TLS + HTTP Basic(7.5+)與 mTLS,正式環境應啟用;未啟用時需網路隔離。啟用後的設定本專案未實測。
- **官方文件與實測的關係**:官方 C3 RBAC 頁寫明 C3 主體必須是 SystemAdmin(理由:consumer lag 架構),**沒有明說** C3 以自己或使用者身分查 Kafka;「使用者操作帶使用者身分」是本專案的實測觀察。官方 C3 RBAC 頁的 MDS 認證範例是帳密(`confluent.metadata.basic.auth.user.info`);官方 mTLS RBAC 頁(7.8+)則有 C3 憑證範例(Streams 用 `TokenCertificateLoginCallbackHandler`、C3→MDS 用 C3 基本 TLS 設定)。本環境 C3→MDS 用 `confluent.metadata.ssl.*` 另設憑證,屬性與官方範例不同,實測可行。

## 追加實測(第 12 章:legacy app 經 REST Proxy)
- **服務帳號(SCRAM)進 REST Proxy = 401**:REST Proxy 的 Basic 一律交給 MDS 驗證,MDS 只查 AD(LDAP),不認 Kafka 內的 SCRAM 帳號;AD 又不放服務帳號。
- **機器用 client 憑證、人用 Basic 並存可行**:換成官方多協定處理器 `io.confluent.common.security.jetty.initializer.AuthenticationHandler`(官方文件:同時支援多種協定;`auth.ssl.principal.mapping.rules` 專供它使用),`ssl.client.authentication=REQUESTED`。原本的 `InstallBearerOrBasicSecurityHandler` 只讀 Basic/Bearer,憑證會被忽略(401);`InstallCompositeSecurityHandler` 能辨識憑證但代理使用者時報 "No incoming Authorization header while impersonating user"。
- **主體對應**:Java 的憑證 DN 是反序 `O=Demo,CN=legacy-orders`;規則要寫成 `RULE:^.*CN=([^,]*).*$/$1/,DEFAULT`。
- 身分傳到 broker:audit log 的主體是 `User:legacy-orders`(不是 restproxy);最小權限生效(寫 payments 403)。
- 憑證身分只能綁 `User:`(官方:mTLS RBAC 不支援群組授權)。
- **身分傳遞(MDS 請求日誌實測)**:人 → REST Proxy 把使用者 Basic 帳密轉給 MDS `GET /security/1.0/authenticate`(主體=使用者)→ MDS 驗 AD 後直接回 token(JWT,1 小時),沒有 /impersonate;機器 → REST Proxy 以自己的憑證(CN=restproxy)呼叫 `POST /security/1.0/impersonate`(body: targetPrincipalName / targetPrincipalType=USER)→ token(sub=目標,cp_proxy=代理者 DN)→ 之後 `GET /authenticate`(主體=目標;用途為推論)→ 以 token 走 OAUTHBEARER 連 broker,broker 用 MDS 公鑰驗章,主體=sub。
- **impersonation 風險**:只有 `confluent.metadata.server.impersonation.super.users`(User:restproxy)的憑證可呼叫 /impersonate(c3 的憑證=403)。修正前 protected.users 只有 bootstrap/kafka-broker/kafka-controller:restproxy 憑證可代 gary、c3、yujie 等(200)。補上 User:gary;User:c3;User:restproxy 後,這些全部 403,一般使用者仍可代,gary 本人登入與 C3 正常。官方:protected.users「列出不可被代理的特權身分,務必包含 super users」,範例為 User: 形式;**實測填入 `Group:` 項目會使整份清單失效**(見下)。audit 的 actingPrincipal 為空。
- **MDS 帳號密碼檔(FILE)備案不可行**:官方 `confluent.metadata.server.user.store` 允許值為 LDAP(預設)、OAUTH、LDAP_WITH_OAUTH、FILE;無 FILE+LDAP,選 FILE 取代 LDAP,違反「人與機器並存」。OAuth 需要額外的身分服務,客戶沒有。(此項依官方文件判斷,未實機測試組合值。)

## 追加實測(第 11 章:分權)
- **【已被推翻,見最後一節「自檢第三輪」】** 當時的結論:**controller 也需要 LDAP 群組設定**(`ldap.*` 與 broker 相同):只設 ConfluentServerAuthorizer 與 MDS 連線時,controller 解析不到 AD 群組(audit 的 `assignedPrincipals` 為空),導致 CreateTopics / DeleteTopics 對「靠群組取得 role」的使用者一律被拒(SystemAdmin 以外的群組角色都受影響)。補上 LDAP 設定後生效。docker-compose 以 `x-ldap-env` 錨點讓 broker 與 controller 共用。**查證**:Confluent 官方文件(MDS / KRaft 設定頁)只明載「MDS 叢集的所有 broker 都需要 `ldap.*`」與「KRaft 上的 RBAC 要在 controller 設 `authorizer.class.name=ConfluentServerAuthorizer`」,未說明 controller 是否需要 LDAP;CFK 文件則說 KRaftController 不直接設 LDAP(由 MDS 集中查找)。映像內授權器預設 `ldap.group.authorization.enable=true`,本實驗中 controller 不設 `ldap.*` 即解析不到群組。故列為「實測結論」,正式環境請與 Confluent 確認。
- **預設 role 的邊界(查 `GET /security/1.0/roles/<role>`)**:`Operator` 只有 Topic Describe、監控與告警、Connector 狀態/暫停;**不能建 topic**。`DeveloperManage` 有 Topic Create/Delete/Describe/DescribeConfigs,**沒有 AlterConfigs**。要改 topic 設定需 ResourceOwner(同時含讀寫資料)或 ClusterAdmin(叢集範圍,Topic Alter/AlterConfigs,無 Read/Write;實測可改 retention.ms、不能讀寫)。→ 「維運」群組 = Operator(叢集)+ DeveloperManage(topic 前綴);分權重點是「管理 ≠ 讀資料 ≠ 改授權」。
- `UserAdmin`(群組 kafka-rbac-admins)可建立 role binding(MDS `AlterAccess`),不能建 topic、不能讀資料。**注意**:UserAdmin 理論上可替自己或他人授權,屬高敏感角色 → 人數最少、臨時提權、audit 必看(`mds.Authorize` AlterAccess 事件)。
- 萬用字元 `*`(LITERAL)綁 DeveloperManage 在實測中未能讓非 super user 建立 topic;demo 改用前綴(`infra.`)。
- Operator 讓成員能 Describe 全部 topic(列表看得到所有 topic 名稱)。

## 追加實測(自檢第二輪,2026-10-03)
- **官方屬性名稱核對**:REST Proxy 的 AuthenticationHandler 用 `auth.ssl.principal.mapping.rules`(官方 AuthenticationHandler 頁);改成 REST Proxy 安全頁的 `confluent.rest.auth.ssl.principal.mapping.rules` 後 ch12 失敗(主體變成 `O=Demo,CN=legacy-orders`),還原後 0 失敗。`ssl.client.authentication` 官方列 NONE/REQUESTED/REQUIRED;AuthenticationHandler 範例為 REQUIRED,人機並存用 REQUESTED 為本專案實測組合。
- **保護清單填群組**:把 `User:gary` 換成 `Group:kafka-admins` 重啟 broker → restproxy 憑證冒充 gary、yujie、**c3(仍在清單內)全部 200**,整份清單失效;還原後 gary、c3 為 403、yujie 為 200。推論為清單解析失敗時 fail-open(原因未查證)。
- **svc-c3 是無用殘留**:移除其 SystemAdmin 綁定後 C3 全部畫面與日誌不受影響;已從 bootstrap-rbac.sh、up.sh、audit-router、保護清單與 Kafka SCRAM 憑證移除。
- **拿掉 c3 的 SystemAdmin**:C3 的 Streams 與 license 立即 `TopicAuthorizationException`(`_confluent-command`、`_confluent-alerts`),約 1 分鐘後 C3 容器退出。
- **ClusterAdmin**(查 MDS roles API):Cluster 範圍,Topic Create/Delete/Alter/AlterConfigs/Describe/DescribeConfigs,無 Read/Write;實測綁給 ming 後可 `kafka-configs --alter retention.ms` 成功,讀(Group 授權先失敗)與寫(Cluster authorization failed)被拒。
- **偽造 token**:Kafka client 以 OAuthBearerUnsecuredLoginCallbackHandler 產生 alg=none、sub=gary 的 token 連 CLIENT 埠 → `Authentication failed`。(簽章竄改過的真 token 未測。)
- **ming produce 被拒的來源**:只有 DeveloperRead 時,Kafka CLI 直連 produce 即 `ClusterAuthorizationException`;MDS roles API 顯示叢集層級 IdempotentWrite 只在 DeveloperWrite / ResourceOwner。官方歸類 `kafka.InitProducerId` 為 PRODUCE 類(預設不記);本 demo router 雖有叢集 produce 拒絕路由,audit 仍查不到該拒絕(原因未明)。
- **broker 內建 Admin REST 保護(ch14)**:加上官方 `kafka.rest.` 設定(InstallBearerOrBasicSecurityHandler、KafkaRestSecurityResourceExtension、public.key.path、confluent.metadata.bootstrap/ssl、client.security.protocol=SASL_SSL),另需 `kafka.rest.bootstrap.servers` 指向 CLIENT 埠(否則認證後回 `Client SASL mechanism OAUTHBEARER not enabled in the server, enabled mechanisms are [SCRAM-SHA-512]`)。結果:匿名 401(不再崩潰)、gary 200、ming 清單空、ming produce 內容 `error_code:40301`(HTTP 仍 200)。已併入主 compose。
- **環境事故與教訓**:修改 broker 共用環境變數時 docker 連動重建 controller;重建期間(預設 10 秒逾時)留下 10 位元組的空 KRaft snapshot(`__cluster_metadata-0/…snapshot`),重啟後 controller 以它為起點,遺失先前建立的 SCRAM 憑證(`kafka-broker`),兩個 broker 啟動即 `Authentication failed … Invalid user credentials` 退出;還原設定無效,只能 `down -v` 重建。已為 controller1、broker1、broker2 加 `stop_grace_period: 60s`。實機:改設定用 systemctl 逐台滾動重啟,避免強制終止 controller。

## 追加實測(自檢第三輪,2026-10-04)
- **audit 排除 c3 會隱藏管理動作**:用 c3 憑證建立再刪除 role binding(皆 204)→ audit 無事件;用 bootstrap 做同樣動作 → 有 2 筆 `mds.Authorize AlterAccess`。已取消排除 `User:c3`;為避免洗版(c3 輪詢 offset 會產生大量被允許的 ListOffsets / OffsetFetch),topic 前綴的 `consume` 路由改為不記錄被允許事件。結果:c3 活動 + 閒置 5 分鐘無洗版;c3 改授權有紀錄(`User:c3 | mds.Authorize AlterAccess granted=true`)。代價:看不到「誰成功讀了資料」(被拒仍記)。
- **移除殘留** `config/mds/mds-users.txt`(沒有任何 MDS 屬性引用,內含明文密碼)與 broker 自訂 command / 掛載。
- (已被後面取代:實測不需要這張憑證)**Admin REST 改用專用憑證** `CN=adminrest`(不列入 impersonation super users,列入 protected.users):ch14 全數通過;MDS 日誌可見 `User Principal: adminrest` 的 `GET /security/1.0/activenodes/https`,證明身分生效。Admin REST 的 Basic/Bearer 流程不需要 impersonation 權限(實測)。
- **REST Proxy 改用憑證式 OAUTHBEARER**:`client.sasl.mechanism=OAUTHBEARER` + `TokenCertificateLoginCallbackHandler` + `client-restproxy` keystore + `metadataServerUrls`;給 `User:restproxy` 取代 `svc-restproxy` 的 `_confluent-command` 讀寫。ch12 全數通過;ch05 的 REST Proxy 流程(gary/yujie/ming 讀寫、401/403)正確(單獨重跑時 ming 唯讀項依賴第 4 章前置狀態)。移除自訂 ensure 後 `kafka-ready`(日誌 "Check if Kafka is healthy")通過,REST Proxy 正常啟動。已移除 `svc-restproxy` SCRAM 帳號、綁定與建立步驟。
- **controller 官方設定實驗**(推翻先前結論):controller 完全不設 `ldap.*`,三種組合(無 LDAP + 旗標 + token key / 無 LDAP + token key / 無 LDAP、無旗標、無 token key)下,`yujie`(只靠群組 kafka-ops 取得 Operator + DeveloperManage(infra.))建立 topic 都成功;不在任何群組的 `ming` 建立被拒(對照,證明授權在運作);ch11 完整章節在「無 LDAP、無旗標、無 token key」下 0 失敗。官方說只有 MDS writer broker 連 LDAP,與結果一致。先前「controller 需要 ldap.*」的失敗原因未查明。目前採官方設定(旗標 + token key,無 ldap.*)。
- **教訓**:(1) 把 `User:c3` 移出 audit 排除會讓 `--timeout-ms` 的審計讀取腳本因事件持續湧入而永遠不結束;(2) 改 `.env` 的 audit router 會連動重建 controller 與 broker(已有 60 秒停止緩衝,本輪多次重建皆無毀損);(3) 實驗用獨立 compose 副本,結束即刪除。

## 自檢第四輪(2026-10-04,針對使用者對簡報的提問,全部實跑)
- **LDAPS 的 CA 要匯入哪裡**:官方 MDS-LDAP 頁:`ldap.java.naming.provider.url=ldaps://…`、`ldap.java.naming.security.protocol=SSL`,信任庫用 `ldap.ssl.truststore.location/password/type`(「Kafka client 的 TLS 設定加 `ldap.` 前綴」)。實測(用另一個「AD 根 CA」簽 LDAP 憑證,`docker-compose.ldaps-test.yml` + `ldaps-test/`):**broker 不設信任庫** → PLAIN+LDAP 登入失敗(`LdapException: LDAP context could not be created`,根因 `PKIX path building failed`)、群組搜尋也失敗(`LdapGroupManager: search will be retried. Groups from the last successful search will continue to be applied`);**加 `ldap.ssl.truststore.*`** → PLAIN 登入、群組同步、MDS `/authenticate`(人)全部恢復。需要此信任庫的只有「會連 AD 的 JVM」= 跑 PLAIN+LDAP callback 的 broker listener 與 MDS(同一批 broker);controller、C3、REST Proxy 不連 AD。也順帶確認:LDAP 重建後需重套 `ldap-config/acl-bind-dn.ldif`(bind DN 讀取權),否則群組搜尋回 `No such object`,broker 啟動會卡住。
- **群組變更怎麼傳到每台 broker**:LDAP 日誌顯示**同一時間只有 MDS writer broker 對 AD 做群組搜尋**(broker2 重啟後 writer 換到 broker1,搜尋來源跟著換)。writer 把「使用者→群組」寫進 `_confluent-metadata-auth`(實際讀 topic:`{"_type":"User","principal":"User:ming"} → {"groups":[…]}`,另有 `RoleBinding` 與 `Status(writerBrokerId, generation)`),**所有 broker 持續消費該 topic 更新本地快取**。實測:在「leader 在 broker2(非 writer)」的 partition 上,加入群組 ≤3 秒生效、移出群組約 6 秒生效(demo 刷新間隔 5 秒)。
- **token 與 AD 帳號**:ming 取得 MDS token 後,從 AD 刪除 ming:**舊 token 仍可呼叫 MDS(200),但用 Basic 重新登入回 401**。→ 帳號停用/離職後,已簽發 token 在剩餘壽命(預設 1 小時)內仍有效;不會自動撤銷。(尚未測:縮短 token 壽命的設定值、Kafka OAUTHBEARER 連線對已簽發 token 的行為。)
- **SCRAM 並行輪替**:同一帳號同一機制再 `--add-config` 一次 = **取代**(舊密碼立即失效,實測);同一帳號可同時有 SCRAM-SHA-256 與 SCRAM-SHA-512 兩個憑證(實測 describe 可見),**且在 listener 同時啟用兩機制後兩組密碼同時可登入(實測)**;但**動態更新 `listener.name.client.sasl.enabled.mechanisms`(kafka-configs --entity-type brokers)被接受卻沒有生效**,要靠設定檔+重啟 broker 才會啟用第二機制。新舊「不同帳號名」並行(ch09)不會創建失敗,但新帳號要重綁 role。
- **多 controller 的 SASL/PLAIN**:`spike/multi-controller/docker-compose.yml`(3 controller + 1 broker,SASL_PLAINTEXT,只測機制、不含 TLS/RBAC):三個 voter 組成 quorum;停掉 leader 後重新選舉(leader 1→2),重啟後回到 Follower、無 lag;broker 為 Observer。→ controller 間用 PLAIN 靜態帳號可行(未驗證:搭配 TLS、RBAC、controller 數量大於 3)。

- **憑證更換(2026-10-04 實測,`spike/cert-rotation/run.sh`,單節點 Kafka SSL listener、要求 client 憑證,結果見 `evidence.log`)**:① 只換 server 憑證(同 CA、新金鑰):`kafka-configs --entity-type brokers --entity-name 1 --add-config listener.name.ssl.ssl.keystore.location=…` 動態生效,不重啟,client 設定不動仍通過(server 憑證序號確實改變)。② 根憑證用**同一把金鑰**重新簽發:client 信任庫只放新根、server 信任庫換成新根,舊 server/client 憑證都照常通過。③ CA **換金鑰**:錯誤順序(先換 server 憑證、client 信任庫仍是舊根)→ client `PKIX path building failed`,還原後恢復;正確順序 ①server+client 信任庫先放新舊兩個根(舊 client 憑證、新舊 server 憑證都通過)→ ②換 server 憑證 → ③重簽 client 憑證 → ④移除舊根:新 client 憑證通過、未重簽的舊 client 憑證被拒。未驗證:長駐 client 是否需重啟才重載信任庫(以每次新啟動 client 模擬)、MDS/REST Proxy/C3(Jetty)換憑證是否需重啟、中繼 CA。

- **Admin REST 的 adminrest 憑證不是必要的(2026-10-04 實測)**:暫時拿掉 `kafka.rest.confluent.metadata.ssl.keystore.*` 後重建 broker1:匿名 401、錯誤密碼 401、gary(Basic / Bearer)列 topic 200 且為全部、ming 200 但清單為空、ming produce 回 error_code 40301,與有憑證時完全相同;唯一差別是 MDS 日誌不再出現主體 `adminrest`(原本只有 `GET /security/1.0/activenodes/https`)。使用者認證(Basic 轉 MDS `/authenticate`、Bearer 以公鑰驗章)與授權(broker 依 RBAC)都與這張憑證無關。→ 已從 demo 移除該憑證、設定與 protected.users 項目。MDS 若改成 `ssl.client.authentication=REQUIRED` 是否需要,未驗證。
- **controller 間用 SCRAM 實測不行(2026-10-04,`spike/multi-controller/docker-compose.scram.yml`)**:3 個 controller(SASL_PLAINTEXT、SCRAM-SHA-512,format 時 `--add-scram`)互相認證出現 `Authentication failed: Invalid user credentials`,沒有任何 controller 成為 leader,quorum 不成立;與官方 SCRAM overview 頁「controller 間不支援 SCRAM」一致,和 KRaft security 頁寫法不同。推測原因(未驗證):SCRAM 憑證存在 metadata log,quorum 未形成前驗證方無從讀取。單 controller 的 SCRAM 情況未測。

- **共用憑證會被 C3 當 client 憑證出示(2026-10-04,EKU 實驗)**:把共用 server 憑證的 EKU 收斂成只有 `serverAuth` 後重啟全部元件,preflight 仍 15/15,但 C3 與 MDS 日誌持續出現 `certificate_unknown`(C3 失敗的呼叫是 `GET /security/1.0/metadataClusterId`、`/v1/metadata/id`,對象為兩台 broker 的 MDS 埠)。歸因實驗:停掉 C3 約 100 秒,MDS 收到「主體 `kafka.demo.local`(共用憑證 CN)」的 `metadataClusterId` 次數由 120 秒內 6 次降為 0。C3 的 JSSE 握手除錯顯示它的 `restClient`(向 MDS 認證等呼叫)出示的是 `CN=c3` 憑證;C3 設定傾印中,`RestConfig`(17 份)的 `ssl.keystore.location` 為共用 server keystore,Kafka 客戶端類(Admin / Consumer / Producer / SslClientConfig / KafkaRestConfig)為 `client-c3.keystore.p12`。推論:查叢集 ID 的那個內部 HTTP 客戶端沿用 C3 REST 設定(共用 server keystore)。MDS 設 `REQUESTED` 時會要求 client 憑證,Java 對「有符合 CA 的 keystore」會自動出示,MDS 驗證時發現 EKU 缺 `clientAuth` 就拒絕握手(不是忽略)。**結論**:不要收斂共用憑證的 EKU;`User:kafka.demo.local` 不可綁任何 role。精確的設定來源(哪個 C3 屬性)未逐一證實;broker 與 REST Proxy 沒有發現出示共用憑證的呼叫(MDS 日誌中該主體只對應 C3 的呼叫)。

- **Prometheus / Alertmanager 啟用 TLS + Basic(2026-10-05 實測,`spike/c3-monitoring-tls/`,用 override 檔啟用)**:
  ① 共用 server 憑證 SAN 原本沒有 prometheus / alertmanager(`openssl verify -verify_hostname prometheus` → hostname mismatch);用**同一把 key、同一個 CA** 重簽並補 SAN 後通過。
  ② Prometheus / Alertmanager 各一份 `web-config`(`tls_server_config` + `basic_auth_users`,bcrypt 用 `htpasswd -nbBC 10`),demo 映像用 `--web.config.file=/mnt/config/web-config-*.yml`。啟用後:無帳密 401、錯誤密碼 401、正確 200、HTTP 400;Alertmanager 無帳密建立靜音 401。
  ③ C3:`confluent.controlcenter.prometheus.url`(https)、`.ssl.truststore.*`(PKCS12 可用)、`.basic.auth.user.info`;`alertmanager.*` 同。`alias.name` 沒設也能運作。實測 C3 總覽畫面有指標、Prometheus 查詢計數持續增加;C3 的 `/3.0/services/alertmanager/status` 回 ONLINE,把 Alertmanager 帳密改錯變 OFFLINE。
  ④ broker 推指標(telemetry exporter):base url 改 https,`api.key` / `api.secret` 即 Basic 帳密,信任庫設 `confluent.telemetry.exporter.<名稱>.https.ssl.truststore.*`;實測 OTLP 端點 `/api/v1/otlp/v1/metrics` 回 200、兩台 broker 指標都進來。未更新的 broker 仍用 HTTP → Prometheus 日誌 `client sent an HTTP request to an HTTPS server`。
  ⑤ **官方 TLS + Basic 頁沒寫、實測必要**:Prometheus 設定檔 `alerting.alertmanagers` 要加 `scheme: https`、`basic_auth`、`tls_config.ca_file`。對照:沒設時 `Error sending alerts … bad response status 400`,Alertmanager 收不到;設了之後測試告警(永遠觸發的規則)送達。
  ⑥ 未驗證:在 C3 畫面建立告警觸發與靜音、mTLS 做法、實際安裝套件是否由 C3 自動產生 alerting 設定。
  ⑦ 還原:`docker compose --profile c3 up -d --no-deps prometheus alertmanager control-center broker1`,再 `broker2`(逐台),最後 `docker restart control-center restproxy`。
- **C3 告警功能的實際運作(2026-10-05 實測,TLS + Basic 狀態下,用 `demo/e2e/c3-create-trigger-action.mjs` 操作 C3 畫面)**:
  C3 告警區只有 Overview / History / Triggers / Actions,**沒有靜音**;API 是 `/3.0/alerts/{triggers,actions,history}`。
  建 trigger → C3 寫 `trigger_rules-generated.yml`(PromQL 規則,alertname 為「trigger 名稱$$guid」)並通知 Prometheus 重新載入(Prometheus 同一秒 `Loading configuration file`)→ 由 **Prometheus 評估規則並送告警給 Alertmanager**。
  建 action(email,需先在 C3 開 `confluent.controlcenter.mail.*`,demo 預設未開會回 400 `Email alerts are not enabled`)→ C3 寫 `alertmanager-generated.yml`(receiver + 依 alertname 比對 trigger guid 的路由),再對 Alertmanager `POST /-/reload`(帶 Basic),日誌 `Reloading Alert Manager configuration succeeded`;`GET /api/v2/status` 讀回,執行中的設定含新 receiver。
  **C3 的 INFO 日誌會印出請求標頭**:`Authorization:Basic …`(Base64 解開 = `c3:prom-pw` / `c3:am-pw`),Prometheus 與 Alertmanager 帳密都會留在 C3 日誌 → 日誌檔要保護。
  未驗證:C3 建立的 trigger 實際觸發並寄出通知(demo 用假 SMTP)、靜音(C3 無此功能,只能直接打 Alertmanager API)。
  測完已刪除 demo trigger / action,並把 `config/c3/alertmanager-generated.yml` 還原為原內容。

## 2026-10-05 補測(Kafka 安全整理簡報的三項未實測)
- **LDAPS 中繼 CA**(`spike/ldaps-intermediate/`,只動 broker2,測完還原):用 nginx stream 在 openldap:389 前面做 TLS,憑證由「root → 中繼 → 葉」簽發,伺服器只送葉憑證(openssl s_client 確認 1 張)。broker2 的 `ldap.ssl.truststore` 只放 root:MDS Basic 401、Kafka PLAIN+LDAP 登入 SaslAuthenticationException,日誌 `PKIX path building failed`;放 root+中繼:皆成功;只放中繼:皆成功、重啟後 PKIX 0 筆。
- **SecurityAdmin / AuditAdmin**(暫時綁 User:ming,測完解除):SecurityAdmin 可查 role binding(lookup role、查某人角色 200),新增/指派 role binding 403,讀與改 audit 設定 403;AuditAdmin 讀與更新 audit 設定 200(PUT 相同內容),查 role binding 403;兩者讀 topic、建 topic 皆被拒。
- **交易 producer**(svc-orders,只有 Topic orders. 的 DeveloperWrite):`kafka-producer-perf-test --transactional-id` → TransactionalIdAuthorizationException;加綁 `DeveloperWrite TransactionalId zz-txn-test LITERAL` 後成功;解除後再次被拒。
- **C3 轉發路徑不帶 token**:C3 內部 HTTP 客戶端向 MDS 出示共用 server 憑證,MDS 日誌主體 `kafka.demo.local`;`/roles` 200、lookup 403(該身分無 role);偽造 token 401。
- **腳本入口**:C3 自己的 API Basic 401、Bearer 200;REST Proxy 與 MDS Basic/Bearer 皆 200。

## 2026-10-05 登入大小寫與 `ldap.principal.mapping`(`spike/ldap-principal-mapping/override.yml`)
- 預設(`ldap.principal.mapping=default`):登入後的身分 = 使用者輸入的字串。以 `GARY` / `Gary` 登入(AD 紀錄與群組 member 是 `gary`):MDS 認證 200、token sub 分別為 `GARY` / `Gary`;需要 SystemAdmin 的查詢 403;Kafka PLAIN+LDAP 認證成功但只看得到 1 個 topic(`gary` 是 16 個)。也就是認證過、群組權限全失。
- 設 `ldap.principal.mapping=ldap`(兩台 broker):以 `gary` / `GARY` / `Gary` 登入,token sub 都是 `gary`,管理查詢 200,Kafka 都看得到 16 個 topic;錯密碼 401;SCRAM 與憑證身分不受影響。
- 官方(LDAP configuration reference):ldap 模式用 LDAP 紀錄的大小寫當身分;Important:role binding 裡的使用者主體要符合 LDAP 紀錄的大小寫。
- 客戶 AD 範例:群組 member 為 `CN=<帳號大寫>,OU=<單位>,OU=A01419,OU=TCBUsers,...`,使用者分散多層 OU → pattern 用 `CN=([^,]+),.*`、`ldap.user.search.scope=2`(官方預設 1)、object class 改 group/user。待確認:CN 與 sAMAccountName 是否相同(含大小寫)、Kafka 群組放哪個 OU、群組人數。

## 2026-10-05 把共用 server 憑證的身分列為 super user 的後果(`spike/server-cert-superuser/`,測完已還原)
- 背景:主管提議 controller 與 broker 之間直接用共用 server 憑證做 mTLS,把憑證 CN 列為 super user。
- 實驗:只在兩台 broker 的 `super.users` 加上 `User:kafka.demo.local`(共用 server 憑證的 CN)。
- 結果:**完全不帶帳密、不帶憑證**,經 C3 的轉發路徑 `https://c3:9022/api/metadata/security/1.0/principals/User:zz-attacker/roles/SystemAdmin` POST → 204,zz-attacker 取得 SystemAdmin;MDS 日誌主體是 `kafka.demo.local`。改之前同一請求是 403。直接打 MDS 不帶任何東西仍是 401。
- 原因:C3 內部的 HTTP 客戶端會向 MDS 出示共用 server 憑證(MDS 設 REQUESTED);請求沒有 Authorization 標頭時,MDS 以憑證 CN 當身分。

## 2026-10-05 controller 與 broker 之間用 mTLS(專用憑證),不用內部帳號(`spike/internal-mtls/`,獨立叢集,測完已關閉)
- 架構:1 controller + 2 broker,接主 demo 網路借用 openldap。CONTROLLER 與 INTERNAL listener 設 `SSL` + `listener.name.<x>.ssl.client.auth=required`,keystore 用專用憑證(CN=kafka-internal,SAN 含各節點主機名稱,EKU serverAuth+clientAuth);CLIENT listener 與 MDS 用另一張 server 憑證。`super.users=User:kafka-internal;User:bootstrap`。沒有任何內部帳號:format 時 0 個 --add-scram,controller 設定檔沒有 JAAS。
- **內部 listener 的 keystore 同時是「該埠的 server 憑證」與「連出去時出示的 client 憑證」**,所以專用憑證必須帶節點主機名稱的 SAN;broker 連 controller 用 `listener.name.controller.ssl.keystore.*`;controller 連 broker 讀 RBAC 用 `confluent.metadata.security.protocol=SSL` + `confluent.metadata.ssl.keystore.*`。
- **踩坑**:Kafka 看到的憑證主體字串是 `O=Demo,CN=kafka-internal`(CN 不在最前面);規則寫 `RULE:^CN=([^,]+).*$/$1/` 對不上,身分變成整串 DN,broker 連 controller 得到 ClusterAuthorizationException 後退出。改成 `RULE:^.*CN=([^,]+).*$/$1/,DEFAULT` 後正常。
- 通過:bootstrap 憑證建第一筆 role binding(204);gary(AD,PLAIN)建 topic(RF=2,ISR 兩台);寫入並從另一台讀回;bootstrap 憑證換 token 建 SCRAM 服務帳號;停掉一台 broker 再啟動,ISR 回到兩台、重啟後 0 筆錯誤;controller quorum leader 正常。
- 內部埠的存取:不帶 client 憑證 → SslAuthenticationException(連不上);帶 c3 的憑證(同 CA 簽發)→ 連得上,身分是 User:c3,只看得到 1 個內部 topic、建 topic 被拒(TopicAuthorizationException),連 controller 是 ClusterAuthorizationException;帶專用憑證 → super user。也就是:同一個 CA 簽的任何憑證都能「連上」內部埠,但權限依自己的身分,防火牆仍然需要。
- 未測:多台 controller 的 quorum 用 mTLS、C3 與 REST Proxy 接這個叢集、專用憑證的更換、controller 的 audit 匯出(本實驗沒設,日誌有 Audit log provider could not be started)。

## 2026-10-05 內部埠只做 TLS、不要求 client 憑證(`spike/internal-mtls/ssl-only.override.yml`,測完已關閉)
- 設定:CONTROLLER 與 INTERNAL listener `ssl.client.auth=none`;因為沒有身分,來者都是 `User:ANONYMOUS`,要讓叢集運作只能 `super.users=User:ANONYMOUS;User:bootstrap`。
- 叢集可運作:建 role binding、AD 帳號建 topic、ISR 兩台。
- 代價(實測):任何人不帶憑證、不帶帳密連 broker 內部埠 9092 → 列出全部 topic、建立 topic、建立 SCRAM 帳號、讀取他人 topic 的資料,全部成功;連 controller 9093 可讀 quorum 狀態。MDS 不帶帳密仍是 401。
- 結論:內部埠等於沒有認證與授權,安全完全依賴網路隔離。

## 2026-10-06 controller 不開授權、controller listener 只做 TLS、broker INTERNAL 用 mTLS(`spike/internal-mtls/ctl-noauthz.override.yml`,測完已關閉)
- 設定:controller `authorizer.class.name=`(空)、`confluent.metadata.server.kraft.controller.enabled=false`、CONTROLLER listener `ssl.client.auth=none`;broker 維持 ConfluentServerAuthorizer,INTERNAL listener `ssl.client.auth=required`(專用憑證)。
- 叢集可啟動、無錯誤;bootstrap 建 role binding、管理員建 topic、ISR 兩台正常。
- **假設成立**:controller 對 broker 9092 的連線數 0(主 demo 有授權器的 controller 是 5)。
- **代價一(經 broker,已登入但沒有任何 role 的 AD 帳號 ming)**:建 topic 成功、建 SCRAM 帳號成功、改別人 topic 的設定(retention.ms)成功;主 demo 同樣動作是 TopicAuthorizationException / ClusterAuthorizationException。讀資料仍被拒(TopicAuthorizationException,由 broker 授權)。刪 topic 因指令工具先查詢(被 broker 擋)而失敗,未確認底層請求是否會被擋。
- **代價二(不帶憑證、不帶帳密直連 controller 9093)**:可查 quorum、可改 broker 的叢集預設動態設定、可改 topic 設定;建 SCRAM 回 UnsupportedEndpointTypeException(此 API 不支援直連 controller);加 ACL 回 SecurityDisabledException(沒有授權器)。
- 經 broker 加 ACL:被拒(DESCRIBE_ACLS 需權限),事後清單為空,未造成提權。
- 原因:KRaft 下建 topic、改設定、建 SCRAM 等請求由 broker 轉給 controller,由 controller 的授權器判斷;controller 沒有授權器就全部放行。

## 2026-10-06 群組與 role 自檢的實測(`spike/group-roles/`,用 User:ming 暫綁,測完全部解除)
- **ResourceOwner(Topic `*` + Group `*`,LITERAL)**:建 topic、改 retention、讀設定、重設 consumer offset、刪 consumer group、刪 topic 全部成功;建 SCRAM 帳號被拒(`ALTER_USER_SCRAM_CREDENTIALS needs ALTER permission`)、改 broker 動態設定被拒(ClusterAuthorizationException)。→ 適合「topic 管理」群組。
- **ClusterAdmin**:建與刪 SCRAM 帳號成功、建與刪 topic 成功。→ 應用系統帳號(OP menu 34、35)需要 ClusterAdmin。
- **AuditAdmin 單獨**:讀 `confluent-audit-log-events` 被拒(TopicAuthorizationException)。加 DeveloperRead @ Topic `confluent-audit-log-events`(LITERAL)+ DeveloperRead @ Group `audit-`(PREFIXED)後讀到資料。→ 稽核群組除了 AuditAdmin 還要這兩筆。
- **lookup roleNames**:`POST /security/1.0/lookup/principals/User:gary/roleNames` 用 bootstrap 憑證查,回 `["SystemAdmin"]`(gary 是經 Group:kafka-admins 取得,所以會把群組的 role 算進去)。**但 ming 用自己的 token 查自己回 403**(需要 SecurityMetadata Describe)。→ OP menu 的第二人資格檢查要用 bootstrap 憑證查,不能用第二人自己的 token。
- 元件主體現況:`User:c3` → SystemAdmin;`User:restproxy` → DeveloperRead + DeveloperWrite @ Topic `_confluent-command`(LITERAL);bootstrap 在 super.users,沒有 role binding。

## 2026-10-06 OP menu 的 vm 後端在 Rocky Linux 9 容器實測(`rocky/`)
- 跳板機容器:Rocky 9 + Java 21 + 從 cp-server 8.3.2 映像複製的 `/usr/bin/kafka-*`、`/usr/share/java`、`/etc/kafka`;工具可直接連 demo 叢集(SASL_SSL PLAIN 與 OAUTHBEARER token 登入都正常)。`gary` 登入殼層 = opmenu;`sudo -u opbootstrap /usr/local/sbin/opmenu-bootstrap kafka|mds` 可用,`gary` 直接讀 `/etc/opmenu/bootstrap` 被拒。
- 節點容器:Rocky 9 systemd(privileged)+ sshd + 假服務;跳板機 ssh 金鑰登入後 `sudo systemctl restart`、`journalctl -u`、清理日誌腳本都依 sudo 規則放行。
- 23 項全部通過(紀錄見 `rocky/test.log`);程式碼一行未改環境值,只換 `/etc/opmenu/opmenu.conf`。
- 修正:設定檔優先順序改為 `$OPMENU_CONF` → `/etc/opmenu/opmenu.conf` → 程式目錄;18/43 的輸出目錄抽成 `OPMENU_OUT_DIR`(程式目錄唯讀時用);vm 後端 bootstrap 改 `sudo -u $OPMENU_BOOTSTRAP_USER`。
- 容器時區是 UTC,紀錄時間與主機差 8 小時;正式環境設 TZ。
- 追加(同日):跳板機 sshd `Match Group opmenu` + `ForceCommand` + 禁轉埠/agent:`ssh jump id`、scp、sftp 都只進選單並記 BYPASS_ATTEMPT(用 SSH_ORIGINAL_COMMAND);`-L` 轉埠實連回 administratively prohibited。MDS 多台逗號分隔逐台嘗試:第一台填不存在主機時選單與包裝腳本都自動用第二台;全掛時登入回 MDS_DOWN。
- 追加(同日):`OPMENU_SSH_AUTH=key|password` 與 ControlMaster 在 Rocky 實測通過:password 模式(PubkeyAuthentication=no,sshpass -e 餵登入選單時的 AD 密碼)可 ssh 到節點重啟服務;節點密碼與 AD 不同時 Permission denied → 項目 FAIL;ControlMaster 第二次連線重用(`-O check` Master running),離開選單 `be_cleanup` 關閉。跳板機 sshpass 來自 EPEL。

## 2026-10-06 誰能指派 role binding(用 User:ming 暫綁各角色,以 AD 帳密呼叫 MDS,測完解除;結果未另存腳本)
- ClusterAdmin 指派 DeveloperRead(Topic 前綴)→ **403**。
- ResourceOwner(Topic 前綴 optest.)指派在自己前綴內(optest.sub.)→ **204**;指派到範圍外(other.)→ **403**。
- UserAdmin 指派到任意前綴 → **204**。
- 結論:授權只有 UserAdmin(跨範圍)與 ResourceOwner(限自己的資源範圍);ClusterAdmin 不能授權。
- 同日確認官方 Control Center system requirements 頁:next-gen 最低 Java 17;≤10 萬 replica 為 4 核 / 8 GB / 200 GB,超過為 8 核 / 16 GB / 300 GB;該頁沒有提到 Prometheus(「不支援外接 Prometheus」僅見於搜尋摘要,未讀到原頁)。

## 2026-10-06 夜~10-07:OP menu 批 B/C/D、設定推算與 LB 相關實驗
- **OP menu 新增**:10 leader 與 partition 分布、11 cluster 與身分鏈健康檢查(併入 MDS 逐台狀態、token 剩餘、controller quorum)、19 生效設定與來源、25/26 維護模式(Alertmanager silence)、27 滾動重啟、44 權限清單匯出、45 audit 查詢;機制:變更時窗、並行鎖。細節與限制見 `opmenu/README.md`;回歸 `opmenu/test-batch-bcd.sh`(36 項)、`opmenu/test-derive.sh`(13 項)。
- **設定推算實測**:`/v1/metadata/id` 不需帳密即可取 cluster ID;`kafka-broker-api-versions` 零 role 可列 broker;`kafka-configs --describe --all`(log.dirs)與 `kafka-metadata-quorum` 要 ClusterAdmin(Operator 被 ClusterAuthorizationException 拒);**broker 停掉後會從叢集的 broker 清單消失**,所以 broker 清單與節點清單不從叢集推算(它們也是重啟、ssh 的允許清單)。探測腳本見 `opmenu-derive/`。
- **LB(nginx 模擬 F5)**:見 `lb-nginx/FINDINGS.md`。L4 透傳保留 legacy app 的 mTLS 身分;L7 終止 TLS 讓 REST Proxy 看不到 client 憑證(連 header 轉送都不認);LB 用固定 client 憑證連後端會讓所有人(含無憑證)變成同一個身分;REST Proxy 到 MDS 同理;nginx 的 upstream TLS session 復用會讓後端沿用先前連線的身分(實驗要關)。
- **REST Proxy 設多台 MDS**:見 `rp-mds-failover/FINDINGS.md`。停任一台 MDS 請求仍成功,第一個受影響請求約 8 秒;不需要在 MDS 前面放 LB。
- **滾動重啟的判斷陷阱**:剛重啟完 10 秒內「在線 2/2、under-replicated 0」是假象(舊 broker 還在清單、ISR 尚未縮減),要先等 settle 再連續多次健康。
- **audit 讀取**:固定 consumer group 第一次提交 offset 後,`--from-beginning` 不再生效、讀不到舊事件;每次要用獨立 group 並關閉 auto commit。
