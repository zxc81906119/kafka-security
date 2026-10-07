// 以使用者的「Kafka 安全.pptx」為底(保留原 9 頁與原文),插入補充頁並補滿空白的第 9 頁。
// 同一份版面規格 → (1) 輸出 PPTX XML (2) 輸出 HTML 供 Playwright 截圖檢查溢出(非 PowerPoint 真實渲染)。
// 用法: node kafka-security-supplement.js [原檔路徑] [輸出路徑]
const fs = require('fs');
const path = require('path');
const JSZip = require('jszip');

const SRC = process.argv[2] || 'C:/Users/user/Desktop/Kafka 安全.pptx';
const OUT = process.argv[3] || path.join(__dirname, 'Kafka-安全-補充版.pptx');
const EMU = 914400;
const e = v => Math.round(v * EMU);
const X = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

// 配色:取自原檔 Office 佈景主題(accent1/2/3、dk2)與其淡色
const C = { ink: '0E2841', blue: '156082', pBlue: 'DCEBF2', orange: 'E97132', pOrange: 'FBE5D6', green: '196B24', pGreen: 'DCEBDD',
  red: 'B3261E', pRed: 'F8DADA', grey: '595959', pGrey: 'F2F2F2', white: 'FFFFFF', line: 'BFBFBF', dgreen: '14551C', dorange: '9A4A1E' };

// ───────── 版面規格建構 ─────────
const run = (t, o = {}) => ({ t, sz: o.sz || 14, b: !!o.b, c: o.c || C.ink });
const para = (runs, o = {}) => ({ runs: Array.isArray(runs) ? runs : [runs], algn: o.algn || 'l', after: o.after || 0 });
const P = (t, o = {}) => para(run(t, o), o);
function box(x, y, w, h, o = {}) { return { k: 'box', x, y, w, h, fill: o.fill, line: o.line, lw: o.lw || 1.5, round: o.round === undefined ? 0.1 : o.round, paras: o.paras || [], anchor: o.anchor || 'ctr', ins: o.ins === undefined ? 0.08 : o.ins }; }
const text = (x, y, w, h, paras, o = {}) => ({ k: 'box', x, y, w, h, paras, anchor: o.anchor || 't', ins: o.ins === undefined ? 0 : o.ins, round: 0 });
const chip = (t, x, y, w, o = {}) => box(x, y, w, o.h || 0.42, { fill: o.fill || C.pBlue, line: o.line || C.blue, lw: o.lw || 1.25, round: 0.5, paras: [P(t, { sz: o.sz || 12, b: o.b !== false, c: o.c || C.blue, algn: o.algn || 'ctr' })], ins: 0.1 });
const arrow = (x1, y1, x2, y2, o = {}) => ({ k: 'arrow', x1, y1, x2, y2, c: o.c || C.grey, w: o.w || 2.25, dash: !!o.dash });
const table = (x, y, colW, rows, o = {}) => ({ k: 'table', x, y, colW, rows, rowH: o.rowH || 0.7, hdrH: o.hdrH || 0.45, sz: o.sz || 12 });
const TAG = box(11.35, 0.14, 1.55, 0.34, { fill: C.orange, line: C.orange, round: 0.5, paras: [P('補充內容', { sz: 11, b: true, c: C.white, algn: 'ctr' })], ins: 0.04 });

// 小工具:帶標題的卡片(上方色帶 + 內容)
function card(x, y, w, h, title, col, pcol, o = {}) {
  const items = [box(x, y, w, h, { fill: C.white, line: col, lw: 1.75, round: 0.04 }),
    box(x, y, w, o.hh || 0.62, { fill: col, line: col, round: 0.04, paras: [P(title, { sz: o.tsz || 17, b: true, c: C.white, algn: 'ctr' })] })];
  return items;
}

// ───────── 各補充頁 ─────────
const SL = {};

SL.compare = { title: '各組件的三個機制對照', items: [
  table(0.92, 1.8, [1.75, 1.75, 5.35, 2.65], [
    ['組件', '傳輸加密', '身分認證(本方案採用)', '授權'],
    ['broker', 'TLS(共用 server 憑證)', '人:SASL/PLAIN → LDAP(AD)  ・  服務:SASL/SCRAM  ・  token:OAUTHBEARER', 'RBAC(MDS)'],
    ['controller', 'TLS', 'SASL/PLAIN(內部靜態帳號);controller 間不支援 SCRAM(官方文件不一致);多 controller 間 PLAIN 未實測', 'ConfluentServerAuthorizer + super.users'],
    ['MDS(內嵌於 broker)', 'HTTPS', 'Basic → LDAP 驗證  ・  Bearer token  ・  client 憑證(mTLS)', '發 token、管理 RBAC'],
    ['REST Proxy', 'HTTPS', '人:Basic(經 MDS)  ・  機器:client 憑證(AuthenticationHandler)', '以使用者 token 連 broker'],
    ['Control Center', 'HTTPS', '人:Basic → MDS 換 token,之後 Bearer  ・  C3 自己:client 憑證', '依登入者的 role'],
  ], { rowH: 0.78, hdrH: 0.46, sz: 12 }),
  text(0.92, 6.55, 11.5, 0.5, [P('官方:RBAC 下 C3 連 Kafka 只支援 OAUTHBEARER;SCRAM overview 頁說 controller 間不支援 SCRAM(KRaft security 頁寫法不同,官方文件不一致)。其餘為本專案 demo 的設定。', { sz: 11, c: C.grey })]),
] };

SL.env = { title: '客戶環境:一張圖', items: [
  box(0.92, 1.85, 3.6, 3.3, { fill: C.pBlue, line: C.blue, lw: 1.5 }),
  text(0.92, 2.0, 3.6, 0.5, [P('AD 目錄', { sz: 22, b: true, algn: 'ctr' })]),
  chip('user', 1.3, 2.75, 1.25, { fill: C.white }), chip('group', 2.9, 2.75, 1.25, { fill: C.white }),
  chip('✗ 沒有服務帳號', 1.3, 3.55, 2.85, { fill: C.pRed, line: C.red, c: C.red }),
  text(0.92, 4.3, 3.6, 0.6, [P('只放實際的人與使用者群組', { sz: 13, c: C.grey, algn: 'ctr' })]),
  box(4.87, 1.85, 3.6, 3.3, { fill: C.pOrange, line: C.orange, lw: 1.5 }),
  text(4.87, 2.0, 3.6, 0.5, [P('1 組 PK + 憑證', { sz: 22, b: true, algn: 'ctr' })]),
  text(4.87, 2.7, 3.6, 0.6, [P('Kafka 生態系各組件共用', { sz: 14, c: C.dorange, algn: 'ctr', b: true })]),
  chip('SAN 涵蓋所有組件的網域 / IP', 5.2, 3.5, 2.95, { fill: C.white, line: C.orange, c: C.dorange, sz: 11 }),
  text(4.87, 4.3, 3.6, 0.6, [P('用來啟動 SSL 加密層(server 端)', { sz: 13, c: C.grey, algn: 'ctr' })]),
  box(8.82, 1.85, 3.6, 3.3, { fill: C.pGreen, line: C.green, lw: 1.5 }),
  text(8.82, 2.0, 3.6, 0.5, [P('Kafka 生態系', { sz: 22, b: true, algn: 'ctr' })]),
  chip('broker / controller', 9.15, 2.75, 2.95, { fill: C.white, line: C.green, c: C.dgreen }), chip('MDS(內嵌於 broker)', 9.15, 3.3, 2.95, { fill: C.white, line: C.green, c: C.dgreen }),
  chip('REST Proxy', 9.15, 3.85, 1.4, { fill: C.white, line: C.green, c: C.dgreen }), chip('C3', 10.7, 3.85, 1.4, { fill: C.white, line: C.green, c: C.dgreen }),
  box(0.92, 5.4, 11.5, 0.56, { fill: C.pGrey, line: C.line, round: 0.3, paras: [P('共用憑證只負責「加密」;不拿來當 client 身分(共用 = 同一個 principal)', { sz: 15, b: true, algn: 'ctr' })] }),
  box(0.92, 6.15, 11.5, 0.56, { fill: C.ink, line: C.ink, round: 0.3, paras: [P('人 → AD(帳密 + 群組)  ・  服務 → 另外想辦法:連 Kafka 用 SCRAM,連 MDS / REST Proxy 用各自的 client 憑證', { sz: 15, b: true, c: C.white, algn: 'ctr' })] }),
] };

SL.split = { title: '怎麼分「人」與「服務」', items: [
  box(0.92, 1.85, 5.6, 3.6, { fill: C.white, line: C.blue, lw: 2 }), box(0.92, 1.85, 5.6, 0.7, { fill: C.blue, line: C.blue, paras: [P('人(USER)', { sz: 22, b: true, c: C.white, algn: 'ctr' })] }),
  text(1.2, 2.7, 5.1, 0.4, [P('有人在場:由人直接或間接操作', { sz: 15, b: true, c: C.blue })]),
  text(1.2, 3.15, 5.1, 2.2, [P('•  登入 C3', { sz: 15, after: 6 }), P('•  手動跑腳本 / CLI', { sz: 15, after: 6 }), P('•  Postman 手動測試、GUI 工具', { sz: 15, after: 6 }), P('→ 用「本人」的 AD 身分', { sz: 15, b: true, c: C.blue })]),
  box(6.82, 1.85, 5.6, 3.6, { fill: C.white, line: C.orange, lw: 2 }), box(6.82, 1.85, 5.6, 0.7, { fill: C.orange, line: C.orange, paras: [P('服務', { sz: 22, b: true, c: C.white, algn: 'ctr' })] }),
  text(7.1, 2.7, 5.1, 0.4, [P('無人值守:其他都是服務', { sz: 15, b: true, c: C.dorange })]),
  text(7.1, 3.15, 5.1, 2.2, [P('•  長駐應用、legacy app', { sz: 15, after: 6 }), P('•  排程、CI、newman', { sz: 15, after: 6 }), P('•  C3 / REST Proxy 的背景程序', { sz: 15, after: 6 }), P('→ 連 Kafka:SCRAM;連 MDS / REST Proxy:client 憑證', { sz: 14, b: true, c: C.dorange })]),
  chip('腳本由手動轉成排程 → 必須改用服務身分,不可借用人的帳號', 0.92, 5.7, 11.5, { fill: C.pRed, line: C.red, c: C.red, sz: 14 }),
  chip('禁止維運共用同一個 AD 帳號;人跑腳本不要寫死密碼', 0.92, 6.25, 11.5, { fill: C.pGrey, line: C.line, c: C.ink, sz: 14 }),
] };

const step = (n, x, y, w, h, t1, t2, col, pcol) => [
  box(x, y, w, h, { fill: pcol, line: col, lw: 1.5, round: 0.08 }),
  box(x + 0.12, y + 0.12, 0.42, 0.42, { fill: col, line: col, round: 0.5, paras: [P(String(n), { sz: 14, b: true, c: C.white, algn: 'ctr' })], ins: 0 }),
  text(x + 0.1, y + 0.65, w - 0.2, 0.55, [P(t1, { sz: 14, b: true, algn: 'ctr' })]),
  text(x + 0.1, y + 1.2, w - 0.2, h - 1.25, [P(t2, { sz: 11, c: C.grey, algn: 'ctr' })]),
];
function qa(x, y, w, h, q, a, col, pcol, warn) {
  return [box(x, y, w, h, { fill: C.white, line: col, lw: 1.5, round: 0.05 }), box(x, y, w, 0.62, { fill: pcol, line: col, round: 0.05, paras: [P(q, { sz: 13, b: true, c: col, algn: 'ctr' })] }),
    text(x + 0.15, y + 0.75, w - 0.3, h - 0.85, [P(a, { sz: 12 })].concat(warn ? [P(warn, { sz: 12, b: true, c: C.red })] : []))];
}
SL.cert = { title: '憑證怎麼來、怎麼用', items: [
  ...step(1, 0.92, 1.8, 1.95, 1.95, '產 PK + CSR', 'DN 由客戶決定(不使用)', C.blue, C.pBlue),
  ...step(2, 3.17, 1.8, 1.95, 1.95, 'SAN', '含各組件對外連線的所有網域 / IP', C.blue, C.pBlue),
  ...step(3, 5.42, 1.8, 1.95, 1.95, '客戶內部 CA 簽發', '由 CSR 衍生出 CERT', C.blue, C.pBlue),
  ...step(4, 7.67, 1.8, 1.95, 1.95, 'keystore(P12)', 'PK + CERT + 中繼 CA 鏈', C.blue, C.pBlue),
  ...step(5, 9.92, 1.8, 2.5, 1.95, 'truststore', '匯入 CA root;AD 的 LDAPS CA 也要匯入', C.blue, C.pBlue),
  arrow(2.87, 2.78, 3.17, 2.78, { c: C.blue }), arrow(5.12, 2.78, 5.42, 2.78, { c: C.blue }), arrow(7.37, 2.78, 7.67, 2.78, { c: C.blue }), arrow(9.62, 2.78, 9.92, 2.78, { c: C.blue }),
  ...qa(0.92, 4.0, 3.7, 2.45, 'CA 要簽 server 與 client 憑證?', 'server:1 張共用。client:平台元件 c3、restproxy、bootstrap,加上每個經 REST Proxy 的 legacy app 各 1 張。', C.blue, C.pBlue),
  ...qa(4.82, 4.0, 3.7, 2.45, 'broker / controller 之間用 mTLS?', '本方案:SASL over TLS(controller 間 PLAIN、broker 間 SCRAM)。共用憑證做 mTLS 只會得到同一個 principal;客戶日後有專用內部憑證才改 mTLS。', C.orange, C.pOrange, '⚠ 與原稿不同,待確認;多 controller 間 PLAIN 未實測'),
  ...qa(8.72, 4.0, 3.7, 2.45, '串接的 client 來自不同 CA root?', '把該 client 的 CA root 匯入 truststore 即可。', C.green, C.pGreen),
] };

SL.kraft = { title: 'KRaft 本體:controller 與 broker', items: [
  box(0.92, 2.1, 2.9, 1.85, { fill: C.pGreen, line: C.green, lw: 2 }),
  text(0.92, 2.2, 2.9, 0.5, [P('controller', { sz: 20, b: true, algn: 'ctr' })]), text(0.92, 2.75, 2.9, 1.1, [P('正式環境 3 個(demo 1 個)', { sz: 12, c: C.grey, algn: 'ctr', after: 4 }), P('CONTROLLER 埠 · SASL_SSL · PLAIN', { sz: 11, b: true, c: C.dgreen, algn: 'ctr' })]),
  box(4.7, 1.95, 4.0, 1.75, { fill: C.pBlue, line: C.blue, lw: 2 }), box(4.7, 3.95, 4.0, 1.75, { fill: C.pBlue, line: C.blue, lw: 2 }),
  ...[['broker 1', 1.95], ['broker 2', 3.95]].flatMap(([n, y]) => [text(4.7, y + 0.08, 4.0, 0.4, [P(n, { sz: 18, b: true, algn: 'ctr' })]),
    text(4.85, y + 0.55, 3.7, 1.15, [P('INTERNAL 9092 · SCRAM', { sz: 11, after: 3 }), P('CLIENT 9094 · PLAIN+LDAP / SCRAM / OAUTHBEARER', { sz: 11, after: 3 }), P('MDS 8091 · HTTPS', { sz: 11 })])]),
  box(9.5, 2.0, 2.92, 3.7, { fill: C.white, line: C.line, lw: 1.5 }),
  text(9.5, 2.1, 2.92, 0.45, [P('連線的 client', { sz: 16, b: true, algn: 'ctr' })]),
  chip('人:PLAIN + AD', 9.7, 2.75, 2.52, { fill: C.pBlue }), chip('服務:SCRAM', 9.7, 3.4, 2.52, { fill: C.pOrange, line: C.orange, c: C.dorange }), chip('平台:OAUTHBEARER', 9.7, 4.05, 2.52, { fill: C.pGreen, line: C.green, c: C.dgreen }),
  arrow(9.5, 4.9, 8.7, 4.9, { c: C.blue }), arrow(9.5, 2.85, 8.7, 2.85, { c: C.blue }),
  arrow(4.7, 2.85, 3.82, 2.85, { c: C.green }), arrow(4.7, 4.8, 3.45, 3.95, { c: C.green }), text(3.85, 2.45, 0.85, 0.3, [P('PLAIN', { sz: 10, b: true, c: C.dgreen, algn: 'ctr' })]),
  arrow(6.7, 3.7, 6.7, 3.95, { c: C.orange, w: 2.5 }), text(6.8, 3.7, 1.2, 0.25, [P('SCRAM', { sz: 10, b: true, c: C.dorange })]),
  chip('防火牆:9092 / 9093 只開給 broker / controller 節點', 0.92, 5.95, 7.8, { fill: C.pRed, line: C.red, c: C.red, sz: 13 }), chip('埠號為 demo 設定', 8.95, 5.95, 3.47, { fill: C.pGrey, line: C.line, c: C.grey, sz: 12 }),
] };

function authCard(x, tag, title, col, pcol, rows) {
  const it = [box(x, 1.85, 3.7, 4.5, { fill: C.white, line: col, lw: 2, round: 0.04 }), box(x, 1.85, 3.7, 0.9, { fill: col, line: col, round: 0.04 }),
    text(x, 1.9, 3.7, 0.5, [P(title, { sz: 20, b: true, c: C.white, algn: 'ctr' })]), text(x, 2.4, 3.7, 0.3, [P(tag, { sz: 13, c: C.white, algn: 'ctr' })])];
  rows.forEach(([k, v], i) => { const y = 2.95 + i * 1.12; it.push(box(x + 0.15, y, 0.85, 0.34, { fill: pcol, line: col, lw: 1, round: 0.5, paras: [P(k, { sz: 11, b: true, c: col, algn: 'ctr' })], ins: 0.02 }), text(x + 0.15, y + 0.4, 3.4, 0.7, [P(v, { sz: 12 })])); });
  return it;
}
SL.auth = { title: '身分認證:三種機制怎麼選', items: [
  ...authCard(0.92, '給「人」用', 'SASL/PLAIN', C.blue, C.pBlue, [['帳密', 'broker 轉給 AD(LDAP)驗證'], ['群組', '可取得 AD 群組,做後續授權'], ['注意', '一定要 TLS;AD 密碼到期 / 鎖定會影響腳本']]),
  ...authCard(4.82, '給「服務」用', 'SASL/SCRAM', C.green, C.pGreen, [['帳密', '存在 Kafka(KRaft)內,不在 AD'], ['授權', '綁 User:svc-xxx,最小權限'], ['注意', '密碼不會自動到期 → 要有輪替流程']]),
  ...authCard(8.72, 'Kafka 資料埠:不建議', 'mTLS', C.red, C.pRed, [['身分', '每個身分一張憑證'], ['共用', '共用憑證 = 同一個 principal(實測)'], ['注意', '憑證身分不支援群組;MDS / REST Proxy 仍用憑證身分(只能綁 User:)']]),
] };

const flowBox = (x, y, w, h, t1, t2, col, pcol) => [box(x, y, w, h, { fill: pcol, line: col, lw: 1.75, round: 0.08 }), text(x + 0.08, y + 0.12, w - 0.16, 0.5, [P(t1, { sz: 15, b: true, algn: 'ctr', c: col })]), text(x + 0.1, y + 0.68, w - 0.2, h - 0.75, [P(t2, { sz: 11, c: C.grey, algn: 'ctr' })])];
SL.rbac = { title: 'RBAC 怎麼運作', items: [
  ...flowBox(0.92, 1.9, 2.4, 1.7, '管理者', '在 C3 或 MDS API 指派 role binding', C.ink, C.pGrey),
  ...flowBox(3.77, 1.9, 2.8, 1.7, 'MDS', '內嵌於 broker 的 HTTP 服務:換 token、管理 RBAC', C.blue, C.pBlue),
  ...flowBox(7.02, 1.9, 2.6, 1.7, 'RBAC topic', '異動時把最新的 RBAC 資訊寫入這個 topic', C.orange, C.pOrange),
  ...flowBox(10.07, 1.9, 2.35, 1.7, '每台 broker', '讀取並 cache 在本地,在本地做授權', C.green, C.pGreen),
  arrow(3.32, 2.75, 3.77, 2.75, { c: C.grey }), arrow(6.57, 2.75, 7.02, 2.75, { c: C.grey }), arrow(9.62, 2.75, 10.07, 2.75, { c: C.grey }),
  ...flowBox(3.77, 4.15, 2.8, 1.55, 'AD(LDAP)', '群組同步由 MDS writer broker 負責;預設每 60 秒重讀', C.red, C.pRed),
  arrow(5.17, 3.6, 5.17, 4.15, { c: C.red, w: 2.5 }), text(5.25, 3.68, 1.5, 0.3, [P('查詢 / bind', { sz: 10, b: true, c: C.red })]),
  box(7.02, 4.15, 5.4, 1.55, { fill: C.white, line: C.line, lw: 1.5, round: 0.08 }),
  text(7.2, 4.25, 5.05, 1.4, [P('client 來請求時', { sz: 14, b: true, after: 4 }), P('broker 依本地的 role binding + 使用者所屬群組判斷;群組異動在 AD 做,Kafka 端不用動', { sz: 12, c: C.grey })]),
  chip('ACL:principal → 資源 + 操作   ・   RBAC:principal → role + 範圍', 0.92, 6.1, 11.5, { fill: C.pGrey, line: C.line, c: C.ink, sz: 14 }),
] };

SL.roles = { title: '預設 role 的邊界', items: [
  table(0.92, 1.8, [2.3, 4.6, 4.6], [
    ['role', '可以', '不可以'],
    ['DeveloperRead', '讀 topic / consumer group', '寫、建 topic'],
    ['DeveloperWrite', '寫資料(含叢集層級 IdempotentWrite)', '讀資料'],
    ['DeveloperManage', '建 / 刪 topic', '改 topic 設定、讀寫資料'],
    ['Operator', '看 topic 清單、監控與告警', '建 topic、讀資料'],
    ['ClusterAdmin(叢集範圍)', '建 / 刪 / 改 topic 與設定', '讀寫資料'],
    ['UserAdmin', '管理 role binding', '建 topic、讀資料'],
    ['ResourceOwner / SystemAdmin', '資源擁有者(含讀寫)/ 全權', '—'],
  ], { rowH: 0.56, hdrH: 0.45, sz: 12 }),
  text(0.92, 6.55, 11.5, 0.5, [P('以上為查詢 MDS roles API 的結果;改 topic 設定要 ResourceOwner 或 ClusterAdmin,DeveloperManage 不行。', { sz: 11, c: C.grey })]),
] };

SL.peri = { title: '周邊組件:人與機器各走哪條路', items: [
  ...[[1.65, C.blue, C.pBlue, '人(Postman · 手動測試)', '人', 'Basic(AD 帳密)', '① REST Proxy 把 Basic 帳密轉給 MDS(/authenticate)\n② MDS 向 AD 驗證,回 token(不經 /impersonate)', 'OAUTHBEARER(帶 token)'],
    [4.05, C.orange, C.pOrange, '機器(legacy app)', 'legacy app', '① client 憑證(CN)→ 對映成主體', '② REST Proxy 用自己的 client 憑證向 MDS 認證\n③ POST /impersonate:代為申請 legacy app 的 token\n④ MDS 回 token(sub = app,cp_proxy = restproxy)', '⑤ OAUTHBEARER(帶 token)']].flatMap(([y0, col, pcol, label, who, l1, mdsTxt, l5]) => [
    text(0.92, y0, 5, 0.32, [P(label, { sz: 14, b: true, c: col })]),
    box(4.3, y0 + 0.36, 2.3, 0.6, { fill: C.pBlue, line: C.blue, lw: 1.25, round: 0.1, paras: [P('MDS', { sz: 14, b: true, algn: 'ctr' })] }),
    arrow(5.05, y0 + 1.15, 5.05, y0 + 0.96, C.blue, {}), arrow(5.8, y0 + 0.96, 5.8, y0 + 1.15, C.blue, {}),
    text(6.7, y0 + 0.25, 6.1, 0.8, mdsTxt.split('\n').map(s => P(s, { sz: 10, b: true, c: C.blue }))),
    box(0.92, y0 + 1.15, 2.0, 0.8, { fill: pcol, line: col, lw: 1.75, round: 0.1, paras: [P(who, { sz: 14, b: true, algn: 'ctr' })] }),
    box(4.3, y0 + 1.15, 2.3, 0.8, { fill: pcol, line: col, lw: 1.75, round: 0.1, paras: [P('REST Proxy', { sz: 14, b: true, algn: 'ctr' })] }),
    box(8.0, y0 + 1.15, 2.0, 0.8, { fill: pcol, line: col, lw: 1.75, round: 0.1, paras: [P('broker', { sz: 14, b: true, algn: 'ctr' })] }),
    arrow(2.92, y0 + 1.55, 4.3, y0 + 1.55, col), arrow(6.6, y0 + 1.55, 8.0, y0 + 1.55, col),
    text(2.0, y0 + 2.0, 2.8, 0.3, [P(l1, { sz: 10, b: true, c: col, algn: 'ctr' })]), text(6.35, y0 + 2.0, 2.3, 0.3, [P(l5, { sz: 10, b: true, c: col, algn: 'ctr' })]),
    text(10.1, y0 + 1.25, 2.7, 0.7, [P('broker 用 MDS 公鑰驗章,', { sz: 10, b: true, c: col }), P('主體 = token 的 sub', { sz: 10, b: true, c: col })]),
  ]),
  chip('C3 自己:c3 憑證 → MDS 換 token(SystemAdmin)→ 連 Kafka', 0.92, 6.55, 11.5, C.green, { sz: 12, h: 0.4 }),
] };

SL.c3 = { title: 'Control Center 登入與授權', items: [
  ...step(1, 0.92, 1.8, 1.95, 1.95, 'Basic 登入', '瀏覽器送 AD 帳密', C.blue, C.pBlue),
  ...step(2, 3.17, 1.8, 1.95, 1.95, 'C3 轉給 MDS', 'MDS 向 AD 驗證', C.blue, C.pBlue),
  ...step(3, 5.42, 1.8, 1.95, 1.95, '回 token', 'JWT 1 小時,會續期;登入上限預設 6 小時', C.blue, C.pBlue),
  ...step(4, 7.67, 1.8, 1.95, 1.95, '之後帶 Bearer', '同時有 HttpOnly cookie;優先看 Bearer', C.blue, C.pBlue),
  ...step(5, 9.92, 1.8, 2.5, 1.95, 'C3 驗章 + 查可見範圍', '本地驗章(實測推論),再向 MDS 查權限', C.blue, C.pBlue),
  arrow(2.87, 2.78, 3.17, 2.78, { c: C.blue }), arrow(5.12, 2.78, 5.42, 2.78, { c: C.blue }), arrow(7.37, 2.78, 7.67, 2.78, { c: C.blue }), arrow(9.62, 2.78, 9.92, 2.78, { c: C.blue }),
  box(0.92, 4.1, 5.6, 1.6, { fill: C.pBlue, line: C.blue, lw: 1.75 }),
  text(1.1, 4.2, 5.25, 1.75, [P('使用者操作', { sz: 17, b: true, c: C.blue, after: 6 }), P('C3 帶「使用者本人」的 token 連 broker', { sz: 14, after: 4 }), P('audit 的主體是 User:gary / User:ming', { sz: 12, c: C.grey })]),
  box(6.82, 4.1, 5.6, 1.6, { fill: C.pOrange, line: C.orange, lw: 1.75 }),
  text(7.0, 4.2, 5.25, 1.75, [P('C3 背景工作', { sz: 17, b: true, c: C.dorange, after: 6 }), P('c3 憑證向 MDS 換 token,身分是 User:c3', { sz: 14, after: 4 }), P('官方要求必須是 SystemAdmin', { sz: 12, c: C.grey })]),
  chip('以上為本專案實測;官方未明說 C3 以誰的身分查詢 Kafka', 0.92, 6.3, 11.5, { fill: C.pGrey, line: C.line, c: C.grey, sz: 12, b: false }),
] };

function risk(x, y, title, found, fix) {
  return [box(x, y, 5.6, 2.45, { fill: C.white, line: C.line, lw: 1.5, round: 0.05 }), text(x + 0.2, y + 0.1, 5.2, 0.4, [P(title, { sz: 16, b: true })]),
    box(x + 0.2, y + 0.58, 5.2, 0.85, { fill: C.pRed, line: C.red, lw: 1, round: 0.08, paras: [P('發現:' + found, { sz: 11.5, c: C.red, b: true })], anchor: 'ctr' }),
    box(x + 0.2, y + 1.52, 5.2, 0.8, { fill: C.pGreen, line: C.green, lw: 1, round: 0.08, paras: [P('對策:' + fix, { sz: 11.5, c: C.dgreen, b: true })], anchor: 'ctr' })];
}
SL.risk = { title: '已知風險與對策', items: [
  ...risk(0.92, 1.8, 'c3 憑證 = 管理員', '能建立 / 刪除 role binding;拿掉它的權限 C3 會退出(實測)', '保護私鑰與檔案權限;列入受保護清單'),
  ...risk(6.82, 1.8, 'REST Proxy 憑證可代人', '可代任何不在保護清單的使用者;清單混入 Group: 會整份失效(實測)', '特權身分逐一以 User: 列入'),
  ...risk(0.92, 4.4, 'Prometheus / Alertmanager', 'demo 未啟用認證,Alertmanager 可無認證寫入靜音', '官方支援 TLS + Basic;未啟用時以網路隔離'),
  ...risk(6.82, 4.4, 'broker 內建 Admin REST', '未設安全擴充時匿名可進入(本 demo 實測);曾使 broker OOM', '依官方 kafka.rest. 設定後,匿名回 401'),
] };

const todo = (n, x, y, t) => [box(x, y, 0.5, 0.5, { fill: C.blue, line: C.blue, round: 0.5, paras: [P(String(n), { sz: 16, b: true, c: C.white, algn: 'ctr' })], ins: 0 }), box(x + 0.65, y - 0.15, 4.85, 0.8, { fill: C.pBlue, line: C.blue, lw: 1.25, round: 0.2, paras: [P(t, { sz: 13, b: true, algn: 'l' })], ins: 0.15 })];
SL.todo = { title: '導入前請客戶確認', items: [
  ...todo(1, 0.92, 2.0, 'AD 唯讀查詢帳號(bind DN)與 LDAPS'), ...todo(2, 0.92, 3.1, '有無 AD CS(內部 CA)與根憑證散佈方式'), ...todo(3, 0.92, 4.2, '能否建幾個一般 AD user 給 legacy app'),
  ...todo(4, 6.82, 2.0, 'license 是否涵蓋 RBAC / audit / C3'), ...todo(5, 6.82, 3.1, 'AD 群組是否巢狀、帳號大小寫與命名'), ...todo(6, 6.82, 4.2, 'Java 版本(建議 21)、Prometheus / Alertmanager 部署'),
  chip('第 3 項若可行:legacy app 走 Basic,不需要 client 憑證', 0.92, 5.4, 11.5, { fill: C.pGreen, line: C.green, c: C.dgreen, sz: 13 }),
  chip('尚未實測:多 controller、真實 AD 環境、Prometheus Basic 認證', 0.92, 6.0, 11.5, { fill: C.pRed, line: C.red, c: C.red, sz: 13 }),
] };

// 最終順序:原頁(數字)與補充頁(鍵名)
const ORDER = [1, 2, 'compare', 3, 'env', 4, 'split', 5, 'cert', 6, 'kraft', 7, 'auth', 8, 'rbac', 'roles', 9, 'peri', 'c3', 'risk', 'todo'];
const FILL9 = 'peri';   // 原第 9 頁(空白)直接填入此內容;ORDER 內的 9 後面不再重複
const ADDED = ORDER.filter(k => typeof k === 'string' && k !== FILL9);

// ───────── PPTX XML 輸出 ─────────
let nid;
const rPr = r => `<a:rPr lang="zh-TW" altLang="en-US" sz="${Math.round(r.sz * 100)}" b="${r.b ? 1 : 0}" dirty="0"><a:solidFill><a:srgbClr val="${r.c}"/></a:solidFill></a:rPr>`;
const paraXml = p => `<a:p><a:pPr algn="${p.algn === 'ctr' ? 'ctr' : 'l'}">${p.after ? `<a:spcAft><a:spcPts val="${p.after * 100}"/></a:spcAft>` : ''}</a:pPr>${p.runs.map(r => `<a:r>${rPr(r)}<a:t>${X(r.t)}</a:t></a:r>`).join('')}</a:p>`;
function boxXml(s) {
  const id = nid++; const ins = e(s.ins);
  const fill = s.fill ? `<a:solidFill><a:srgbClr val="${s.fill}"/></a:solidFill>` : '<a:noFill/>';
  const ln = s.line ? `<a:ln w="${Math.round(s.lw * 12700)}"><a:solidFill><a:srgbClr val="${s.line}"/></a:solidFill></a:ln>` : '<a:ln><a:noFill/></a:ln>';
  const geom = s.round > 0 ? `<a:prstGeom prst="roundRect"><a:avLst><a:gd name="adj" fmla="val ${Math.round(Math.min(s.round, 0.5) * 100000 * 0.6)}"/></a:avLst></a:prstGeom>` : '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>';
  const body = s.paras.length ? s.paras.map(paraXml).join('') : '<a:p><a:endParaRPr lang="zh-TW"/></a:p>';
  return `<p:sp><p:nvSpPr><p:cNvPr id="${id}" name="${s.paras.length ? '文字方塊' : '圖形'} ${id}"/><p:cNvSpPr${s.fill || s.line ? '' : ' txBox="1"'}/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="${e(s.x)}" y="${e(s.y)}"/><a:ext cx="${e(s.w)}" cy="${e(s.h)}"/></a:xfrm>${geom}${fill}${ln}</p:spPr><p:txBody><a:bodyPr wrap="square" lIns="${ins}" tIns="${ins}" rIns="${ins}" bIns="${ins}" rtlCol="0" anchor="${s.anchor === 'ctr' ? 'ctr' : 't'}"><a:noAutofit/></a:bodyPr><a:lstStyle/>${body}</p:txBody></p:sp>`;
}
function arrowXml(s) {
  const id = nid++; const x = Math.min(s.x1, s.x2), y = Math.min(s.y1, s.y2), w = Math.abs(s.x2 - s.x1), h = Math.abs(s.y2 - s.y1);
  const flipH = s.x2 < s.x1 ? ' flipH="1"' : '', flipV = s.y2 < s.y1 ? ' flipV="1"' : '';
  return `<p:cxnSp><p:nvCxnSpPr><p:cNvPr id="${id}" name="箭頭 ${id}"/><p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr><p:spPr><a:xfrm${flipH}${flipV}><a:off x="${e(x)}" y="${e(y)}"/><a:ext cx="${e(w)}" cy="${e(h)}"/></a:xfrm><a:prstGeom prst="line"><a:avLst/></a:prstGeom><a:ln w="${Math.round(s.w * 12700)}"><a:solidFill><a:srgbClr val="${s.c}"/></a:solidFill>${s.dash ? '<a:prstDash val="dash"/>' : ''}<a:tailEnd type="triangle" w="med" len="med"/></a:ln></p:spPr></p:cxnSp>`;
}
function tableXml(s) {
  const id = nid++; const totalW = s.colW.reduce((a, b) => a + b, 0); const totalH = s.hdrH + (s.rows.length - 1) * s.rowH;
  const border = c => ['lnL', 'lnR', 'lnT', 'lnB'].map(t => `<a:${t} w="9525"><a:solidFill><a:srgbClr val="${c}"/></a:solidFill></a:${t}>`).join('');
  const rowsXml = s.rows.map((r, ri) => `<a:tr h="${e(ri === 0 ? s.hdrH : s.rowH)}">${r.map((c, ci) => {
    const hdr = ri === 0; const fill = hdr ? C.blue : (ci === 0 ? C.pBlue : (ri % 2 ? C.white : C.pGrey));
    const col = hdr ? C.white : C.ink;
    return `<a:tc><a:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r>${rPr({ sz: s.sz, b: hdr || ci === 0, c: col })}<a:t>${X(c)}</a:t></a:r></a:p></a:txBody><a:tcPr marL="${e(0.08)}" marR="${e(0.08)}" marT="${e(0.04)}" marB="${e(0.04)}" anchor="ctr">${border(C.line)}<a:solidFill><a:srgbClr val="${fill}"/></a:solidFill></a:tcPr></a:tc>`;
  }).join('')}</a:tr>`).join('');
  return `<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="${id}" name="表格 ${id}"/><p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr><p:xfrm><a:off x="${e(s.x)}" y="${e(s.y)}"/><a:ext cx="${e(totalW)}" cy="${e(totalH)}"/></p:xfrm><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table"><a:tbl><a:tblPr firstRow="1"/><a:tblGrid>${s.colW.map(w => `<a:gridCol w="${e(w)}"/>`).join('')}</a:tblGrid>${rowsXml}</a:tbl></a:graphicData></a:graphic></p:graphicFrame>`;
}
const shapeXml = s => s.k === 'box' ? boxXml(s) : s.k === 'arrow' ? arrowXml(s) : tableXml(s);
function slideXml(title, items, tag) {
  nid = 3;
  const titleSp = `<p:sp><p:nvSpPr><p:cNvPr id="2" name="標題 1"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr><p:spPr/><p:txBody><a:bodyPr><a:normAutofit/></a:bodyPr><a:lstStyle/><a:p><a:r><a:rPr lang="zh-TW" altLang="en-US" sz="3400" dirty="0"/><a:t>${X(title)}</a:t></a:r></a:p></p:txBody></p:sp>`;
  const body = (tag ? [TAG] : []).concat(items).map(shapeXml).join('');
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>${titleSp}${body}</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>`;
}

// ───────── HTML 預覽 ─────────
const px = v => (v * 96).toFixed(1) + 'px';
function htmlShape(s) {
  if (s.k === 'arrow') {
    const dx = s.x2 - s.x1, dy = s.y2 - s.y1, len = Math.hypot(dx, dy) * 96, ang = Math.atan2(dy, dx) * 180 / Math.PI;
    return `<div class="arr" style="left:${px(s.x1)};top:${px(s.y1)};width:${len}px;transform:rotate(${ang}deg);border-top:${s.w * 1.33}px ${s.dash ? 'dashed' : 'solid'} #${s.c}"><i style="border-left-color:#${s.c}"></i></div>`;
  }
  if (s.k === 'table') {
    const rows = s.rows.map((r, ri) => `<tr style="height:${px(ri === 0 ? s.hdrH : s.rowH)}">${r.map((c, ci) => { const hdr = ri === 0; const bg = hdr ? C.blue : (ci === 0 ? C.pBlue : (ri % 2 ? C.white : C.pGrey)); return `<td style="background:#${bg};color:#${hdr ? C.white : C.ink};font-weight:${hdr || ci === 0 ? 700 : 400};font-size:${s.sz * 1.333}px">${X(c)}</td>`; }).join('')}</tr>`).join('');
    return `<table class="tb" style="left:${px(s.x)};top:${px(s.y)};width:${px(s.colW.reduce((a, b) => a + b, 0))}"><colgroup>${s.colW.map(w => `<col style="width:${px(w)}">`).join('')}</colgroup>${rows}</table>`;
  }
  const ps = s.paras.map(p => `<p style="text-align:${p.algn === 'ctr' ? 'center' : 'left'};margin:0 0 ${p.after * 1.33}px">${p.runs.map(r => `<span style="font-size:${r.sz * 1.333}px;font-weight:${r.b ? 700 : 400};color:#${r.c}">${X(r.t)}</span>`).join('')}</p>`).join('');
  const st = `left:${px(s.x)};top:${px(s.y)};width:${px(s.w)};height:${px(s.h)};padding:${px(s.ins)};${s.fill ? `background:#${s.fill};` : ''}${s.line ? `border:${s.lw * 1.33}px solid #${s.line};` : ''}border-radius:${s.round > 0 ? Math.min(s.round, 0.5) * Math.min(s.w, s.h) * 96 * 0.6 + 'px' : 0};justify-content:${s.anchor === 'ctr' ? 'center' : 'flex-start'}`;
  return `<div class="bx" style="${st}">${ps}</div>`;
}
function slideHtml(title, items, tag, n) {
  return `<div class="sl" data-n="${n}"><div class="ttl">${X(title)}</div>${(tag ? [TAG] : []).concat(items).map(htmlShape).join('')}</div>`;
}
const HTML_HEAD = `<meta charset="utf-8"><style>body{margin:0;background:#888}.sl{position:relative;width:1280px;height:720px;background:#fff;overflow:hidden;margin:0 0 8px;font-family:'Microsoft JhengHei','Noto Sans CJK TC',sans-serif;line-height:1.2}
.ttl{position:absolute;left:88px;top:38px;width:1104px;height:139px;font-size:45px;display:flex;align-items:center;color:#000}
.bx{position:absolute;box-sizing:border-box;display:flex;flex-direction:column;overflow:hidden}.arr{position:absolute;height:0;transform-origin:0 0}.arr i{position:absolute;right:-2px;top:-7px;border:7px solid transparent;border-left:12px solid}
.tb{position:absolute;border-collapse:collapse;table-layout:fixed}.tb td{border:1px solid #BFBFBF;padding:3px 8px;vertical-align:middle}</style>`;

// ───────── 主流程 ─────────
(async () => {
  const z = await JSZip.loadAsync(fs.readFileSync(SRC));
  const ct = await z.file('[Content_Types].xml').async('string');
  const pres = await z.file('ppt/presentation.xml').async('string');
  const presRels = await z.file('ppt/_rels/presentation.xml.rels').async('string');
  const origIds = [...pres.matchAll(/<p:sldId id="(\d+)" r:id="(rId\d+)"\/>/g)].map(m => ({ id: +m[1], rid: m[2] }));
  const relTarget = rid => (presRels.match(new RegExp(`Id="${rid}"[^>]*Target="([^"]+)"`)) || presRels.match(new RegExp(`Target="([^"]+)"[^>]*Id="${rid}"`)) || [])[1];
  const origSlideFiles = origIds.map(o => relTarget(o.rid));   // e.g. slides/slide1.xml
  if (origSlideFiles.length !== 9) throw new Error('預期原檔 9 頁,實際 ' + origSlideFiles.length);

  // 修正原第 2 頁標題錯字 KAKFA → KAFKA(只改這一處)
  const s2f = 'ppt/' + origSlideFiles[1];
  let s2 = await z.file(s2f).async('string');
  if (s2.includes('KAKFA')) { s2 = s2.replace('KAKFA', 'KAFKA'); z.file(s2f, s2); console.log('已修正第 2 頁標題錯字 KAKFA → KAFKA'); }

  // 填滿原第 9 頁(原本空白):保留其 rels(版面 2),改寫內容
  const s9f = 'ppt/' + origSlideFiles[8];
  z.file(s9f, slideXml(SL[FILL9].title, SL[FILL9].items, true));

  // 新增補充頁
  let maxId = Math.max(...origIds.map(o => o.id)), maxRid = Math.max(...[...presRels.matchAll(/Id="rId(\d+)"/g)].map(m => +m[1]));
  const existing = Object.keys(z.files).filter(n => /^ppt\/slides\/slide\d+\.xml$/.test(n)).map(n => +n.match(/(\d+)\.xml/)[1]);
  let nextNum = Math.max(...existing) + 1;
  const layoutRel = await z.file('ppt/slides/_rels/' + path.basename(origSlideFiles[1]) + '.rels').async('string');
  const layoutTarget = (layoutRel.match(/Target="([^"]*slideLayout\d+\.xml)"/) || [])[1];
  let newCt = '', newRels = '', sldMap = {};
  for (const k of ADDED) {
    const n = nextNum++, rid = 'rId' + (++maxRid), sid = ++maxId;
    z.file(`ppt/slides/slide${n}.xml`, slideXml(SL[k].title, SL[k].items, true));
    z.file(`ppt/slides/_rels/slide${n}.xml.rels`, `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="${layoutTarget}"/></Relationships>`);
    newCt += `<Override PartName="/ppt/slides/slide${n}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>`;
    newRels += `<Relationship Id="${rid}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide${n}.xml"/>`;
    sldMap[k] = `<p:sldId id="${sid}" r:id="${rid}"/>`;
  }
  z.file('[Content_Types].xml', ct.replace('</Types>', newCt + '</Types>'));
  z.file('ppt/_rels/presentation.xml.rels', presRels.replace('</Relationships>', newRels + '</Relationships>'));
  const idOf = i => `<p:sldId id="${origIds[i - 1].id}" r:id="${origIds[i - 1].rid}"/>`;
  const lst = ORDER.map(k => typeof k === 'number' ? idOf(k) : (k === FILL9 ? '' : sldMap[k])).join('');
  // 補充頁 'peri' 取代原 9 頁內容 → 9 頁位置即 peri
  z.file('ppt/presentation.xml', pres.replace(/<p:sldIdLst>[\s\S]*?<\/p:sldIdLst>/, `<p:sldIdLst>${lst}</p:sldIdLst>`));
  // docProps/app.xml 內的頁數資訊讓 PowerPoint 自行重算(移除 Slides 計數以免不一致)
  if (z.file('docProps/app.xml')) { let app = await z.file('docProps/app.xml').async('string'); app = app.replace(/<Slides>\d+<\/Slides>/, `<Slides>${ORDER.length - 1}</Slides>`); z.file('docProps/app.xml', app); }
  fs.writeFileSync(OUT, await z.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' }));
  console.log('已輸出', OUT, '共', ORDER.length - 1, '頁(原 9 頁 + 補充 ' + ADDED.length + ' 頁)');

  // 預覽 HTML(只含補充頁與第 9 頁;原頁為使用者原文不動)
  const pv = ORDER.filter(k => typeof k === 'string').map((k, i) => slideHtml(SL[k].title, SL[k].items, true, k));
  fs.writeFileSync(path.join(__dirname, 'preview-kafka-supplement.html'), `<!doctype html><html><head>${HTML_HEAD}</head><body>${pv.join('')}</body></html>`);
})();
