# 設計依據審查:每個選擇的依據是「客戶前提」、「官方」,還是「只有實測」

審查原則(2026-10-04 起):方案依 **客戶先天條件 + 官方限制與建議** 決定;實測只用來驗證選定的方案能不能運作,不能反過來決定方案。
這份文件取代 `BEST-PRACTICE-REVIEW.md` 的分類方式(該檔偏重「實測有沒有通」)。

**客戶前提**:① AD 只有 user / group,沒有服務帳號 ② 憑證管理最小化、希望共用一組 server 憑證 ③ RHEL 9 VM、手動安裝、無 Ansible ④ legacy app 只能走 HTTP(REST Proxy)⑤ 依 AD 群組 + RBAC 分層授權 ⑥ 範圍:Kafka(broker / KRaft controller / MDS)、REST Proxy、Control Center

**分類**
- **A** 客戶前提 + 官方明文支持
- **B** 官方允許(或官方範例),選擇符合前提
- **C** 偏離官方建議,原因是客戶前提;**必須向客戶說明風險與補償**
- **D** 官方未明述,只靠實測;**可能被問倒,要標註**

**官方資料來源**:官方頁面經 WebFetch 取得,已要求逐字引用;WebFetch 本身是摘要工具,重要項目導入前請對原頁再複核。頁面未提及的,標「官方頁未明述」,不當作官方立場。

---

## 一、認證與身分

| # | 決策 | 客戶前提 | 官方 | 實測 | 類別 | 風險 / 補償 |
|---|---|---|---|---|---|---|
| 1 | 人:SASL/PLAIN + LDAP callback,只掛在 CLIENT 埠 | ①⑤ | [LDAP 認證頁](https://docs.confluent.io/platform/current/security/authentication/ldap/client-authentication-ldap.html):「Credentials are sent in PLAIN text, so be sure to use TLS with LDAP」;群組可綁 RBAC | ✅ | **A** | 必須 SASL_SSL;demo 的 `ldap://` 只是示範 |
| 2 | LDAP 以 simple bind 連 AD,外加 LDAPS | ① | [MDS LDAP 設定頁](https://docs.confluent.io/platform/current/kafka/configure-mds/ldap-auth-config.html):simple 是明文、「provides no security」,正式環境建議使用更安全的 SASL 方式 | LDAPS + `ldap.ssl.truststore.*` 實測可用;不設信任庫會失敗 | **C** | 以 LDAPS 保護 simple bind;導入前請客戶確認 AD 是否提供其他方式。bind 帳號為唯讀查詢帳號 |
| 3 | AD 故障時的行為 | — | [LDAP 設定參考](https://docs.confluent.io/platform/current/security/authorization/ldap/ldap-config-ref.html):`ldap.retry.timeout.ms` 預設 86400000(24 小時),逾時後「the Confluent Server Authorizer is marked as failed」;`ldap.refresh.interval.ms` 預設 60000 | ch09:AD 掛掉時 SCRAM 服務不受影響、人的新登入失敗;群組搜尋失敗時沿用上次成功的群組(日誌) | **B** | AD 停擺超過 24 小時授權器會失效;要有 AD 高可用與告警。demo 的 5 秒刷新僅為示範,正式用預設 |
| 6 | 服務:Kafka SCRAM,不放 AD | ① | SCRAM 為官方支援的 SASL 機制 | ✅ | **A** | 密碼不會到期 → 密碼庫 + 輪替流程 |
| 7 | SCRAM 輪替:新帳號名並行;或同帳號 SHA-256 + SHA-512 並行 | ① | 官方頁未明述輪替做法 | 同帳號同機制重設 = 取代(舊密碼立即失效);兩機制並存可行,但啟用第二機制需設定檔 + 重啟 broker(動態設定被接受但不生效) | **D** | 預設用新帳號名並行(要重綁 role) |
| 8 | broker 之間:INTERNAL 埠 SASL_SSL + SCRAM(`kafka-broker`);controller → broker 另用 `kafka-controller` | ①②(使用者決定) | [mTLS RBAC 設定頁](https://docs.confluent.io/platform/current/kafka/configure-mds/mutual-tls-auth-rbac.html)範例 inter-broker 用 mTLS;LDAP 認證頁:不建議 inter-broker 用 PLAIN + LDAP(「intermittent LDAP errors can cause significant broker performance issues」),建議在叢集內部認證(mTLS、無 callback 的 PLAIN 等) | ✅ | **B**(偏離官方範例) | 改 mTLS 會讓持有共用私鑰的元件(REST Proxy、C3 主機)變成 super user → 不採用。`kafka-controller` 憑證必須在 format 時預建,事後補會因授權器起不來而逾時 |
| 9 | controller listener:SASL_SSL + PLAIN 靜態帳號 | ① | SCRAM overview 頁:controller 間不支援 SCRAM(KRaft security 頁寫法不同);PLAIN 為官方範例 | 3 個 controller 用 SCRAM 互相認證失敗、選不出 leader;PLAIN 可組成 quorum、leader 切換正常(僅 SASL_PLAINTEXT 機制測試) | **A** | 多 controller 搭配 TLS + RBAC 未測 |
| 10 | 平台元件(C3、REST Proxy)用 client 憑證向 MDS 換 token,再以 OAUTHBEARER 連 broker | ①② | C3 在 RBAC 下只支援 OAUTHBEARER(官方原句);[mTLS RBAC 頁](https://docs.confluent.io/platform/current/security/authorization/rbac/configure-mtls-rbac.html)有 C3 與 REST Proxy 的憑證式設定;C3 使用 keystore 中的 client 憑證 | ✅ | **A** | c3 憑證 = 管理員(MDS 需要 SystemAdmin),要保護私鑰並列入 protected.users |

## 二、憑證與 TLS

| # | 決策 | 客戶前提 | 官方 | 實測 | 類別 | 風險 / 補償 |
|---|---|---|---|---|---|---|
| 11 | **所有元件共用一張 server 憑證** | ② | [TLS 頁](https://docs.confluent.io/platform/current/security/protect-data/encrypt-tls.html):「Each Confluent Server broker needs its own private-key/certificate pair」 | 共用憑證當 client 身分,MDS 看到的主體都一樣(ch08) | **C** | 私鑰外洩 = 可偽裝伺服器;所有元件都持有同一把私鑰。**待決定**:共用憑證的 EKU 目前含 `clientAuth`,建議收斂成只有 `serverAuth`,避免它被拿來當 client 憑證(未實測,可能影響 ch08 的示範) |
| 12 | Kafka 資料埠 `ssl.client.auth=none` | ① | 資料埠以 SASL 認證,TLS 只做加密;官方頁未明述 none 為建議 | ✅ | **B** | — |
| 13 | 平台元件各一張 client 憑證(c3、restproxy、bootstrap)+ 每個 legacy app 一張 | ①② | mTLS RBAC 頁:各元件有各自的 keystore | ✅ | **A** | 憑證綁 CN;CN 不變就不用重綁 role |
| 14 | 憑證更換:先信任庫、再憑證、最後移除舊根;每個元件就緒才做下一個 | ③ | [CFK 憑證管理文件](https://docs.confluent.io/operator/current/co-manage-certificates.html):「Always renew truststores for all components before renewing certificates」、驗證新舊兩個 CA、「Wait for each component's rollout to complete before proceeding」、先在非正式環境演練;元件間順序文件未規定 | 單節點實驗三情境 + demo 全元件四階段演練 ✅ | **B** | 元件順序(controller → broker → REST Proxy → C3)是參考升級順序,不是憑證文件的規定;動態更新(Kafka 官方 dynamic config 頁)只涵蓋 Kafka listener,MDS 埠實測不會跟著換,本方案以 rolling restart 為主 |

## 三、MDS / RBAC

| # | 決策 | 客戶前提 | 官方 | 實測 | 類別 | 風險 / 補償 |
|---|---|---|---|---|---|---|
| 15 | **MDS 與 REST Proxy `ssl.client.authentication=REQUESTED`** | ① ④ 人沒有憑證、機器有憑證,要並存 | mTLS RBAC 頁範例 `confluent.metadata.server.ssl.client.authentication=REQUIRED`;REST Proxy 頁列出 NONE / REQUESTED / REQUIRED 三個合法值,REQUESTED =「requests (but does not require)」;**人機並存在官方頁未明述**;mTLS RBAC 頁限制:僅新部署、對憑證主體**不支援群組授權** | 人機並存 ✅ | **C / D** | 信任整個 CA、身分取自 CN → 企業 CA 若會發憑證給很多人,要限縮 truststore 或用專用子 CA。憑證主體只能用 `User:` 綁定(符合官方限制) |
| 16 | REST Proxy 同時吃 Basic(人)與 client 憑證(機器) | ④ | mTLS RBAC 頁:`rest.servlet.initializor.classes=io.confluent.common.security.jetty.initializer.AuthenticationHandler`;REST Proxy 頁沒有談兩種並存 | ✅ | **D** | 對映規則屬性:官方 REST Proxy 頁寫 `confluent.rest.auth.ssl.principal.mapping.rules`,我們用 `auth.ssl.principal.mapping.rules`(實測加 `confluent.rest.` 前綴會讓 handler 失效)→ 屬性名與官方頁不同,導入前請向 Confluent 確認 |
| 17 | REST Proxy 代機器 impersonate;`super.users=User:restproxy`;`protected.users` 列所有特權 User | ④ | mTLS RBAC 頁:super users 可 impersonate、protected users 不可被代理,「elevated-permission service principals should be protected」 | `Group:` 混入會讓整份清單失效;c3 憑證呼叫 `/impersonate` 回 403;清單大小寫不符會讓保護失效(見右) | **A** | 靜態名單:AD 新增管理員要同步更新;restproxy 私鑰要保護。**清單區分大小寫,必須寫 AD 記錄的大小寫**(客戶的使用者名稱是 CN 大寫):實測清單寫 User:gary 時,代理 gary 回 403,但代理真正的 GARY 回 200(漏洞);改成 User:GARY 後 GARY 回 403。大小寫不同的 gary、Gary 能拿到 token,但用它做需 UserAdmin 的事回 403(不會繼承 GARY 的群組權限) |
| 18 | bootstrap 為永久 super user(SCRAM 與憑證兩個入口) | ⑤ | [RBAC 概覽](https://docs.confluent.io/platform/current/security/authorization/rbac/overview.html):要先在 broker 設定 `super.user` 才能啟動 RBAC | ✅ | **B** | 官方要求有一個 super user;我們多了「雙入口」與「當日常工具」,建議只留一種入口、完成第一批授權後改用專用身分 |
| 19 | 角色綁在 AD 群組、最小權限 | ⑤ | RBAC 概覽:「grant each user the minimum role required」、綁群組避免逐一授權 | ✅ | **A** | SystemAdmin 人數官方概覽頁未明述上限;建議限縮 |
| 20 | controller 使用 `ConfluentServerAuthorizer` + `kraft.controller.enabled=true` + token key;不設 `ldap.*` | ① | 官方 MDS 設定頁(controller 需 kraft 旗標與 token key;只有 MDS writer broker 連 LDAP) | 單一 controller 實測 ✅;早期「需要 ldap.*」是我的誤判 | **A** | 多 controller 搭配 RBAC 未測 |

## 四、稽核、監控、其他

| # | 決策 | 官方 | 實測 | 類別 | 風險 / 補償 |
|---|---|---|---|---|---|
| 21 | audit:自訂 router;不排除 c3;排除 kafka-broker / kafka-controller;topic 前綴的「被允許 consume」不記錄(被拒仍記) | [audit 概念頁](https://docs.confluent.io/platform/current/security/compliance/audit-logs/audit-logs-concepts.html):預設只記 Management 與 Authorize;produce / consume 要「be very selective … only the most sensitive topics」;excluded principals 用於可信的 audit 讀寫者;建議把 audit 送到另一個叢集;預設保留 90 天 | 取消排除 c3 才看得到 c3 改授權;不關「被允許 consume」會被 C3 輪詢洗版,讀取腳本卡住 | **B / D** | 看不到「誰成功讀了資料」;合規需要時,只對最敏感的 topic 開啟。audit 與業務同叢集、7 天保留僅為 demo,正式環境獨立叢集、依法遵保存 |
| 22 | C3 走 HTTPS(9022);demo 仍留 HTTP 9021 給容器內健康檢查 | C3 範例只有 HTTPS;官方頁未明述 HTTP 的風險 | 2026-10-08 起 demo 的瀏覽器、自動化腳本、API 檢查都走 HTTPS 9022(第 17 章驗證憑證通過、不信任 CA 時被擋) | **D**(9021 殘留僅 demo) | 正式環境只開 HTTPS,移除 HTTP listener,否則登入時 AD 密碼明文 |
| 23 | Prometheus / Alertmanager:HTTPS + Basic(2026-10-08 起 demo 已啟用) | 官方支援 TLS + Basic(7.5+)、mTLS(7.9.1+)(摘要,未逐字複核) | 第 17 章實跑:無帳密 401、錯密碼 401、正確 200、明文 HTTP 400;broker 推指標(api.key / api.secret)與 C3 連線都正常;**官方 TLS + Basic 頁沒寫、實測必要**:Prometheus 設定檔 `alerting.alertmanagers` 要加 `scheme: https`、`basic_auth`、`tls_config.ca_file`(`spike/SPIKE-FINDINGS.md`) | **B**(Prometheus→Alertmanager 那段設定屬 **D**) | Alertmanager 一般帳號即可寫入(Basic 沒有細部授權),OP menu 維護模式用專用帳號;C3 INFO 日誌會印出 Authorization 標頭(Base64),日誌檔要保護 |
| 24 | broker 內建 Admin REST:Basic / Bearer 保護,不設 MDS 連線的服務帳號,不設 client 憑證 | [Admin REST 安全頁](https://docs.confluent.io/platform/current/kafka-rest/production-deployment/confluent-server/security.html):RBAC 設定列 `kafka.rest.confluent.metadata.basic.auth.user.info`(服務帳號);沒有要求 client 憑證;「Without principal propagation … the REST Proxy user makes all requests to Kafka」 | 匿名 401;Basic / Bearer 依使用者授權;不設服務帳號功能正常(建 topic、produce、列群組、刪 topic);設了之後唯一差異是 MDS 日誌的呼叫主體 | **C / D** | AD 沒有服務帳號所以不設;官方未說明不設的後果,未驗證 MDS 改 REQUIRED 時是否仍可行。簡報不提,RUNBOOK 第 14 章保留 |
| 25 | `kafka.rest.bootstrap.servers` 指向 CLIENT 埠 | 官方頁未列 | 指到只開 SCRAM 的 INTERNAL 埠會回 `OAUTHBEARER not enabled` | **D** | 由 INTERNAL 只開 SCRAM 的設計造成 |

---

## 五、需要處理的清單(依優先)

1. **#11 共用憑證 EKU**:**不要收斂**(實測:C3 內部客戶端會出示共用憑證,收斂後對 MDS 的呼叫被拒);治理規則:共用憑證對應的身分 `kafka.demo.local` 永遠不綁任何 role。client 憑證目前沒有 EKU 欄位,是否補 `clientAuth` 尚未測。
2. **#15 / #16**:REQUESTED 並存與對映規則屬性名,向 Confluent 確認並在導入文件寫明限制(truststore 限縮、專用子 CA)。
3. **#2 / #21 / #23**:LDAPS 與 audit 的正式環境做法、Prometheus / Alertmanager 的 TLS + Basic,放進導入步驟。
4. **#18**:bootstrap 雙入口與日常使用,導入後改用專用身分。
5. **#24**:不設 Admin REST 服務帳號的後果,導入前如客戶要用 Admin REST 再實測。
6. ~~簡報補一頁「與官方建議的差異」~~——**使用者決定不做**:簡報只呈現「依客戶前提與官方可用方式選定的做法」,不特意寫與官方不一致之處;本文件僅供內部與顧問備查。

## 六、這份審查的限制

- 官方內容由 WebFetch 摘要取得(已要求逐字引用),不是我逐頁閱讀。
- 官方「Security best practices」總頁沒有抓到,私鑰權限、CA 私鑰存放沒有官方專頁依據。
- Prometheus / Alertmanager、SystemAdmin 人數的官方說法,本輪沒有逐字複核。
- 第 15 章(離職情境)腳本仍從未執行,不可當成已驗證。

---

## 附:2026-10-07 demo 對齊客戶設計後的更新

- **AD 帳號與群組**:使用者名稱 = CN(大寫,GARY、YUJIE、MING),分散在多層 OU;`ldap.user.name.attribute=cn`、`ldap.user.search.scope=2`、群組 member pattern `(?i)CN=([^,]+),.*`、`ldap.principal.mapping=ldap`。登入大小寫不分(打 gary 與 GARY 都成功),但登入後的 principal 一律是 AD 記錄的大小寫(`User:GARY`),**之後所有 role binding、受保護清單、查詢都區分大小寫**。
- **群組(7 組 + 示範用)**:`orders-read`(DeveloperRead)、`ops`(Operator)、`topic-admin`(ResourceOwner Topic\*、Group\*)、`cluster-admin`(ClusterAdmin)、`rbac-admin`(UserAdmin)、`security`(SecurityAdmin + AuditAdmin + audit 讀取)、`breakglass`(SystemAdmin,平常是空的);`orders-write` 是設計外、只為示範「人也能寫」的機制。
- **組長 GARY 不再是 SystemAdmin**,屬 `cluster-admin`、`topic-admin`、`rbac-admin`、`security`。實測 C3 畫面仍可指派 role;第 1 到 16 章都能運作(見實跑紀錄)。
- **實測的角色能力**(`spike/group-roles-aligned/run.log`):`ops`(Operator)只能列出 topic,建 topic、讀資料、改授權都被拒,連 `kafka-topics --describe` 也被拒;`topic-admin`(ResourceOwner)能建/刪 topic、讀資料,**並能在自己的 Topic\* 範圍內改授權(204)**,是強角色,必須臨時加入、事後收回;`rbac-admin`(UserAdmin)只能改授權。
- **2026-10-08 傳輸加密補強(第 17 章,實跑 9/9)**:① AD 連線改 LDAPS(broker 的 `ldap.java.naming.provider.url=ldaps://…:636`、`ldap.java.naming.security.protocol=SSL`、`ldap.ssl.truststore.*`;openldap 日誌證實 broker 連線全在 636、389 沒有 broker;不信任 CA 就連不上)。模擬 AD 的 openldap 仍開 389,只給 phpLDAPadmin 與 ldapmodify 用(真實 AD 的管理走 AD 自己的工具)。② Prometheus、Alertmanager 以 `web-config` 啟用 TLS + Basic,共用 server 憑證的 SAN 補 prometheus、alertmanager(**同一把 key、同一個 CA 重簽**,不換身分、client 憑證不用重發)。③ C3 走 HTTPS 9022(共用 server 憑證)。OP menu 維護模式(25、26)支援 Alertmanager Basic:`OPMENU_ALERTMANAGER_AUTH_FILE` 放專用帳號,帳密以 `curl -K -` 從 stdin 給,不出現在行程清單。**未驗證**:真實 AD 的 LDAPS 憑證鏈(中繼 CA 要放進信任庫,見 `spike/ldaps-intermediate`)、Alertmanager mTLS、C3 在 HTTPS 下由 F5 等 LB 終止 TLS 時的行為。
- **2026-10-08 CyberArk 整合(第 18 章,實跑 13/13)**:以 CyberArk 的開源版秘密管理 **Conjur OSS**(profile `cyberark`:postgres + conjur + nginx TLS 入口 + CLI;`scripts/conjur.sh`)示範「秘密管理」這條路——policy(`config/conjur/policy/kafka.yml`)定義機器身分與秘密、host API key 換 token(8 分鐘)、取秘密;沒被授權回 404、錯 key 401;應用啟動時取 SCRAM 密碼在 tmpfs 組設定(`scripts/app-with-conjur.sh`);輪替(改 Kafka 密碼 + 更新 Conjur,應用重啟跟上、舊密碼失效);OP menu 以 `OPMENU_ALERTMANAGER_AUTH_CMD` 執行時取帳密;**Confluent Secret Protection**(官方)加密 broker 設定檔的 AD 查詢密碼,主金鑰存 Conjur,broker2 啟動前以 host 身分取(`docker-compose.cyberark.yml`、`config/conjur/fetch-secret.py`;對應 systemd ExecStartPre)。**輪替實測發現**:① 帳號與密碼放兩個變數有空檔 → 改單一變數 credential(JSON);② 輪替腳本複製角色失敗不能繼續 → 逐筆檢查、先驗證新帳號再寫 Conjur、失敗回滾;③ audit 不記 orders.* 讀取成功 → 先隔離(解除角色)再看 DENIED;④ **只刪 SCRAM 憑證擋不住已連著的連線(14 筆全寫完),解除角色才切斷**(connections.max.reauth.ms 預設 0)。**本機做不到、未驗證**:PAM 側(PSM 代登入與錄影、CPM 輪替主機帳號、PVWA 依單借出)、商業版 CCP 的 AppID 認證細節、Conjur 高可用。**同日補驗 summon**:CyberArk 官方 `summon`(v0.13.1)+ `summon-conjur`(v0.9.3)對 Conjur OSS 可用:broker2 以 `summon -p summon-conjur -f secrets.yml /etc/confluent/docker/run` 啟動,PID 1 = summon、java 為子程序,主金鑰只在 java 的程序環境(docker inspect、/tmp 皆無),錯 API key → 401、啟動程式不執行;正式環境 systemd `ExecStart` 一行即可,免 ExecStartPre(ExecStartPre 的環境變數不會傳給 ExecStart)。踩坑:Docker Desktop 單檔 bind mount 時 summon-conjur 讀不到 netrc,改掛目錄並在 conjur.conf 設 `netrc_path`。分類:秘密管理 **B**(官方 Secret Protection + Conjur 公開 API),PAM **D**(未驗證)。
- **2026-10-08 帳號被偷之後(第 19 章,實跑 8/8)**:接續第 18 章「只刪 SCRAM 憑證擋不住舊連線」的缺口。① **SASL 重新認證** `listener.name.client.connections.max.reauth.ms`(demo 60 秒,正式建議 1 小時):同樣的實驗 45 筆只寫進 27 筆、舊連線在重新認證時被切斷;**不能動態改**(kafka-configs 拒絕;per-listener 寫法被接受但不生效);② **認證失敗告警**:telemetry 加 `socket.server.failed.authentication.total` 等,Prometheus 規則 `config/c3/security_rules.yml` → Alertmanager,實測 firing 並送達;**踩坑**:`metrics.include` 用萬用字元或沒排除 delta 型態,Prometheus 整批 500 拒收(連原本監控指標也丟),每個名稱後加 `(?!.*delta).*`;③ **TLS 套件**:`ssl.enabled.protocols=TLSv1.3,TLSv1.2` + `ssl.cipher.suites` 只留 AEAD,未設定前 Kafka listener 接受 `ECDHE-RSA-AES128-SHA`(CBC + SHA-1),設定後被拒;MDS(Jetty)本來就拒;只設 Kafka listener;④ **連線上限** `max.connections.per.ip=2`(動態,設在 brokers 層級;`--entity-type ips` 不收),超額連線被拒;⑤ **client quota** `producer_byte_rate=100000`:2741 → 167 筆/秒(1/16);寫入量太小(400 筆)看不出效果;⑥ **AD 帳戶鎖定是雙面刃**(OpenLDAP ppolicy 模擬):對 GARY 連續 6 次錯誤登入 → 連對的密碼也被擋(MDS、Kafka PLAIN 同時),bootstrap 憑證與 SCRAM 機器帳號不受影響,管理員解鎖後恢復。**已查明(2026-10-09)**:刪除 SCRAM 憑證(`kafka-configs --delete-config SCRAM-SHA-512`)之後,下一次重啟 broker 會失敗(authorizer 的 client 連自己的 INTERNAL listener 被拒 `Invalid user credentials`,fatal exit)。全新叢集可 100% 重現(新建帳號再刪除、或對不存在的帳號刪除);只建不刪、改密碼、刪除後重建同名、controller 重啟、日誌膨脹都正常;刪除後把帳號重建即可救回。demo 已把所有「刪除 SCRAM」改成覆寫隨機密碼(`scripts/scram-disable.sh`),整條章節鏈後直接重啟兩台 broker 正常;網路上沒有對應的已知 bug,原因為推測、未驗證,正式環境確認 Confluent 說法前不要刪 SCRAM 憑證。分類:**B**(官方設定與 API,docker 實測);客戶環境的 AD 鎖定原則、F5 登入速率限制、各元件 TLS 套件限定、重新認證間隔對大量 client 的負載**未驗證**。
- **2026-10-09 Schema Registry 與欄位級加密(第 20 章,實跑 5/5)**:SR(profile sr)納入 MDS / AD 群組授權:不帶帳密 401;subject 授權跟群組走(yujie 只能碰 orders.);KEK 授權(`Kek:<名稱>`,`dek.registry.rbac.enable=true`):security 群組可建、orders-write 只讀 orders-kek、無 role 者 403。SR 需要 SR 叢集範圍的 SecurityAdmin(官方文件;`impersonation.super.users` 沒有用)。**CSFLE 加密與解密未驗證**:註冊帶 ENCRYPT 規則的 schema 回 402「Both enterprise and add-on CSFLE licenses are required」(需企業版 + CSFLE 加購授權)。**靜默失敗**:SR 沒開 `RuleSetResourceExtension` 時規則被默默丟掉、producer 不報錯、卡號以明文寫入 topic(測試時觀察,未納入腳本)。官方文件:解密能力由 KMS 控制不是 RBAC;KMS 型態為 AWS / Azure / GCP / Vault(local-kms 僅測試),地端無 Conjur 內建型態。分類:SR RBAC **B**(官方設定,docker 實測);CSFLE **D**(授權限制,未驗證)。
- **demo 的限制**:OpenLDAP 的 `groupOfNames` 至少要有一個 member,所以每個群組放一個不存在的 NOBODY 佔位,否則最後一位成員移不掉(真實 AD 沒有這個限制)。
