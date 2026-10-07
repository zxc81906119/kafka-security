// 簡化版(方案摘要)規格:依完整版重新編排,一頁一個結論,細節留在備忘稿。
// 編排順序(顧問簡報):全景 → 設計決策 → 認證 → 授權 → 加密 → 各身分做法 → 維運 → 風險 → 待確認 → 下一步。
// 不含監控與 audit。沿用完整版的圖形規格,同一個 IISI 生成器輸出:
//   SPEC=./build-solution-short.js OUT=Confluent-Security-Solution-IISI-short.pptx node build-solution-iisi.js
const path = require('path');
const { SLIDES: ALL, THEME, HEX, H } = require('./build-solution-deck.js');
const { node, chip, tint, text, P, MUTE, arrow, solid, white, box, badge, table, HUM, SVC, PLT, MDS, RISK, INK } = H;

const pick = (title) => { const s = ALL.find(x => x.title === title); if (!s) throw new Error('找不到頁面:' + title); return s; };
const SHORT = [];
const add = (s) => SHORT.push(s);
// 圖示 + 兩行字的橫向節點
const pill = (x, y, w, h, col, ic, t, s) => [tint(x, y, w, h, col, { round: 0.12 }), ...badge(ic, x + 0.12, y + (h - 0.52) / 2, 0.52, col),
  text(x + 0.76, y, w - 0.82, h, [P(t, { sz: 13, b: true, c: col }), P(s, { sz: 10.5, ...MUTE })], { anchor: 'ctr' })];

// 1 封面
add({ layout: 'TITLE', title: 'Confluent 安全解決方案', coverSub: '方案摘要:認證、授權、加密與維運', items: [], notes: '方案摘要版:只講做法與結論。出處、實測依據與限制在各頁備忘稿;完整版有逐項前提與驗證狀態。本版不含監控(Prometheus、Alertmanager)與 audit。' });

// 2 方案全景
const ROWS = [
  ['FaDesktop', '人 · 瀏覽器', '登入 Control Center', HUM, 'AD 帳密', 'Control Center', '本人的 token'],
  ['FaTerminal', '人 · 腳本、Postman', '呼叫 REST API', HUM, 'AD 帳密', 'REST Proxy', '本人的 token'],
  ['FaUser', '人 · CLI', 'Kafka 指令工具', HUM, 'AD 帳密', null, null],
  ['FaCogs', '服務', '應用 · 排程', SVC, 'SCRAM 帳密', null, null],
  ['FaPlug', 'legacy app', '只能 HTTP', SVC, 'client 憑證', 'REST Proxy', 'app 的 token'],
];
add({ title: '方案全景:誰用什麼進來', sub: '五條進入路徑,授權集中在 MDS 的 RBAC', items: [
  ...ROWS.flatMap(([ic, t, s, col, cred, gw, tok], i) => {
    const y = 1.5 + i * 0.92, ym = y + 0.45, lab = (x, tx) => text(x, y + 0.04, 1.6, 0.3, [P(tx, { sz: 10.5, b: true, c: col, algn: 'ctr' })]);
    const out = [...pill(0.6, y, 2.5, 0.8, col, ic, t, s), lab(3.1, cred)];
    if (gw) out.push(arrow(3.1, ym, 4.7, ym, col), white(4.7, y + 0.1, 2.1, 0.62, col, { round: 0.25, paras: [P(gw, { sz: 12.5, b: true, algn: 'ctr' })] }), arrow(6.8, ym, 8.4, ym, col), lab(6.8, tok));
    else out.push(arrow(3.1, ym, 8.4, ym, col));
    return out;
  }),
  tint(8.4, 1.5, 2.75, 4.48, PLT, { round: 0.04 }), text(8.4, 1.56, 2.75, 0.35, [P('Kafka 叢集', { sz: 14, b: true, c: PLT, algn: 'ctr' })]),
  white(8.6, 2.0, 2.35, 1.0, HUM, { round: 0.08, paras: [P('broker', { sz: 13, b: true, algn: 'ctr', after: 2 }), P('驗證身分 · 本地授權', { sz: 10.5, algn: 'ctr', ...MUTE })] }),
  white(8.6, 3.2, 2.35, 1.3, MDS, { round: 0.08, paras: [P('MDS · RBAC', { sz: 13, b: true, c: MDS, algn: 'ctr', after: 2 }), P('簽發 token', { sz: 10.5, algn: 'ctr', ...MUTE }), P('集中管理授權', { sz: 10.5, algn: 'ctr', ...MUTE })] }),
  white(8.6, 4.7, 2.35, 1.05, PLT, { round: 0.08, paras: [P('controller', { sz: 13, b: true, algn: 'ctr', after: 2 }), P('只收內部帳號', { sz: 10.5, algn: 'ctr', ...MUTE })] }),
  arrow(11.15, 3.25, 11.6, 3.25, HUM, { w: 2.5 }),
  tint(11.6, 2.0, 1.13, 2.5, HUM, { round: 0.08 }), ...badge('FaUsers', 11.89, 2.15, 0.55, HUM),
  text(11.6, 2.85, 1.13, 1.5, [P('AD', { sz: 14, b: true, algn: 'ctr', c: HUM, after: 2 }), P('人與群組', { sz: 10, algn: 'ctr', ...MUTE }), P('LDAPS', { sz: 10, algn: 'ctr', ...MUTE })]),
  solid(0.6, 6.15, 12.13, 0.65, INK, [P('認證來源有三種(AD 帳密、SCRAM、client 憑證);授權只在一處:MDS 的 RBAC', { sz: 15, b: true, c: 'background1', algn: 'ctr' })]),
], notes: '全景:人有三個入口,都用 AD 帳密:瀏覽器登入 Control Center、腳本或 Postman 經 REST Proxy、CLI 直連 broker 的 9094。服務用 SCRAM 帳密直連 broker。legacy app 只能 HTTP,出示 client 憑證給 REST Proxy。Control Center 與 REST Proxy 向 MDS 取得 token(人是本人的 token;legacy app 由 REST Proxy 代為申請),再帶 token 連 broker。MDS 內嵌在 broker,負責簽發 token 與管理 RBAC;各 broker 讀取 RBAC 資料後在本地授權。人的密碼由 AD 驗證(LDAPS),群組由 MDS 定期向 AD 同步。controller 只收內部帳號,人與服務都不直接連它。' });

// 3 設計決策(表格)
add({ title: '設計決策:前提決定做法', sub: '每個選擇都對應一個客戶前提或官方限制', items: [
  table(0.6, 1.5, [3.7, 5.3, 3.13], [
    ['前提或限制', '方案的選擇', '依據'],
    ['AD 只有人與群組,沒有服務帳號', '人用 AD 帳密;服務用 Kafka 內的 SCRAM 帳號', '客戶前提'],
    ['憑證越少越好', 'server 端共用一組憑證;client 憑證只給平台元件與 legacy app', '客戶前提'],
    ['legacy app 只能 HTTP', '經 REST Proxy,用 client 憑證換 token', '客戶前提'],
    ['不同職責要有不同權限', 'AD 群組綁 role;人員異動只改 AD', '客戶前提'],
    ['controller listener 不支援 SCRAM', '連 broker 用 SCRAM;連 controller 用 PLAIN 靜態帳號', '官方 SCRAM overview 頁'],
    ['RHEL 9 手動安裝,沒有 Ansible', '手動流程標準化;改設定時逐台滾動重啟', '客戶前提'],
  ], { rowH: 0.72, hdrH: 0.46, sz: 12.5, col: INK }),
], notes: '六個設計決策與依據。①AD 只有 user 與 group,沒有服務帳號,所以人用 AD,服務帳號放在 Kafka(SCRAM)。②客戶希望憑證越少越好,所以 server 端共用一組憑證,只做加密;client 憑證只發給需要向 MDS 證明身分的平台元件(c3、restproxy、bootstrap)與 legacy app。③legacy app 只能 HTTP,所以經 REST Proxy,出示 client 憑證,由 REST Proxy 代為向 MDS 申請 token。④權限依職責分層,用 AD 群組綁 role。⑤官方 SCRAM overview 頁說明 controller listener 不支援 SCRAM,所以連 controller 的 9093 用 PLAIN 靜態帳號,連 broker 的 9092 用 SCRAM;內部通道不走 AD(AD 沒有服務帳號,且 AD 異常不應牽連叢集),也不另發 client 憑證。⑥RHEL 9 手動安裝、沒有 Ansible,所以流程要標準化。' });

// 4 四種身分(表格;原「人的三個入口」併入備忘稿)
const hp = pick('人的完整路徑');
add({ title: '認證:四種身分,各有來源', sub: '出示什麼、從哪裡進、誰驗證、授權綁什麼', items: [
  { ...table(0.6, 1.5, [2.6, 1.9, 3.4, 2.5, 1.73], [
    ['身分', '出示什麼', '從哪裡進', '誰驗證身分', '授權綁什麼'],
    ['人(瀏覽器、CLI、腳本)', 'AD 帳密', 'Control Center、REST Proxy、MDS、broker 9094', 'AD(由 broker 或 MDS 轉驗)', 'Group:AD 群組'],
    ['服務(應用、排程)', 'SCRAM 帳密', 'broker 9094', 'broker(帳密存在 Kafka)', 'User:服務帳號'],
    ['平台元件、legacy app', 'client 憑證,換成 MDS 的 token', 'MDS、REST Proxy', 'MDS 或 REST Proxy(CN 對映成主體)', 'User:憑證 CN'],
    ['內部元件(broker、controller)', '內部帳號', 'broker 9092 用 SCRAM;controller 9093 用 PLAIN', '被連的那一方', 'super.users'],
  ], { rowH: 0.85, hdrH: 0.46, sz: 12, col: INK }), rowCols: [HUM, SVC, MDS, PLT] },
  chip('腳本呼叫 Control Center 的 API:只收 Bearer,先用 AD 帳密向 MDS 換 token', 0.6, 5.6, 12.13, HUM, { sz: 12.5, h: 0.45 }),
  solid(0.6, 6.2, 12.13, 0.6, INK, [P('前三種由 broker 依 MDS 的 RBAC 授權;內部帳號列為 super.users,只開放節點之間連線', { sz: 14, b: true, c: 'background1', algn: 'ctr' })]),
], notes: '四種身分。①人:AD 帳密。直連 broker 的 9094 時用 SASL/PLAIN,由 broker 轉 AD 驗密碼;經 Control Center、REST Proxy 或直接呼叫 MDS 時用 Basic,由 MDS 向 AD 驗證並簽發 token。登入只驗密碼;群組由 MDS 定期向 AD 同步,授權時依帳號名稱查群組,RBAC 綁 Group:。②服務:SCRAM 帳密存在 Kafka(KRaft),由 broker 驗證,RBAC 綁 User:。③平台元件(c3、restproxy)用 client 憑證向 MDS 換 token;legacy app 出示憑證給 REST Proxy,由 REST Proxy 依 CN 對映成主體並代為向 MDS 申請 token;憑證身分只能綁 User:,不能綁群組。④內部元件:連 broker 的 9092 用 SCRAM(kafka-broker、kafka-controller),連 controller 的 9093 用 PLAIN 靜態帳號,broker 與 controller 都是;授權用 super.users;這兩個埠用防火牆限制只給節點之間連線。 人的三條路徑:' + hp.notes + ' 腳本與 Postman:REST Proxy 與 MDS 都接受 Basic(AD 帳密),也接受 Bearer;Control Center 自己的 API 只收 Bearer(官方),實測用 Basic 回 401、帶 MDS 簽發的 token 回 200,所以腳本要先用 AD 帳密向 MDS 的 /security/1.0/authenticate 換 token。腳本的帳密建議放環境變數或密碼庫,不寫進腳本檔。腳本由手動改成排程後,要改用服務身分,不借用人的帳號。token 到期後要重新取得,長時間執行的腳本要處理;token 壽命的實際影響尚未實測。' });

// 6 授權:五層(表格)
const gr = pick('AD 群組 → role:依職責分層授權');
add({ title: '授權:AD 群組分五層', sub: '人員異動只改 AD,Kafka 端零變更', items: [
  { ...table(0.6, 1.5, [2.6, 4.33, 1.3, 1.3, 1.3, 1.3], [
    ['AD 群組', '綁定的 role', '讀資料', '寫資料', '管 topic', '改授權'],
    ['kafka-readonly', 'DeveloperRead', '可', '', '', ''],
    ['kafka-developers', 'DeveloperRead、DeveloperWrite(orders. 前綴)', '可', '可', '', ''],
    ['kafka-ops', 'Operator、DeveloperManage(infra. 前綴)', '', '', '可', ''],
    ['kafka-rbac-admins', 'UserAdmin', '', '', '', '可'],
    ['kafka-admins', 'SystemAdmin(緊急用)', '可', '可', '可', '可'],
  ], { rowH: 0.62, hdrH: 0.46, sz: 12, col: INK }), rowCols: [HUM, SVC, PLT, MDS, RISK] },
  chip('人員異動只改 AD:加入群組即生效,移出群組即收回(預設最長約 60 秒)', 0.6, 5.4, 12.13, HUM, { sz: 12.5, h: 0.48 }),
  chip('臨時提權:依單據加入 kafka-ops 或 kafka-rbac-admins,做完移出', 0.6, 6.05, 12.13, SVC, { sz: 12.5, h: 0.48 }),
], notes: gr.notes });

// 7 加密:共用憑證(只留左側「一組憑證 → 各元件」)
const tls = pick('TLS 與憑證:共用 1 組,只做加密');
const tlsLeft = tls.items.filter(it => { const x = it.x !== undefined ? it.x : it.x1, y = it.y !== undefined ? it.y : it.y1; return x !== undefined && x < 6.6 && y < 4.4; });
add({ title: '加密:共用一組憑證', sub: '只做傳輸加密,不承載權限', items: [
  ...tlsLeft,
  chip('只做傳輸加密,不承載權限', 6.9, 1.65, 5.83, PLT, { sz: 12.5, h: 0.5 }),
  chip('共用憑證的身分(CN)永遠不綁任何 role', 6.9, 2.3, 5.83, RISK, { sz: 12.5, h: 0.5 }),
  chip('SAN 涵蓋所有元件的主機名稱', 6.9, 2.95, 5.83, SVC, { sz: 12, h: 0.5 }),
  chip('平台元件另用 client 憑證換 token(c3、restproxy、bootstrap)', 6.9, 3.6, 5.83, MDS, { sz: 12, h: 0.5 }),
  solid(0.6, 5.0, 12.13, 0.7, INK, [P('連 AD 的 broker 另匯入 AD 的 LDAPS CA root,一份設定', { sz: 15, b: true, c: 'background1', algn: 'ctr' })]),
], notes: tls.notes });

// 8 服務帳號
add({ title: '服務帳號:SCRAM,同帳號改密碼', sub: '帳密存在 Kafka 內,不放 AD', items: [
  ...node(0.6, 1.5, 3.85, 1.9, { icon: 'FaIdBadge', title: '帳密存在 Kafka 內', sub: '不放 AD', col: SVC, tsz: 15, ssz: 12 }),
  ...node(4.73, 1.5, 3.85, 1.9, { icon: 'FaExclamationTriangle', title: '密碼不會自動到期', sub: '要有輪替流程', col: RISK, tsz: 15, ssz: 12 }),
  ...node(8.86, 1.5, 3.87, 1.9, { icon: 'FaLock', title: 'SCRAM 搭配 TLS', sub: 'KRaft 放在私有網路', col: HUM, tsz: 15, ssz: 12 }),
  text(0.6, 3.7, 12.13, 0.35, [P('輪替:同帳號改密碼', { sz: 14, b: true, c: SVC })]),
  ...['① Kafka 端改密碼', '② client 換新密碼並重啟', '③ 驗證新密碼可用', '④ 驗證舊密碼已失效'].flatMap((t, i) => [chip(t, 0.6 + i * 3.13, 4.15, 2.75, SVC, { sz: 12 }), i < 3 ? arrow(0.6 + i * 3.13 + 2.75, 4.36, 0.6 + (i + 1) * 3.13, 4.36, SVC, { w: 2 }) : null].filter(Boolean)),
  solid(0.6, 5.0, 12.13, 0.7, INK, [P('舊密碼對新連線立即失效;已連線的 client 不受影響,改完立刻換 client', { sz: 14, b: true, c: 'background1', algn: 'ctr' })]),
  chip('不能有失敗窗口的服務:改用新帳號並行(client 要改帳號、role 要重綁)', 0.6, 5.95, 12.13, SVC, { sz: 12.5 }),
], notes: pick('服務帳號:SCRAM,不放 AD').notes });

// 9 legacy app
const rpNotes = pick('REST Proxy:legacy app 的入口').notes;
const flow = [['FaPlug', 'legacy app', '出示 client 憑證', SVC], ['FaExchangeAlt', 'REST Proxy', '憑證 CN → 主體', HUM], ['FaShieldAlt', 'MDS', '代為申請 token', MDS], ['FaServer', 'broker', '驗章,依 token 授權', PLT]];
add({ title: 'legacy app:憑證換 token', sub: '經 REST Proxy,身分一路傳到 broker', items: [
  ...flow.flatMap(([ic, t, sb, col], i) => [...node(0.6 + i * 3.15, 1.7, 2.45, 2.0, { icon: ic, title: t, sub: sb, col, tsz: 15, ssz: 12 }), i < 3 ? arrow(3.05 + i * 3.15, 2.7, 3.75 + i * 3.15, 2.7, 'text1', { w: 2.25 }) : null].filter(Boolean)),
  chip('人走 Basic(AD 帳密)經 REST Proxy,不用憑證', 0.6, 4.2, 12.13, PLT, { sz: 13, h: 0.5 }),
  chip('憑證身分只能綁 User:,不能綁群組', 0.6, 4.85, 12.13, MDS, { sz: 13, h: 0.5 }),
  chip('restproxy 憑證可代人:特權身分要列入保護清單', 0.6, 5.5, 12.13, RISK, { sz: 13, h: 0.5 }),
], notes: rpNotes });

// 10 C3(表格)
add({ title: 'Control Center:兩種身分', sub: '人用本人身分,背景工作用憑證', items: [
  table(0.6, 1.5, [2.5, 4.8, 4.83], [
    ['項目', '使用者操作', 'C3 背景工作'],
    ['怎麼取得身分', 'AD 帳密登入,MDS 簽發本人的 token', 'c3 憑證向 MDS 換 token'],
    ['身分是誰', '使用者本人', 'User:c3'],
    ['需要的權限', '依本人的 AD 群組', 'SystemAdmin'],
    ['怎麼連 Kafka', '帶本人的 token(OAUTHBEARER)', '帶 c3 的 token(OAUTHBEARER)'],
    ['要留意', '登入有時間上限(預設 6 小時),到期重新登入', 'c3 憑證等於管理員,私鑰要保護'],
  ], { rowH: 0.75, hdrH: 0.46, sz: 12.5, col: HUM }),
], notes: pick('Control Center:人用本人身分').notes });

// 11 要保管的祕密(表格)
add({ title: '維運:要保管的六類祕密', sub: '放在哪、怎麼輪替、驗證到哪', items: [
  table(0.6, 1.5, [3.0, 3.3, 3.9, 1.93], [
    ['祕密', '放在哪裡', '輪替方式與要留意的事', '輪替驗證'],
    ['共用 server 憑證與私鑰', '各元件主機', '先更新信任庫,再換憑證,逐元件重啟', '已實測'],
    ['client 憑證', 'c3、restproxy、bootstrap、各 legacy app', 'CN 不變,換憑證不用重綁權限', '已實測'],
    ['SCRAM 服務帳號', 'Kafka 內;密碼放密碼庫', '同帳號改密碼,client 換新密碼', '已實測'],
    ['MDS token 簽章金鑰', '私鑰在 broker 與 controller', '外洩可偽造任何人的 token', '待驗證'],
    ['內部帳號', 'Kafka 內與設定檔', 'kafka-broker、kafka-controller,只給節點之間使用', '待驗證'],
    ['AD 查詢帳號', 'broker 設定檔,權限 600', '只讀人與群組;不用真人帳號', '待驗證'],
  ], { rowH: 0.7, hdrH: 0.46, sz: 12, col: INK }),
], notes: '六類要保管的祕密。最後一欄標示輪替流程是否已在 demo 實測。①共用 server 憑證:依官方 CFK 憑證文件的順序,先更新所有信任庫、再換憑證、每個元件就緒才做下一個;元件順序 controller、broker、REST Proxy、C3(參考升級文件);換檔不重啟時各埠仍出示舊憑證(實測)。②client 憑證:RBAC 綁的是 CN,CN 不變就不用重綁。legacy app 的憑證可省,前提是客戶能為它建專用 AD 帳號改走 Basic。③SCRAM 服務帳號:同帳號改密碼,舊密碼對新連線立即失效,已連線的不受影響(實測);官方 SCRAM 文件沒有輪替流程。④MDS token 簽章金鑰對:私鑰在 MDS 所在的 broker 與 controller,公鑰在 broker、REST Proxy、C3;輪替流程未驗證。⑤內部帳號 kafka-broker、kafka-controller:SCRAM 存在 Kafka,PLAIN 靜態帳號在設定檔;輪替流程未驗證。⑥AD 查詢帳號:只讀 user 與 group,建議 LDAPS;輪替流程未驗證。' });

// 12 風險表
add({ title: '四個要留意的風險', sub: '影響與對策', items: [
  table(0.6, 1.5, [3.5, 4.6, 4.03], [
    ['風險', '影響', '對策'],
    ['c3 憑證等於管理員', '外洩可改任何授權;拿掉權限 C3 會退出', '保護私鑰與檔案權限'],
    ['restproxy 憑證可代人', '可代不在保護清單的使用者', '特權身分逐一列入保護清單'],
    ['私鑰外洩(server、token 簽章)', '可偽裝伺服器、偽造任何人的 token', '權限 600、最小化存放、輪替計畫'],
    ['SCRAM 密碼不到期', '外洩風險累積', '密碼庫加輪替流程與提醒'],
  ], { rowH: 0.7, hdrH: 0.46, sz: 12.5, col: RISK }),
], notes: '逐項依據與驗證狀態見完整版的「風險與對策」與「已驗證 vs 待驗證」兩頁。' });

// 13 待確認表
add({ title: '導入前請客戶確認', sub: '六件需要客戶回覆的事', items: [
  table(0.6, 1.5, [4.4, 4.2, 3.53], [
    ['項目', '為什麼要問', '沒確認的影響'],
    ['AD 唯讀查詢帳號與 LDAPS', '人登入與群組同步都靠它', '人無法登入、群組同步失敗'],
    ['Kafka 憑證與 AD 的 LDAPS 憑證由誰簽發', '決定憑證怎麼簽發、信任庫放什麼', '信任庫不全,連線失敗'],
    ['能否為 legacy app 建立專用 AD 帳號', '可改走 Basic,省掉每個 app 的憑證', '每個 legacy app 都需要一張憑證'],
    ['license 是否涵蓋 RBAC 與 C3', '這些是商用功能', '功能無法啟用'],
    ['AD 是否有多台 DC', 'LDAP 停擺超過 24 小時,授權器會失效', '單台 DC 故障會讓授權整體失效'],
    ['AD 群組是否巢狀、帳號大小寫與命名', '影響群組與帳號的比對', '權限可能對不上'],
  ], { rowH: 0.62, hdrH: 0.46, sz: 12, col: HUM }),
], notes: '完整版的同名頁有八件事(另含 Java 版本與 Prometheus、Alertmanager 部署)。LDAP 停擺 24 小時是官方 ldap.retry.timeout.ms 的預設值。AD 群組巢狀、大小寫的實際行為尚未在真實 AD 驗證。' });

// 14 下一步
add({ title: '下一步', sub: '三個階段', items: [
  ...[['FaComments', '客戶確認', '回覆前一頁的六件事', HUM], ['FaCalendarCheck', '調整方案', '依客戶回覆更新設計', SVC], ['FaServer', 'RHEL 實機驗證', '補上尚未驗證的項目', PLT]].flatMap(([ic, t, s, col], i) => [...node(0.6 + i * 4.13, 1.7, 3.85, 2.3, { icon: ic, title: t, sub: s, col, tsz: 18, ssz: 13 }), i < 2 ? arrow(4.45 + i * 4.13, 2.85, 4.73 + i * 4.13, 2.85, 'text1', { w: 2.5 }) : null].filter(Boolean)),
  text(0.6, 4.4, 12.13, 0.35, [P('尚未驗證,實機階段要補的項目', { sz: 14, b: true, c: SVC })]),
  ...['真實 AD 的行為(巢狀群組、大小寫)', '多台 controller 搭配 TLS 與 RBAC', 'RHEL 實機(systemd、防火牆、路徑)', 'MDS 金鑰、內部帳號、AD 查詢帳號的輪替'].map((t, i) => chip(t, 0.6 + (i % 2) * 6.18, 4.85 + Math.floor(i / 2) * 0.62, 5.95, SVC, { sz: 12.5, h: 0.48 })),
], notes: '下一步:先請客戶回覆前一頁的六件事,依回覆調整方案,再到 RHEL 實機驗證。目前的驗證是在 docker demo(以 OpenLDAP 模擬 AD)完成;尚未驗證的主要項目:真實 AD 的巢狀群組與大小寫行為、多台 controller 搭配 TLS 與 RBAC 的滾動重啟、RHEL 實機的 systemd 與防火牆、MDS 金鑰對與內部帳號及 AD 查詢帳號的輪替流程。' });

module.exports = { SLIDES: SHORT, THEME, HEX, OUT: path.join(__dirname, 'Confluent-Security-Solution-IISI-short.pptx') };
