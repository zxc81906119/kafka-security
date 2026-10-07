// 「Kafka 安全整理」表格版:依使用者自己列的五頁大綱(桌面 Kafka 安全整理.pptx)整理成表格。
//   SPEC=./build-kafka-notes.js OUT=Kafka-安全整理-表格版.pptx node build-solution-iisi.js
const path = require('path');
const { SLIDES: ALL, THEME, HEX, H } = require('./build-solution-deck.js');
const { chip, table, text, P, HUM, SVC, PLT, MDS, RISK, INK } = H;
const S = [];
const add = (s) => S.push(s);

add({ layout: 'TITLE', title: 'Kafka 安全整理', coverTitle: 'Kafka 安全整理', coverSub: '傳輸加密、認證、授權、元件交互', noCoverLines: true, items: [], notes: '依原本的五頁大綱整理成表格:傳輸加密、認證、授權、與 Kafka 元件交互。' });

// 傳輸加密(一):要準備什麼
add({ title: '傳輸加密:要準備的憑證與信任庫', sub: 'server 端共用一組憑證;要證明身分的元件另有 client 憑證', items: [
  table(0.6, 1.5, [2.4, 3.6, 3.3, 2.83], [
    ['項目', '放什麼', '誰要設定', '注意'],
    ['keystore', '共用的一組 server 私鑰與憑證', 'broker、controller、MDS、C3、REST Proxy', 'SAN 要涵蓋這些元件對外的網域或 IP'],
    ['truststore', '簽發 server 憑證的 root CA 憑證', '每一條連線的 client 端(見下一頁)', '只放 CA 憑證,不放私鑰'],
    ['LDAPS 的 truststore', '簽發 AD server 憑證的 CA 憑證', 'broker 與 MDS(共用一組設定)', 'AD 走 LDAPS 時才需要;AD 只送出自己的憑證時,要匯入中繼 CA'],
    ['client 憑證', '各自的私鑰與憑證;憑證的 CN 就是身分', 'C3、REST Proxy、bootstrap、各 legacy app', '向 MDS 或 REST Proxy 證明身分;共用的 server 憑證不當身分'],
  ], { rowH: 0.82, hdrH: 0.46, sz: 12.5, col: INK }),
], notes: 'broker、controller、C3、REST Proxy、MDS 共用一組 server 私鑰與憑證,設定在 keystore;SAN 必須涵蓋這些元件對外的網域或 IP。client 端的 truststore 匯入簽發 server 憑證的 root CA 憑證。MDS 與 broker 會連 AD,AD 走 LDAPS 時,要另外設定信任庫,匯入簽發 AD server 憑證的 root CA;MDS 與 broker 共用一組設定。補充(原大綱沒列):C3、REST Proxy、bootstrap 與經 REST Proxy 的 legacy app 另外各有一張 client 憑證,用來向 MDS 或 REST Proxy 證明身分(見認證與元件交互各頁);共用的 server 憑證只做加密,它的 CN 不綁任何 role。AD 的 LDAPS 憑證若由中繼 CA 簽發而 AD 只送出自己的憑證(不附中繼 CA),實測(2026-10-05,demo 的 broker2 連到一個只送葉憑證的 LDAPS 端點):信任庫只放 root CA 時,MDS 的 Basic 登入與 Kafka 的 PLAIN 加 LDAP 登入都失敗,broker 日誌是 PKIX path building failed;信任庫放 root CA 加中繼 CA,或只放中繼 CA,兩種登入都成功。AD 若會送出完整鏈,則只放 root CA 即可(主 demo 先前的 LDAPS 實驗)。' });

// 傳輸加密(二):哪些連線
add({ title: '傳輸加密:哪些連線要設信任庫', sub: '列是 client 端,欄是連到的 server 端', items: [
  { ...table(0.6, 1.5, [2.63, 1.9, 1.9, 1.9, 1.9, 1.9], [
    ['client 端 ↓ / server 端 →', 'broker', 'controller', 'MDS', 'C3', 'REST Proxy'],
    ['broker', '需要', '需要', '', '', ''],
    ['controller', '需要', '需要', '', '', ''],
    ['MDS', '需要', '', '', '', ''],
    ['C3', '需要', '', '需要', '', ''],
    ['REST Proxy', '需要', '', '需要', '', ''],
    ['外部 client', '需要', '', '需要', '需要', '需要'],
  ], { rowH: 0.6, hdrH: 0.46, sz: 12.5, col: INK }), rowCols: [HUM, PLT, MDS, SVC, SVC, INK] },
  chip('標「需要」的每一條連線,client 端都匯入同一張 root CA 憑證', 0.6, 5.75, 12.13, HUM, { sz: 12.5, h: 0.45 }),
  chip('外部 client:人的 CLI 與瀏覽器、服務、legacy app、bootstrap', 0.6, 6.3, 12.13, SVC, { sz: 12.5, h: 0.45 }),
], notes: '原列的九條連線:broker→broker、controller→broker、MDS→broker、broker→controller、controller→controller、C3→broker、C3→MDS、REST Proxy→broker、REST Proxy→MDS。補充(原大綱沒列,已併入表格最後一列與後兩欄):外部 client 連進來時也需要信任同一張 root CA:人的 CLI 與服務連 broker;瀏覽器連 C3;腳本與 legacy app 連 REST Proxy;bootstrap 與腳本直接呼叫 MDS。' });

// 認證
add({ title: '認證:誰連誰,用什麼機制', sub: '連到 broker 與 controller 的五種連線', items: [
  { ...table(0.6, 1.5, [2.6, 1.8, 2.9, 4.83], [
    ['誰連', '連到哪', '機制', '帳密或憑據在哪'],
    ['broker、controller', 'broker', 'SASL/SCRAM-SHA-512', 'Kafka 內的 SCRAM 帳號'],
    ['broker、controller', 'controller', 'SASL/PLAIN', '寫在 JAAS 設定的帳號與密碼'],
    ['人', 'broker', 'SASL/PLAIN + LDAP', 'AD 的帳號與密碼'],
    ['服務', 'broker', 'SASL/SCRAM-SHA-512', 'Kafka 內的 SCRAM 帳號'],
    ['C3、REST Proxy、bootstrap', 'broker', 'SASL/OAUTHBEARER', '帶 MDS token:元件自己的(用 client 憑證換),或代人、代 legacy app 取得的'],
  ], { rowH: 0.72, hdrH: 0.46, sz: 12.5, col: INK }), rowCols: [PLT, PLT, HUM, SVC, MDS] },
  chip('前兩列是叢集內部元件互連;後三列是外部連進 broker', 0.6, 5.85, 12.13, PLT, { sz: 12.5, h: 0.48 }),
], notes: 'Kafka 叢集內部元件溝通:broker、controller 連 broker 用 SASL/SCRAM-SHA-512;broker、controller 連 controller 用 SASL/PLAIN,帳號密碼寫在 JAAS 設定。人連 broker 用 SASL/PLAIN 加 LDAP(AD)。服務連 broker 用 SASL/SCRAM-SHA-512。C3 與 REST Proxy 連 broker 用 SASL/OAUTHBEARER,會先用 client 憑證向 MDS 換 MDS token;bootstrap 連 broker 也用同樣的方式,不另建 SCRAM 帳號。補充:元件處理自己的工作時帶元件自己的 token;人經 C3 或 REST Proxy 操作時帶本人的 token;legacy app 經 REST Proxy 時帶代表該 app 的 token。' });

// 授權
add({ title: '授權:MDS 管 RBAC,broker 判斷', sub: 'RBAC 資料與群組資料都放在同一個 Kafka topic', items: [
  table(0.6, 1.5, [0.9, 2.6, 8.63], [
    ['順序', '誰', '做什麼'],
    ['1', 'MDS', '內嵌在 broker 的 HTTP REST 服務,提供 token 簽發與 RBAC 的 API'],
    ['2', 'MDS', 'RBAC 的 API 被呼叫後,把 RBAC 資訊寫入 Kafka topic'],
    ['3', 'MDS', '定期查 AD;使用者與群組的對應有變更時,寫入同一個 topic'],
    ['4', 'broker', '把 topic 的資料讀進本地快取;用已認證的使用者查出所屬群組'],
    ['5', 'broker', '把使用者與群組拿去比對 RBAC 資訊,判斷這個動作有沒有權限'],
  ], { rowH: 0.72, hdrH: 0.46, sz: 12.5, col: MDS }),
], notes: '授權依靠內嵌元件 MDS 管理 RBAC 資訊。MDS 是 HTTP REST 服務,提供 token 簽發與 RBAC 相關的 API。RBAC 的 API 被呼叫後,會把 RBAC 資訊寫入 Kafka topic。MDS 也會定期把 AD 的 user 與 groups 對應的變更寫入同一個 topic。Kafka 用已認證的 user 對應 topic 中的 groups,再比對 RBAC 資訊,判斷這個 user 有沒有權限。補充(demo 實測):topic 是 _confluent-metadata-auth;同一時間只有一台 broker 的 MDS 負責向 AD 查詢並寫入;每台 broker 各自讀取整個 topic 更新本地快取。' });

// AD 群組 → RBAC role(建議做法)
add({ title: '授權:AD 群組對應 RBAC role', sub: '建議做法:人不寫資料,高權限群組平時是空的', items: [
  { ...table(0.6, 1.5, [2.45, 2.55, 3.15, 1.9, 2.08], [
    ['AD 群組或身分', '綁定的 role', '範圍(scope)', '平時是否有人', '用途'],
    ['kafka-<系統>-read', 'DeveloperRead', 'Topic:<topic 前綴>;Group(consumer group):<group 前綴>', '有:該系統維護人員', '看 topic、讀資料'],
    ['kafka-ops', 'Operator', '整個叢集', '有:維運人員', '看叢集狀態;不能讀寫資料'],
    ['kafka-topic-admin', 'ResourceOwner', 'Topic:全部;Group:全部', '空:依變更單臨時加入', '建、刪、改 topic 與 consumer group;不能改叢集設定、不能建帳號'],
    ['kafka-cluster-admin', 'ClusterAdmin', '整個叢集', '空:依變更單臨時加入', '叢集設定、應用系統帳號;不能讀寫資料'],
    ['kafka-rbac-admin', 'UserAdmin', '整個叢集', '空:依變更單臨時加入', '只管授權;不碰資料'],
    ['kafka-security', 'SecurityAdmin、AuditAdmin;另加 DeveloperRead', '整個叢集;DeveloperRead 綁 audit 紀錄的 topic 與 consumer group 前綴 audit-', '有:資安與稽核人員', '檢視授權設定;管理 audit 設定;讀 audit 紀錄'],
    ['kafka-breakglass', 'SystemAdmin', '整個叢集', '空:緊急時一到兩人', '全部權限'],
    ['服務帳號(SCRAM)', '讀:DeveloperRead;寫:DeveloperWrite', 'Topic:自己的 topic;讀取時另加 Group:自己的 consumer group', '不適用', '寫資料只由服務帳號做;綁 User:'],
  ], { rowH: 0.52, hdrH: 0.42, sz: 11, col: INK }), rowCols: [HUM, PLT, PLT, PLT, MDS, MDS, RISK, SVC] },
  chip('名稱與前綴是範例;topic 與 consumer group 各有自己的名稱,命名規範要請客戶確認', 0.6, 6.4, 12.13, HUM, { sz: 12, h: 0.45 }),
], notes: 'AD 群組與 role 對應的建議做法。設計原則:①人不寫資料(讀取群組只讀,維運群組連資料都讀不到),寫資料只由服務帳號做(SCRAM,綁 User:,只綁自己的 topic);②讀取群組依系統切 topic 前綴,避免跨系統讀取,前提是客戶有 topic 命名規範(尚未確認);③建 topic 與改授權分成兩個群組,平時是空的,依變更單臨時加入、做完移出(臨時加入與移出的流程在 demo 第 11 章實測過);④資安與稽核另設群組;⑤SystemAdmin 只在緊急時使用。建 topic 的角色(2026-10-06 改)選 ResourceOwner 綁 Topic * 與 Group *:實測可建、刪、改 topic 與設定、重設 offset、刪 consumer group,但建 SCRAM 帳號與改 broker 設定被拒;叢集設定與應用系統帳號另設 kafka-cluster-admin(ClusterAdmin,實測可建刪 SCRAM)。kafka-security 的 AuditAdmin 實測讀不到 audit topic,所以另綁 DeveloperRead。官方依據(Confluent Platform 文件):RBAC overview 頁:"As a best practice, grant each user the minimum role required to complete their tasks.";role binding 建議上限 1000(soft limit);群組綁定的使用者 ID 大小寫要與 AD 紀錄一致。Predefined roles 頁:建議把 SystemAdmin 限制在每個叢集一到兩人,用於初始設定或正式環境的緊急狀況;UserAdmin:"Users granted this role should be extremely trustworthy because they can grant roles to themselves and others.",並可用 audit log 監看;ClusterAdmin:"This role cannot read or write Kafka topic data because it does not have Read or Write operations on Topic.";DeveloperManage 可建立或刪除 topic,但不能改設定。官方沒有提供群組怎麼切的範本;本頁的切法是依上述原則與職責分離的要求所做的設計。SecurityAdmin 與 AuditAdmin 的權限實測(2026-10-05,暫時綁給一個沒有其他角色的 AD 帳號,測完解除):SecurityAdmin 可以查詢 role binding(查誰有某個角色、查某人的角色),不能新增或指派 role binding(403),不能讀 audit 設定(403);AuditAdmin 可以讀取與更新 audit 設定(GET 與 PUT 皆 200),不能查詢 role binding(403);兩者都不能讀 topic 資料、不能建立 topic。依系統切群組會讓 role binding 變多,要留意 1000 筆的建議上限。不同環境(例如測試與正式)建議各用一套群組。讀資料需要兩個綁定:Topic 的 DeveloperRead,以及 consumer group(資源類型 Group)的 DeveloperRead;只綁 Topic 時 consumer 無法加入 group。Topic 的名稱與 consumer group 的名稱是兩套各自獨立的名稱,前綴不一定相同,要分開綁定、分開規範;另外資源類型 Group 指 consumer group,與主體的 Group:(AD 群組)不同。demo 的做法是 Topic 與 Group 各綁一筆前綴(例如 Topic orders. 與 Group demo-)。只寫資料的服務只需要 Topic 的 DeveloperWrite。使用交易(transaction)的 producer 另需要 TransactionalId 資源的 DeveloperWrite(實測,2026-10-05):只有 Topic 的 DeveloperWrite 時,交易寫入出現 TransactionalIdAuthorizationException;加綁 TransactionalId 的 DeveloperWrite 後成功;解除後再次被拒。' });

// 元件主體的綁定與群組管理規則(2026-10-06 自檢新增;綁定內容為 demo 現況,role 權限為實測)
add({ title: '授權:元件身分的綁定與群組管理規則', sub: '人以外的身分也要綁;群組本身要有人管', items: [
  text(0.6, 1.4, 12.13, 0.33, [P('元件身分(client 憑證的 CN)', { sz: 13.5, b: true, c: PLT })]),
  { ...table(0.6, 1.78, [2.6, 4.3, 5.23], [
    ['身分', '綁定', '說明'],
    ['bootstrap 憑證', 'super.users(不是 role binding)', '不受授權限制;只在初始化與緊急時使用'],
    ['C3 的憑證', 'SystemAdmin', '官方要求;所以 C3 本身不能被未登入的人借用身分'],
    ['REST Proxy 的憑證', 'DeveloperRead、DeveloperWrite @ Topic _confluent-command', '官方範例;只用於 license topic,人與 legacy app 的請求用各自的身分'],
    ['共用的 server 憑證', '不綁任何 role、不列為 super user', '管理介面也持有它;綁了會讓未登入的請求取得權限'],
  ], { rowH: 0.5, hdrH: 0.4, sz: 11.5, col: INK }), rowCols: [PLT, MDS, MDS, RISK] },
  text(0.6, 4.35, 12.13, 0.33, [P('群組管理規則', { sz: 13.5, b: true, c: HUM })]),
  table(0.6, 4.73, [3.4, 8.73], [
    ['規則', '做法'],
    ['各環境各一套群組', '各環境的 AD 各自建同名群組;授權是每個叢集各自綁,成員依環境分開管'],
    ['每個群組有負責人', '負責人核准加入;定期(例如每季)覆核成員'],
    ['空群組的臨時加入', '依變更單加入,做完移出;設定移除期限,到期未移出要有提醒'],
  ], { rowH: 0.46, hdrH: 0.4, sz: 11.5, col: HUM }),
], notes: '元件身分的綁定是 demo 現況(2026-10-06 用 MDS lookup 查得):User:c3 → SystemAdmin;User:restproxy → DeveloperRead 與 DeveloperWrite @ Topic _confluent-command(LITERAL);bootstrap 在 super.users,沒有 role binding。共用 server 憑證 CN 不綁的理由見 spike/server-cert-superuser。群組管理規則不是 Confluent 功能,是銀行常見的權限管理要求。雙人確認與覆核人群組已於 2026-10-06 依客戶要求移除。' });

// 官方 RBAC 角色與 scope 圖(沿用完整版)
const rs = ALL.find(x => x.title === 'Confluent 內建角色與 scope');
if (!rs) throw new Error('找不到角色與 scope 頁');
const rsItems = JSON.parse([['只檢視授權設定,不能改', '可檢視授權設定,不能改'], ['② 叢集裡的資源 + 比對方式', '② 叢集裡的資源 + 比對方式(名稱為範例)'], ['本專案的例子', '對應上一頁的例子'], ['ops → Operator @ 叢集', 'kafka-ops → Operator @ 叢集'], ['ops → DeveloperManage @ infra.', '讀取群組 → DeveloperRead @ 前綴']].reduce((j, [a, b]) => { if (j.split(a).length !== 2) throw new Error('角色頁找不到:' + a); return j.split(a).join(b); }, JSON.stringify(rs.items)));
add({ title: 'Confluent 內建 RBAC 角色與 scope', sub: '本方案用到的內建角色,依「綁在叢集」或「綁在資源」分兩類', items: rsItems, notes: rs.notes + ' 更正與補充:官方 Predefined roles 頁除了這十個角色,另列有 KsqlAdmin(本方案範圍沒有 ksqlDB,未列入);十個是 demo 的 MDS 實際回傳的數量。SecurityAdmin 依官方原文是 Enables management of platform-wide security initiatives(設定加密、audit log 追蹤等安全功能);demo 實測到的是:可以查詢 role binding,不能新增或指派,也不能讀 audit 設定(audit 設定要 AuditAdmin)。右側資源名稱(orders.、infra.、demo-)是範例。' });

// 元件交互總覽
add({ title: '與 Kafka 元件交互:總覽', sub: '五種交互,認證方式與結果', items: [
  { ...table(0.6, 1.5, [2.9, 2.7, 3.5, 3.03], [
    ['誰連誰', '怎麼認證', '對方做什麼', '結果'],
    ['bootstrap 服務帳號 → MDS', 'mTLS(提供 client 憑證)', 'MDS 做權限控管', 'bootstrap 應為 super user'],
    ['C3、REST Proxy → MDS', 'mTLS(提供 client 憑證)', 'MDS 認證後,簽發代表元件本身的 token', '元件帶 token 與 broker 交互'],
    ['人 → C3', '瀏覽器 Basic 登入', 'C3 轉給 MDS,由 MDS 向 AD 驗證', '取得代表本人的 token(見「人 → C3」頁)'],
    ['人 → REST Proxy', 'Basic(AD 帳號密碼)', 'REST Proxy 轉給 MDS,由 MDS 向 AD 驗證', '取得代表本人的 token,帶去與 broker 交互'],
    ['legacy app → REST Proxy', 'mTLS(提供 client 憑證)', 'REST Proxy 向 MDS 做 impersonate', '取得代表 legacy app 的 token(見「legacy app → REST Proxy」頁)'],
  ], { rowH: 0.74, hdrH: 0.46, sz: 12.5, col: INK }), rowCols: [PLT, MDS, HUM, HUM, SVC] },
], notes: 'bootstrap 服務帳號連 MDS:使用 mTLS 認證(須提供 client 憑證),由 MDS 做權限控管,bootstrap 應為 super user。C3、REST Proxy 連 MDS:使用 mTLS 認證,MDS 認證後簽發代表元件本身的 MDS token,元件用它與 broker 交互。人連 C3 與 legacy app 連 REST Proxy 的步驟見後兩頁。補充(原大綱沒列):人用腳本或 Postman 經 REST Proxy 時用 Basic(AD 帳號密碼),REST Proxy 把帳密轉給 MDS 驗證並取得本人的 token,不經 impersonate。用詞:原大綱的「服務 → REST Proxy」在這裡改稱 legacy app(只能 HTTP、用憑證的服務),以便和認證頁用 SCRAM 直連 broker 的「服務」區分。' });

// 人 → C3
add({ title: '人 → C3:登入與之後的請求', sub: '登入取得 token;之後依請求類型處理', items: [
  { ...table(0.6, 1.5, [0.9, 2.2, 9.03], [
    ['順序', '誰', '做什麼'],
    ['1', '瀏覽器', '用 Basic(AD 帳號密碼)登入 C3'],
    ['2', 'C3', '把 Basic 資訊轉給 MDS'],
    ['3', 'MDS', '向 AD 驗證,回傳代表本人的 MDS token'],
    ['4', 'C3', '把 MDS token 回給瀏覽器(回應內容與 cookie 都有)'],
    ['5', '瀏覽器', '之後發請求給 C3 時,用 Bearer 標頭帶這個 token'],
  ], { rowH: 0.5, hdrH: 0.42, sz: 12, col: HUM }) },
  table(0.6, 4.62, [3.6, 8.53], [
    ['C3 收到請求後', 'token 怎麼處理'],
    ['請求要與 MDS 交互', '把 MDS token 轉給 MDS,由 MDS 驗證'],
    ['請求不與 MDS 交互', 'C3 用 MDS 的公鑰在本地驗證'],
    ['操作與 broker 有關', 'C3 帶這個 MDS token 與 broker 交互'],
  ], { rowH: 0.48, hdrH: 0.42, sz: 12, col: INK }),
], notes: '人連 C3:瀏覽器用 Basic 登入;C3 把 Basic 資訊轉給 MDS 做 AD 驗證;MDS 回傳代表人的 MDS token 並放在回應的 cookie;C3 把 MDS token 放在回應的 cookie 給瀏覽器儲存。之後瀏覽器發請求給 C3:如果要與 MDS 交互,C3 把 MDS token 轉給 MDS 驗證;若未與 MDS 交互,則用 MDS 公鑰在本地驗證;若操作與 broker 有關,則拿 MDS token 與 broker 交互。補充(demo 實測):token 同時在回應內容與 HttpOnly 的 auth_token cookie;瀏覽器之後的請求主要用 Authorization: Bearer 標頭帶 token,兩者都有時伺服器優先看 Bearer。補充(demo 實測,2026-10-05):轉給 MDS 的路徑,C3 不先驗 token;帶偽造的 token 時 MDS 回 401。完全不帶 token 時,C3 內部的 HTTP 客戶端會向 MDS 出示共用的 server 憑證,MDS 把請求認成 User:kafka.demo.local;這個身分沒有任何 role,所以查詢授權資料回 403,只有不需要權限的角色清單回 200。因此共用憑證的身分不可以綁任何 role。' });

// 服務 → REST Proxy
add({ title: 'legacy app → REST Proxy:憑證換 token', sub: '只能 HTTP 的服務;憑證的 CN 就是它的帳號', items: [
  table(0.6, 1.5, [0.9, 2.6, 8.63], [
    ['順序', '誰', '做什麼'],
    ['1', 'legacy app', '用 mTLS 連 REST Proxy,提供 client 憑證'],
    ['2', 'REST Proxy', '取出憑證的 CN,當作這個 app 的帳號'],
    ['3', 'REST Proxy', '用自己的 client 憑證向 MDS 認證'],
    ['4', 'REST Proxy', '向 MDS 做 impersonate,取得代表這個 app 的 MDS token'],
    ['5', 'REST Proxy', '帶這個 MDS token 與 broker 交互'],
  ], { rowH: 0.74, hdrH: 0.46, sz: 12.5, col: SVC }),
], notes: '服務連 REST Proxy:使用 mTLS 認證(須提供 client 憑證);REST Proxy 取出服務憑證的 CN 當作服務帳號;向 MDS 做 impersonate,取得服務的 MDS token;用 MDS token 與 broker 交互。補充(原大綱沒列,已併入第 3 步):REST Proxy 呼叫 impersonate 時,是用自己的 client 憑證(CN 為 restproxy)向 MDS 認證。' });

// 準備事項(一)
add({ title: '準備事項(一):憑證、金鑰與帳號', sub: '依前面各頁整理:導入前要先備妥的東西', items: [
  table(0.6, 1.5, [4.5, 2.6, 5.03], [
    ['要準備什麼', '用在哪裡', '注意事項'],
    ['共用的 server 私鑰與憑證', '傳輸加密', 'SAN 要列出所有元件的主機名稱或 IP'],
    ['簽發 server 憑證的 root CA 憑證', '傳輸加密', '放進各元件與外部 client 的信任庫'],
    ['client 憑證:c3、restproxy、bootstrap、各 legacy app', '認證、元件交互', '憑證的 CN 就是身分,命名要先定'],
    ['AD 的 LDAPS 用的 CA 憑證', '傳輸加密(連 AD)', '有中繼 CA 時一併提供'],
    ['MDS 簽發 token 用的金鑰對', '授權、元件交互', '私鑰外洩可偽造任何人的 token,要限制存放位置'],
    ['內部帳號 kafka-broker、kafka-controller 的密碼', '認證(叢集內部)', 'SCRAM 帳號在初始化叢集時建立;controller 的 JAAS 設定另放同名的 PLAIN 帳號'],
    ['每個服務一個 SCRAM 帳號', '認證', '密碼放密碼庫;密碼不會自動到期,要有輪替流程'],
    ['bootstrap(super user)的保管方式', '認證、元件交互', '不受授權限制;只用 client 憑證,不另建帳號;用完離線保管,指定保管人'],
  ], { rowH: 0.56, hdrH: 0.46, sz: 12, col: INK }),
], notes: '準備事項依前面各頁整理。共用的 server 憑證:SAN 要涵蓋 broker、controller、MDS、C3、REST Proxy 對外的網域或 IP。client 憑證:C3、REST Proxy、bootstrap 與每個 legacy app 各一張,憑證的 CN 經對映後就是 RBAC 綁定的主體,所以 CN 的命名要先定。MDS 的 token 簽章金鑰對:私鑰用來簽發 token,公鑰給 broker、REST Proxy、C3 驗證;輪替流程未在 demo 驗證。內部帳號:連 broker 用的 SCRAM 帳號要在初始化(format)叢集時預先建立,否則授權器起不來(demo 實測);連 controller 用的 PLAIN 帳號寫在 JAAS 設定。服務帳號:每個服務一個 SCRAM 帳號,SCRAM 密碼不會自動到期。bootstrap 是 super user,不受授權檢查,官方建議只給少數人。bootstrap 與 C3、REST Proxy 一樣只用 client 憑證,不另建 SCRAM 帳號:對 MDS 直接出示憑證;對 broker 先用憑證向 MDS 換 token 再以 OAUTHBEARER 連線(demo 實測,2026-10-05:可列出 topic、建立與刪除 topic、建立與刪除 SCRAM 帳號)。代價:MDS 無法簽發 token 時 bootstrap 連不上 broker(此情況為推論,未實際停掉 MDS 測試);那時仍可用內部帳號(SCRAM,super user)直連 broker。內部帳號的兩份帳密各自存放:連 broker 的 SCRAM 帳號存在 Kafka 內,連 controller 的 PLAIN 帳號寫在 controller 的 JAAS 設定(user_kafka-broker、user_kafka-controller);名稱相同,授權時都是同一個主體,super.users 只要列一次;但密碼不會同步,輪替時兩邊都要改。這兩個名稱不能被其他來源使用(例如 AD 不可有同名帳號),因為任何機制只要以這個名稱通過認證就是 super user。' });

// 準備事項(二)
add({ title: '準備事項(二):AD、命名規範與流程', sub: '需要 AD 管理員、應用團隊與維運一起確認', items: [
  table(0.6, 1.5, [4.5, 2.6, 5.03], [
    ['要準備什麼', '用在哪裡', '注意事項'],
    ['AD 唯讀查詢帳號', '認證、授權', '只讀使用者與群組;不用真人帳號'],
    ['使用者與群組在 AD 的位置', '認證、授權', '用來設定搜尋範圍;帳號大小寫要與 AD 一致'],
    ['建立 AD 群組並放入成員', '授權', '依「AD 群組對應 RBAC role」頁,各環境的 AD 各建一套;高權限群組先保持空的;每個群組指定負責人'],
    ['topic 與 consumer group 的命名規範', '授權', '兩套名稱各自定前綴;沒有規範就無法依前綴授權'],
    ['服務與 legacy app 的清單', '認證、授權', '列出各自要讀寫的 topic 與 consumer group'],
    ['臨時加入高權限群組的變更流程', '授權', '依變更單加入,做完移出;緊急用的群組指定一到兩人'],
    ['防火牆連線', '傳輸加密', '元件之間的九條連線、broker 連 AD、外部 client 連入'],
  ], { rowH: 0.6, hdrH: 0.46, sz: 12, col: INK }),
], notes: 'AD 唯讀查詢帳號:broker 驗證人的密碼時先用它搜尋使用者,MDS 也用它定期查群組。使用者與群組的位置(搜尋的起點)要由 AD 管理員提供;官方說明群組綁定的使用者 ID 大小寫要與 AD 紀錄一致。AD 群組:依「AD 群組對應 RBAC role」頁建立,讀取群組依系統各一個,建 topic、改授權、緊急用的群組平時保持空的。命名規範:topic 與 consumer group 是兩套各自獨立的名稱,要分別定前綴,才能用前綴綁定;沒有規範時只能逐一綁定,role binding 數量會變多(官方建議上限 1000 筆)。防火牆(補充,前面各頁沒有列):元件之間的九條連線見「哪些連線要設信任庫」頁,另外要開 broker 連 AD(LDAPS),以及人、服務、legacy app 連到 broker、C3、REST Proxy;controller 的埠與 broker 的內部埠只開給叢集節點。實際的埠號依部署設定,本頁不列。' });

// NO_NOTES:輸出的簡報不含備忘稿(使用者要求);規格內的 notes 保留作為依據紀錄
module.exports = { SLIDES: S, THEME, HEX, NO_END: true, NO_NOTES: true };
