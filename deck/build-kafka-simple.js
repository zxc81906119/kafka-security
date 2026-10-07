// 2026-10-05:文字以主管修改版(Kafka-安全整理-精簡版-v4-主管修改版.pptx)為準。
// 「Kafka 安全整理」精簡版:依主管意見,三個對象各簡述認證與授權,不談流程。
//   SPEC=./build-kafka-simple.js OUT=Kafka-安全整理-精簡版.pptx node build-solution-iisi.js
// 詳細版見 build-kafka-notes.js(依據與實測紀錄在該檔的 notes 與 demo/spike/SPIKE-FINDINGS.md)。
const { THEME, HEX, H } = require('./build-solution-deck.js');
const { chip, table, text, P, HUM, SVC, PLT, MDS, RISK, INK } = H;
const S = [];
const add = (s) => S.push(s);

add({ layout: 'TITLE', title: 'Kafka 安全整理', coverTitle: 'Kafka 安全整理', coverSub: '應用系統、C3 使用者、叢集連線設定', noCoverLines: true, items: [] });

// 總覽
add({ title: '總覽:三個對象的認證與授權', sub: '應用系統、管理介面(C3) 使用者、叢集連線設定', items: [
  { ...table(0.6, 1.5, [2.4, 3.3, 3.7, 2.73], [
    ['對象', '認證', '授權', '帳號在哪裡管'],
    ['應用系統', '直連 broker:SCRAM 帳號;經 REST Proxy:client 憑證', 'RBAC 綁在帳號或憑證的名稱上,只授權指定的 topic', '直連 broker:Kafka 內;REST Proxy:憑證'],
    ['管理介面 (C3) 使用者', 'AD 帳號', 'AD 群組對應 RBAC', 'AD'],
    ['叢集連線設定', '內部互連:內部帳號或專用憑證;C3 與 REST Proxy 用 client 憑證', '內部互連是 super user;元件依 RBAC', '依選用的方案'],
  ], { rowH: 1.0, hdrH: 0.5, sz: 13.5, col: INK }), rowCols: [SVC, HUM, PLT] },
  chip('所有連線都走 TLS;各元件共用一組 server 憑證', 0.6, 5.5, 12.13, PLT, { sz: 13, h: 0.5 }),
] });

// 應用系統(兩種連線方式)
add({ title: '應用系統', sub: '兩種連線方式:直連 Kafka broker,或經 REST Proxy', items: [
  table(0.6, 1.5, [2.3, 4.9, 4.93], [
    ['項目', '直連 Kafka broker', '經 REST Proxy'],
    ['適用的系統', '能使用 Kafka 用戶端程式的系統', '只能用 HTTP 的系統'],
    ['認證', 'SCRAM 帳號', 'client 憑證'],
    ['授權', 'RBAC 綁在帳號上', 'RBAC 綁在憑證的名稱上'],
    ['建議的 role', '讀資料:DeveloperRead;寫資料:DeveloperWrite', '相同'],
    ['開放範圍', '只開放應用系統的 topic 與 consumer group', '相同'],
    ['帳號在哪裡管', 'Kafka 內;新系統上線申請帳號並綁定可存取資源(topic) 的 role', '不另建帳號;新系統上線時簽發憑證,綁定可存取資源(topic) 的 role'],
    ['密碼管理', '於 Kafka 設定', '依據憑證效期'],
  ], { rowH: 0.66, hdrH: 0.46, sz: 13.5, col: SVC }),
] });

// C3 使用者
add({ title: '管理介面(C3) 使用者', sub: 'AD 帳號認證 + AD 群組對應 RBAC', items: [
  table(0.6, 1.5, [2.6, 9.53], [
    ['項目', '做法'],
    ['認證', '透過 AD 帳號認證'],
    ['授權', '透過 AD 群組對應 RBAC'],
    ['帳號管理', '帳號與群組都在 AD;人員異動只改 AD 群組,Kafka 不用改'],
  ], { rowH: 0.46, hdrH: 0.42, sz: 12.5, col: HUM }),
  text(0.6, 3.42, 12.13, 0.33, [P('建議的 RBAC 群組', { sz: 13.5, b: true, c: HUM })]),
  { ...table(0.6, 3.8, [3.4, 4.3, 4.43], [
    ['AD 群組', '對應的 role', '用途'],
    ['kafka-<系統>-read', 'DeveloperRead', '看 topic、讀資料'],
    ['kafka-ops', 'Operator', '看叢集狀態'],
    ['kafka-topic-admin', 'ResourceOwner(Topic、Group)', '建立、刪除、修改 topic 與 consumer group'],
    ['kafka-cluster-admin', 'ClusterAdmin', '叢集設定、應用系統帳號'],
    ['kafka-rbac-admin', 'UserAdmin', '管理授權'],
    ['kafka-security', 'SecurityAdmin、AuditAdmin、audit 紀錄的 DeveloperRead', '檢視授權設定、audit 設定與紀錄'],
    ['kafka-breakglass', 'SystemAdmin', '全部權限,緊急時才用'],
  ], { rowH: 0.38, hdrH: 0.4, sz: 11.5, col: INK }), rowCols: [HUM, PLT, PLT, PLT, MDS, MDS, RISK] },
] });

// 維運操作選單(OP menu):分層
add({ title: '維運操作選單(OP menu):分層', sub: '操作員只能從選單執行審核過的作業;能不能做由 Kafka 的 RBAC 或主機的 sudo 規則決定', items: [
  { ...table(0.6, 1.5, [1.9, 2.5, 4.9, 2.83], [
    ['層級', '誰用(AD 群組)', '項目', '真正的門'],
    ['值班查看', 'kafka-ops', '健康檢查(含身分鏈)、topic 狀態、consumer 落後量、磁碟、憑證到期日、leader 分布', 'Kafka RBAC:唯讀'],
    ['服務操作', 'kafka-ops', '重啟單一 broker、滾動重啟、維護模式、查看服務日誌', '各節點 sudo 規則,只開放指定指令;一次只重啟一台,滾動重啟每台等叢集恢復才換下一台'],
    ['變更作業', 'kafka-topic-admin(topic);kafka-cluster-admin + kafka-rbac-admin(應用系統帳號:建帳號、綁權限)', '建立或修改 topic、新增或下架應用系統帳號、更換密碼', 'Kafka RBAC;執行前顯示影響並要求確認'],
    ['授權與緊急', 'kafka-rbac-admin(指派權限);kafka-security(匯出 audit);緊急模式依 sudo 規則', '指派權限、匯出 audit、查詢 audit、匯出權限清單、緊急模式', 'Kafka RBAC;緊急模式用 bootstrap 憑證,經 sudo 切換專用帳號才讀得到;逐條記錄'],
  ], { rowH: 0.8, hdrH: 0.46, sz: 12, col: HUM }), rowCols: [PLT, PLT, MDS, RISK] },
  chip('Kafka 的動作由 RBAC 依操作員本人的 AD 帳號判斷;主機的動作由 sudo 規則判斷;兩邊的群組都在 AD,選單本身不判斷權限', 0.6, 5.35, 12.13, HUM, { sz: 12, h: 0.48 }),
  chip('每次執行留紀錄:時間、操作者、項目、結果;變更類執行前顯示影響並要求確認;可限制變更時段,同一時間只允許一人執行變更', 0.6, 5.95, 12.13, PLT, { sz: 12, h: 0.48 }),
] });

// 維運操作選單(OP menu):做法與編號範例
add({ title: '維運操作選單(OP menu):做法', sub: '一支 shell 選單放在跳板機;環境相依的部分獨立成一個檔案', items: [
  { ...table(0.6, 1.5, [2.3, 5.4, 4.43], [
    ['部分', '負責什麼', '調整時'],
    ['核心流程', '操作員用本人 AD 帳號登入跳板機,選單就是登入殼層;登入身分 → 選單 → 確認 → 執行 → 記錄', '不用改'],
    ['選單項目', '每個項目一段:編號、層級、是否需確認、做什麼', '新增項目加一段即可'],
    ['環境後端', '怎麼執行 Kafka 工具、重啟服務(systemd)、看日誌、看磁碟、列憑證', '節點或服務名稱變動時只改這個檔案'],
  ], { rowH: 0.62, hdrH: 0.44, sz: 12.5, col: PLT }), rowCols: [HUM, MDS, SVC] },
  text(0.6, 3.95, 12.13, 0.32, [P('編號範例:十位數是層級,個位數是項目', { sz: 13, b: true, c: HUM })]),
  { ...table(0.6, 4.3, [1.9, 10.23], [
    ['層級', '項目編號'],
    ['1 值班查看', '10 leader 分布  11 健康檢查(含身分鏈)  12 topic 狀態  13 consumer 落後量  14 topic 設定  15 應用系統連線  16 磁碟用量  17 憑證到期日  18 收集診斷資訊  19 生效設定'],
    ['2 服務操作', '21 重啟單一 broker  22 重啟 REST Proxy 或 C3  23 查看服務日誌  24 清理過期日誌  25 開始維護模式  26 結束維護模式  27 滾動重啟'],
    ['3 變更作業', '31 建立 topic  32 修改 topic 設定  33 刪除 topic  34 新增應用系統帳號  35 更換應用系統密碼  36 重設 consumer 讀取位置  37 下架應用系統帳號'],
    ['4 授權與緊急', '41 查看權限  42 指派或移除權限  43 匯出 audit 紀錄  44 匯出權限清單  45 查詢 audit 紀錄  91 緊急模式'],
  ], { rowH: 0.5, hdrH: 0.42, sz: 12, col: INK }), rowCols: [PLT, PLT, MDS, RISK] },
] });

// 叢集連線設定(兩個方案都相同的部分)
add({ title: '叢集連線設定', sub: '元件之間的連線;全部走 TLS', items: [
  { ...table(0.6, 1.5, [4.3, 4.4, 3.43], [
    ['連線', '認證', '授權'],
    ['broker、controller 互連', '兩個方案,見下一頁', 'super user'],
    ['C3、REST Proxy 連 broker', 'client 憑證', 'RBAC 綁在憑證的名稱上'],
    ['broker 連 AD', 'AD 的唯讀查詢帳號', '只能查詢使用者與群組'],
  ], { rowH: 0.85, hdrH: 0.46, sz: 13.5, col: PLT }), rowCols: [PLT, MDS, HUM] },
  chip('傳輸加密:各元件共用一組 server 憑證,並信任同一張 CA 憑證', 0.6, 5.1, 12.13, PLT, { sz: 13, h: 0.48 }),
] });

// 叢集內部連線:兩個方案
add({ title: '叢集內部連線:兩個方案', sub: 'controller 與 broker 之間的認證方式', items: [
  table(0.6, 1.5, [2.3, 4.9, 4.93], [
    ['項目', '方案 A:內部帳號', '方案 B:共用一張專用憑證(mTLS)'],
    ['連 broker', '內部帳號(SCRAM)', 'client 憑證(mTLS)'],
    ['連 controller', '內部帳號(PLAIN,寫在設定檔)', 'client 憑證(mTLS)'],
    ['授權', '內部帳號是 super user', '憑證的名稱是 super user'],
    ['要管的東西', '兩份密碼:Kafka 內一份、設定檔一份', '一張憑證,只放在 broker 與 controller;要含這些主機的名稱'],
    ['定期要做的事', '更換密碼,兩邊都要改', '憑證到期前更換'],
    ['代價', '初始化叢集時要先建帳號', '多一張憑證;不需要任何內部帳號'],
  ], { rowH: 0.58, hdrH: 0.5, sz: 13, col: PLT }),
  chip('方案 B 不能用共用的 server 憑證:管理介面(C3)也持有它,實測會讓未登入的人取得最高權限', 0.6, 5.68, 12.13, RISK, { sz: 12.5, h: 0.48 }),
  chip('兩個方案的內部埠都要用防火牆限制,只開放給 broker 與 controller', 0.6, 6.28, 12.13, PLT, { sz: 12.5, h: 0.48 }),
] });

// 準備事項
add({ title: '需要準備的事項', sub: '依三個對象整理', items: [
  { ...table(0.6, 1.5, [4.2, 2.9, 5.03], [
    ['要準備什麼', '用在哪個對象', '說明'],
    ['AD 的唯讀查詢帳號', '管理介面對 AD 查詢', '用來查詢使用者與群組;不用真人帳號'],
    ['建立 AD 群組並放入成員', '管理介面使用者', '依建議的 RBAC 群組,各環境的 AD 各建一套;高權限群組先保持空的;每個群組指定負責人,定期覆核成員'],
    ['一組 server 憑證', '叢集連線設定', '憑證上的名稱要涵蓋所有元件的主機'],
    ['C3、REST Proxy 的 client 憑證', '叢集連線設定', '元件用來向叢集證明自己的身分'],
    ['經 REST Proxy 的應用系統:各一張 client 憑證', '應用系統', '憑證上的名稱就是授權用的帳號,命名要先定'],
    ['應用系統清單', '應用系統', '直連或經 REST Proxy;各自讀寫哪些 topic 與 consumer group'],
    ['topic 與 consumer group 的命名規範', '應用系統、C3 使用者', '有規範才能依名稱的開頭一次授權'],
    ['跳板機接 AD', '維運操作選單', '操作員用本人帳號登入,選單沿用這個身分'],
    ['操作員的作業項目清單', '維運操作選單', '依客戶現有 SOP 確認哪些項目要放進選單'],
    ['各節點是否接 AD;sudo 規則', '維運操作選單', '節點接 AD 則 sudo 規則引用 AD 群組;否則用共用維運帳號'],
  ], { rowH: 0.48, hdrH: 0.46, sz: 13, col: INK }) },
] });

module.exports = { SLIDES: S, THEME, HEX, NO_END: true, NO_NOTES: true };
