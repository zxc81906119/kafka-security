// 客戶安全解決方案簡報(草稿,尚未套公司模板)
// 結構:標題用版面配置區(placeholder)、顏色全用佈景色彩(scheme color)→ 日後套公司模板時,顏色與字型會跟著模板走。
// 同一份版面規格 → (1) pptxgenjs 輸出 PPTX  (2) HTML 預覽(Playwright 截圖檢查溢出,非 PowerPoint 真實渲染)。
// 用法: node build-solution-deck.js   → deck/Confluent-Security-Solution-Draft.pptx 與 deck/preview-sol/*.png
const fs = require('fs');
const path = require('path');
const pptxgen = require('pptxgenjs');
const React = require('react');
const { renderToStaticMarkup } = require('react-dom/server');
const sharp = require('sharp');
const FA = require('react-icons/fa');

const OUT = process.env.OUT || path.join(__dirname, 'Confluent-Security-Solution-Draft.pptx');
const THEME = {
  name: 'Confluent Security Draft', headFontFace: 'Microsoft JhengHei', bodyFontFace: 'Microsoft JhengHei',
  colors: { dk1: '1A1A1A', lt1: 'FFFFFF', dk2: '0E2841', lt2: 'F2F4F7', accent1: '156082', accent2: 'E97132', accent3: '196B24', accent4: '0F9ED5', accent5: '7A4EAB', accent6: 'B3261E', hlink: '156082', folHlink: '7A4EAB' },
};
const HEX = { text1: THEME.colors.dk1, text2: THEME.colors.dk2, background1: THEME.colors.lt1, background2: THEME.colors.lt2, accent1: THEME.colors.accent1, accent2: THEME.colors.accent2, accent3: THEME.colors.accent3, accent4: THEME.colors.accent4, accent5: THEME.colors.accent5, accent6: THEME.colors.accent6 };

// ───────── 規格建構(顏色以佈景色彩名稱表示:accent1 藍=人/AD、accent2 橘=服務、accent3 綠=平台/正常、accent5 紫=MDS、accent6 紅=風險)─────────
const HUM = 'accent1', SVC = 'accent2', PLT = 'accent3', MDS = 'accent5', RISK = 'accent6', INK = 'text2';
const run = (t, o = {}) => ({ t, sz: o.sz || 14, b: !!o.b, c: o.c || 'text1', a: o.a });
const para = (runs, o = {}) => ({ runs: Array.isArray(runs) ? runs : [runs], algn: o.algn || 'l', after: o.after || 0 });
const P = (t, o = {}) => para(run(t, o), o);
const MUTE = { c: 'text1', a: 0.62 };
const box = (x, y, w, h, o = {}) => ({ k: 'box', x, y, w, h, fill: o.fill, tint: o.tint === undefined ? 0 : o.tint, line: o.line, lw: o.lw || 1.5, round: o.round === undefined ? 0.1 : o.round, paras: o.paras || [], anchor: o.anchor || 'ctr', ins: o.ins === undefined ? 0.08 : o.ins });
const tint = (x, y, w, h, col, o = {}) => box(x, y, w, h, { fill: col, tint: 0.88, line: col, ...o });
const solid = (x, y, w, h, col, paras, o = {}) => box(x, y, w, h, { fill: col, tint: 0, line: col, paras, ...o });
const white = (x, y, w, h, col, o = {}) => box(x, y, w, h, { fill: 'background1', tint: 0, line: col, ...o });
const text = (x, y, w, h, paras, o = {}) => ({ k: 'box', x, y, w, h, paras, anchor: o.anchor || 't', ins: o.ins === undefined ? 0 : o.ins, round: 0, tint: 0 });
const chip = (t, x, y, w, col, o = {}) => box(x, y, w, o.h || 0.42, { fill: col, tint: o.solid ? 0 : 0.88, line: col, lw: 1.25, round: 0.5, paras: [P(t, { sz: o.sz || 12, b: o.b !== false, c: o.solid ? 'background1' : (o.c || col), algn: 'ctr' })], ins: 0.1 });
const icon = (name, x, y, s, col) => ({ k: 'icon', name, x, y, s, col });
const arrow = (x1, y1, x2, y2, col, o = {}) => ({ k: 'arrow', x1, y1, x2, y2, col: col || 'text1', w: o.w || 2.25, dash: !!o.dash });
const table = (x, y, colW, rows, o = {}) => ({ k: 'table', x, y, colW, rows, rowH: o.rowH || 0.62, hdrH: o.hdrH || 0.46, sz: o.sz || 12, col: o.col || HUM });
const badge = (name, x, y, s, col) => [box(x, y, s, s, { fill: col, tint: 0.85, line: col, round: 0.5, lw: 1 }), icon(name, x + s * 0.22, y + s * 0.22, s * 0.56, col)];
// 圖示 + 標題 + 說明 的垂直節點
function node(x, y, w, h, o) {
  const col = o.col || HUM, items = [tint(x, y, w, h, col, { round: 0.08 })];
  items.push(...badge(o.icon, x + w / 2 - 0.3, y + 0.15, 0.6, col));
  items.push(text(x + 0.08, y + 0.85, w - 0.16, 0.45, [P(o.title, { sz: o.tsz || 14, b: true, algn: 'ctr', c: col === 'accent2' ? 'accent2' : col })]));
  if (o.sub) items.push(text(x + 0.1, y + 1.3, w - 0.2, h - 1.35, [P(o.sub, { sz: o.ssz || 11, algn: 'ctr', ...MUTE })]));
  return items;
}
// 步驟(編號圓 + 標題 + 說明)
function step(n, x, y, w, h, t1, t2, col) {
  return [tint(x, y, w, h, col, { round: 0.08 }),
    box(x + 0.12, y + 0.12, 0.42, 0.42, { fill: col, tint: 0, line: col, round: 0.5, paras: [P(String(n), { sz: 14, b: true, c: 'background1', algn: 'ctr' })], ins: 0 }),
    text(x + 0.1, y + 0.62, w - 0.2, 0.5, [P(t1, { sz: 14, b: true, algn: 'ctr', c: col })]),
    text(x + 0.1, y + 1.15, w - 0.2, h - 1.2, [P(t2, { sz: 11, algn: 'ctr', ...MUTE })])];
}
const RM = (a) => a;   // 佔位,保持可讀

// ───────── 各頁內容 ─────────
const SLIDES = [];
const add = (s) => SLIDES.push(s);

add({ layout: 'TITLE', title: 'Confluent Platform 安全解決方案', subtitle: '依客戶前提設計:AD 僅有 user / group · 共用單一 server 憑證 · RHEL 9 手動部署', note: '草稿 v0.1', items: [
  ...badge('FaShieldAlt', 9.6, 1.6, 1.5, HUM), ...badge('FaUsers', 11.3, 2.5, 1.2, SVC), ...badge('FaKey', 9.9, 3.5, 1.2, PLT), ...badge('FaServer', 11.4, 4.2, 1.0, MDS),
  text(0.9, 5.6, 9, 0.8, [P('範圍:Kafka(broker / controller / MDS)· REST Proxy · Control Center', { sz: 14, ...MUTE }), P('草稿 v0.1 — 待調整後套用公司模板', { sz: 12, ...MUTE })]),
], notes: '封面。客戶前提:RHEL 9 手動部署、AD 只有 user 與 group。範圍:Kafka(含 controller 與 MDS RBAC)、REST Proxy、Control Center。' });

add({ layout: 'SECTION', title: '客戶前提與設計原則', subtitle: '先把限制說清楚,方案才站得住', items: [], notes: '' });

add({ title: '客戶前提', items: [
  ...[['FaUsers', 'AD 只有人與群組', '沒有服務帳號', HUM], ['FaKey', '憑證數量越少越好', '希望憑證管理最小化', SVC], ['FaServer', 'RHEL 9 VM · 手動安裝', '目前沒有 Ansible', PLT],
    ['FaPlug', 'legacy app 只能 HTTP', '不能用 Kafka client', SVC], ['FaSitemap', '不同職責,不同權限', '分層授權,不是全有或全無', HUM], ['FaCubes', '範圍', 'Kafka · REST Proxy · C3', MDS]].flatMap(([ic, t, s, col], i) =>
    node(0.6 + (i % 3) * 4.13, 1.55 + Math.floor(i / 3) * 2.7, 3.85, 2.45, { icon: ic, title: t, sub: s, col, tsz: 17, ssz: 13 })),
], notes: '六個前提:AD 只有 user/group(沒有服務帳號);希望憑證數量越少越好(設計上共用一組 server 憑證);RHEL 9 手動部署、尚無 Ansible;legacy app 只能 HTTP;權限要依職責分層(不同職責不同權限,唯讀只是其中一層;做法是 AD 群組 + RBAC);範圍限於 Kafka、REST Proxy、C3。' });

add({ title: '設計原則:兩個身分平面', items: [
  tint(0.6, 1.55, 4.7, 3.7, HUM), ...badge('FaUser', 0.85, 1.75, 0.8, HUM), text(1.85, 1.85, 3.3, 0.6, [P('人', { sz: 24, b: true, c: HUM })]),
  text(0.9, 2.85, 4.1, 1.0, [P('AD 帳密 + AD 群組', { sz: 16, b: true, after: 6 }), P('登入 C3 · 手動腳本 · Postman', { sz: 13, ...MUTE })]),
  chip('授權跟著 AD 群組走', 0.9, 4.45, 4.1, HUM),
  tint(8.03, 1.55, 4.7, 3.7, SVC), ...badge('FaCogs', 8.28, 1.75, 0.8, SVC), text(9.28, 1.85, 3.3, 0.6, [P('服務', { sz: 24, b: true, c: SVC })]),
  text(8.33, 2.75, 4.2, 1.6, [P('連 Kafka:SCRAM 帳密', { sz: 16, b: true, after: 4 }), P('連 MDS / REST Proxy:client 憑證', { sz: 16, b: true, after: 8 }), P('應用 · 排程 · legacy app · 平台元件', { sz: 13, ...MUTE })]),
  chip('授權綁 User:服務名稱', 8.33, 4.45, 4.1, SVC),
  tint(5.6, 2.3, 2.13, 1.9, MDS), ...badge('FaShieldAlt', 6.37, 2.45, 0.6, MDS), text(5.65, 3.15, 2.03, 0.5, [P('MDS · RBAC', { sz: 15, b: true, algn: 'ctr', c: MDS })]), text(5.7, 3.6, 1.93, 0.5, [P('集中管理授權規則', { sz: 11, algn: 'ctr', ...MUTE })]),
  arrow(5.3, 3.25, 5.6, 3.25, HUM), arrow(8.03, 3.25, 7.73, 3.25, SVC),
  solid(0.6, 5.55, 12.13, 0.7, INK, [P('怎麼分?有人在場、由人直接或間接操作 = 人;其餘(無人值守)= 服務', { sz: 17, b: true, c: 'background1', algn: 'ctr' })]),
  text(0.6, 6.4, 12.13, 0.4, [P('腳本由手動轉成排程 → 必須改用服務身分,不借用人的帳號', { sz: 12, algn: 'ctr', ...MUTE })]),
], notes: '核心主張:AD 管人,Kafka 管機器。人與服務用不同的身分來源,但授權都集中在 MDS 的 RBAC。' });

add({ title: '方案總覽:組件與安全機制', items: [
  ...[['FaCube', 'Controller', 'SASL/PLAIN · 內部帳號', HUM], ['FaServer', 'Broker', 'PLAIN+LDAP · SCRAM · token', HUM], ['FaExchangeAlt', 'REST Proxy', '人 Basic · 機器憑證', HUM],
    ['FaDesktop', 'Control Center', '人用本人身分', HUM], ['FaLock', 'TLS 與憑證', '共用 1 組 server 憑證', MDS], ['FaShieldAlt', 'MDS · RBAC', 'AD 群組 → role', MDS],
    ['FaCogs', '服務帳號', 'SCRAM + 最小權限', MDS], ['FaClipboardList', 'Audit log', '誰被拒、誰改授權', MDS], ['FaSitemap', '整合與導入', '全景 · 步驟 · 風險', PLT]].flatMap(([ic, t, s, col], i) =>
    node(0.6 + (i % 3) * 4.13, 1.5 + Math.floor(i / 3) * 1.85, 3.85, 1.7, { icon: ic, title: t, sub: s, col, tsz: 15, ssz: 12 })),
], notes: '前四格(藍)是 Confluent 的組件:Controller、Broker、REST Proxy、Control Center;後面(紫)是貫穿全案的安全機制,最後是整合與導入。MDS 是 Broker 內建的服務,不是獨立組件。' });

add({ layout: 'SECTION', title: '逐項介紹', subtitle: '每一項:傳輸加密 · 認證 · 授權 · 注意事項', items: [], notes: '' });

// TLS
add({ title: 'TLS 與憑證:共用 1 組,只做加密', items: [
  ...badge('FaCertificate', 0.8, 1.75, 1.3, SVC), text(0.6, 3.2, 1.7, 0.7, [P('1 組 PK + 憑證', { sz: 14, b: true, algn: 'ctr', c: SVC })]), text(0.55, 3.75, 1.8, 0.6, [P('SAN 涵蓋所有組件的網域 / IP', { sz: 10.5, algn: 'ctr', ...MUTE })]),
  ...['controller', 'broker', 'MDS', 'REST Proxy', 'C3'].map((n, i) => [arrow(2.35, 2.4, 3.3, 1.75 + i * 0.5, SVC, { w: 1.5 }), white(3.3, 1.55 + i * 0.5, 2.0, 0.4, SVC, { round: 0.5, lw: 1, paras: [P(n, { sz: 12, b: true, algn: 'ctr' })] })]).flat(),
  text(3.3, 4.05, 2.0, 0.3, [P('server 端啟動 TLS', { sz: 10.5, algn: 'ctr', ...MUTE })]),
  tint(0.6, 4.5, 6.0, 1.6, HUM), text(0.8, 4.6, 5.6, 0.4, [P('client 端', { sz: 15, b: true, c: HUM })]),
  chip('只需 truststore(匯入 CA root)', 0.8, 5.05, 5.6, HUM), chip('連 AD 的 broker(含 MDS):匯入 AD 的 LDAPS CA root,一份設定', 0.8, 5.55, 5.6, HUM),
  tint(7.0, 1.5, 5.73, 2.8, SVC), text(7.2, 1.6, 5.3, 0.4, [P('平台元件用 client 憑證向 MDS 證明身分', { sz: 15, b: true, c: SVC })]),
  chip('c3', 7.2, 2.15, 1.5, SVC), chip('restproxy', 8.8, 2.15, 1.7, SVC), chip('bootstrap', 10.6, 2.15, 1.9, SVC),
  text(7.2, 2.68, 5.4, 1.6, [P('+ 每個經 REST Proxy 的 legacy app 各 1 張(由 REST Proxy 辨識後代為申請 token)', { sz: 11.5, b: true, after: 3 }), P('人的路徑不用:人走 AD 帳密。RBAC 下 C3 連 broker 只能 OAUTHBEARER,所以先以憑證向 MDS 換 token', { sz: 11, after: 3 }), P('綁 RBAC 的是 CN:換憑證只要 CN 不變,不用重綁權限', { sz: 11, ...MUTE })]),
  tint(7.0, 4.4, 5.73, 1.8, RISK), text(7.2, 4.48, 5.3, 0.4, [P('要請客戶簽認', { sz: 15, b: true, c: RISK })]),
  text(7.2, 4.9, 5.4, 1.3, [P('•  私鑰外洩 = 可偽裝伺服器;共用憑證對應的身分(CN)永遠不綁任何 role', { sz: 11, after: 3 }), P('•  只換 server 憑證(CA 不變):逐台換 keystore,truststore 不動', { sz: 11, after: 3 }), P('•  CA 換金鑰:truststore 先新舊並存 → 重簽 server 與 client 憑證 → 移除舊 root', { sz: 11 })]),
  solid(0.6, 6.35, 12.13, 0.5, INK, [P('共用憑證只負責加密、不承載權限;身分另外處理', { sz: 15, b: true, c: 'background1', algn: 'ctr' })]),
], notes: 'server 端共用一組 PK+憑證,SAN 要涵蓋所有組件對外連線的網域/IP;客戶內部 CA 簽發。client 只需 truststore。需要 client 憑證的是平台元件(c3、restproxy、bootstrap)與經 REST Proxy 的 legacy app。第 8 章實測:共用憑證當 client 身分,MDS 看到的主體都一樣。另外實測發現:MDS 設 REQUESTED 時會要求 client 憑證,C3 內部有一個用共用 keystore 的 HTTP 客戶端(查叢集 ID)會自動出示共用憑證,MDS 日誌的主體是 kafka.demo.local;所以這個身分一律不綁 role,且共用憑證不要收斂 EKU(收斂後這些呼叫會被拒)。AD 的 LDAPS CA root(信任庫放的是簽發 LDAPS 憑證的 CA 憑證,不是 AD 伺服器自己的憑證;若 LDAPS 憑證由中繼 CA 簽發且 AD 只送出自己的憑證、不附完整鏈,中繼 CA 也要匯入,此情況未實測):官方 MDS-LDAP 頁用 ldap.java.naming.security.protocol=SSL 與 ldap.ssl.truststore.*;實測 broker 不設信任庫時 PLAIN+LDAP 登入與群組同步都失敗(PKIX path building failed),加上後恢復;只有連 AD 的 JVM(broker 的 PLAIN+LDAP listener 與 MDS,同一批 broker,一份 ldap.ssl.truststore.* 設定即可)需要,controller、C3、REST Proxy 不連 AD。輪替(已在單節點實驗實測,見下一頁):CA 不變只換 server 憑證 → 只換 keystore;CA 根換新但金鑰不變 → truststore 新增新 root、舊的到期前移除;CA 換金鑰 → 先讓所有 truststore(server 與 client 兩邊)同時信任新舊 root,再用新 CA 重簽 server 憑證與 client 憑證(c3、restproxy、bootstrap、各 legacy app),確認後移除舊 root。有中繼 CA 時 keystore 要帶完整鏈。' });

// 憑證更換
const rotCard = (x, col, ic, head, sub) => [white(x, 1.5, 3.9, 4.45, col, { round: 0.04, lw: 1.5 }), ...badge(ic, x + 0.15, 1.62, 0.6, col), text(x + 0.9, 1.6, 2.9, 0.4, [P(head, { sz: 14, b: true, c: col })]), text(x + 0.9, 2.0, 2.9, 0.3, [P(sub, { sz: 11, ...MUTE })])];
const rotBox = (x, y, txt, col) => box(x + 0.2, y, 3.5, 0.5, { fill: col, tint: 0.88, line: col, lw: 1, round: 0.2, paras: [P(txt, { sz: 11.5, b: true, algn: 'ctr' })], ins: 0.05 });
const rotStep = (x, y, n, txt, col) => [box(x + 0.2, y, 0.36, 0.36, { fill: col, tint: 0, line: col, round: 0.5, paras: [P(String(n), { sz: 11, b: true, c: 'background1', algn: 'ctr' })], ins: 0 }), text(x + 0.65, y - 0.05, 3.05, 0.5, [P(txt, { sz: 11, b: true })], { anchor: 'ctr' })];
add({ title: '憑證更換:三種情境,順序不能錯', items: [
  ...rotCard(0.6, PLT, 'FaSyncAlt', '只換 server 憑證', 'CA 不變(例如到期更新)'),
  rotBox(0.6, 2.5, '換 keystore(新憑證)', PLT), arrow(2.55, 3.0, 2.55, 3.3, PLT, { w: 2 }), rotBox(0.6, 3.3, 'truststore 不動', PLT), arrow(2.55, 3.8, 2.55, 4.1, PLT, { w: 2 }), rotBox(0.6, 4.1, 'client 不用改', PLT),
  chip('實測:換 keystore 後,client 設定不用改', 0.8, 4.95, 3.5, PLT, { sz: 10.5, h: 0.5 }),
  ...rotCard(4.715, HUM, 'FaIdCard', 'CA 根換新、金鑰不變', '同一把金鑰重新簽發根憑證'),
  rotBox(4.715, 2.5, '信任庫換成新根', HUM), arrow(6.67, 3.0, 6.67, 3.3, HUM, { w: 2 }), rotBox(4.715, 3.3, '舊的 server / client 憑證照常通過', HUM), arrow(6.67, 3.8, 6.67, 4.1, HUM, { w: 2 }), rotBox(4.715, 4.1, '不用重簽任何憑證', HUM),
  chip('實測:信任庫換成新根,舊的 server / client 憑證照常通過', 4.915, 4.95, 3.5, HUM, { sz: 10.5, h: 0.5 }),
  ...rotCard(8.83, SVC, 'FaKey', 'CA 換金鑰', '新根、新金鑰:所有憑證都要重簽'),
  ...rotStep(8.83, 2.5, 1, '所有信任庫先放「新舊兩個根」(server + client)', SVC),
  ...rotStep(8.83, 3.1, 2, '換 server 憑證(新 CA 簽發)', SVC),
  ...rotStep(8.83, 3.7, 3, '重簽 client 憑證(c3、restproxy、bootstrap、legacy app)', SVC),
  ...rotStep(8.83, 4.3, 4, '全部確認後,才移除舊根', SVC),
  chip('先換 server 憑證、client 還沒信任新根 → PKIX 失敗(實測)', 9.03, 4.82, 3.5, RISK, { sz: 10, h: 0.46 }), chip('移除舊根後,舊 CA 簽發且未重簽的 client 憑證被拒(實測)', 9.03, 5.36, 3.5, RISK, { sz: 10, h: 0.46 }),
  solid(0.6, 6.15, 12.13, 0.65, INK, [P('官方 CFK 憑證文件建議:先更新所有信任庫、再換憑證、逐台重啟,每個元件就緒再做下一個', { sz: 13, b: true, c: 'background1', algn: 'ctr' })]),
], notes: '憑證更換實驗(demo/spike/cert-rotation,單節點 Kafka、SSL listener 要求 client 憑證,可動態換 keystore/truststore):T1 只換 server 憑證(同 CA、新金鑰):用 kafka-configs 動態更新 listener.name.ssl.ssl.keystore.location,不重啟,client 設定完全不動仍通過(動態更新只涵蓋 Kafka listener;在 demo 實測 MDS 8091 埠不會跟著換,broker 仍要重啟,REST Proxy、C3 本來就要重啟,所以本方案以 rolling restart 為主,動態更新價值有限)。T4 根憑證用同一把金鑰重新簽發:client 信任庫只放新根、server 信任庫換成新根,舊的 server 與 client 憑證都照常通過。T2 CA 換金鑰且順序錯(先換 server 憑證、client 信任庫仍是舊根):client 出現 PKIX path building failed;還原後恢復。T3 正確順序:①server 與 client 信任庫先放新舊兩個根(舊 client 憑證與新舊 server 憑證都通過)→②換 server 憑證→③重簽 client 憑證(新 CA)→④移除舊根:新 client 憑證通過,尚未重簽的舊 client 憑證被拒。未驗證:長駐 client 是否需要重啟才會重新載入信任庫(以每次新啟動的 client 模擬);有中繼 CA 的情況。MDS / REST Proxy / C3 換憑證需要重啟:已在 demo 全元件演練實測(換檔不重啟,各埠仍出示舊憑證),見下一頁;這些元件有沒有不重啟的動態重載方式未驗證。' });

// 元件更換順序
const ph = ['① 信任庫:新舊並存', '② 換 server 憑證', '③ 重簽 client 憑證', '④ 移除舊根'];
const rows = [
  ['controller', 'FaCube', PLT, ['逐台重啟', '逐台重啟', '—', '逐台重啟']],
  ['broker(含 MDS)', 'FaServer', HUM, ['逐台重啟', '逐台重啟', '—', '逐台重啟']],
  ['REST Proxy', 'FaExchangeAlt', SVC, ['重啟', '重啟', '重啟', '重啟']],
  ['Control Center', 'FaDesktop', MDS, ['重啟', '重啟', '重啟', '重啟']],
  ['應用 / CLI(client)', 'FaLaptopCode', 'text2', ['信任庫加新根', '—', 'legacy app 換新憑證', '信任庫移除舊根']],
];
add({ title: '元件更換順序:先信任、後出示、最後移除', items: [
  ...ph.map((p, i) => box(3.3 + i * 2.36, 1.45, 2.25, 0.62, { fill: INK, tint: 0, line: INK, round: 0.15, paras: [P(p, { sz: 12, b: true, c: 'background1', algn: 'ctr' })], ins: 0.05 })),
  ...rows.flatMap(([n, ic, col, cells], r) => {
    const y = 2.2 + r * 0.74;
    return [tint(0.6, y, 2.6, 0.62, col, { round: 0.12, lw: 1 }), icon(ic, 0.72, y + 0.12, 0.38, col), text(1.2, y, 1.95, 0.62, [P(n, { sz: 12, b: true, c: col })], { anchor: 'ctr' }),
      ...cells.map((c, i) => c === '—' ? text(3.3 + i * 2.36, y, 2.25, 0.62, [P('不用動', { sz: 11.5, algn: 'ctr', ...MUTE })], { anchor: 'ctr' }) : box(3.3 + i * 2.36, y, 2.25, 0.62, { fill: col, tint: 0.88, line: col, lw: 1, round: 0.15, paras: [P(c, { sz: 11.5, b: true, c: col, algn: 'ctr' })], ins: 0.03 }))];
  }),
  tint(0.6, 5.95, 5.95, 0.85, PLT, { round: 0.06, lw: 1, ins: 0.12, anchor: 'ctr', paras: [P('每階段:controller(逐台)→ broker(逐台)→ REST Proxy → C3,就緒才做下一個', { sz: 11.5, b: true, c: PLT, after: 2 }), P('CFK 憑證文件:信任庫先於憑證、每階段全部元件做完 · 元件順序:參考升級文件', { sz: 11, c: PLT })] }),
  tint(6.78, 5.95, 5.95, 0.85, RISK, { round: 0.06, lw: 1, ins: 0.12, anchor: 'ctr', paras: [P('只換檔沒重啟,各元件仍出示舊憑證(實測)', { sz: 11.5, b: true, c: RISK, after: 2 }), P('controller 與 broker 沒有 client 憑證 → ③ 階段不用重啟', { sz: 11, c: RISK })] }),
], notes: '在實際 demo 環境(demo/spike/cert-rotation/rotate-demo.sh,log 為 rotate-demo.log)用「新根 CA2(新金鑰)」演練整套更換:階段 1:信任庫換成 {CA1,CA2},controller、broker1、broker2、REST Proxy、C3 全部重啟。階段 2:server 憑證換成 CA2 簽發;檔案換好、尚未重啟時,controller 9093、broker 9094 與 MDS 8091、REST Proxy 8086、C3 9022 仍出示舊憑證;依序重啟後全部變成新簽發者;過程中包含 controller 與 broker1 已換、broker2 還沒換的混合狀態,Kafka 人員登入、MDS 登入、REST Proxy(人與 legacy 憑證)、C3 網頁皆正常。階段 3:client 憑證(c3、restproxy、bootstrap、legacy-orders)用新根重簽,CN 不變所以 RBAC 不用重綁;REST Proxy、C3 重啟(換了檔案要重啟才載入;其實舊憑證在移除舊根前仍有效,階段 3 就重啟是為了在移除舊根之前先驗證新憑證,出問題還能回頭);controller 與 broker 沒有 client 憑證所以不用;legacy app 與 bootstrap 是直接讀檔,換檔即生效;新舊根並存期間,舊 CA 簽發的 legacy 憑證仍被接受。階段 4:信任庫只留新根,全部重啟;舊 CA 簽發的 legacy 憑證被拒(TLS 握手失敗),仍只信任舊根的 client 連不上新憑證。順序的依據:Confluent for Kubernetes 憑證管理文件的 CA 輪替流程是「步驟為主」:先更新所有元件的信任庫、確認每個元件都有新舊兩個 CA,再更新憑證;每個元件 rollout 完成才繼續。不是「一個元件做完全部步驟再換下一個」(那樣會在其他元件還沒信任新根時就出示新憑證)。也不是「一個步驟同時重啟全部」:每個步驟內逐個元件、逐台 rolling。該文件沒有規定元件之間的順序;本頁的 controller → broker(一次一台)→ REST Proxy → C3 是參考官方升級文件的順序(KRaft controller 先、broker 次之、Control Center 最後),不是憑證輪替文件的明文規定。注意:本頁以「重啟」載入為準,這也是官方的建議做法:Confluent for Kubernetes 憑證管理文件寫「Always renew truststores for all components before renewing certificates」、驗證每個元件信任庫都有新舊兩個 CA、「Wait for each component’s rollout to complete before proceeding」、先在非正式環境演練。動態載入是選項:官方 dynamic config 頁說 Kafka 的 keystore / truststore 可用 listener 前綴動態更新、只影響新連線(inter-broker listener 要求新 keystore 被該 listener 信任庫信任);CFK 文件的動態憑證載入只涵蓋 Kafka 與 Kafka REST、且只到個別 listener。Kafka 的 listener keystore / truststore 可用 kafka-configs 動態更新、不用重啟 JVM(單節點實驗實測),這不是 rolling restart;但 demo 全元件演練沒有使用動態更新,MDS 埠(Jetty)、REST Proxy、C3 是否能不重啟載入新憑證未驗證。正式環境有 3 個 controller,需逐台重啟以維持 quorum;demo 只有 1 個 controller,多 controller 搭配 TLS 與 RBAC 的滾動重啟未驗證。' });

// Controller
add({ title: 'Controller(KRaft)', items: [
  ...[0, 1, 2].map(i => [tint(0.6 + i * 1.9, 1.6, 1.7, 1.3, PLT), ...badge('FaCube', 0.6 + i * 1.9 + 0.55, 1.7, 0.6, PLT), text(0.6 + i * 1.9, 2.4, 1.7, 0.4, [P('controller ' + (i + 1), { sz: 12, b: true, algn: 'ctr' })])]).flat(),
  text(0.6, 3.0, 5.5, 0.5, [P('Raft quorum:正式環境 3 個;主 demo 1 個', { sz: 12.5, b: true, c: SVC })]),
  tint(6.5, 1.6, 6.23, 2.4, PLT), text(6.7, 1.7, 5.8, 0.4, [P('CONTROLLER 9093', { sz: 15, b: true, c: PLT })]),
  chip('SASL_SSL', 6.7, 2.2, 1.7, PLT), chip('SASL/PLAIN', 8.5, 2.2, 1.9, PLT), chip('靜態內部帳號', 10.5, 2.2, 2.0, PLT),
  text(6.7, 2.8, 5.8, 1.3, [P('帳號:kafka-controller · kafka-broker', { sz: 13, b: true, after: 3 }), P('controller → broker(9092):SCRAM 身分 kafka-controller', { sz: 12, b: true, c: PLT, after: 3 }), P('授權資料(role binding、使用者→群組)透過 broker 的 RBAC topic 取得', { sz: 12, ...MUTE, after: 2 })]),
  white(0.6, 3.75, 5.5, 1.1, PLT, { round: 0.06 }), text(0.8, 3.85, 5.1, 0.9, [P('授權', { sz: 13, b: true, c: PLT, after: 3 }), P('ConfluentServerAuthorizer + super.users', { sz: 12.5 })]),
  tint(0.6, 5.1, 5.5, 1.0, RISK), ...badge('FaFire', 0.75, 5.2, 0.7, RISK), text(1.6, 5.2, 4.4, 0.8, [P('防火牆:9093 只開給 broker / controller 節點', { sz: 12.5, b: true, c: RISK })]),
  tint(6.5, 4.15, 6.23, 2.0, SVC), ...badge('FaInfoCircle', 6.65, 4.3, 0.7, SVC), text(7.55, 4.22, 5.0, 1.9, [P('為什麼是 PLAIN 靜態帳號:三種做法逐一排除', { sz: 14, b: true, c: SVC, after: 3 }), P('•  不用 SCRAM:官方 SCRAM overview 頁說明 controller listener 不支援', { sz: 12, after: 3 }), P('•  不走 AD:AD 不含服務帳號,而且內部通道一旦依賴 AD,AD 異常時就會牽連叢集本身', { sz: 12, after: 3 }), P('•  不走 mTLS:客戶希望憑證越少越好,不為內部通道另發 client 憑證', { sz: 12, after: 3 }), P('→ 因此採用 PLAIN 靜態帳號:帳號寫在 JAAS 設定,不依賴 AD、不另發憑證', { sz: 12, b: true, c: SVC })]),
  solid(0.6, 6.35, 12.13, 0.5, INK, [P('controller 只認內部帳號;人與服務都不直接連它', { sz: 15, b: true, c: 'background1', algn: 'ctr' })]),
], notes: '官方:SCRAM overview 頁說 KRaft controller 之間不支援 SCRAM、broker→controller 可用;但 KRaft security 頁的寫法不同,官方文件間不一致,實測 3 個 controller 用 SCRAM-SHA-512:互相認證失敗(Invalid user credentials)、選不出 leader,與 SCRAM overview 頁一致(推測原因:SCRAM 憑證存放在 metadata log,quorum 還沒形成就無法驗證,此為推測)。主 demo 僅 1 個 controller;另以獨立實驗(spike/multi-controller:3 controller + 1 broker,SASL_PLAINTEXT)驗證 PLAIN:三個 voter 組成 quorum,停掉 leader 後重新選舉、重啟後回到 follower 無 lag,未驗證搭配 TLS / RBAC。另:官方 MDS 設定頁說 RBAC 下 controller 應設 confluent.metadata.server.kraft.controller.enabled=true,且只有 MDS writer broker 連 LDAP;本專案原以為 controller 需要 ldap.*,重建環境後重測已推翻:無 LDAP 的 controller 仍能依群組授權(ch11 通過),現採官方設定。' });

// Broker
add({ title: 'Broker:三個入口,各管一件事', items: [
  tint(0.6, 1.55, 2.3, 4.3, HUM), ...badge('FaServer', 1.15, 1.75, 1.2, HUM), text(0.6, 3.1, 2.3, 0.5, [P('broker', { sz: 20, b: true, algn: 'ctr', c: HUM })]),
  text(0.7, 3.65, 2.1, 1.6, [P('ConfluentServerAuthorizer', { sz: 11, algn: 'ctr', ...MUTE, after: 4 }), P('Kafka 埠不要求 client 憑證(MDS 才要求)', { sz: 10.5, algn: 'ctr', ...MUTE, after: 4 })]),
  ...[['INTERNAL 9092', 'SASL_SSL · SCRAM-SHA-512', 'broker ↔ broker\ncontroller → broker', PLT, 'FaNetworkWired'], ['CLIENT 9094', 'SASL_SSL · PLAIN+LDAP / SCRAM / OAUTHBEARER(帶 MDS token)', '人 · 服務 · token', HUM, 'FaUsers'], ['MDS 8091', 'HTTPS · Basic(LDAP)/ Bearer / client 憑證(REQUESTED)', 'C3 · REST Proxy · 管理 API', MDS, 'FaShieldAlt']].flatMap(([n, p, who, col, ic], i) => {
    const y = 1.55 + i * 1.5;
    return [arrow(2.9, 3.7, 3.4, y + 0.65, col, { w: 1.75 }), tint(3.4, y, 9.33, 1.3, col, { round: 0.06 }), ...badge(ic, 3.55, y + 0.3, 0.7, col),
      text(4.45, y + 0.12, 3.4, 0.45, [P(n, { sz: 17, b: true, c: col })]), text(4.45, y + 0.65, 8.1, 0.55, [P(p, { sz: 13, b: true })]), text(9.0, y + 0.12, 3.6, 0.45, [P(who, { sz: 12, algn: 'r', ...MUTE })])];
  }),
  chip('內部通道不走 AD、不走 mTLS(AD 不含服務帳號、憑證不另發)→ 身分由帳號提供:INTERNAL 用 SCRAM、CONTROLLER 用 PLAIN;LDAP callback 只掛 CLIENT', 0.6, 6.1, 8.3, RISK, { sz: 11, h: 0.6 }), chip('防火牆:9092 只開給 broker / controller 節點', 9.05, 6.1, 3.68, RISK, { sz: 11.5, h: 0.6 }),
], notes: '人用 SASL/PLAIN,broker 把帳密交給 LDAP(AD)驗證密碼;登入時不查群組,群組由 MDS writer 定期從 AD 同步,授權時依帳號名稱查本地快取(實測);服務用 SCRAM;平台元件用 OAUTHBEARER(MDS token)。INTERNAL 埠的使用者:broker 間用 kafka-broker;controller 連 broker(讀 RBAC 資料、audit 匯出)用 kafka-controller,皆為 SCRAM 與 super user。LDAP callback 不用在 inter-broker:客戶 AD 沒有服務帳號,官方也不建議 PLAIN + LDAP。INTERNAL 埠只是另一個 SASL 埠,任何有效 SCRAM 帳號都能「認證」進去(授權仍生效),所以必須用防火牆限制。' });

// MDS
add({ title: 'MDS:RBAC 的中樞(內嵌於 broker)', items: [
  ...[['FaUserCog', '管理者', '在 C3 或 API 指派 role binding', INK], ['FaShieldAlt', 'MDS', '認證:Basic(AD)· MDS token(Bearer)· client 憑證(mTLS)\n換 token · 管理 RBAC', MDS], ['FaDatabase', 'RBAC topic', 'role binding 與使用者→群組', SVC], ['FaServer', '每台 broker', '讀取並 cache,本地授權', PLT]].flatMap(([ic, t, s, col], i) => node(0.6 + i * 3.1, 1.55, 2.75, 2.1, { icon: ic, title: t, sub: s, col, ssz: 11.5 })),
  arrow(3.35, 2.6, 3.7, 2.6, 'text1'), arrow(6.45, 2.6, 6.8, 2.6, 'text1'), arrow(9.55, 2.6, 9.9, 2.6, 'text1'),
  ...node(3.7, 4.0, 2.75, 2.2, { icon: 'FaUsers', title: 'AD(LDAP)', sub: '唯讀 bind 帳號:搜尋使用者、定期查群組\n驗密碼:用使用者自己的 DN + 密碼 simple bind', col: HUM, ssz: 11.5 }), arrow(5.07, 3.65, 5.07, 4.0, HUM, { w: 2.5 }), text(5.15, 3.68, 1.4, 0.3, [P('查詢 / bind', { sz: 10, b: true, c: HUM })]),
  tint(6.8, 4.0, 5.93, 2.2, MDS), text(7.0, 4.1, 5.5, 0.4, [P('重點', { sz: 15, b: true, c: MDS })]),
  text(7.0, 4.5, 5.55, 1.7, [P('•  群組異動在 AD 做,Kafka 端零變更;由一台 broker 擔任 writer 向 AD 查群組(預設 60 秒;demo 5 秒),寫入 RBAC topic,其他 broker 讀取後更新快取', { sz: 10.5, after: 3 }), P('•  人:Basic(AD 帳密)經 MDS 向 AD 驗證;各 broker 都連 AD,需匯入 AD 的 LDAPS CA root', { sz: 10.5, after: 3 }), P('•  機器 / 平台元件:client 憑證(mTLS)→ CN 對映成主體 → 向 MDS 換 token;憑證主體只能綁 User:(不支援群組)', { sz: 10.5, after: 3 }), P('•  token:JWT,壽命可設(demo 設 1 小時);元件自動重新換;刪除 AD 帳號後,舊 token 到期前仍有效(實測)', { sz: 10.5 })]),
  tint(0.6, 4.0, 2.75, 2.2, RISK), ...badge('FaExclamationTriangle', 1.55, 4.15, 0.6, RISK), text(0.7, 4.85, 2.55, 1.3, [P('需要 AD 唯讀查詢帳號', { sz: 12.5, b: true, c: RISK, algn: 'ctr', after: 3 }), P('bind DN;不要用真人帳號;建議 LDAPS', { sz: 11, algn: 'ctr', ...MUTE })]),
], notes: '官方:MDS 在異動 RBAC 時把最新資訊寫入 topic,broker 讀取後 cache 在本地授權;群組同步只有 MDS writer broker 週期性向 LDAP 取(實測:LDAP 日誌同一時間只有 writer 查詢,broker2 重啟後 writer 換成 broker1;writer 把使用者→群組寫進 _confluent-metadata-auth,內容含 RoleBinding、User(群組對照)、Status(writerBrokerId),其他 broker 消費該 topic 更新本地快取;leader 在非 writer 的 partition 上,加入群組 3 秒內生效、移出約 6 秒)。注意:使用者認證(MDS 以使用者帳密 bind、CLIENT 埠 PLAIN+LDAP callback)由各 broker 自己連 AD,所以 AD 防火牆來源要涵蓋所有 broker(controller 不需要 LDAP 設定,實測)。客戶前提:需要 AD 唯讀查詢帳號(bind DN,只讀 user/group OU,建議 LDAPS);使用者密碼由 simple bind 以使用者自己的 DN 驗證。token:平台元件(C3、REST Proxy 自己的工作)由 client 函式庫重新換 token,不需人工;人用 C3 登入有 6 小時上限,到期重新登入;實測從 AD 刪除使用者後,已簽發 token 仍可呼叫 MDS(200),Basic 重新登入回 401,離職流程要考慮最長一個 token 壽命的空窗(demo 設 1 小時;設定 confluent.metadata.server.token.max.lifetime.ms)。writer 是什麼:MDS 內嵌在多台 broker,但同一時間只有一台 broker 擔任 writer(RBAC topic 的 Status 記錄會寫 writerBrokerId 與 generationId;實測 broker2 重啟後 writer 由 broker2 換成 broker1)。實測 LDAP 日誌:群組搜尋只由 writer 發出,結果寫進 RBAC topic,其他 broker 消費該 topic 更新快取。writer 的挑選方式與角色綁定寫入是否一律經過 writer,未驗證。人登入的 LDAP 流程(實測,PLAIN+LDAP 與 MDS Basic 皆相同):先用唯讀 bind 帳號搜尋使用者取得完整 DN,再用使用者自己的 DN 與密碼做一次 simple bind,成功即密碼正確,然後斷線。MDS 的 Bearer 是 MDS 自己簽發的 token(JWT),不是外部 OAuth2 token;Kafka 的 OAUTHBEARER 只是攜帶這個 token 的機制名稱。機器 / 平台元件以 client 憑證向 MDS 認證(MDS 設 REQUESTED,所以人 Basic 與機器憑證可並存),憑證 CN 經對映規則成為主體,只能用 User: 綁 role(官方 mTLS RBAC 頁:憑證主體不支援群組授權);REST Proxy 另可用自己的憑證代機器呼叫 /impersonate 申請 token(需列入 impersonation super users)。MDS 簽發的 token 不含群組:實測 yujie、gary 的 token 只有 jti、iss、sub、exp、iat、nbf、azp、auth_time;PLAIN+LDAP 登入也只驗證密碼、不查群組。授權時 broker 用主體名稱查 writer 同步進 RBAC topic 的群組對照快取(實測:只綁 Group:kafka-developers,yujie 不需任何個別設定就能讀取;移除綁定即被拒),所以才需要 writer 定期向 AD 同步。官方文件對 MDS 自簽 token 是否含群組沒有說明,以上為實測觀察。' });

// AD 群組 → role
const yes = (x, y) => icon('FaCheckCircle', x, y, 0.4, PLT), no = (x, y) => icon('FaTimesCircle', x, y, 0.4, 'text1');
const GR = [['kafka-developers', 'DeveloperRead / Write(orders. 前綴)', [1, 1, 0, 0]], ['kafka-readonly', 'DeveloperRead', [1, 0, 0, 0]], ['kafka-ops', 'Operator + DeveloperManage(infra. 前綴)', [0, 0, 1, 0]], ['kafka-rbac-admins', 'UserAdmin', [0, 0, 0, 1]], ['kafka-admins', 'SystemAdmin(break-glass)', [1, 1, 1, 1]]];
add({ title: 'AD 群組 → role:依職責分層授權', items: [
  ...['讀資料', '寫資料', '管 topic(建/刪)', '改授權'].map((h, i) => text(6.15 + i * 1.65, 1.5, 1.65, 0.5, [P(h, { sz: 12, b: true, algn: 'ctr', c: INK })])),
  ...GR.flatMap(([g, r, v], i) => {
    const y = 2.05 + i * 0.72, col = i === 4 ? RISK : (i === 1 ? HUM : (i === 0 ? SVC : (i === 2 ? PLT : MDS)));
    return [tint(0.6, y, 11.95 + 0.0, 0.62, col, { round: 0.12 }), text(0.8, y + 0.04, 2.5, 0.5, [P(g, { sz: 13, b: true, c: col })], { anchor: 'ctr' }), text(3.1, y + 0.04, 3.1, 0.55, [P(r, { sz: 10.5, ...MUTE })], { anchor: 'ctr' }),
      ...v.map((ok, j) => (ok ? yes : no)(6.15 + j * 1.65 + 0.62, y + 0.11))];
  }),
  ...['AD 加入群組', '做事', 'AD 移出群組', 'audit 全程留痕'].map((t, i) => [i < 3 ? arrow(0.6 + i * 3.05 + 2.65, 5.95, 0.6 + (i + 1) * 3.05, 5.95, 'text1', { w: 2 }) : null, box(0.6 + i * 3.05, 5.65, 2.65, 0.6, { fill: i === 3 ? INK : HUM, tint: i === 3 ? 0 : 0.85, line: i === 3 ? INK : HUM, round: 0.4, paras: [P(t, { sz: 14, b: true, c: i === 3 ? 'background1' : HUM, algn: 'ctr' })] })]).flat().filter(Boolean),
  text(0.6, 6.4, 12.13, 0.4, [P('臨時提權:依單據加進 kafka-ops / kafka-rbac-admins,做完移出;移出後最長約 60 秒(預設刷新)才收回,Kafka 端零變更', { sz: 12, algn: 'ctr', ...MUTE })]),
], notes: '權限放在 Kafka(RBAC + AD 群組);維運選單/腳本只是操作介面,以操作者本人身分執行。DeveloperManage 不能改 topic 設定;要改設定需 ResourceOwner 或 ClusterAdmin(叢集範圍、無讀寫)。UserAdmin 理論上可替自己授權,人數最少、臨時提權、audit 必看。' });

// Confluent 內建角色與 scope
const CL = [['SystemAdmin', '全部權限(含改授權);break-glass'], ['UserAdmin', '管理授權(role binding),不碰資料'], ['ClusterAdmin', '叢集與 topic 設定,不能讀寫資料'], ['Operator', '營運與監控,不能建 topic、不能讀寫'], ['SecurityAdmin', '只檢視授權設定,不能改'], ['AuditAdmin', '管理稽核(audit)設定']];
const RS = [['ResourceOwner', '對該資源全權(含授權該資源)'], ['DeveloperRead', '讀 topic、加入 consumer group'], ['DeveloperWrite', '寫 topic(含 idempotent 寫入)'], ['DeveloperManage', '管理資源(建 / 刪 topic),不能改設定']];
const roleRows = (rows, y0, col) => rows.flatMap(([n, d], i) => [chip(n, 0.6, y0 + i * 0.42, 1.85, col, { sz: 11, h: 0.34 }), text(2.55, y0 + i * 0.42 + 0.02, 3.95, 0.34, [P(d, { sz: 11 })], { anchor: 'ctr' })]);
add({ title: 'Confluent 內建角色與 scope', items: [
  tint(0.45, 1.45, 6.2, 2.9, MDS, { round: 0.03, lw: 1 }), text(0.6, 1.5, 6, 0.32, [P('叢集範圍(Cluster scope):綁在整個叢集', { sz: 12.5, b: true, c: MDS })]), ...roleRows(CL, 1.88, MDS),
  tint(0.45, 4.45, 6.2, 2.15, SVC, { round: 0.03, lw: 1 }), text(0.6, 4.5, 6, 0.32, [P('資源範圍(Resource scope):綁在指定資源', { sz: 12.5, b: true, c: SVC })]), ...roleRows(RS, 4.88, SVC),
  white(6.9, 1.45, 5.83, 5.15, HUM, { round: 0.03, lw: 1.5 }), text(7.05, 1.5, 5.5, 0.32, [P('scope 圖:role binding 綁在哪一層', { sz: 12.5, b: true, c: HUM })]),
  tint(7.1, 1.9, 5.43, 4.0, PLT, { round: 0.04, lw: 1.25 }), text(7.25, 1.95, 5.2, 0.3, [P('① Kafka 叢集(scope = 叢集 ID)', { sz: 12, b: true, c: PLT })]),
  box(7.3, 2.3, 5.03, 0.55, { fill: MDS, tint: 0.85, line: MDS, lw: 1, round: 0.2, paras: [P('叢集範圍角色綁這層 → 整個叢集都適用', { sz: 11.5, b: true, c: MDS, algn: 'ctr' })], ins: 0.05 }),
  text(7.25, 2.95, 5.2, 0.3, [P('② 叢集裡的資源 + 比對方式', { sz: 12, b: true, c: SVC })]),
  ...[['Topic', 'orders.  (PREFIXED)'], ['Topic', 'infra.  (PREFIXED)'], ['Group', 'demo-  (PREFIXED)'], ['Topic', 'orders.events  (LITERAL)']].flatMap(([a, b], i) => box(7.3 + (i % 2) * 2.57, 3.3 + Math.floor(i / 2) * 0.75, 2.46, 0.62, { fill: SVC, tint: 0.88, line: SVC, lw: 1, round: 0.15, paras: [P(a, { sz: 10.5, b: true, c: SVC, algn: 'ctr' }), P(b, { sz: 10.5, algn: 'ctr' })], ins: 0.03 })),
  text(7.25, 4.85, 5.2, 0.9, [P('資源範圍角色綁「資源類型 + 名稱 + 比對方式」', { sz: 11, b: true, after: 2 }), P('LITERAL = 名稱完全相同;PREFIXED = 名稱開頭相同', { sz: 10.5, ...MUTE })]),
  text(7.05, 5.95, 5.5, 0.28, [P('本專案的例子', { sz: 11, b: true, ...MUTE })]),
  chip('ops → Operator @ 叢集', 7.05, 6.2, 2.3, MDS, { sz: 10, h: 0.34 }), chip('ops → DeveloperManage @ infra.', 9.45, 6.2, 3.1, SVC, { sz: 10, h: 0.34 }),
], notes: '角色與範圍來自本 demo 的 MDS(GET /security/1.0/roles)實際回傳:叢集範圍(scopeType=Cluster):SystemAdmin、UserAdmin、ClusterAdmin、Operator、SecurityAdmin、AuditAdmin;資源範圍(scopeType=Resource):ResourceOwner、DeveloperRead、DeveloperWrite、DeveloperManage。權限細節為本專案實測:DeveloperManage 不能 AlterConfigs;ClusterAdmin 可改 topic 設定但不能讀寫;Operator 不能建 topic;IdempotentWrite 只包含在 DeveloperWrite / ResourceOwner。scope 的意思:role binding 綁在「哪個叢集」(叢集範圍角色),或綁在叢集內「哪個資源」(資源類型 + 名稱 + LITERAL / PREFIXED)。' });

// 服務帳號
add({ title: '服務帳號:SCRAM,不放 AD', items: [
  ...[['建立', 'kafka-configs 在 Kafka 內建立', 'FaPlus'], ['保管', '密碼放密碼庫', 'FaLock'], ['授權', 'RBAC 綁 User:svc-x\n前綴最小權限', 'FaUserShield'], ['使用', 'client 設定檔\n權限 600', 'FaFileCode'], ['輪替', '同帳號改密碼\n→ client 換新密碼', 'FaSyncAlt']].flatMap(([t, s, ic], i) => {
    const x = 0.6 + i * 2.48;
    return [...step(i + 1, x, 1.6, 2.2, 2.1, t, s, SVC), i < 4 ? arrow(x + 2.2, 2.65, x + 2.48, 2.65, SVC, { w: 2 }) : null];
  }).filter(Boolean),
  tint(0.6, 3.9, 3.85, 1.2, SVC), ...badge('FaIdBadge', 0.8, 4.1, 0.7, SVC), text(1.65, 4.0, 2.7, 1.1, [P('帳密存在 Kafka(KRaft)內', { sz: 13, b: true, after: 4 }), P('不在 AD', { sz: 12, ...MUTE })]),
  tint(4.65, 3.9, 3.85, 1.2, RISK), ...badge('FaExclamationTriangle', 4.85, 4.1, 0.7, RISK), text(5.7, 4.0, 2.7, 1.1, [P('密碼不會自動到期', { sz: 13, b: true, c: RISK, after: 4 }), P('要有輪替流程與提醒', { sz: 12, ...MUTE })]),
  tint(8.7, 3.9, 4.03, 1.2, HUM), ...badge('FaLock', 8.9, 4.1, 0.7, HUM), text(9.75, 4.0, 2.9, 1.1, [P('官方:SCRAM 搭配 TLS', { sz: 13, b: true, after: 4 }), P('KRaft 放在私有網路', { sz: 12, ...MUTE })]),
  ...['① Kafka 端改密碼', '② client 換新密碼並重啟', '③ 驗證新密碼可用', '④ 驗證舊密碼已失效'].flatMap((s, i) => [chip(s, 0.6 + i * 3.13, 5.3, 2.75, SVC, { sz: 12 }), i < 3 ? arrow(0.6 + i * 3.13 + 2.75, 5.51, 0.6 + (i + 1) * 3.13, 5.51, SVC, { w: 2 }) : null].filter(Boolean)),
  solid(0.6, 5.95, 12.13, 0.9, INK, [P('同帳號改密碼 = 取代:舊密碼對新連線立即失效(實測)', { sz: 13, b: true, c: 'background1', algn: 'ctr', after: 3 }), P('已連線的 client 不受影響;改完立刻換 client,換好之前重新連線的會失敗', { sz: 11.5, c: 'background1', algn: 'ctr' })]),
], notes: '服務身分用 SASL/SCRAM-SHA-512,不放 AD(AD 沒有服務帳號)。SCRAM 的缺點是密碼無自動到期,所以配套:密碼庫與輪替流程。輪替做法(同帳號直接改密碼):①新密碼先存入密碼庫,用 bootstrap 的 SCRAM 身分執行 kafka-configs --alter --add-config SCRAM-SHA-512=[password=新密碼] --entity-type users --entity-name 帳號;②立刻讓每個 client 換成新密碼並重啟或重新載入;③用新密碼設定檔連線,確認沒有 SaslAuthenticationException 且授權正常(帳號名稱不變,RBAC 綁定不用重綁);④用舊密碼確認已被拒;出問題時再執行一次 kafka-configs 把密碼改回舊的。實測:對同一帳號同一機制再設一次密碼會直接取代,舊密碼對新連線立即失效;已連線的 client 在 Kafka 端改密碼後不受影響(45 秒後仍送出訊息,無認證錯誤),因為密碼是在連線建立時驗證。風險:在 client 換新密碼之前,任何重新連線(應用重啟、broker 重啟、leader 轉移、閒置斷線)都會失敗,所以改完要立刻換 client;若設定了 connections.max.reauth.ms(定期重新認證),已連線的 client 也會在重新認證時失敗(demo 未設定,未實測)。kafka-configs 的密碼在指令列,可能留在 shell 歷史或被 ps 看到,導入時要留意。官方(SCRAM overview 頁):SCRAM 憑證儲存在 KRaft,適用於 KRaft 位於私有網路的環境;SCRAM 只應搭配 TLS 使用。該頁沒有說明 SCRAM 密碼輪替流程,本頁的做法是依實測與客戶條件(通常不改帳號名稱)選擇。需要完全沒有風險窗口的服務,可改用新帳號並行(ch09 實測,新帳號要重綁 role),細節見 SPIKE-FINDINGS。' });

// SCRAM 輪替:特例(不能有失敗窗口)
add({ title: '特例:不能有失敗窗口的服務', items: [
  text(0.6, 1.5, 12.13, 0.35, [P('上一頁的做法,會有一段失敗窗口', { sz: 14, b: true, c: HUM })]),
  tint(0.6, 1.95, 3.2, 1.0, PLT, { round: 0.08, ins: 0.1, anchor: 'ctr', paras: [P('Kafka 端改密碼', { sz: 14, b: true, c: PLT, algn: 'ctr', after: 3 }), P('舊密碼對新連線立即失效', { sz: 11, algn: 'ctr', ...MUTE })] }),
  arrow(3.8, 2.45, 4.2, 2.45, 'text1', { w: 2.25 }),
  tint(4.2, 1.95, 5.0, 1.0, RISK, { round: 0.08, ins: 0.1, anchor: 'ctr', paras: [P('失敗窗口', { sz: 14, b: true, c: RISK, algn: 'ctr', after: 3 }), P('client 還沒換新密碼、就重新連線 → 失敗', { sz: 11.5, algn: 'ctr' })] }),
  arrow(9.2, 2.45, 9.6, 2.45, 'text1', { w: 2.25 }),
  tint(9.6, 1.95, 3.13, 1.0, PLT, { round: 0.08, ins: 0.1, anchor: 'ctr', paras: [P('client 換好新密碼', { sz: 14, b: true, c: PLT, algn: 'ctr' })] }),
  text(0.6, 3.3, 12.13, 0.35, [P('不能承受窗口的服務:改用新帳號並行(新舊同時有效)', { sz: 14, b: true, c: SVC })]),
  ...['① 建新帳號 svc-x-v2', '② 重綁相同 role', '③ client 改帳號與密碼', '④ 刪舊帳號與舊 binding'].flatMap((t, i) => [chip(t, 0.6 + i * 3.13, 3.8, 2.75, SVC, { sz: 12 }), i < 3 ? arrow(0.6 + i * 3.13 + 2.75, 4.01, 0.6 + (i + 1) * 3.13, 4.01, SVC, { w: 2 }) : null].filter(Boolean)),
  ...['舊帳號仍可使用', 'RBAC 綁的是帳號名稱', '逐步切換,新舊並存', '全部切完才刪'].map((t, i) => text(0.6 + i * 3.13, 4.3, 2.75, 0.3, [P(t, { sz: 11, algn: 'ctr', ...MUTE })])),
  chip('代價:每次輪替,client 都要改帳號名稱並重啟', 0.6, 4.95, 5.95, RISK, { sz: 12 }), chip('代價:新帳號的 role binding 要重綁', 6.78, 4.95, 5.95, RISK, { sz: 12 }),
  solid(0.6, 5.85, 12.13, 0.7, INK, [P('只有不能承受失敗窗口的服務才用;日常輪替仍用同帳號改密碼', { sz: 14, b: true, c: 'background1', algn: 'ctr' })]),
], notes: '上一頁是預設做法:同帳號直接改密碼,client 只改密碼,role binding 不動;缺點是 client 換好之前重新連線會失敗(已連線的不受影響,實測)。新帳號並行用在不能承受任何失敗窗口的服務:建立新帳號並重綁相同 role,client 改帳號與密碼並逐步切換,全部切完後刪舊帳號與舊 binding(ch09 實測;RBAC 綁的是主體名稱,所以新帳號必須重綁)。代價:每次輪替 client 都要改帳號名稱並重啟,所以不建議作為日常輪替。官方:CFK 認證管理文件對內部帳號與 MDS 的 LDAP bind 帳號的輪替使用新舊並行,該文件沒有涵蓋 SCRAM;Apache Kafka 與 Confluent 的 SCRAM 文件都沒有說明密碼輪替流程,所以兩種做法都是依實測與客戶條件做的選擇。' });

// REST Proxy
const rpLane = (y0, col, label, ic, who, l1, mdsTxt, l5) => [
  text(0.6, y0, 5, 0.32, [P(label, { sz: 14, b: true, c: col })]),
  tint(4.0, y0 + 0.38, 2.3, 0.62, MDS, { round: 0.1 }), ...badge('FaShieldAlt', 4.1, y0 + 0.46, 0.46, MDS), text(4.65, y0 + 0.46, 1.5, 0.46, [P('MDS', { sz: 14, b: true })], { anchor: 'ctr' }),
  arrow(4.75, y0 + 1.2, 4.75, y0 + 1.0, MDS, { w: 2 }), arrow(5.5, y0 + 1.0, 5.5, y0 + 1.2, MDS, { w: 2 }),
  text(6.4, y0 + 0.3, 6.3, 0.8, [P(mdsTxt, { sz: 10, b: true, c: MDS })]),
  tint(0.6, y0 + 1.2, 2.0, 0.8, col, { round: 0.1 }), ...badge(ic, 0.7, y0 + 1.33, 0.52, col), text(1.3, y0 + 1.33, 1.25, 0.52, [P(who, { sz: 13, b: true })], { anchor: 'ctr' }),
  tint(4.0, y0 + 1.2, 2.3, 0.8, col, { round: 0.1 }), ...badge('FaExchangeAlt', 4.1, y0 + 1.33, 0.52, col), text(4.7, y0 + 1.33, 1.55, 0.52, [P('REST Proxy', { sz: 13, b: true })], { anchor: 'ctr' }),
  tint(7.6, y0 + 1.2, 2.0, 0.8, col, { round: 0.1 }), ...badge('FaServer', 7.7, y0 + 1.33, 0.52, col), text(8.3, y0 + 1.33, 1.25, 0.52, [P('broker', { sz: 13, b: true })], { anchor: 'ctr' }),
  arrow(2.6, y0 + 1.6, 4.0, y0 + 1.6, col), arrow(6.3, y0 + 1.6, 7.6, y0 + 1.6, col),
  text(1.7, y0 + 2.05, 2.8, 0.3, [P(l1, { sz: 10, b: true, c: col, algn: 'ctr' })]), text(6.05, y0 + 2.05, 2.3, 0.3, [P(l5, { sz: 10, b: true, c: col, algn: 'ctr' })]),
  text(9.75, y0 + 1.3, 3.0, 0.7, [P('broker 用 MDS 公鑰驗章,\n主體 = token 的 sub', { sz: 10, b: true, c: col })]),
];
add({ title: 'REST Proxy:legacy app 的入口', items: [
  ...rpLane(1.4, HUM, '人(Postman · 手動測試)', 'FaUser', '人', 'Basic(AD 帳密)', '① REST Proxy 把 Basic 帳密轉給 MDS(/authenticate)\n② MDS 向 AD 驗證,回 token(不經 /impersonate)', 'OAUTHBEARER(帶 token)'),
  ...rpLane(3.8, SVC, '機器(legacy app)', 'FaPlug', 'legacy app', '① client 憑證(CN)→ 對映成主體', '② REST Proxy 用自己的 client 憑證(CN=restproxy)向 MDS 認證\n③ POST /impersonate:代為申請 legacy app 的 token\n④ MDS 回 token(sub = app,cp_proxy = restproxy)', '⑤ OAUTHBEARER(帶 token)'),
  chip('REST Proxy 端 ssl.client.authentication=REQUESTED:人沒有憑證、機器有憑證,兩者並存 · 憑證身分只能綁 User:', 0.6, 6.25, 12.13, PLT, { sz: 11, h: 0.38 }),
  chip('⚠ restproxy 憑證可代人 → 特權身分逐一以 User: 列入 protected.users;混入 Group: 整份失效(實測)', 0.6, 6.66, 12.13, RISK, { sz: 11, h: 0.38 }),
], notes: 'REST Proxy 是中心:它向 MDS 要 token,再帶 token 以 OAUTHBEARER 連 broker(MDS 不呼叫 broker),broker 用 MDS 公鑰驗章、以 sub 為主體授權。機器五步:legacy app 出示 client 憑證 → REST Proxy 依對映規則得到主體 → REST Proxy 用自己的憑證(CN=restproxy)向 MDS 認證並呼叫 /impersonate → MDS 回 sub=app、cp_proxy=restproxy 的 token → REST Proxy 以 OAUTHBEARER 連 broker。人 Basic 進入,REST Proxy 把帳密轉給 MDS 驗證換 token(沒有 /impersonate);機器出示 client 憑證,REST Proxy 用 AuthenticationHandler 把 DN 對映成主體,再以 restproxy 自己的憑證呼叫 MDS /impersonate 取得該主體的 token。客戶前提:人沒有 client 憑證、機器需要憑證,兩者必須並存,所以設 REQUESTED(官方 AuthenticationHandler 範例是 REQUIRED、純 mTLS);人機並存的組合為本專案實測驗證。' });

// C3
add({ title: 'Control Center:人用本人身分', items: [
  ...[['Basic 登入', '瀏覽器送 AD 帳密'], ['C3 轉給 MDS', 'MDS 向 AD 驗證'], ['回 token', 'JWT 壽命可設(demo 1 小時)\nC3 登入上限預設 6 小時'], ['之後帶 Bearer', '另有 HttpOnly cookie\n優先看 Bearer(實測)'], ['驗證', 'C3 自己的 API:\n本地驗章(實測)\n轉給 MDS 的請求:\n由 MDS 驗證']].flatMap(([t, s], i) => {
    const x = 0.6 + i * 2.48, w = 2.2;
    return [...step(i + 1, x, 1.55, w, 2.0, t, s, HUM), i < 4 ? arrow(x + w, 2.55, x + 2.48, 2.55, HUM, { w: 2 }) : null];
  }).filter(Boolean),
  tint(0.6, 3.85, 5.95, 1.5, HUM), ...badge('FaUser', 0.8, 4.0, 0.7, HUM), text(1.65, 3.95, 4.8, 1.5, [P('使用者操作', { sz: 15, b: true, c: HUM, after: 3 }), P('C3 帶「使用者本人」的 token 連 broker', { sz: 12.5, after: 2 }), P('audit 主體 = User:gary / ming', { sz: 11.5, ...MUTE })]),
  tint(6.78, 3.85, 5.95, 1.5, SVC), ...badge('FaCogs', 6.98, 4.0, 0.7, SVC), text(7.83, 3.95, 4.8, 1.5, [P('C3 背景工作', { sz: 15, b: true, c: SVC, after: 3 }), P('c3 憑證向 MDS 換 token = User:c3', { sz: 12.5, after: 2 }), P('官方要求 SystemAdmin', { sz: 11.5, ...MUTE })]),
  chip('RBAC 下 C3 連 Kafka 只支援 OAUTHBEARER(官方)', 0.6, 5.75, 5.95, PLT, { sz: 12 }), chip('c3 憑證 = 管理員:拿掉權限 C3 會退出(實測)', 6.78, 5.75, 5.95, RISK, { sz: 12 }),
  text(0.6, 6.35, 12.13, 0.5, [P('「使用者操作帶使用者身分」是本專案實測;官方未明說 C3 以誰的身分查詢 Kafka', { sz: 11.5, algn: 'ctr', ...MUTE })]),
], notes: '登入時瀏覽器第一個呼叫帶 Basic(C3 代轉 MDS),之後都帶 Bearer;同時有 HttpOnly auth_token cookie,伺服器優先看 Bearer。C3 自己的 API(例如 /2.0/clusters/kafka)在本地用 MDS 公鑰驗章:偽造或沒有簽章的 token,C3 直接回 401,MDS 的請求日誌(io.confluent.rest-utils.requests)沒有任何對應請求;有效 token 才會再以使用者 token 呼叫 MDS 查可見範圍(lookup/.../visibility)。但經 C3 轉給 MDS 的路徑(/api/metadata/security/1.0/...,例如在 C3 改 role binding)C3 不先驗章:同樣的偽造 token 會被轉給 MDS,由 MDS 回 401(實測,2026-10-05)。所以在 C3 改 role binding 時,驗證 token 的是 MDS。登入 session 上限由 confluent.controlcenter.auth.bearer.token.max.lifetime.ms 控制(官方:預設 6 小時、上限 24 小時、須不小於 MDS 的 token 壽命)。C3 自己的背景工作用 c3 憑證換 token,拿掉 SystemAdmin 後 Streams/license 立即授權失敗,約 1 分鐘後容器退出(實測)。' });

// Prometheus / Alertmanager:四條連線
add({ title: 'C3 周邊:Prometheus · Alertmanager', items: [
  ...node(0.6, 1.5, 3.0, 1.85, { icon: 'FaServer', title: 'broker 1 / 2', sub: 'telemetry exporter', col: PLT }),
  ...node(5.2, 1.5, 3.0, 1.85, { icon: 'FaChartLine', title: 'Prometheus', sub: '指標 · 9090', col: SVC }),
  ...node(9.73, 1.5, 3.0, 1.85, { icon: 'FaBell', title: 'Alertmanager', sub: '告警 · 靜音 · 9093', col: SVC }),
  ...node(5.2, 3.95, 3.0, 1.5, { icon: 'FaDesktop', title: 'Control Center', sub: 'next-gen', col: HUM }),
  arrow(3.6, 2.4, 5.2, 2.4, PLT, { w: 2.5 }), text(3.65, 1.85, 1.5, 0.3, [P('① 推指標', { sz: 12, b: true, algn: 'ctr', c: PLT })]), text(3.65, 2.5, 1.5, 0.3, [P('HTTPS + Basic', { sz: 10, algn: 'ctr', ...MUTE })]),
  arrow(8.2, 2.4, 9.73, 2.4, SVC, { w: 2.5 }), text(8.25, 1.85, 1.45, 0.3, [P('② 送告警', { sz: 12, b: true, algn: 'ctr', c: SVC })]), text(8.25, 2.5, 1.45, 0.3, [P('HTTPS + Basic', { sz: 10, algn: 'ctr', ...MUTE })]),
  arrow(6.7, 3.95, 6.7, 3.35, HUM, { w: 2.5 }), text(6.8, 3.45, 1.7, 0.3, [P('③ 查指標 · 重載規則', { sz: 12, b: true, c: HUM })]), text(6.8, 3.7, 1.7, 0.25, [P('HTTPS + Basic', { sz: 10, ...MUTE })]),
  arrow(8.2, 4.55, 11.2, 3.35, HUM, { w: 2.5 }), text(9.55, 4.25, 2.6, 0.3, [P('④ 狀態 · 重載設定', { sz: 12, b: true, c: HUM })]), text(9.55, 4.5, 2.6, 0.25, [P('HTTPS + Basic', { sz: 10, ...MUTE })]),
  chip('用 Basic 不用 mTLS:客戶希望憑證越少越好,不另發 client 憑證', 0.6, 5.65, 5.95, PLT, { sz: 11 }), chip('SAN 要補 prometheus、alertmanager(實測:否則主機名稱驗證失敗)', 6.78, 5.65, 5.95, RISK, { sz: 11 }),
  chip('Prometheus 的 alerting 要設 https + 帳密 + CA(官方頁未寫,實測必要)', 0.6, 6.2, 5.95, SVC, { sz: 11 }), chip('C3 日誌會印出 Basic 標頭(Base64 即帳密)→ 日誌要保護', 6.78, 6.2, 5.95, RISK, { sz: 11 }),
], notes: 'C3 next-gen 需要 Prometheus 與 Alertmanager 另外部署。官方支援 C3 與它們之間的 TLS + HTTP Basic(7.5 以後)與 mTLS。本頁是在 demo 實測啟用 TLS + Basic 的結果(spike/c3-monitoring-tls,用 override 檔啟用,帳密為 demo 測試值):①broker 推指標:telemetry exporter 的 base url 改 https,api.key / api.secret 就是 Prometheus 的 Basic 帳密,另設信任庫(confluent.telemetry.exporter.<名稱>.https.ssl.truststore.*);實測 Prometheus 的 OTLP 端點回 200,兩台 broker 的指標都進來。未更新的 broker 仍用 HTTP,Prometheus 日誌是 client sent an HTTP request to an HTTPS server。②Prometheus 送告警給 Alertmanager:必須在 Prometheus 的設定檔 alerting 區段設 scheme: https、basic_auth、tls_config.ca_file;官方 TLS + Basic 頁沒有寫這一段,對照實測:沒設時日誌是 Error sending alerts … bad response status 400,Alertmanager 一筆都沒收到;設了之後測試告警送達。③C3 查 Prometheus:confluent.controlcenter.prometheus.url 改 https、ssl.truststore.*、basic.auth.user.info;實測 C3 總覽畫面有指標、查詢計數持續增加(PKCS12 信任庫可用)。④C3 連 Alertmanager:alertmanager.url 改 https + 同樣兩項;C3 的狀態 API 回 ONLINE,故意改錯密碼則變 OFFLINE。web-config 檔(Prometheus --web.config.file):tls_server_config 放共用 server 憑證與私鑰,basic_auth_users 放 bcrypt 雜湊(htpasswd -B 可產生)。共用 server 憑證的 SAN 原本沒有 prometheus 與 alertmanager,openssl 驗證主機名稱 prometheus 回 hostname mismatch;用同一把 key、同一個 CA 重簽、SAN 補上這兩個名稱後通過,所以導入時共用憑證的 SAN 要涵蓋 Prometheus 與 Alertmanager 的主機名稱。未啟用時(demo 預設)實測:不帶憑證可讀指標,Alertmanager 可無認證建立與刪除靜音;啟用後,無帳密與錯誤密碼都是 401,無帳密建立靜音也是 401。C3 畫面建立 trigger 與 email action 已實測:C3 把 trigger 寫成 Prometheus 規則檔(trigger_rules-generated.yml)並通知 Prometheus 重新載入,由 Prometheus 評估並送告警給 Alertmanager;action 寫進 alertmanager-generated.yml(receiver 與依 alertname 的路由),再對 Alertmanager 發 POST /-/reload(帶 Basic),實測重新載入成功、Alertmanager 執行中的設定出現新 receiver。C3 沒有靜音功能(告警區只有 Overview、History、Triggers、Actions),靜音只能直接對 Alertmanager 的 API 操作。C3 的 INFO 日誌會印出請求標頭,包含 Authorization: Basic(Base64 解開即帳密),日誌檔需要保護。未驗證:C3 建立的 trigger 實際觸發並寄出通知(demo 用假的 SMTP)、mTLS 做法、confluent.controlcenter.*.alias.name 的作用(本實測沒設也能運作)。demo 映像的 Prometheus 設定檔是靜態檔,實際安裝套件是否由 C3 自動產生 alerting 設定,未驗證。沒有 Schema Registry 時,C3 預設連 localhost:8081,把 schema.registry.enable 設為 false 可關閉該連線。 為什麼用 Basic 不用 mTLS:官方兩種都支援(TLS + Basic 自 7.5,另有 mTLS 設定頁);依客戶前提(憑證越少越好),mTLS 要替 broker、C3、Prometheus、Alertmanager 各發 client 憑證,Basic 只要帳號密碼,所以選 Basic;帳密的代價見下。防火牆:Prometheus 9090 要開給 broker(推指標)與 C3;Alertmanager 9093 要開給 C3 與 Prometheus(送告警);這四條以外不用開。新增的要管理項目:Prometheus 與 Alertmanager 各一組 Basic 帳密(demo 用同名 c3),bcrypt 雜湊在 web-config,明文放在 broker 設定(api.secret)與 C3 設定(basic.auth.user.info),輪替流程未驗證,應列入「要管理的憑證與帳號」清單;共用 server 憑證的私鑰也要放到 Prometheus 與 Alertmanager 的主機,私鑰的存放處變多,外洩風險範圍變大。Basic 沒有唯讀與寫入的分級:broker、C3 查指標、C3 重載規則都用同一組帳密(官方也沒有提供分級)。未驗證:KRaft controller 是否也要設 telemetry exporter(demo 的 controller 沒設,正式環境有 3 個 controller)、Prometheus 與 Alertmanager 更換共用憑證時是否要重啟、email 告警帶 SMTP 帳密時帳密如何寫進 alertmanager-generated.yml、帶 Basic 的使用者能否呼叫 Prometheus 的 /-/quit(映像啟動時有開 --web.enable-lifecycle)、人用瀏覽器直接開 Prometheus 或 Alertmanager 網頁的體驗。' });

// Audit
add({ title: 'Audit log:誰被拒、誰改了授權', items: [
  ...node(0.6, 1.55, 3.85, 2.55, { icon: 'FaClipboardList', title: '官方預設', sub: 'Management + Authorize\n含 allowed 與 denied\n→ confluent-audit-log-events', col: MDS, tsz: 16, ssz: 12 }),
  ...node(4.73, 1.55, 3.85, 2.55, { icon: 'FaSlidersH', title: '自訂 router', sub: '依 topic 前綴記錄 produce / consume\n/ describe 的「被拒」事件\n被允許的 consume 不記(避免洗版)', col: PLT, tsz: 16, ssz: 12 }),
  ...node(8.86, 1.55, 3.87, 2.55, { icon: 'FaExclamationTriangle', title: '查不到的', sub: '部分拒絕(例:缺 IdempotentWrite)\nREST Proxy 的 actingPrincipal 為空', col: RISK, tsz: 16, ssz: 12 }),
  arrow(4.45, 2.8, 4.73, 2.8, 'text1'), arrow(8.58, 2.8, 8.86, 2.8, 'text1'),
  chip('能看到:誰被拒(需自訂 router)', 0.6, 4.45, 6.0, PLT, { sz: 12.5 }), chip('能看到:誰嘗試改授權(DENIED)', 6.73, 4.45, 6.0, PLT, { sz: 12.5 }),
  chip('共用帳號 → audit 只剩一個名字;個人身分 → 看得到是誰', 0.6, 5.05, 12.13, HUM, { sz: 12.5 }),
  chip('⚠ 不能假設所有拒絕都查得到:稽核需求要另外盤點', 0.6, 5.65, 12.13, RISK, { sz: 13 }), chip('官方建議:produce / consume 只對最敏感的 topic 開;audit 送到另一個叢集、依法遵保存', 0.6, 6.2, 12.13, PLT, { sz: 12 }),
], notes: '官方預設:Management 與 Authorize 兩類事件(含 allowed/denied);produce、consume、describe、interbroker、heartbeat 預設關閉。本 demo 用自訂 router 開啟資料面事件。實測:只有 DeveloperRead 的 ming produce 被拒(叢集層級 IdempotentWrite,官方歸 PRODUCE 類 kafka.InitProducerId),audit 查不到,原因未明;本 demo 的 router 只排除 kafka-broker 與 kafka-controller 兩個內部身分,c3 不排除(曾觀察到記錄 allowed 事件時 C3 每幾秒產生 ListOffsets/OffsetFetch 而洗版審計 topic;現行 router 不記被允許的 consume)。' });

add({ layout: 'SECTION', title: '整合起來', subtitle: '全景 · 人與機器的完整路徑 · 要管理的憑證 · 導入步驟 · 風險', items: [], notes: '' });

// 全景圖
add({ title: '全景整合圖', items: [
  tint(0.5, 1.45, 2.8, 2.15, HUM), ...badge('FaUsers', 0.65, 1.6, 0.7, HUM), text(1.45, 1.6, 1.8, 0.7, [P('人', { sz: 18, b: true, c: HUM })], { anchor: 'ctr' }), text(0.65, 2.45, 2.55, 1.1, [P('gary · yujie · ming', { sz: 12, b: true, after: 3 }), P('瀏覽器 · CLI · Postman', { sz: 11, ...MUTE }), P('身分來自 AD', { sz: 11, b: true, c: HUM })]),
  tint(0.5, 3.9, 2.8, 2.2, SVC), ...badge('FaCogs', 0.65, 4.05, 0.7, SVC), text(1.45, 4.05, 1.8, 0.7, [P('機器', { sz: 18, b: true, c: SVC })], { anchor: 'ctr' }), text(0.65, 4.9, 2.55, 1.2, [P('應用(SCRAM)', { sz: 12, b: true, after: 3 }), P('legacy app(client 憑證)', { sz: 12, b: true, after: 3 }), P('SCRAM 連 Kafka;憑證連 REST Proxy', { sz: 10.5, b: true, c: SVC })]),
  tint(3.95, 1.45, 2.55, 4.65, 'accent4'), text(3.95, 1.52, 2.55, 0.4, [P('入口', { sz: 15, b: true, algn: 'ctr', c: 'accent4' })]),
  white(4.15, 2.0, 2.15, 1.25, 'accent4', { round: 0.08, paras: [P('Control Center', { sz: 13, b: true, algn: 'ctr', after: 3 }), P('人:Basic → token', { sz: 10.5, algn: 'ctr', ...MUTE })] }),
  white(4.15, 3.45, 2.15, 1.25, 'accent4', { round: 0.08, paras: [P('REST Proxy', { sz: 13, b: true, algn: 'ctr', after: 3 }), P('人:Basic\nlegacy app:憑證', { sz: 10.5, algn: 'ctr', ...MUTE })] }),
  white(4.15, 4.9, 2.15, 1.05, 'accent4', { round: 0.08, paras: [P('CLIENT 9094', { sz: 13, b: true, algn: 'ctr', after: 3 }), P('CLI:PLAIN+LDAP\n應用:SCRAM', { sz: 10.5, algn: 'ctr', ...MUTE })] }),
  arrow(3.3, 2.7, 3.95, 2.7, HUM, { w: 3 }), arrow(3.3, 5.0, 3.95, 5.0, SVC, { w: 3 }),
  tint(7.1, 1.45, 3.9, 4.65, PLT), text(7.3, 1.52, 3.5, 0.4, [P('Kafka 叢集', { sz: 15, b: true, c: PLT })]),
  white(7.3, 2.0, 1.65, 1.3, MDS, { round: 0.08, paras: [P('broker 1', { sz: 13, b: true, algn: 'ctr' }), P('+ MDS', { sz: 12, b: true, algn: 'ctr', c: MDS })] }), white(9.05, 2.0, 1.75, 1.3, MDS, { round: 0.08, paras: [P('broker 2', { sz: 13, b: true, algn: 'ctr' }), P('+ MDS', { sz: 12, b: true, algn: 'ctr', c: MDS })] }),
  white(7.3, 3.55, 3.5, 0.8, PLT, { round: 0.08, paras: [P('controller(正式 3 個)', { sz: 12.5, b: true, algn: 'ctr' })] }),
  white(7.3, 4.6, 3.5, 1.25, MDS, { round: 0.08, paras: [P('RBAC 授權', { sz: 13, b: true, algn: 'ctr', c: MDS, after: 3 }), P('topic:_confluent-metadata-auth', { sz: 10.5, algn: 'ctr', ...MUTE }), P('broker 本地 cache', { sz: 10.5, algn: 'ctr', ...MUTE })] }),
  arrow(6.5, 3.75, 7.1, 3.75, 'text1', { w: 3 }),
  tint(11.6, 1.45, 1.25, 1.9, HUM), ...badge('FaUsers', 11.88, 1.6, 0.7, HUM), text(11.6, 2.45, 1.25, 0.8, [P('AD', { sz: 14, b: true, algn: 'ctr', c: HUM }), P('LDAP', { sz: 11, algn: 'ctr', ...MUTE })]),
  arrow(11.0, 2.4, 11.6, 2.4, HUM, { w: 2.5 }),
  tint(11.6, 3.7, 1.25, 2.4, SVC), ...badge('FaChartLine', 11.88, 3.85, 0.7, SVC), text(11.6, 4.65, 1.25, 1.3, [P('Prometheus', { sz: 10, b: true, algn: 'ctr', c: SVC }), P('Alertmanager', { sz: 10, b: true, algn: 'ctr', c: SVC }), P('(C3 用)', { sz: 10, algn: 'ctr', ...MUTE })]),
  chip('人', 0.5, 6.35, 1.0, HUM, { h: 0.42, sz: 11 }), chip('機器 / 服務', 1.65, 6.35, 1.7, SVC, { h: 0.42, sz: 11 }), chip('叢集 / 平台', 3.5, 6.35, 1.6, PLT, { h: 0.42, sz: 11 }), chip('MDS / RBAC', 5.25, 6.35, 1.6, MDS, { h: 0.42, sz: 11 }),
  text(7.2, 6.35, 5.6, 0.42, [P('授權集中在 MDS 的 RBAC;人綁 AD 群組,服務綁 User:', { sz: 11.5, b: true, algn: 'r', c: INK })], { anchor: 'ctr' }),
], notes: '全景:人經 C3、REST Proxy 或 CLI 進入;機器經 SCRAM 直連或 client 憑證經 REST Proxy;所有身分的授權由 MDS 的 RBAC 集中判斷,broker 本地 cache。群組同步由 MDS writer broker 負責;使用者認證(MDS Basic、CLIENT 埠 PLAIN+LDAP)由各 broker 連 AD,AD 防火牆來源要涵蓋所有 broker(controller 不需要 LDAP 設定,實測)。' });

// 人的路徑
function lane(y, col, label, ic, steps) {
  const items = [tint(0.6, y, 12.13, 1.45, col, { round: 0.06 }), ...badge(ic, 0.75, y + 0.3, 0.8, col), text(1.7, y + 0.35, 1.6, 0.8, [P(label, { sz: 14, b: true, c: col })], { anchor: 'ctr' })];
  steps.forEach((s, i) => { const x = 3.4 + i * 2.35; items.push(white(x, y + 0.25, 2.0, 0.95, col, { round: 0.1, lw: 1, paras: [P(s, { sz: 11, b: true, algn: 'ctr' })] })); if (i < steps.length - 1) items.push(arrow(x + 2.0, y + 0.72, x + 2.35, y + 0.72, col, { w: 1.75 })); });
  return items;
}
add({ title: '人的完整路徑', items: [
  ...lane(1.55, HUM, 'C3\n瀏覽器', 'FaDesktop', ['Basic 帳密\n→ MDS(LDAP)', 'token\n(JWT,壽命可設)', 'Bearer 帶本人身分\n連 broker', 'RBAC\n(AD 群組)']),
  ...lane(3.2, HUM, 'CLI 直連\nbroker', 'FaTerminal', ['SASL/PLAIN\n帳密', 'broker 轉 LDAP\n驗證密碼', '主體 = 本人帳號', 'RBAC\n(AD 群組)']),
  ...lane(4.85, HUM, 'REST Proxy\nPostman', 'FaExchangeAlt', ['Basic 帳密', 'REST Proxy 轉\nMDS 驗證 → token', 'OAUTHBEARER\n連 broker', 'RBAC\n(AD 群組)']),
  text(0.6, 6.45, 12.13, 0.4, [P('三條路徑最後都由 RBAC 依「AD 群組」授權並留 audit:人員異動只改 AD', { sz: 14, b: true, algn: 'ctr', c: HUM })]),
], notes: '人的三條路徑:C3(Basic→token→Bearer)、CLI 直連 broker(SASL/PLAIN + LDAP callback)、REST Proxy(Basic 轉 MDS 換 token)。授權都依 AD 群組。' });

add({ title: '機器的完整路徑', items: [
  ...lane(1.55, SVC, '應用服務\nSCRAM', 'FaCogs', ['SASL/SCRAM\n帳號密碼', 'broker 驗證\n(帳密在 KRaft)', '主體 = svc-x', 'RBAC\nUser:svc-x']),
  ...lane(3.2, SVC, 'legacy app\nHTTP', 'FaPlug', ['client 憑證\n(CN = 主體)', 'REST Proxy 對映 DN\n→ /impersonate', 'token\nOAUTHBEARER', 'RBAC\nUser:app']),
  ...lane(4.85, PLT, '平台元件\nC3 · REST Proxy', 'FaNetworkWired', ['client 憑證\n(CN=c3 / restproxy)', 'MDS 換 token', 'C3:SystemAdmin\nREST Proxy:專屬 role', 'protected.users\n防被冒充']),
  text(0.6, 6.45, 12.13, 0.4, [P('機器不進 AD:身分在 Kafka 內(SCRAM)或憑證(CN),RBAC 綁 User:,授權事件皆留 audit', { sz: 14, b: true, algn: 'ctr', c: SVC })]),
], notes: '機器三條路徑:應用用 SCRAM 直連;legacy app 用 client 憑證經 REST Proxy;平台元件(C3、REST Proxy)用 client 憑證向 MDS 換 token。憑證身分只能綁 User:,不能綁群組。' });

// 憑證與帳號清單
add({ title: '要管理的憑證與帳號', items: [
  table(0.6, 1.5, [2.9, 1.5, 3.9, 3.83], [
    ['項目', '數量', '存放', '輪替 / 備註'],
    ['server 憑證(共用)', '1 組', '所有節點 secrets 目錄', 'SAN 涵蓋全部;逐台換;換 CA 時 truststore 先信任新舊'],
    ['平台 client 憑證', '3(c3 · restproxy · bootstrap)', '對應主機;bootstrap 離線保管', 'RBAC 綁 CN,CN 不變則不用重綁'],
    ['legacy app client 憑證', '每個 app 1 張', 'app 主機', '可省:若客戶能建專用 AD 帳號,改 Basic'],
    ['MDS token 簽章金鑰對', '1 組', '私鑰:MDS broker 與 controller;公鑰:broker · REST Proxy · C3', '私鑰外洩 = 可偽造 token;輪替未驗證'],
    ['SCRAM 服務帳號', '每個服務 1 個', 'KRaft 內;密碼放密碼庫', '密碼不自動到期 → 輪替流程'],
    ['AD 唯讀帳號與 LDAPS 信任庫', '各 1', 'broker 設定(權限 600)', '只讀 user / group OU;建議 LDAPS;AD 憑證更換時更新信任庫'],
    ['內部與 break-glass 帳號', '3', 'KRaft + JAAS 設定檔;bootstrap 密碼封存', 'kafka-broker · kafka-controller · bootstrap(break-glass);輪替未驗證'],
    ['AD 群組', '5', 'AD', '人員異動只改 AD'],
  ], { rowH: 0.54, hdrH: 0.46, sz: 11, col: HUM }),
  chip('最少化:1 server 憑證 + 2 長期 client 憑證 + 1 備用(bootstrap)', 0.6, 6.4, 12.13, PLT, { sz: 13 }),
], notes: '憑證最少化:1 組 server 憑證 + c3、restproxy 兩張長期 client 憑證 + 1 張備用(bootstrap)。legacy app 的憑證可省,前提是客戶能建專用 AD 帳號(非真人)讓 app 走 Basic。另需保管:MDS token 簽章金鑰對(私鑰在 MDS broker 與 controller、公鑰在 broker / REST Proxy / C3,外洩可偽造 token,輪替流程未驗證)、內部帳號 kafka-broker / kafka-controller(SCRAM 與 PLAIN 靜態帳號,輪替流程未驗證)、AD LDAPS CA root 信任庫。' });

// 導入步驟
add({ title: '導入步驟(RHEL 9 手動部署)', items: [
  ...[['憑證與 truststore', '含 AD 的 LDAPS CA 與 MDS 金鑰對', 'FaCertificate'], ['controller', 'format + add-scram', 'FaCube'], ['broker + MDS + LDAP', '三個入口', 'FaServer'], ['第一批 role binding', 'bootstrap → kafka-admins', 'FaUserShield'], ['REST Proxy · C3', '含 Prometheus + Alertmanager', 'FaDesktop'], ['audit 與驗證', '路由 + 逐項驗證', 'FaClipboardList']].flatMap(([t, s, ic], i) => {
    const x = 0.6 + i * 2.05;
    return [tint(x, 1.6, 1.85, 2.9, i % 2 ? PLT : HUM, { round: 0.08 }), box(x + 0.7, 1.7, 0.45, 0.45, { fill: INK, tint: 0, line: INK, round: 0.5, paras: [P(String(i + 1), { sz: 14, b: true, c: 'background1', algn: 'ctr' })], ins: 0 }),
      ...badge(ic, x + 0.6, 2.3, 0.65, i % 2 ? PLT : HUM), text(x + 0.08, 3.1, 1.69, 0.6, [P(t, { sz: 12.5, b: true, algn: 'ctr' })]), text(x + 0.1, 3.75, 1.65, 0.7, [P(s, { sz: 10.5, algn: 'ctr', ...MUTE })]), i < 5 ? arrow(x + 1.85, 3.0, x + 2.05, 3.0, 'text1', { w: 1.75 }) : null];
  }).filter(Boolean),
  chip('controller 要在 format 時預建 kafka-broker / kafka-controller 的 SCRAM 憑證,否則授權器起不來(實測)', 0.6, 4.85, 12.13, RISK, { sz: 13 }),
  chip('改設定:systemctl 逐台滾動重啟;demo 曾因強殺 controller 留下空 snapshot 而遺失 SCRAM 憑證 → 停止逾時要足夠', 0.6, 5.45, 12.13, SVC, { sz: 12 }),
  text(0.6, 6.1, 12.13, 0.6, [P('demo 的 14 個章節對應每一步的驗證;路徑與 systemd 單元需在 RHEL 實機核對(本專案未在 RHEL 實機驗證)', { sz: 11.5, algn: 'ctr', ...MUTE })]),
], notes: '順序:憑證與 truststore → controller(kafka-storage format --add-scram,須在 broker 啟動前)→ broker + MDS + LDAP → 以 bootstrap 憑證建立第一批 role binding(管理權交給 AD 群組 kafka-admins)→ REST Proxy、C3、Prometheus/Alertmanager → audit 路由與驗證。實測教訓:改共用設定時 docker 連動重建 controller,逾時強殺留下空 KRaft snapshot,controller 重啟後遺失 SCRAM 憑證,broker 無法啟動。' });

// 風險
const RK = [['c3 憑證 = 管理員', '能建立 / 刪除 role binding;拿掉權限 C3 會退出(實測)', '保護私鑰與檔案權限;列入保護清單', 'FaKey'], ['restproxy 憑證可代人', '可代不在保護清單的使用者;混入 Group: 整份失效', '特權身分逐一以 User: 列入', 'FaUserSecret'],
  ['私鑰外洩(server · token)', 'server 私鑰外洩 = 可偽裝伺服器;token 簽章私鑰外洩 = 可偽造任何人的 token', '權限 600;最小化存放;輪替計畫;共用身分不綁 role', 'FaCertificate'], ['SCRAM 密碼不到期', '長期不換 → 外洩風險累積', '密碼庫 + 輪替流程 + 提醒', 'FaSyncAlt'],
  ['監控元件預設未認證', 'Prometheus / Alertmanager 可無認證讀寫', '啟用 TLS + Basic;未啟用時網路隔離', 'FaChartLine'], ['audit 不是全記', '部分拒絕查不到;成功的 consume 預設不記(避免洗版)', '稽核需求另外盤點', 'FaClipboardList']];
add({ title: '風險與對策', items: RK.flatMap(([t, f, fx, ic], i) => {
  const x = 0.6 + (i % 3) * 4.13, y = 1.5 + Math.floor(i / 3) * 2.75;
  return [white(x, y, 3.85, 2.55, 'text1', { round: 0.05, lw: 1 }), ...badge(ic, x + 0.15, y + 0.12, 0.55, RISK), text(x + 0.8, y + 0.12, 2.95, 0.55, [P(t, { sz: 13.5, b: true })], { anchor: 'ctr' }),
    tint(x + 0.15, y + 0.8, 3.55, 0.8, RISK, { round: 0.08, lw: 1, paras: [P('發現:' + f, { sz: 10.5, b: true, c: RISK })] }), tint(x + 0.15, y + 1.68, 3.55, 0.75, PLT, { round: 0.08, lw: 1, paras: [P('對策:' + fx, { sz: 10.5, b: true, c: PLT })] })];
}), notes: '六個主要風險與對策。前兩項是平台元件憑證的風險(c3 憑證=管理員、restproxy 憑證可代人),都是實測發現。第三項:共用 server 私鑰外洩可偽裝伺服器,也能以共用身分向 MDS 認證(該身分不綁 role,無權限);MDS token 簽章私鑰外洩可偽造任何人的 token,其輪替流程未驗證。' });

add({ title: '風險與對策(續)', items: [
  ...[['Postman cookie 優先於 Basic', 'MDS 驗證後回 auth_token cookie,優先於 Basic:同一 session 換身分仍以前一人執行(實測:誤新增 role binding)', '換身分前清除 cookie;collection 層級 pre-request 清除', 'FaPaperPlane'],
    ['移出群組後的延遲', '移出群組最長約 60 秒收回;刪除 AD 帳號後,已簽發 token 到期前仍有效(實測)', '預留刷新時間;離職:停用 AD 帳號,並視需要縮短 token 壽命(token.max.lifetime.ms)', 'FaUserClock'],
    ['多 controller 的機制', '官方說明 controller listener 不支援 SCRAM,採 PLAIN;PLAIN 已實測(機制),未含 TLS / RBAC', '導入前在實機以 TLS + RBAC 實測', 'FaCube']].flatMap(([t, f, fx, ic], i) => {
    const x = 0.6 + i * 4.13, y = 1.5;
    return [white(x, y, 3.85, 2.9, 'text1', { round: 0.05, lw: 1 }), ...badge(ic, x + 0.15, y + 0.12, 0.55, RISK), text(x + 0.8, y + 0.12, 2.95, 0.55, [P(t, { sz: 13.5, b: true })], { anchor: 'ctr' }),
      tint(x + 0.15, y + 0.8, 3.55, 1.15, RISK, { round: 0.08, lw: 1, paras: [P('發現:' + f, { sz: 10.5, b: true, c: RISK })] }), tint(x + 0.15, y + 2.05, 3.55, 0.7, PLT, { round: 0.08, lw: 1, paras: [P('對策:' + fx, { sz: 10.5, b: true, c: PLT })] })];
  }),
  chip('前兩項是已實測的操作陷阱,第三項導入前須實機驗證', 0.6, 4.8, 12.13, SVC, { sz: 14 }),
], notes: 'Postman cookie 陷阱(SPIKE 實測):MDS 驗證成功後回 auth_token cookie,cookie 優先於 Basic;同一 Postman session 換身分仍以前一人執行,實測 yujie 曾以 gary 身分新增 role binding。群組移出延遲:ldap.refresh.interval.ms 官方預設 60000;已簽發 token:實測刪除 AD 帳號後,舊 token 到期前仍可呼叫 MDS,Basic 重新登入回 401;token 路徑下授權是否依現在群組未測。多 controller:官方 SCRAM overview 與 KRaft security 頁說法不一致;3 個 controller 間 SASL/PLAIN 已用獨立實驗驗證(機制)。' });


// 驗證 vs 待驗證
add({ title: '已驗證 vs 待驗證', items: [
  tint(0.6, 1.5, 5.95, 4.4, PLT), ...badge('FaCheckCircle', 0.8, 1.65, 0.7, PLT), text(1.65, 1.7, 4.8, 0.6, [P('demo 已實跑驗證', { sz: 17, b: true, c: PLT })], { anchor: 'ctr' }),
  text(0.85, 2.55, 5.5, 3.7, ['AD 群組 RBAC:加入群組生效(demo 5 秒;預設 60 秒)', 'AD 群組分層授權:唯讀 / 維運 / 授權管理(含臨時提權)', '服務帳號 SCRAM 與輪替', '人機並存:REST Proxy / legacy app', 'C3 人與機器流程、風險', 'audit 事件', 'LDAPS 信任庫 · 3 controller PLAIN · SCRAM 並行', '憑證更換三情境與元件順序(單節點 + demo 全元件)'].map(t => P('✔  ' + t, { sz: 13, after: 6 }))),
  tint(6.78, 1.5, 5.95, 4.4, SVC), ...badge('FaQuestionCircle', 6.98, 1.65, 0.7, SVC), text(7.83, 1.7, 4.8, 0.6, [P('待驗證 / 待確認', { sz: 17, b: true, c: SVC })], { anchor: 'ctr' }),
  text(7.03, 2.55, 5.5, 3.7, ['真實 AD:巢狀群組、大小寫、UPN', '多 controller 搭配 TLS + RBAC', 'RHEL 實機:systemd、firewalld、路徑',
    '長駐 client 是否需重啟才重載信任庫;中繼 CA 的更換', 'Prometheus / Alertmanager 啟用 TLS + Basic', 'Java 21(demo 映像為 Java 25)', '縮短 token 壽命對元件換 token 頻率的影響', 'MDS 金鑰對與內部帳號的輪替流程'].map(t => P('?  ' + t, { sz: 13, after: 6 }))),
  chip('demo 使用 OpenLDAP 模擬 AD;商用功能(RBAC、audit、C3)需 license', 0.6, 6.15, 12.13, HUM, { sz: 12, h: 0.42 }),
], notes: '如實呈現:左邊是 demo 已實跑驗證的項目;右邊是尚未驗證或需在客戶環境確認的項目。' });

// 客戶確認
add({ title: '導入前請客戶確認', items: [
  ...[['AD 唯讀查詢帳號(bind DN)與 LDAPS', 'FaUserShield', HUM], ['Kafka 憑證由誰簽發:有無 AD CS(內部 CA)與根憑證散佈方式', 'FaCertificate', PLT], ['能否為 legacy app 建立專用 AD 帳號(非真人)', 'FaPlug', SVC], ['license 是否涵蓋 RBAC / audit / C3', 'FaFileContract', MDS], ['AD 群組是否巢狀、帳號大小寫與命名', 'FaSitemap', HUM], ['Java 版本(建議 21)與 Prometheus / Alertmanager 部署', 'FaCoffee', PLT], ['AD 是否有多台 DC(高可用):LDAP 停擺超過 24 小時,授權器會失效', 'FaServer', HUM], ['AD 的 LDAPS 憑證由誰簽發(根 CA、有無中繼 CA)', 'FaLink', PLT]].flatMap(([t, ic, col], i) => {
    const x = 0.6 + (i % 2) * 6.15, y = 1.45 + Math.floor(i / 2) * 1.2;
    return [tint(x, y, 5.95, 1.05, col, { round: 0.08 }), box(x + 0.15, y + 0.28, 0.5, 0.5, { fill: col, tint: 0, line: col, round: 0.5, paras: [P(String(i + 1), { sz: 15, b: true, c: 'background1', algn: 'ctr' })], ins: 0 }), ...badge(ic, x + 0.85, y + 0.22, 0.6, col), text(x + 1.65, y + 0.05, 4.2, 0.95, [P(t, { sz: 13, b: true })], { anchor: 'ctr' })];
  }),
  chip('第 3 項若可行:legacy app 走 Basic,不需要 client 憑證', 0.6, 6.3, 12.13, PLT, { sz: 13 }),
], notes: '請客戶確認的八件事。第 3 項決定 legacy app 要不要 client 憑證;第 2 項決定 Kafka 憑證如何簽發與散佈;第 7 項:官方 ldap.retry.timeout.ms 預設 24 小時,LDAP 持續失敗超過這段時間授權器會被標為失敗,所以 AD 要有多台 DC;第 8 項:LDAPS 的 CA 要匯入 broker 的信任庫,若由中繼 CA 簽發且 AD 不附完整鏈,中繼 CA 也要匯入。' });

add({ title: '下一步', items: [
  ...[['FaComments', '客戶確認', '回覆前一頁的八件事', HUM], ['FaCalendarCheck', '調整方案', '依客戶回覆更新設計', SVC], ['FaServer', 'RHEL 實機驗證', '補上目前未驗證的項目', PLT]].flatMap(([ic, t, s, col], i) => [...node(0.6 + i * 4.13, 1.8, 3.85, 2.4, { icon: ic, title: t, sub: s, col, tsz: 18, ssz: 13 }), i < 2 ? arrow(4.45 + i * 4.13, 3.0, 4.73 + i * 4.13, 3.0, 'text1', { w: 2.5 }) : null].filter(Boolean)),
  chip('Demo 與 Word 手冊可作為每一步的實作與證據', 0.6, 4.7, 12.13, MDS, { sz: 14 }),
], notes: '' });

module.exports = { SLIDES, THEME, HEX, OUT, H: { node, chip, tint, text, P, MUTE, badge, arrow, box, solid, white, step, table, icon, HUM, SVC, PLT, MDS, RISK, INK } };

// ───────── 輸出 ─────────
if (require.main === module) {
  (async () => {
    // 圖示
    const ICON = {};
    const need = new Set();
    SLIDES.forEach(s => s.items.forEach(it => { if (it.k === 'icon') need.add(it.name + '|' + it.col); }));
    for (const k of need) {
      const [name, col] = k.split('|'); const Comp = FA[name]; if (!Comp) throw new Error('未知圖示 ' + name);
      const svg = renderToStaticMarkup(React.createElement(Comp, { color: '#' + HEX[col], size: 256 }));
      ICON[k] = (await sharp(Buffer.from(svg)).png().toBuffer()).toString('base64');
    }
    const pres = new pptxgen(); pres.layout = 'LAYOUT_WIDE'; pres.theme = { headFontFace: THEME.headFontFace, bodyFontFace: THEME.bodyFontFace };
    pres.title = 'Confluent Platform 安全解決方案(草稿)'; pres.author = '';
    const C = pres.SchemeColor, SHP = pres.ShapeType;
    pres.defineSlideMaster({ title: 'TITLE', background: { color: C.background1 }, objects: [
      { rect: { x: 0, y: 0, w: 0.35, h: 7.5, fill: { color: C.accent1 } } },
      { placeholder: { options: { name: 'title', type: 'title', x: 0.9, y: 2.2, w: 8.4, h: 1.6, fontSize: 38, bold: true, color: C.text2, valign: 'bottom', margin: 0 }, text: '' } },
      { placeholder: { options: { name: 'subtitle', type: 'body', x: 0.9, y: 4.0, w: 8.4, h: 1.2, fontSize: 18, color: C.text1, valign: 'top', margin: 0 }, text: '' } }] });
    pres.defineSlideMaster({ title: 'SECTION', background: { color: C.text2 }, objects: [
      { placeholder: { options: { name: 'title', type: 'title', x: 0.9, y: 2.5, w: 11.5, h: 1.2, fontSize: 38, bold: true, color: C.background1, valign: 'bottom', margin: 0 }, text: '' } },
      { placeholder: { options: { name: 'subtitle', type: 'body', x: 0.9, y: 3.85, w: 11.5, h: 0.9, fontSize: 18, color: C.background2, valign: 'top', margin: 0 }, text: '' } }] });
    pres.defineSlideMaster({ title: 'CONTENT', background: { color: C.background1 }, slideNumber: { x: 12.3, y: 7.08, w: 0.6, h: 0.3, fontSize: 10, color: C.text1 }, objects: [
      { placeholder: { options: { name: 'title', type: 'title', x: 0.6, y: 0.3, w: 12.13, h: 0.95, fontSize: 28, bold: true, color: C.text2, valign: 'middle', margin: 0 }, text: '' } },
      { text: { text: 'Confluent Platform 安全解決方案 · 草稿', options: { x: 0.6, y: 7.08, w: 6, h: 0.3, fontSize: 10, color: C.text1, transparency: 50, margin: 0 } } }] });

    const col = k => C[k]; let curSec = '封面'; pres.addSection({ title: curSec });
    for (const s of SLIDES) {
      if (s.layout === 'SECTION') { curSec = s.title; pres.addSection({ title: curSec }); }
      const slide = pres.addSlide({ masterName: s.layout || 'CONTENT', sectionTitle: curSec });
      slide.addText(s.title, { placeholder: 'title', lang: 'zh-TW' });
      if (s.subtitle) slide.addText(s.subtitle, { placeholder: 'subtitle', lang: 'zh-TW' });
      for (const it of s.items) {
        if (it.k === 'icon') { slide.addImage({ data: 'image/png;base64,' + ICON[it.name + '|' + it.col], x: it.x, y: it.y, w: it.s, h: it.s }); continue; }
        if (it.k === 'img') { slide.addImage({ path: it.file, x: it.x, y: it.y, w: it.w, h: it.h }); continue; }
        if (it.k === 'arrow') {
          const x = Math.min(it.x1, it.x2), y = Math.min(it.y1, it.y2), w = Math.abs(it.x2 - it.x1), h = Math.abs(it.y2 - it.y1);
          slide.addShape(SHP.line, { x, y, w, h, flipH: it.x2 < it.x1, flipV: it.y2 < it.y1, line: { color: col(it.col), width: it.w, endArrowType: 'triangle', dashType: it.dash ? 'dash' : 'solid' } }); continue;
        }
        if (it.k === 'table') {
          const rows = it.rows.map((r, ri) => r.map((c, ci) => ({ text: c, options: { bold: ri === 0 || ci === 0, fontSize: it.sz, color: ri === 0 ? C.background1 : C.text1, fill: ri === 0 ? { color: col(it.col) } : (ci === 0 ? { color: col(it.col), transparency: 85 } : { color: ri % 2 ? C.background1 : C.background2 }), valign: 'middle', lang: 'zh-TW' } })));
          slide.addTable(rows, { x: it.x, y: it.y, colW: it.colW, rowH: it.rows.map((_, i) => i === 0 ? it.hdrH : it.rowH), border: { type: 'solid', pt: 0.75, color: 'BFBFBF' }, margin: [0.04, 0.08, 0.04, 0.08] }); continue;
        }
        // box
        const hasFill = !!it.fill, o = { x: it.x, y: it.y, w: it.w, h: it.h };
        if (hasFill) o.fill = { color: col(it.fill), transparency: Math.round(it.tint * 100) };
        if (it.line) o.line = { color: col(it.line), width: it.lw };
        if (it.round > 0) { o.rectRadius = Math.min(it.round, 0.5) * Math.min(it.w, it.h) * 0.9; }
        const shape = it.round > 0 ? SHP.roundRect : SHP.rect;
        if (!it.paras.length) { slide.addShape(shape, o); continue; }
        const runs = [];
        it.paras.forEach((p, pi) => p.runs.forEach((r, ri) => {
          const lines = r.t.split('\n');
          lines.forEach((ln, li) => runs.push({ text: ln, options: { fontSize: r.sz, bold: r.b, color: col(r.c), transparency: r.a !== undefined ? Math.round((1 - r.a) * 100) : undefined, align: p.algn === 'ctr' ? 'center' : (p.algn === 'r' ? 'right' : 'left'), paraSpaceAfter: p.after, breakLine: (li < lines.length - 1) || (ri === p.runs.length - 1 && pi < it.paras.length - 1), lang: 'zh-TW' } }));
        }));
        const to = { ...o, margin: it.ins * 72, valign: it.anchor === 'ctr' ? 'middle' : 'top', isTextBox: !hasFill && !it.line };
        if (hasFill || it.line) to.shape = shape;
        slide.addText(runs, to);
      }
      if (s.notes) slide.addNotes(s.notes);
    }
    await pres.writeFile({ fileName: OUT });
    const { applyTheme } = require('C:/Users/user/AppData/Roaming/Claude/local-agent-mode-sessions/skills-plugin/5f4e0bf9-0b49-4a04-b3ed-cd2ce26f0b32/7226f3b7-7d1a-4497-a472-38efd0bcc700/skills/pptx/scripts/apply_theme.js');
    await applyTheme(OUT, THEME);
    console.log('已輸出', OUT, SLIDES.length, '頁');
  })().catch(e => { console.error(e); process.exit(1); });
}
