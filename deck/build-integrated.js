// 2026-10-08:整合建議方案(依客戶前提)+ CyberArk 整合章節。
//   SPEC=./build-integrated.js OUT=Kafka-安全整合建議-v1.pptx node build-solution-iisi.js
// 用語:正式環境;不提測試環境細節。群組名稱沿用精簡版(kafka-*)。
const { THEME, HEX, H } = require('./build-solution-deck.js');
const { chip, table, text, P, node, arrow, tint, step, HUM, SVC, PLT, MDS, RISK, INK } = H;
const S = [];
const add = (s) => S.push(s);
const sec = (title, subtitle) => add({ layout: 'SECTION', title, subtitle, items: [] });
const note = (t, y, col, o = {}) => chip(t, 0.6, y, 12.13, col, { sz: o.sz || 12.5, h: o.h || 0.46 });

add({ layout: 'TITLE', coverTitle: 'Kafka 安全整合建議', coverSub: '依客戶前提的整體方案,與行內 CyberArk 的整合方式', noCoverLines: true, items: [] });

// ───────────────── 0. 前提對應
add({ title: '客戶前提與本方案的對應', sub: '每一項前提都有一個明確的做法;細節在後面各章', items: [
  { ...table(0.6, 1.5, [3.6, 8.53], [
    ['客戶前提', '本方案的做法'],
    ['AD 只有 user 與 group;使用者名稱 = CN', '人用 AD 帳號登入,授權綁在 AD 群組;服務與平台元件不佔用 AD 帳號;身分名稱以 AD 記錄為準(登入不分大小寫)'],
    ['憑證要少:共用一張 server 憑證', '一張 server 憑證只做傳輸加密、不當身分;需要身分的元件各一張 client 憑證(C3、REST Proxy、初始化用的 bootstrap、經 REST Proxy 的應用系統)'],
    ['RHEL 9 VM,手動安裝', '設定檔 + systemd;維運選單(OP menu)放跳板機;不依賴自動化工具'],
    ['有系統只能用 HTTP', '經 REST Proxy;以 client 憑證為身分,REST Proxy 代為向 MDS 取 token,身分一路傳到 broker'],
    ['人只能唯讀,依 AD 群組分層', '7 個 AD 群組對應角色;需要變更時臨時加入群組、做完移出,Kafka 端零變更'],
    ['負載平衡用 F5', '只放在 REST Proxy 前面,L4 透傳;REST Proxy 連 MDS 設多台即可,不需要 LB'],
    ['有 CyberArk', '當「秘密管理層」:人的特權存取、主機帳號輪替、應用程式取密碼;不改變身分與授權設計(第五章)'],
  ], { rowH: 0.62, hdrH: 0.44, sz: 12, col: INK }), rowCols: [HUM, PLT, PLT, SVC, HUM, PLT, RISK] },
] });

// ───────────────── 1. 整體架構
sec('一、整體架構', '元件、連線與四條身分路徑');
add({ title: '整體架構', sub: '正式環境的元件與主要連線;內部埠只開給 broker 與 controller', items: [
  ...node(0.6, 1.55, 2.1, 1.6, { icon: 'FaUsers', title: '使用者', sub: 'AD 帳號;瀏覽器、工具、腳本', col: HUM, ssz: 10.5 }),
  ...node(0.6, 3.3, 2.1, 1.6, { icon: 'FaServer', title: '應用系統', sub: 'SCRAM 帳號或 client 憑證', col: SVC, ssz: 10.5 }),
  ...node(0.6, 5.05, 2.1, 1.6, { icon: 'FaTerminal', title: '跳板機 + OP menu', sub: '本人 AD 身分', col: HUM, tsz: 13, ssz: 10.5 }),
  ...node(3.3, 1.55, 2.2, 1.6, { icon: 'FaDesktop', title: 'Control Center', sub: 'HTTPS;人用 AD,自身用憑證', col: PLT, ssz: 10.5 }),
  ...node(3.3, 3.3, 2.2, 1.6, { icon: 'FaExchangeAlt', title: 'F5 → REST Proxy', sub: 'L4 透傳;帳密或 client 憑證', col: PLT, ssz: 10.5 }),
  ...node(3.3, 5.05, 2.2, 1.6, { icon: 'FaChartLine', title: '監控', sub: 'TLS + 帳密', col: PLT, ssz: 10.5 }),
  tint(6.2, 1.55, 4.0, 5.2, MDS, { round: 0.06 }),
  text(6.3, 1.6, 3.8, 0.4, [P('Kafka 叢集', { sz: 15, b: true, c: MDS, algn: 'ctr' })]),
  ...node(6.4, 2.05, 3.6, 1.6, { icon: 'FaDatabase', title: 'broker ×N(內建 MDS)', sub: '對外埠:AD 帳密、SCRAM、token', col: MDS, tsz: 13, ssz: 10.5 }),
  ...node(6.4, 3.8, 3.6, 1.6, { icon: 'FaCogs', title: 'controller ×3', sub: '內部憑證(mTLS);只接 broker', col: MDS, tsz: 13, ssz: 10.5 }),
  text(6.4, 5.5, 3.6, 1.15, [P('內部連線:mTLS,broker 與 controller 共用一張內部憑證(身分是 super user);MDS 負責驗證、授權、簽 token', { sz: 10.5, algn: 'ctr', c: MDS })], { anchor: 'ctr' }),
  ...node(10.6, 1.55, 2.13, 1.6, { icon: 'FaAddressBook', title: 'AD', sub: '使用者與群組;加密連線', col: HUM, ssz: 10.5 }),
  ...node(10.6, 3.3, 2.13, 1.6, { icon: 'FaShieldAlt', title: 'CyberArk', sub: 'PSM、CPM、CCP', col: RISK, ssz: 10.5 }),
  ...node(10.6, 5.05, 2.13, 1.6, { icon: 'FaNetworkWired', title: '防火牆', sub: '內部埠只開給叢集', col: PLT, ssz: 10.5 }),
  arrow(2.7, 2.35, 3.3, 2.35, HUM), arrow(2.7, 4.1, 3.3, 4.1, SVC), arrow(5.5, 2.35, 6.2, 2.6, PLT), arrow(5.5, 4.1, 6.2, 3.3, PLT),
  arrow(10.1, 2.7, 10.6, 2.35, HUM), arrow(10.6, 4.1, 10.1, 4.1, RISK, { dash: true }), arrow(2.7, 5.85, 6.2, 5.9, HUM, { dash: true }),
] });

add({ title: '四條身分路徑', sub: '誰用什麼身分進來;最後都由 broker 的 RBAC 判斷', items: [
  { ...table(0.6, 1.5, [1.9, 3.3, 3.5, 3.43], [
    ['對象', '認證', '授權', '密碼或憑證放哪'],
    ['人', 'AD 帳密 → MDS 向 AD 驗證 → 簽發 1 小時 token;C3 與 REST Proxy 以本人身分連 broker', '角色綁在 AD 群組;依「現在」的群組判斷,異動立即生效', 'AD;不經 CyberArk'],
    ['服務(直連)', 'Kafka 內建 SCRAM 帳號', '角色綁在帳號上;只開放自己的 topic 與 consumer group', 'Kafka 內 + 應用端;密碼由 CyberArk 保管與取用'],
    ['平台元件', 'client 憑證(C3、REST Proxy、bootstrap)向 MDS 換 token', 'C3 必須是 SystemAdmin(官方要求);REST Proxy 可代為申請,受保護清單擋特權身分', '各主機 0600;私鑰可由 CyberArk 保管'],
    ['只能 HTTP 的系統', 'client 憑證經 REST Proxy,代為向 MDS 取 token', '角色綁在憑證的名稱上;broker 看到的是該系統,不是 REST Proxy', '應用端;私鑰可由 CyberArk 保管'],
  ], { rowH: 0.95, hdrH: 0.44, sz: 12, col: INK }), rowCols: [HUM, SVC, PLT, SVC] },
  note('共用 server 憑證只做傳輸加密;把它當身分會讓所有持有者變成同一個人(實測),所以不綁任何角色', 6.2, RISK),
] });

// ───────────────── 2. 人與授權
sec('二、人與授權', 'AD 帳號、7 個群組、唯讀與臨時提權');
add({ title: '人:AD 帳號登入,授權跟著群組走', sub: '帳號與群組都在 AD;人員異動只改 AD,Kafka 端不用改', items: [
  { ...table(0.6, 1.5, [2.6, 9.53], [
    ['項目', '做法'],
    ['登入', 'C3、REST Proxy、工具、OP menu 都用 AD 帳密;登入大小寫不分,系統內的身分名稱以 AD 記錄的 CN 為準'],
    ['授權', '角色綁在 AD 群組;加入群組約數秒生效(MDS 定期重讀群組);移出群組後已發出的 token 立刻失去權限'],
    ['離職與調動', '只改 AD;帳號停用前,已發出的 token 在到期前仍能通過認證但沒有任何權限,所以離職要同時停用 AD 帳號'],
    ['角色綁定的主體', '群組用 Group:名稱;個人與憑證用 User:名稱,區分大小寫,要寫 AD 記錄的寫法'],
    ['唯讀原則', '正式環境人只有讀取權;建 topic、改授權、看叢集狀態分給三個維運群組,臨時加入、做完移出'],
  ], { rowH: 0.66, hdrH: 0.44, sz: 12.5, col: HUM }) },
  note('人的 AD 密碼不經 CyberArk;CyberArk 管的是「主機登入」與「機器密碼」(第五章)', 6.1, HUM),
] });

add({ title: 'AD 群組與角色(7 組)', sub: '高權限群組平常是空的;每個群組指定負責人,定期覆核成員', items: [
  { ...table(0.6, 1.5, [3.0, 4.0, 5.13], [
    ['AD 群組', '對應的角色', '實際能做什麼'],
    ['kafka-<系統>-read', 'DeveloperRead(該系統的 topic)', '看 topic、讀資料;正式環境人的日常權限'],
    ['kafka-ops', 'Operator', '看叢集狀態;建不了 topic、讀不到資料、改不了授權,連 topic 細節也看不到'],
    ['kafka-topic-admin', 'ResourceOwner(Topic、Group)', '建立、刪除、修改 topic 與 consumer group,讀得到資料,並能在自己範圍內改授權 → 強角色,只臨時加入'],
    ['kafka-cluster-admin', 'ClusterAdmin', '叢集設定、建立應用系統的 SCRAM 帳號;不能讀寫資料、不能改授權'],
    ['kafka-rbac-admin', 'UserAdmin', '只管授權(指派、移除角色),不能建 topic、不能讀資料'],
    ['kafka-security', 'SecurityAdmin、AuditAdmin、audit 紀錄的讀取', '檢視授權設定、audit 設定與紀錄;不能改授權'],
    ['kafka-breakglass', 'SystemAdmin', '全部權限;平常沒有人,緊急時經核准臨時加入,事後移出'],
  ], { rowH: 0.55, hdrH: 0.44, sz: 11.5, col: INK }), rowCols: [HUM, PLT, RISK, PLT, MDS, MDS, RISK] },
  note('「能做什麼」是實測結果,不是推論;topic-admin 比直覺強,所以列為臨時角色', 6.25, PLT),
] });

add({ title: '人只能唯讀:臨時提權與收回', sub: '需要變更時的流程;全程只動 AD,Kafka 端零變更', items: [
  ...step(1, 0.6, 1.6, 2.3, 2.3, '申請', '依現行核准方式提出;指定群組與時限', HUM),
  ...step(2, 3.1, 1.6, 2.3, 2.3, '加入 AD 群組', 'AD 管理員把人加進 kafka-topic-admin 等群組', HUM),
  ...step(3, 5.6, 1.6, 2.3, 2.3, '數秒內生效', 'MDS 定期重讀群組;本人用同一個帳號操作', PLT),
  ...step(4, 8.1, 1.6, 2.3, 2.3, '做完移出', '時限到或工作完成即移出;已發出的 token 立刻失去權限', PLT),
  ...step(5, 10.6, 1.6, 2.13, 2.3, '事後可查', 'audit 紀錄:誰、什麼時候、對什麼做了什麼、結果', MDS),
  arrow(2.9, 2.75, 3.1, 2.75, 'text1'), arrow(5.4, 2.75, 5.6, 2.75, 'text1'), arrow(7.9, 2.75, 8.1, 2.75, 'text1'), arrow(10.4, 2.75, 10.6, 2.75, 'text1'),
  { ...table(0.6, 4.3, [3.0, 9.13], [
    ['情境', '加入哪個群組'],
    ['看叢集健康、分割區狀態', 'kafka-ops(看得到、改不了)'],
    ['建立或修改 topic、重設 consumer 讀取位置', 'kafka-topic-admin(強角色,做完立刻移出)'],
    ['新系統上線要授權', 'kafka-rbac-admin(只管授權)'],
    ['建立應用系統帳號、叢集設定', 'kafka-cluster-admin'],
  ], { rowH: 0.42, hdrH: 0.4, sz: 12, col: HUM }), rowCols: [PLT, RISK, MDS, PLT] },
] });

// ───────────────── 3. 服務、元件與線路
sec('三、應用系統、平台元件與線路', 'SCRAM、client 憑證、F5、傳輸加密');
add({ title: '應用系統:兩種連線方式', sub: '能用 Kafka 用戶端的直連;只能 HTTP 的經 REST Proxy', items: [
  { ...table(0.6, 1.5, [2.3, 4.9, 4.93], [
    ['項目', '直連 broker', '經 REST Proxy'],
    ['認證', 'SCRAM 帳號(Kafka 內建,不佔 AD)', 'client 憑證;REST Proxy 以自己的憑證向 MDS 代為申請該系統的 token'],
    ['授權', '角色綁在帳號上', '角色綁在憑證的名稱上;broker 與 audit 看到的是該系統'],
    ['最小權限', '只開放自己的 topic 與 consumer group;碰別的 topic 被拒', '相同'],
    ['上線流程', '建帳號 → 綁角色 → 密碼交付(建議經 CyberArk)', '簽憑證 → 綁角色 → 私鑰交付(建議經 CyberArk)'],
    ['密碼或憑證更換', '新帳號並行 → 應用切換 → 停舊,不中斷', '憑證到期前換發'],
    ['必要的保護', '密碼不落地:啟動時從 CyberArk 取', '受保護清單:管理員與平台身分不可被代為申請;清單區分大小寫'],
  ], { rowH: 0.62, hdrH: 0.44, sz: 12, col: SVC }) },
  note('REST Proxy 的憑證可以代任何不在受保護清單的身分,所以清單要列入所有特權身分,寫法要與 AD 記錄一致', 6.2, RISK),
] });

add({ title: '平台元件與憑證', sub: '憑證總數:一張共用 server 憑證 + 一張內部憑證 + 各元件一張 client 憑證 + 經 REST Proxy 的系統各一張', items: [
  { ...table(0.6, 1.5, [3.0, 4.6, 4.53], [
    ['憑證', '用途', '要注意'],
    ['共用 server 憑證(1 張)', '所有元件的 TLS 加密;名稱要涵蓋所有主機與 F5 的名稱', '只做加密、不當身分、不綁任何角色;不要收斂憑證用途(C3 內部會出示它)'],
    ['C3 的 client 憑證', 'C3 自身向 MDS 認證;該身分必須是 SystemAdmin(官方要求)', '拿到私鑰等於管理員:檔案權限、不入版本庫、列入受保護清單'],
    ['REST Proxy 的 client 憑證', '代應用系統向 MDS 申請 token', '同上;受保護清單擋特權身分'],
    ['內部憑證(1 張,broker 與 controller 共用)', '內部埠與 controller 埠的 mTLS;身分是 super user', '拿到私鑰等於叢集管理員:每台 0600、不入版本庫;稽核分不出是哪一台'],
    ['bootstrap 的 client 憑證', '初始化第一批授權;平常不用', '封存,建議由 CyberArk 保管、依單借出'],
    ['只能 HTTP 的系統各一張', '該系統的身分', '隨系統數增加;命名規範先定'],
  ], { rowH: 0.58, hdrH: 0.44, sz: 12, col: PLT }), rowCols: [PLT, RISK, RISK, RISK, RISK, SVC] },
  note('CA 可用行內既有的 AD CS;若 CyberArk 含 Certificate Manager 也可由它簽發與續期(選配)', 6.2, PLT),
] });

add({ title: '負載平衡(F5)', sub: '只放在 REST Proxy 前面;其他連線不需要', items: [
  { ...table(0.6, 1.5, [2.6, 9.53], [
    ['項目', '做法與依據'],
    ['位置', '應用系統 → F5 → REST Proxy ×N;broker、MDS、C3 不經 F5'],
    ['模式', 'L4(TCP)透傳。F5 不終止 TLS:終止會讓 REST Proxy 看不到 client 憑證,憑證身分全部失效(實測 401)'],
    ['危險設定', 'F5 終止 TLS 再用固定憑證連後端:所有呼叫者(含沒憑證的)都變成同一個身分(實測)'],
    ['server 憑證', '名稱要含 F5 的虛擬伺服器名稱'],
    ['consumer', 'REST Proxy 的 consumer 實例綁在某一台,需要 sticky(同一來源固定到同一台);producer 不需要'],
    ['REST Proxy → MDS', '設定多台 MDS 位址即可自動切換(實測:停一台仍全部成功,首次切換約 8 秒),不需要 LB'],
    ['要確認的 F5 設定', '虛擬伺服器類型、後端 TLS session 復用、persistence、idle timeout、SNAT'],
  ], { rowH: 0.56, hdrH: 0.44, sz: 12, col: PLT }), rowCols: [PLT, PLT, RISK, PLT, PLT, MDS, HUM] },
] });

add({ title: '傳輸加密與入口保護', sub: '每一條線都加密;每一個入口都要認證', items: [
  { ...table(0.6, 1.5, [3.2, 5.0, 3.93], [
    ['線路或入口', '做法', '說明'],
    ['broker → AD', '加密連線(636 埠),信任行內 CA;只有連 AD 的 broker 需要信任庫', 'AD 憑證若有中繼 CA,信任庫要放進中繼 CA(實測)'],
    ['使用者 → C3', '只開 HTTPS', '使用者端要信任行內 CA'],
    ['Prometheus、Alertmanager', 'TLS + 帳密;C3 與 broker 推送指標都帶帳密', '沒有細部授權:帳密依用途分開;日誌會印出帳密標頭,要保護'],
    ['broker 內建 Admin REST', '依官方設定安全擴充:匿名擋下、依使用者角色', '未設定時完全沒有認證;與 MDS 共用埠,不能靠防火牆擋'],
    ['內部埠(broker 互連、controller)', 'mTLS:broker 與 controller 共用一張內部憑證;防火牆只開給叢集節點', '憑證身分是 super user,私鑰要保護;稽核分不出是哪一台'],
    ['應用與工具 → broker', 'TLS;人用 AD 帳密、服務用 SCRAM、元件用 token', '同一個對外埠'],
  ], { rowH: 0.62, hdrH: 0.44, sz: 12, col: PLT }), rowCols: [HUM, HUM, PLT, RISK, MDS, SVC] },
] });

add({ title: '帳號被偷之後:六道防線', sub: '假設某個帳密外洩,多久被發現、能做多少事、多久失效', items: [
  { ...table(0.6, 1.5, [2.3, 3.7, 3.3, 2.83], [
    ['機制', '設定', '效果', '測試環境結果'],
    ['重新認證', 'SASL re-authentication:長連線每隔一段時間重新驗證(建議 1 小時)', '帳號被停用或改密碼後,既有長連線在期限內被切斷', '改密碼後舊連線被切斷(測試值 60 秒)'],
    ['認證失敗告警', '認證失敗次數的告警規則(Prometheus)', '密碼被猜、被撞庫時能發現', '連續失敗觸發告警'],
    ['TLS 版本與套件', '只開 TLS 1.3 / 1.2 與 AEAD 套件', '擋掉老舊、較弱的套件', '設定前 broker 接受舊的 CBC 套件;設定後被拒'],
    ['單一來源連線上限', '每個來源 IP 的連線數上限', '一個來源不能開無限條連線', '超過上限的連線被拒'],
    ['流量配額', 'client quota(位元組/秒)', '被偷的帳號最多能灌多少', '超過配額即被限速'],
    ['AD 帳戶鎖定', 'AD 的鎖定原則', '擋暴力猜密碼;但鎖定也能被拿來鎖別人的帳號(雙面刃)', '鎖定後 MDS 與 Kafka 同時失敗;緊急路徑與機器帳號不受影響;解鎖即恢復'],
  ], { rowH: 0.78, hdrH: 0.44, sz: 11.5, col: RISK }), rowCols: [PLT, MDS, PLT, SVC, SVC, HUM] },
] });

add({ title: 'SCRAM 帳號:停用,不要刪除', sub: 'Apache Kafka 已知問題;影響 Confluent Platform 8.3.x', items: [
  { ...table(0.6, 1.5, [2.4, 9.73], [
    ['項目', '說明'],
    ['已知問題', '刪除 SCRAM 憑證後,broker 重放 metadata 時會丟掉整組 SCRAM 使用者(KAFKA-20774);修復在 Kafka 4.5.0(尚未發行),Confluent Platform 8.3.x 內含 Kafka 4.3.x,受影響'],
    ['症狀', '內部通道用 SCRAM:broker 重啟後起不來。內部通道用 mTLS:broker 起得來,但對外埠所有 SCRAM 登入失敗'],
    ['何時發生', '全新叢集刪除一個 SCRAM 帳號後重啟 broker 即重現;跑很久、已有 metadata 快照的叢集不一定重現——沒重現不代表安全'],
    ['本方案的做法', '停用 = 覆寫成隨機密碼 + 解除角色,一律不刪除;內部通道採 mTLS,降低 broker 起不來的風險'],
    ['已經刪過', '重建被刪的同名帳號(任何密碼),再滾動重啟 broker 即恢復;不必清資料'],
  ], { rowH: 0.8, hdrH: 0.44, sz: 12.5, col: RISK }), rowCols: [RISK, MDS, PLT, SVC, HUM] },
] });

add({ title: 'Schema Registry 與欄位級加密(CSFLE)', sub: '授權沿用同一套身分與群組;欄位加密本身需要加購授權', items: [
  { ...table(0.6, 1.5, [2.3, 7.13, 2.7], [
    ['項目', '做法與結果', '狀態'],
    ['認證', 'REST 要帳密:不帶或密碼錯 401', '測試環境已驗證'],
    ['subject 授權', '跟 AD 群組走:訂單群組只能碰 orders. 開頭的 subject,其他被拒;列出 subject 只看到有權限的', '測試環境已驗證'],
    ['金鑰加密金鑰(KEK)管理', '只有 security 群組能建;應用群組只被授權讀;無角色者被拒', '測試環境已驗證'],
    ['Schema Registry 自身', '以 client 憑證向 MDS 換 token 連 Kafka,不佔 AD 帳號', '測試環境已驗證'],
    ['規則沒生效的風險', '沒開規則 extension 時,加密規則被默默丟掉、資料以明文寫入;上線前與每次改規則後,要讀 topic 原始位元組確認', '測試環境已驗證'],
    ['欄位實際加密與解密', '註冊帶加密規則的 schema 需要企業版加 CSFLE 加購授權,否則回 402;加密、解密、金鑰輪替', '未驗證(待授權)'],
    ['解密權限與 KMS', '由 KMS 控制,不是 Kafka 的 RBAC;內建支援 AWS、Azure、GCP、HashiCorp Vault;地端 HSM 需自訂 Java 驅動', '依官方文件'],
  ], { rowH: 0.62, hdrH: 0.44, sz: 12, col: MDS }), rowCols: [SVC, SVC, SVC, SVC, RISK, RISK, PLT] },
] });

add({ title: '監控、告警與稽核', sub: '看得到、告得了、查得到', items: [
  { ...table(0.6, 1.5, [2.8, 9.33], [
    ['項目', '做法'],
    ['監控', 'C3 搭配 Prometheus;指標由 broker 推送;維護前用 OP menu 對該節點靜音告警,做完即結束'],
    ['告警', 'Alertmanager 路由;靜音與告警變更要有人看(有帳密就能靜音,所以帳密分開)'],
    ['稽核(audit)', 'broker 寫入 audit 事件:誰、什麼時候、對什麼、允許或拒絕;授權變更(含非管理員的嘗試)都有紀錄'],
    ['定期覆核', 'OP menu 匯出權限清單(角色、主體、資源範圍)供覆核;SystemAdmin 保持最少人數'],
    ['紀錄保護', 'OP menu 每個動作留紀錄並集中到 syslog;C3、Prometheus 日誌含帳密標頭,權限要收緊'],
  ], { rowH: 0.7, hdrH: 0.44, sz: 12.5, col: MDS }) },
] });

// ───────────────── 4. 維運與緊急
sec('四、日常維運與緊急', 'OP menu、跳板機與主機、初始化與緊急模式');
add({ title: 'OP menu:分層與真正的門', sub: '操作員只從選單執行審核過的作業;選單不判斷權限', items: [
  { ...table(0.6, 1.5, [1.8, 2.7, 4.9, 2.73], [
    ['層級', '誰用(AD 群組)', '項目', '真正的門'],
    ['值班查看', 'kafka-ops', '健康檢查(含身分鏈)、topic 狀態、consumer 落後量、磁碟、憑證到期日、leader 分布、生效設定', 'Kafka RBAC:唯讀'],
    ['服務操作', 'kafka-ops', '重啟單一 broker、滾動重啟、維護模式、查看服務日誌', '各節點 sudo 規則;一次一台,每台等叢集恢復才換下一台'],
    ['變更作業', 'kafka-topic-admin;kafka-cluster-admin + kafka-rbac-admin', '建立或修改 topic、應用系統帳號上線與下架、更換密碼', 'Kafka RBAC;執行前顯示影響並要求確認;可限制時段、同一時間只允許一人'],
    ['授權與緊急', 'kafka-rbac-admin、kafka-security;緊急模式依 sudo 規則', '指派權限、匯出與查詢 audit、匯出權限清單、緊急模式', 'Kafka RBAC;緊急模式經 sudo 切換專用帳號,逐條記錄'],
  ], { rowH: 0.8, hdrH: 0.44, sz: 12, col: HUM }), rowCols: [PLT, PLT, MDS, RISK] },
  note('Kafka 的動作由 RBAC 依本人 AD 帳號判斷;主機的動作由 sudo 規則判斷;每次執行留紀錄', 5.9, HUM),
] });

add({ title: '跳板機與主機:兩種情況', sub: '不影響 Kafka 本身(broker 查 AD 不需要主機加入網域);只影響人怎麼登入主機', items: [
  { ...table(0.6, 1.5, [2.4, 4.85, 4.88], [
    ['項目', '主機有加入 AD', '主機沒有加入 AD'],
    ['登入跳板機', '本人 AD 帳號;OP menu 直接取登入者,不再問帳密', '本機帳號(或經 CyberArk PSM 代登入);OP menu 自己問 AD 帳密'],
    ['sudo 規則', '直接引用 AD 群組;人員異動只改 AD', '維護本機帳號與群組,或把 PSM 當門'],
    ['跳板機 → 主機', '操作員用本人身分 ssh;主機日誌直接看得到是誰', '用自動化帳號 ssh(key 由 CyberArk 保管與輪替、執行時取);「是誰」靠 OP menu 紀錄'],
    ['CyberArk 份量', '管 root 與 breakglass、PSM 錄影', '加上日常 ssh 身分也靠它'],
    ['建議', '較簡單、稽核直接;若客戶可做,建議這條', '可行;多一個自動化帳號要管'],
  ], { rowH: 0.7, hdrH: 0.44, sz: 12, col: HUM }), rowCols: [HUM, PLT, SVC, RISK, MDS] },
  note('OP menu 兩種情況都支援,只差一個設定;待客戶回答:主機與跳板機是否加入 AD、人連主機是否一律經 PSM', 6.1, PLT),
] });

add({ title: '初始化與緊急', sub: 'bootstrap 只用於初始化;緊急時用自己的身分加 breakglass 群組', items: [
  ...step(1, 0.6, 1.6, 2.9, 2.1, '初始化', '用 bootstrap 憑證建立第一批授權:C3、REST Proxy、7 個群組', PLT),
  ...step(2, 3.7, 1.6, 2.9, 2.1, '驗收', '用 AD 身分確認:rbac-admin 能改授權、ops 不能變更、無群組被拒', HUM),
  ...step(3, 6.8, 1.6, 2.9, 2.1, '封存', 'bootstrap 憑證私鑰離線保管(建議 CyberArk);日常不使用', RISK),
  ...step(4, 9.9, 1.6, 2.83, 2.1, '緊急', '經核准臨時加入 kafka-breakglass,用本人身分操作;事後移出並查 audit', RISK),
  arrow(3.5, 2.65, 3.7, 2.65, 'text1'), arrow(6.6, 2.65, 6.8, 2.65, 'text1'), arrow(9.7, 2.65, 9.9, 2.65, 'text1'),
  { ...table(0.6, 4.0, [3.0, 9.13], [
    ['情境', '處理'],
    ['AD 或 MDS 身分機制失效', 'bootstrap 憑證經 OP menu 緊急模式(sudo 切換專用帳號)執行單一指令,逐條記錄;事後輪替憑證'],
    ['SystemAdmin 人數', '保持最少;平常 kafka-breakglass 是空的'],
    ['紀錄', '緊急模式每一條指令都記錄;CyberArk PSM 可加錄影'],
  ], { rowH: 0.5, hdrH: 0.4, sz: 12, col: RISK }), rowCols: [RISK, MDS, PLT] },
] });

// ───────────────── 5. CyberArk
sec('五、CyberArk 整合', '先懂元件,再看接在哪裡');
add({ title: 'CyberArk 是什麼:會用到的元件', sub: '一套「特權存取與秘密管理」平台;不同模組解決不同問題', items: [
  { ...table(0.6, 1.5, [2.6, 5.0, 4.53], [
    ['元件', '做什麼', '我們用在哪'],
    ['Vault + PVWA', '加密保存密碼、私鑰等「秘密」;PVWA 是管理與申請的網頁介面(核准流程、借出紀錄)', '保管 bootstrap 私鑰、root 密碼、breakglass 相關;依單借出'],
    ['CPM', '自動定期更換被納管帳號的密碼或 SSH key', '輪替跳板機與各主機的 root、本機帳號'],
    ['PSM / PSM for SSH', '人連主機時由它代登入(密碼不經手)並錄影;可當跳板', '人登入跳板機與主機;緊急操作有錄影'],
    ['CCP', '應用程式用的取密碼 API:以應用識別 + 主機或憑證認證,回傳密碼', '應用系統啟動時取 SCRAM 密碼;平台元件啟動前取設定檔密碼'],
    ['Conjur', '新一代的秘密管理(含 Kubernetes、CI/CD);host 身分換短效 token 取秘密', '若客戶已採用,可取代 CCP 的角色'],
    ['Summon', '小工具:啟動程式前把秘密變成環境變數,不改程式碼', '不方便改程式的應用或腳本'],
    ['Certificate Manager(選配)', '憑證簽發、到期追蹤與自動續期', '共用 server 憑證與 client 憑證的生命週期'],
  ], { rowH: 0.56, hdrH: 0.44, sz: 11.5, col: RISK }), rowCols: [RISK, RISK, HUM, SVC, SVC, SVC, PLT] },
] });

add({ title: 'CyberArk 整合總圖', sub: '身分與授權不變;CyberArk 只接管「密碼與私鑰放哪、誰能拿、怎麼輪替、怎麼錄影」', items: [
  { ...table(0.6, 1.5, [2.1, 3.5, 4.8, 1.73], [
    ['對象', '現有機制(不變)', 'CyberArk 接入點', '模組'],
    ['人', 'AD 帳密換 token;角色綁 AD 群組', '不經 CyberArk;只有「登入跳板機」這段可先過 PSM', '—'],
    ['跳板機 + OP menu', '本人 AD 身分 + sudo;動作留紀錄', 'PSM 代登入與錄影;sudo 引用 AD 群組;緊急操作有錄影', 'PSM'],
    ['主機 OS 帳號', '本機帳號 + sudoers', 'CPM 定期輪替 root 與本機帳號;人要用時經 PSM 借', 'CPM'],
    ['bootstrap / breakglass', 'client 憑證 0600;群組平常空的', '私鑰存 Vault,依單核准借出、用完換發', 'Vault + PVWA'],
    ['應用系統', 'SCRAM 帳密或 client 憑證 + 最小權限', '啟動時向 CCP 取密碼或私鑰,在記憶體使用、不落地;不改程式用 Summon', 'CCP / Conjur / Summon'],
    ['平台元件設定檔', '設定檔內的密碼', 'Confluent Secret Protection 加密設定檔,主金鑰啟動時向 CCP 取;或啟動前取密碼寫 0600 檔', 'CCP + Secret Protection'],
    ['共用 server 憑證', '一張憑證只做加密', '(選配)Certificate Manager 簽發與續期', 'Cert Manager'],
  ], { rowH: 0.56, hdrH: 0.42, sz: 11.5, col: RISK }), rowCols: [HUM, HUM, PLT, RISK, SVC, PLT, PLT] },
  note('Kafka 的 SCRAM 密碼沒有現成的 CPM 平台:用「新帳號並行 → 切換 → 停舊」腳本,由 CPM 自訂平台或排程呼叫', 6.25, RISK, { sz: 12 }),
] });

add({ title: '人連主機的三種模式', sub: '決定 OP menu 的 ssh 身分怎麼設計;要向客戶確認', items: [
  { ...table(0.6, 1.5, [2.4, 3.6, 3.6, 2.53], [
    ['模式', '人怎麼連', '跳板機 → 主機', '對 OP menu 的影響'],
    ['A. PSM 就是跳板機(最常見)', '人用 AD 帳號連 PSM for SSH,由它取主機帳密開 session、錄影', '主機 22 埠通常只開給 PSM;原本的跳板機變成被納管的主機', 'OP menu 用自動化帳號 ssh 各主機,key 由 CyberArk 保管、執行時取;人仍以 AD 身分登入選單'],
    ['B. PSM 在跳板機前面', '人經 PSM 進跳板機', '維持跳板機直連主機', '幾乎不用改;補上 CyberArk 管理的 key 與集中紀錄'],
    ['C. 兩層都經 PSM', '人經 PSM 進跳板機,再經 PSM 連主機', '繞兩次', 'ssh 要改成經 PSM,複雜,不建議'],
  ], { rowH: 1.05, hdrH: 0.44, sz: 12, col: RISK }), rowCols: [RISK, PLT, HUM] },
  note('建議:A 或 B 皆可;重點是「主機 22 埠允許哪些來源」與「跳板機是否加入 AD」,兩個答案決定做法', 5.6, HUM),
] });

add({ title: '應用程式取密碼與輪替', sub: '密碼不落地;換密碼不中斷', items: [
  text(0.6, 1.5, 6, 0.35, [P('取密碼(每次啟動)', { sz: 13.5, b: true, c: SVC })]),
  ...step(1, 0.6, 1.9, 2.8, 1.9, '認證', '應用以 AppID + 主機或憑證向 CCP 認證', SVC),
  ...step(2, 3.6, 1.9, 2.8, 1.9, '取密碼', '取得 SCRAM 帳密(或憑證私鑰)', SVC),
  ...step(3, 6.6, 1.9, 2.8, 1.9, '記憶體使用', '組成連線設定,不寫入磁碟', SVC),
  ...step(4, 9.6, 1.9, 3.13, 1.9, '連 broker', 'SCRAM 認證;broker RBAC 判斷', MDS),
  arrow(3.4, 2.85, 3.6, 2.85, 'text1'), arrow(6.4, 2.85, 6.6, 2.85, 'text1'), arrow(9.4, 2.85, 9.6, 2.85, 'text1'),
  text(0.6, 4.05, 6, 0.35, [P('輪替(定期或事件觸發)', { sz: 13.5, b: true, c: PLT })]),
  ...step(1, 0.6, 4.45, 2.8, 1.9, '建新帳號', '建立 v2 帳號並綁同樣角色,寫回 Vault', PLT),
  ...step(2, 3.6, 4.45, 2.8, 1.9, '並行', '新舊同時可用,應用逐批重啟切換', PLT),
  ...step(3, 6.6, 4.45, 2.8, 1.9, '停舊', '全部切換後停用舊帳號,舊密碼立刻失效', PLT),
  ...step(4, 9.6, 4.45, 3.13, 1.9, '誰來做', 'CPM 自訂平台呼叫腳本,或排程;全程 audit 可查', RISK),
  arrow(3.4, 5.4, 3.6, 5.4, 'text1'), arrow(6.4, 5.4, 6.6, 5.4, 'text1'), arrow(9.4, 5.4, 9.6, 5.4, 'text1'),
] });

add({ title: '設定檔密碼加密:輪替與重啟', sub: 'Confluent Secret Protection;主金鑰由 CyberArk 保管', items: [
  { ...table(0.6, 1.5, [2.5, 9.63], [
    ['項目', '做法與結果(測試環境實測)'],
    ['兩層金鑰', '主金鑰(CyberArk 保管,啟動時取)加密資料金鑰;資料金鑰加密設定檔裡的密碼。叢集共用同一把主金鑰、同一份密文檔'],
    ['輪替主金鑰', '只重包資料金鑰,值的密文不變;需要「目前的」與「新的」passphrase(也要保管,只讓管理員讀);新主金鑰只顯示一次,要立刻寫回 CyberArk'],
    ['輪替資料金鑰', '只需要目前的 passphrase;所有值重新加密;主金鑰不變,CyberArk 不用動'],
    ['檔與主金鑰要成對', '新檔配舊金鑰、舊檔配新金鑰都解不開;不成對時 broker 起不來。輪替前先備好舊檔與舊主金鑰以便退回'],
    ['一定要重啟', '啟動時才讀。維護窗口內一台一台做:換檔 → 取新主金鑰 → 重啟 → 確認健康 → 下一台'],
    ['重啟期間服務', '測試環境 2 台 broker、副本 2:輪替並滾動重啟期間持續寫入 1200 筆,全部寫入、零遺失;正式環境建議副本 3、最小同步副本 2,controller 也逐台重啟'],
    ['注意', 'passphrase 在這個版本的指令只能直接放在指令列(不讀檔),輪替要在受控的管理主機上做'],
  ], { rowH: 0.66, hdrH: 0.44, sz: 11.5, col: PLT }), rowCols: [PLT, PLT, SVC, PLT, RISK, HUM, RISK] },
] });

// ───────────────── 6. 收尾
sec('六、待確認、限制與導入順序', '');
add({ title: '要向客戶確認的事項', sub: '答案會決定幾個分支的做法', items: [
  { ...table(0.6, 1.5, [3.4, 5.2, 3.53], [
    ['主題', '問題', '影響'],
    ['AD', '使用者名稱與 CN 是否完全相同(含大小寫);Kafka 群組放哪個 OU;群組人數', '群組查詢設定、主體寫法'],
    ['主機', '跳板機與各主機是否加入 AD;人連主機是否一律經 PSM;主機 22 埠允許哪些來源', '登入與 sudo 設計、OP menu 的 ssh 身分'],
    ['CyberArk', '有哪些模組(PSM、CPM、CCP、Conjur、Summon、Certificate Manager);應用主機與 Kafka 節點能否連到 CCP / PSM;AppID 用 IP 還是憑證認;輪替週期與負責人', '第五章每一列的做法'],
    ['F5', '虛擬伺服器類型(L4)、後端 TLS session 復用、persistence、idle timeout、SNAT;REST Proxy 幾台', '憑證名稱、sticky 設定'],
    ['變更管理', '變更核准方式;維運作業項目清單;現有 OP menu 樣貌', 'OP menu 的核准檢查與項目'],
    ['憑證', 'CA 由誰簽(AD CS 或 Certificate Manager);有效期政策', '憑證生命週期'],
    ['資料保護', '是否需要欄位級加密(CSFLE);取得加購授權的方式;地端 KMS 或 HSM 的型號與是否有 Java 驅動;重新認證間隔、連線上限與配額的政策', 'CSFLE 能否導入、金鑰放哪'],
  ], { rowH: 0.66, hdrH: 0.44, sz: 12, col: HUM }), rowCols: [HUM, PLT, RISK, PLT, MDS, PLT, RISK] },
] });

add({ title: '未驗證與限制(如實說明)', sub: '已實測的以外,這些尚未在客戶環境驗證', items: [
  { ...table(0.6, 1.5, [3.4, 8.73], [
    ['項目', '狀態'],
    ['CyberArk:秘密管理', '已用 CyberArk 的開源版 Conjur 實測「應用程式取密碼、輪替、OP menu 取帳密、設定檔密碼不落地」;商業版 CCP / Conjur 的 API 細節以客戶版本文件為準'],
    ['CyberArk:PAM(PSM、CPM、PVWA)', '無法在測試環境重現,整合方式為通用模式;需在客戶環境 PoC'],
    ['真實 AD', '巢狀群組、群組異動的實際延遲、AD 憑證鏈(中繼 CA)要以客戶 AD 驗證'],
    ['F5', '以同類負載平衡器實測 L4 透傳可行、L7 終止不可;F5 本身的行為要以客戶設定驗證'],
    ['多 controller 與 RHEL 部署', '設計依官方文件;以本方案的測試環境為準,未在客戶 VM 驗證'],
    ['C3 經 F5', '未驗證;建議 C3 不經 F5'],
    ['SCRAM 密碼輪替', '已實測新舊並行流程(建新帳號、驗證、隔離、看 audit、才停用舊帳號,停用是覆寫成隨機密碼、不刪除);由 CPM 自訂平台或排程觸發同一支腳本,需在客戶環境確認'],
    ['停用帳號對已連線的影響', '實測:只停用 SCRAM 憑證擋不住已連著的連線,必須先解除角色;長連線的應用要能在失敗時重新取帳密'],
    ['Conjur 可用性與根的秘密', '取不到帳密應用與 broker 起不來,要規劃高可用與重試;機器 API key(secret zero)的保護與輪替未示範'],
  ], { rowH: 0.58, hdrH: 0.44, sz: 12.5, col: RISK }) },
] });

add({ title: '未驗證與限制(續)', sub: '資料保護、金鑰管理與參數值', items: [
  { ...table(0.6, 1.5, [3.4, 8.73], [
    ['項目', '狀態'],
    ['欄位級加密(CSFLE)', '需要企業版加 CSFLE 加購授權;測試環境的試用授權註冊加密規則會被拒(HTTP 402),所以加密、解密、金鑰輪替都未驗證'],
    ['地端 KMS 與 HSM', '內建只支援 AWS、Azure、GCP、HashiCorp Vault;HSM 需自訂 Java 驅動(官方有介面說明,未見 HSM 範例);廠商是否有現成驅動未確認'],
    ['CyberArk 能否當 KMS', '開源版 Conjur 是秘密管理,不是 KMS(它把秘密交出去,不代為加解密);PAM 等其他模組是否提供 KMS 式服務未確認,要問客戶的 CyberArk 窗口'],
    ['主金鑰輪替', '已實測單台與兩台共用同一把金鑰的逐台重啟;更多台與 controller 的流程依官方文件與同樣原則,正式環境要在維護窗口內演練'],
    ['SCRAM 刪除問題', '依 Apache Kafka 回報與測試環境實測;升級到含修復的版本(4.5.0 以上)前維持「停用不刪除」'],
    ['防線參數', '重新認證 60 秒、連線上限 2、配額等是測試值;正式值要依客戶的應用特性與容量評估'],
  ], { rowH: 0.78, hdrH: 0.44, sz: 12.5, col: RISK }) },
] });

add({ title: '導入順序建議', sub: '先把身分與授權做對,再接 CyberArk', items: [
  ...step(1, 0.6, 1.6, 2.3, 2.6, '基礎', 'AD 群組與唯讀查詢帳號;憑證;叢集與 TLS;初始授權與驗收', PLT),
  ...step(2, 3.1, 1.6, 2.3, 2.6, '人與系統上線', 'C3、REST Proxy、F5;應用系統帳號與憑證;命名規範', HUM),
  ...step(3, 5.6, 1.6, 2.3, 2.6, '維運', 'OP menu、監控告警、audit 匯出與覆核;緊急流程演練', MDS),
  ...step(4, 8.1, 1.6, 2.3, 2.6, 'CyberArk 第一階段', 'PSM 代登入與錄影;CPM 輪替主機帳號;bootstrap 私鑰入 Vault', RISK),
  ...step(5, 10.6, 1.6, 2.13, 2.6, 'CyberArk 第二階段', '應用程式經 CCP 取密碼;設定檔密碼不落地;SCRAM 輪替自動化', RISK),
  arrow(2.9, 2.9, 3.1, 2.9, 'text1'), arrow(5.4, 2.9, 5.6, 2.9, 'text1'), arrow(7.9, 2.9, 8.1, 2.9, 'text1'), arrow(10.4, 2.9, 10.6, 2.9, 'text1'),
  note('第 1 到 3 步已在測試環境完整驗證;第 4、5 步依客戶回答的 CyberArk 模組決定範圍', 4.7, PLT),
  note('每一步都有驗收標準:身分對、權限對、紀錄查得到;不過關不進下一步', 5.3, HUM),
] });

module.exports = { SLIDES: S, THEME, HEX, NO_END: false, NO_NOTES: true };
