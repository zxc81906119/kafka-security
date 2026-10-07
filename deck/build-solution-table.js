// 簡化版(全表格):每頁一張表,標題寫結論。
// 建置:SPEC=./build-solution-table.js OUT=Confluent-Security-Solution-IISI-table.pptx node build-solution-iisi.js
const path = require('path');
const { SLIDES: ALL, THEME, HEX, H } = require('./build-solution-deck.js');
const { table, HUM, SVC, PLT, MDS, RISK } = H;
const note = (title) => { const s = ALL.find(x => x.title === title); return s ? s.notes : ''; };
const SL = [];
const add = (s) => SL.push(s);
const T = (colW, rows, o) => table(0.6, 1.5, colW, rows, Object.assign({ hdrH: 0.46, sz: 12 }, o));

add({ layout: 'TITLE', title: 'Confluent 安全解決方案', coverSub: '結論版(表格):每個元件怎麼做', items: [], notes: '全表格版,每頁一張表。出處、實測依據與限制在各頁備忘稿,完整版有逐項前提與驗證狀態。' });

add({ title: '人走 AD,服務走 SCRAM 或憑證', sub: '授權集中在 MDS 的 RBAC', items: [
  T([2.0, 2.7, 3.7, 2.6, 1.13], [
    ['類型', '誰', '怎麼認證', '授權綁什麼', '身分在'],
    ['人', '手動操作、C3、Postman', 'AD 帳密', 'Group:AD 群組', 'AD'],
    ['服務', '應用、排程', 'SCRAM 帳密', 'User:服務名稱', 'Kafka 內'],
    ['內部元件', 'broker、controller 互連', 'SCRAM(連 broker:broker、controller);PLAIN 靜態帳號(連 controller:broker、controller)', 'super.users', 'Kafka 內、設定檔'],
    ['legacy app', '只能用 HTTP 的應用', 'client 憑證,經 REST Proxy 換 token', 'User:憑證 CN', '憑證'],
    ['平台元件', 'C3、REST Proxy', 'client 憑證向 MDS 換 token', 'User:憑證 CN', '憑證'],
  ], { rowH: 0.78, col: HUM }),
], notes: note('設計原則:兩個身分平面') + ' 內部元件:連 broker 的 9092(broker 之間、controller 連 broker)用 SCRAM(帳號 kafka-broker、kafka-controller,format 時預建);連 controller 的 9093(broker 連 controller、controller 之間)都用 SASL/PLAIN 靜態帳號 kafka-broker、kafka-controller(SCRAM 在 controller listener 官方不支援);授權用 super.users;PLAIN 帳密寫在 JAAS 設定檔。各監聽埠細節見元件總表。' });

add({ title: '要管理的憑證與帳號', sub: '七類,數量越少越好', items: [
  T([3.1, 1.4, 4.0, 3.63], [
    ['項目', '數量', '用在哪', '存放與輪替'],
    ['server 憑證(共用)', '1 組', '全部元件的傳輸加密,CN 不綁 role', '每個節點;換 CA 時信任庫先信任新舊'],
    ['平台 client 憑證', '3', 'c3、restproxy、bootstrap 向 MDS 證明身分', '對應主機;CN 不變就不用重綁'],
    ['legacy app client 憑證', '每個 app 1 張', '經 REST Proxy 換 token', 'app 主機;可改專用 AD 帳號走 Basic'],
    ['MDS token 簽章金鑰對', '1 組', 'MDS 簽 token,元件驗章', '私鑰在 MDS 與 controller;輪替流程待定'],
    ['SCRAM 服務帳號', '每個服務 1 個', '服務連 Kafka', 'Kafka 內;密碼放密碼庫'],
    ['內部與 break-glass 帳號', '3', 'broker、controller 互連與緊急管理', 'JAAS 設定檔與 KRaft;輪替流程待定'],
    ['AD 唯讀帳號與 LDAPS 信任庫', '各 1', '搜尋使用者與群組', 'broker 設定;AD 憑證更換時更新'],
  ], { rowH: 0.6, col: SVC, sz: 11.5 }),
], notes: note('要管理的憑證與帳號') + ' 共用 server 憑證只做加密,其身分(CN)永遠不綁任何 role;連 AD 的 broker 另匯入 AD 的 LDAPS CA root,一份設定。' });

add({ title: '每條連線:誰驗證,token 給誰', sub: '八條連線路徑,最後都由 broker 或 MDS 判斷授權', items: [
  T([2.45, 1.9, 2.9, 2.75, 2.13], [
    ['路徑', '出示什麼', '誰驗證身分', 'token 給誰', '誰判斷授權'],
    ['人 → broker(9094)', 'AD 帳密', 'broker,轉 AD 驗密碼', '無', 'broker(群組快取與 RBAC)'],
    ['服務 → broker(9094)', 'SCRAM 帳密', 'broker(Kafka 內的帳密)', '無', 'broker(RBAC,User:)'],
    ['人 → C3', 'AD 帳密', 'C3 轉 MDS,MDS 向 AD 驗', 'MDS 發給瀏覽器;C3 帶它連 broker', 'broker;改 role binding 由 MDS'],
    ['人 → REST Proxy', 'AD 帳密(Basic)', 'REST Proxy 轉 MDS,MDS 向 AD 驗', 'MDS 發給 REST Proxy,再帶去 broker', 'broker'],
    ['legacy app → REST Proxy', 'client 憑證', 'REST Proxy(CN 對映成主體)', 'REST Proxy 向 MDS 申請,帶去 broker', 'broker'],
    ['平台元件 → MDS', 'client 憑證', 'MDS(CN 對映成主體)', 'MDS 發給元件,元件帶去 broker', 'broker'],
    ['broker、controller 互連', 'SCRAM(9092)或 PLAIN(9093)', '被連的那一方', '無', 'super.users'],
    ['bootstrap → MDS', 'client 憑證', 'MDS', '無(憑證直接呼叫)', 'MDS(super user)'],
  ], { rowH: 0.6, col: HUM, sz: 10.5 }),
], notes: '連線路徑表:欄位依序是「出示什麼、誰驗證身分、token 給誰、誰判斷授權」。①人用 CLI 或應用連 CLIENT 9094:broker 把帳密轉 LDAP(AD)驗密碼,不發 token,授權時 broker 用主體名稱查 MDS writer 同步的群組快取與 RBAC。②服務用 SCRAM:帳密存在 Kafka(KRaft),由 broker 驗證,授權綁 User:。③人登入 C3:瀏覽器送 AD 帳密,C3 轉給 MDS,MDS 向 AD 驗,回 JWT;之後 C3 用本人 token 以 OAUTHBEARER 連 broker;在 C3 改 role binding 時,請求轉給 MDS,由 MDS 驗證 token 並判斷本人是否有 AlterAccess(UserAdmin 或 SystemAdmin)。④人用 Basic 連 REST Proxy:REST Proxy 把帳密轉給 MDS 換 token,再以 OAUTHBEARER 連 broker。⑤legacy app 出示 client 憑證:REST Proxy 依對映規則得到主體,再用自己的憑證向 MDS 呼叫 /impersonate 申請 token(sub 為該 app),帶去 broker。⑥平台元件(c3、restproxy)用 client 憑證向 MDS 換 token,再以 OAUTHBEARER 連 broker。⑦broker 與 controller:連 broker 的 9092 用 SCRAM,連 controller 的 9093 用 PLAIN 靜態帳號,授權用 super.users。⑧bootstrap 對 MDS 直接出示憑證呼叫 REST API,不換 token(官方文件沒有明確建議直接 mTLS 或先換 token,本方案依客戶條件選擇直接 mTLS);它對 Kafka 另用 SCRAM 帳號 bootstrap。' });

add({ title: '權限依 AD 群組分五層', sub: '人員異動只改 AD,Kafka 端零變更', items: [
  T([2.7, 4.6, 1.2, 1.2, 1.2, 1.23], [
    ['AD 群組', 'role', '讀資料', '寫資料', '管 topic', '改授權'],
    ['kafka-developers', 'DeveloperRead / Write(orders. 前綴)', '✔', '✔', '—', '—'],
    ['kafka-readonly', 'DeveloperRead', '✔', '—', '—', '—'],
    ['kafka-ops', 'Operator + DeveloperManage(infra. 前綴)', '—', '—', '✔', '—'],
    ['kafka-rbac-admins', 'UserAdmin', '—', '—', '—', '✔'],
    ['kafka-admins', 'SystemAdmin(break-glass)', '✔', '✔', '✔', '✔'],
  ], { rowH: 0.75, col: MDS, sz: 12.5 }),
], notes: note('AD 群組 → role:依職責分層授權') });

add({ title: '服務帳號用 SCRAM,同帳號改密碼', sub: '帳密存在 Kafka 內,不放 AD', items: [
  T([1.6, 5.4, 5.13], [
    ['階段', '做法', '備註'],
    ['建立', 'kafka-configs 在 Kafka 內建立 SCRAM 帳號', '帳密存在 Kafka,不放 AD'],
    ['保管', '密碼放密碼庫', '密碼不會自動到期,要有輪替提醒'],
    ['授權', 'RBAC 綁 User:服務名稱,依前綴給最小權限', '只給需要的 topic 前綴'],
    ['使用', 'client 設定檔,權限 600', 'SCRAM 搭配 TLS 使用'],
    ['輪替', '同帳號改密碼:Kafka 端改 → client 換新密碼並重啟 → 驗證新密碼可用、舊密碼已失效', '舊密碼對新連線立即失效,已連線的不受影響;不能有失敗窗口的服務改用新帳號並行'],
  ], { rowH: 0.8, col: SVC, sz: 11.5 }),
], notes: note('服務帳號:SCRAM,不放 AD') });

add({ title: 'legacy app 用憑證換 token', sub: '經 REST Proxy,身分一路傳到 broker', items: [
  T([1.0, 2.7, 5.6, 2.83], [
    ['步驟', '誰', '做什麼', '身分變成'],
    ['①', 'legacy app', '向 REST Proxy 出示 client 憑證', '憑證 CN'],
    ['②', 'REST Proxy', '依對映規則把 CN 對映成主體', 'User:CN'],
    ['③', 'REST Proxy → MDS', '用自己的憑證認證,呼叫 /impersonate 代為申請 token', 'token 的 sub = 該 app'],
    ['④', 'REST Proxy → broker', '帶 token 以 OAUTHBEARER 連線', 'broker 驗章,依 sub 授權'],
    ['人', 'REST Proxy → MDS', '把 Basic(AD 帳密)轉給 MDS 換 token,不用憑證', '本人'],
  ], { rowH: 0.75, col: SVC, sz: 12 }),
], notes: note('REST Proxy:legacy app 的入口') });

add({ title: 'C3:人用本人身分,背景用憑證', sub: '兩種操作,兩種身分', items: [
  T([3.0, 1.8, 4.0, 3.33], [
    ['操作', '身分', '怎麼取得', '授權依據'],
    ['使用者登入 C3', '本人', 'AD 帳密經 C3 轉給 MDS,取得 token', '所屬群組的 role'],
    ['在 C3 看與管 Kafka', '本人', 'C3 帶本人的 token 連 broker', '本人的 RBAC'],
    ['在 C3 改 role binding', '本人', 'C3 轉給 MDS,由 MDS 驗證 token', '本人要有 UserAdmin 或 SystemAdmin'],
    ['C3 背景工作', 'User:c3', 'c3 憑證向 MDS 換 token', 'SystemAdmin'],
  ], { rowH: 0.8, col: HUM, sz: 12 }),
], notes: note('Control Center:人用本人身分') });

add({ title: '四個要留意的風險', sub: '影響與對策', items: [
  T([3.5, 4.6, 4.03], [
    ['風險', '影響', '對策'],
    ['c3 憑證等於管理員', '外洩可改任何授權;拿掉權限 C3 會退出', '保護私鑰與檔案權限'],
    ['restproxy 憑證可代人', '可代不在保護清單的使用者', '特權身分逐一列入保護清單'],
    ['私鑰外洩(server、token 簽章)', '可偽裝伺服器、偽造任何人的 token', '權限 600、最小化存放、輪替計畫'],
    ['SCRAM 密碼不到期', '外洩風險累積', '密碼庫加輪替流程與提醒'],
  ], { rowH: 0.75, col: RISK, sz: 12.5 }),
], notes: '逐項依據與驗證狀態見完整版第 27 頁(風險與對策)與第 29 頁(已驗證 vs 待驗證)。' });

add({ title: '導入前請客戶確認', sub: '六件需要客戶回覆的事', items: [
  T([4.4, 4.2, 3.53], [
    ['項目', '為什麼要問', '沒確認的影響'],
    ['AD 唯讀查詢帳號與 LDAPS', '人登入與群組同步都靠它', '人無法登入、群組同步失敗'],
    ['Kafka 憑證與 AD 的 LDAPS 憑證由誰簽發', '決定憑證怎麼簽發、信任庫放什麼', '信任庫不全,連線失敗'],
    ['能否為 legacy app 建立專用 AD 帳號', '可改走 Basic,省掉每個 app 的憑證', '每個 legacy app 都需要一張憑證'],
    ['license 是否涵蓋 RBAC、audit、C3', '這些是商用功能', '功能無法啟用'],
    ['AD 是否有多台 DC', 'LDAP 停擺超過 24 小時,授權器會失效', '單台 DC 故障會讓授權整體失效'],
    ['AD 群組是否巢狀、帳號大小寫與命名', '影響群組與帳號的比對', '權限可能對不上'],
  ], { rowH: 0.62, col: HUM, sz: 12 }),
], notes: '完整版第 30 頁有八件事(另含 Java 版本與 Prometheus、Alertmanager 部署)。AD 群組巢狀、大小寫的實際行為尚未在真實 AD 驗證。' });

module.exports = { SLIDES: SL, THEME, HEX, OUT: path.join(__dirname, 'Confluent-Security-Solution-IISI-table.pptx') };
