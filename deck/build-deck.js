// 簡報內容(圖像化版本):套用 IISI 2026 template。用法:node build-deck.js
// 原則:一頁一個重點、圖多字少;架構圖/流程圖用形狀與圖示繪製,實測畫面用截圖。
const path = require('path');
const { C, SH, slide, cover, section, back, build, SLIDES, ICONS } = require('./deck-lib');
const OUT = path.join(__dirname, 'Confluent-Security-Solution.pptx');

// ───────── 1 封面 ─────────
let s = cover('AD 管人,Kafka 管機器', 'Confluent Platform 8.3 安全方案');
s.text('AD 只放 user / group 時,人與服務如何串接 Kafka、REST Proxy、Control Center', 0.5, 4.6, 11.35, 0.45, { fs: 18, color: C.ink });
s.text('方案說明 + 線上 Demo(實測環境:CP 8.3.2 · KRaft · MDS RBAC)', 0.5, 5.1, 11.35, 0.4, { fs: 14, color: C.blue, bold: true });

section('方案設計', '兩個身分平面、人/服務判斷準則、憑證與 listener 策略');

// ───────── 3 客戶環境一張圖 ─────────
s = slide('客戶環境一張圖', '方案要在這些條件下成立');
s.box(0.7, 1.85, 3.7, 3.75, { fill: C.pBlue, noline: true });
s.icon('FaDatabase', 2.0, 2.05, 1.1, C.blue);
s.text('AD 目錄', 0.7, 3.25, 3.7, 0.45, { fs: 20, bold: true, align: 'center', color: C.ink });
s.chip('user', 1.0, 3.85, 1.5, { fill: C.white, line: C.blue }); s.chip('group', 2.6, 3.85, 1.5, { fill: C.white, line: C.blue });
s.chip('✗ 沒有服務帳號', 1.0, 4.45, 3.1, { fill: C.pRed, color: C.red });
s.text('只存放人與群組', 0.7, 5.0, 3.7, 0.4, { fs: 12, color: C.grey, align: 'center' });
s.box(4.85, 1.85, 3.7, 3.75, { fill: C.pOrange, noline: true });
s.icon('FaKey', 6.15, 2.05, 1.1, C.orange);
s.text('1 張共用憑證', 4.85, 3.25, 3.7, 0.45, { fs: 20, bold: true, align: 'center', color: C.ink });
s.chip('同一把 key', 5.15, 3.85, 1.5, { fill: 'FBE3BC', color: '9A5B00' }); s.chip('同一個 DN', 6.75, 3.85, 1.5, { fill: 'FBE3BC', color: '9A5B00' });
s.chip('不想管憑證', 5.15, 4.45, 3.1, { fill: 'FBE3BC', color: '9A5B00' });
s.box(9.0, 1.85, 3.6, 3.75, { fill: C.pGreen, noline: true });
s.icon('FaServer', 10.25, 2.05, 1.1, C.green);
s.text('Kafka 生態系', 9.0, 3.25, 3.6, 0.45, { fs: 20, bold: true, align: 'center', color: C.ink });
s.chip('Broker', 9.25, 3.85, 1.5, { fill: 'CBE9D1', color: '1E6B2B' }); s.chip('Controller', 10.85, 3.85, 1.5, { fill: 'CBE9D1', color: '1E6B2B' });
s.chip('MDS / RBAC', 9.25, 4.4, 1.5, { fill: 'CBE9D1', color: '1E6B2B' }); s.chip('REST Proxy', 10.85, 4.4, 1.5, { fill: 'CBE9D1', color: '1E6B2B' });
s.chip('Control Center', 9.25, 4.95, 3.1, { fill: 'CBE9D1', color: '1E6B2B' });
s.tbox('', 0.7, 5.95, 11.9, 0.85, { fill: C.ink, line: C.ink });
s.icon('FaServer', 1.0, 6.12, 0.5, C.white);
s.text('RHEL 9 VM  ·  手動安裝  ·  暫時沒有 Ansible', 1.7, 5.95, 10.5, 0.85, { fs: 20, bold: true, color: C.white });

// ───────── 4 兩個身分平面 ─────────
s = slide('核心主張:兩個身分平面', '人走 AD(群組授權);機器走 Kafka 內的服務帳號');
s.box(0.6, 1.8, 9.5, 2.25, { fill: C.pBlue, noline: true });
s.text('人', 0.8, 1.9, 1, 0.5, { fs: 24, bold: true, color: C.blue });
s.person('gary', '組長', 2.0, 1.95); s.person('yujie', '組員', 3.35, 1.95); s.person('ming', '新進', 4.7, 1.95);
s.arrow(5.55, 2.85, 6.15, 2.85, { color: C.blue, w: 3 });
s.node(6.2, 2.25, 3.7, 1.2, 'FaDatabase', 'AD 帳號 + 群組', 'LDAP 驗證(經 MDS)', { line: C.blue });
s.box(0.6, 4.25, 9.5, 2.25, { fill: C.pOrange, noline: true });
s.text('機器', 0.8, 4.35, 1.2, 0.5, { fs: 24, bold: true, color: C.orange });
s.badge('FaRobot', 3.0, 5.25, 0.95, { fill: 'FBE3BC', color: C.orange });
s.text('svc-orders', 2.0, 5.8, 2, 0.3, { fs: 15, bold: true, color: C.ink, align: 'center' });
s.arrow(3.75, 5.3, 6.15, 5.3, { color: C.orange, w: 3 });
s.node(6.2, 4.7, 3.7, 1.2, 'FaKey', 'SCRAM 服務帳號', 'Kafka 內建,不在 AD', { line: C.orange, color: C.orange });
s.tbox('', 10.4, 1.8, 2.2, 4.7, { fill: C.white, line: C.ink, lw: 2.25 });
s.icon('FaShieldAlt', 11.0, 2.0, 1.0, C.ink);
s.text('RBAC 授權', 10.4, 3.05, 2.2, 0.45, { fs: 18, bold: true, align: 'center', color: C.ink });
s.chip('Group:\nkafka-developers', 10.55, 3.7, 1.9, { h: 0.7, fs: 10 });
s.chip('User:\nsvc-orders', 10.55, 4.6, 1.9, { h: 0.7, fs: 10, fill: C.pOrange, color: '9A5B00' });
s.text('最小權限', 10.4, 5.5, 2.2, 0.4, { fs: 12, align: 'center', color: C.grey });
s.arrow(10.1, 2.85, 10.4, 2.85, { color: C.blue, w: 3 }); s.arrow(10.1, 5.3, 10.4, 5.3, { color: C.orange, w: 3 });

// ───────── 5 人 vs 服務 ─────────
s = slide('怎麼分「人」與「服務」', '看「誰在操作、誰負責」,不是看用什麼工具');
s.box(0.6, 1.8, 5.9, 3.95, { fill: C.pBlue, noline: true });
s.text('有人在場 = 人', 0.8, 1.9, 5.5, 0.55, { fs: 22, bold: true, color: C.blue });
[['FaDesktop', 'C3 瀏覽器'], ['FaTerminal', '手動跑腳本'], ['FaPaperPlane', 'Postman 手測']].forEach(([ic, t], i) => {
  s.tbox('', 0.85 + i * 1.9, 2.6, 1.75, 1.45, { fill: C.white, line: C.blue });
  s.icon(ic, 1.45 + i * 1.9, 2.75, 0.55, C.blue);
  s.text(t, 0.85 + i * 1.9, 3.4, 1.75, 0.5, { fs: 13, bold: true, align: 'center', color: C.ink });
});
s.arrow(3.55, 4.1, 3.55, 4.6, { color: C.blue, w: 3 });
s.tbox('各人自己的 AD 帳號', 1.0, 4.65, 5.1, 0.85, { fill: C.blue, line: C.blue, color: C.white, fs: 19, bold: true });
s.box(6.8, 1.8, 5.8, 3.95, { fill: C.pOrange, noline: true });
s.text('無人值守 = 服務', 7.0, 1.9, 5.4, 0.55, { fs: 22, bold: true, color: C.orange });
[['FaClock', '排程'], ['FaCogs', 'CI / CD'], ['FaServer', '長駐程式']].forEach(([ic, t], i) => {
  s.tbox('', 7.05 + i * 1.85, 2.6, 1.7, 1.45, { fill: C.white, line: C.orange });
  s.icon(ic, 7.6 + i * 1.85, 2.75, 0.55, C.orange);
  s.text(t, 7.05 + i * 1.85, 3.4, 1.7, 0.5, { fs: 13, bold: true, align: 'center', color: C.ink });
});
s.arrow(9.7, 4.1, 9.7, 4.6, { color: C.orange, w: 3 });
s.tbox('SCRAM 服務帳號(密碼庫注入)', 7.1, 4.65, 5.3, 0.85, { fill: C.orange, line: C.orange, color: C.white, fs: 19, bold: true });
s.tbox('', 0.6, 6.0, 12.0, 0.85, { fill: C.ink, line: C.ink });
s.text('腳本共用 · 憑證各人各自', 0.9, 6.0, 5.6, 0.85, { fs: 20, bold: true, color: C.white });
s.text('手動 → 排程:改用服務身分,不借人的帳號', 6.6, 6.0, 5.8, 0.85, { fs: 16, color: 'FFD9A0', bold: true });

// ───────── 6 身分地圖 ─────────
s = slide('身分地圖', '每種身分怎麼認證');
s.tbox('Kafka + MDS\nRBAC 授權', 4.95, 3.35, 3.4, 1.7, { fill: C.ink, line: C.ink, color: C.white, fs: 22, bold: true, r: 0.25 });
s.node(0.6, 1.8, 3.9, 1.35, 'FaUsers', 'AD 帳號(人)', '密碼 → LDAP 驗證', { line: C.blue });
s.node(0.6, 5.35, 3.9, 1.35, 'FaRobot', '應用服務', 'SCRAM-SHA-512', { line: C.orange, color: C.orange });
s.node(8.8, 1.8, 3.8, 1.35, 'FaDesktop', 'C3 / REST Proxy', 'client 憑證(CN=c3 / restproxy)', { line: C.green, color: C.green, sfs: 11 });
s.node(8.8, 5.35, 3.8, 1.35, 'FaKey', 'bootstrap', 'client 憑證 · break-glass', { line: C.red, color: C.red });
s.node(4.75, 5.55, 3.8, 1.2, 'FaServer', 'broker / controller', '內部靜態帳號', { line: C.grey, color: C.grey });
s.arrow(4.5, 2.6, 5.0, 3.5, { color: C.blue, w: 2.5 }); s.arrow(4.5, 6.0, 5.0, 4.9, { color: C.orange, w: 2.5 });
s.arrow(8.8, 2.6, 8.3, 3.5, { color: C.green, w: 2.5 }); s.arrow(8.8, 6.0, 8.3, 4.9, { color: C.red, w: 2.5 });
s.arrow(6.65, 5.55, 6.65, 5.1, { color: C.grey, w: 2.5 });

// ───────── 7 憑證策略 ─────────
s = slide('憑證策略:共用憑證只做加密', '客戶不想管憑證 → 憑證越少越好,身分不放在憑證上');
s.icon('FaKey', 0.9, 2.4, 1.5, C.orange);
s.text('1 張共用\nserver 憑證', 0.6, 4.05, 2.2, 0.9, { fs: 16, bold: true, align: 'center', color: C.ink });
['Broker', 'Controller', 'MDS', 'REST Proxy', 'Control Center'].forEach((t, i) => {
  const y = 1.85 + i * 0.72;
  s.tbox(t, 4.6, y, 2.3, 0.55, { fill: C.pGreen, line: C.green, fs: 14, bold: true });
  s.icon('FaLock', 7.05, y + 0.08, 0.4, C.green);
  s.arrow(2.6, 3.4, 4.55, y + 0.27, { color: C.orange, w: 1.75 });
});
s.tbox('只做傳輸加密', 0.7, 5.6, 6.7, 0.6, { fill: C.pGreen, line: C.green, fs: 16, bold: true, color: '1E6B2B' });
s.text('身分另外處理', 8.0, 1.8, 4.6, 0.45, { fs: 18, bold: true, color: C.ink });
['c3', 'restproxy', 'bootstrap'].forEach((t, i) => {
  s.icon('FaCertificate', 8.3 + i * 1.5, 2.4, 0.8, C.blue);
  s.text(t, 8.0 + i * 1.5, 3.25, 1.4, 0.35, { fs: 13, bold: true, align: 'center', color: C.ink });
});
s.text('各 1 張 client 憑證:平台元件向 MDS 認證\n憑證身分只能用 User: 綁 role(官方:不支援群組)', 8.0, 3.65, 4.6, 0.6, { fs: 12, color: C.grey, valign: 'top' });
s.shape(SH.line, 8.0, 4.3, 4.6, 0, { line: C.line, width: 1 });
s.icon('FaRobot', 8.3, 4.6, 0.8, C.orange);
s.text('服務用 SCRAM', 9.3, 4.55, 3.3, 0.45, { fs: 17, bold: true, color: C.ink });
s.text('帳號密碼 · 免憑證 · 密碼進密碼庫', 9.3, 5.0, 3.3, 0.4, { fs: 12, color: C.grey });
s.tbox('風險:共用 private key 外洩 = 可偽裝「伺服器」', 0.6, 6.35, 12.0, 0.5, { fill: C.pRed, line: C.red, color: C.red, fs: 14, bold: true });

// ───────── 8 共用憑證不能當身分 ─────────
s = slide('為什麼共用憑證不能當身分', '實測:同一個 DN → Kafka 看到同一個 principal');
s.box(0.6, 1.8, 5.9, 3.35, { fill: C.pRed, noline: true });
s.text('共用憑證', 0.8, 1.85, 5.5, 0.5, { fs: 20, bold: true, color: C.red });
s.node(0.85, 2.55, 2.4, 0.8, 'FaKey', 'C3', '', { line: C.red, color: C.red, fs: 16 }); s.node(0.85, 3.65, 2.4, 0.8, 'FaKey', 'REST Proxy', '', { line: C.red, color: C.red, fs: 14 });
s.arrow(3.25, 2.95, 3.95, 3.35, { color: C.red, w: 2.5 }); s.arrow(3.25, 4.05, 3.95, 3.65, { color: C.red, w: 2.5 });
s.tbox('MDS 看到\nkafka.demo.local\n(同一個人)', 4.0, 2.65, 2.35, 1.5, { fill: C.white, line: C.red, fs: 13, bold: true, color: C.red });
s.icon('FaTimesCircle', 5.9, 2.5, 0.45, C.red);
s.box(6.8, 1.8, 5.8, 3.35, { fill: C.pGreen, noline: true });
s.text('各自憑證', 7.0, 1.85, 5.4, 0.5, { fs: 20, bold: true, color: C.green });
s.node(7.05, 2.55, 2.4, 0.8, 'FaKey', 'C3', '', { line: C.green, color: C.green, fs: 16 }); s.node(7.05, 3.65, 2.4, 0.8, 'FaKey', 'REST Proxy', '', { line: C.green, color: C.green, fs: 14 });
s.arrow(9.45, 2.95, 10.2, 2.95, { color: C.green, w: 2.5 }); s.arrow(9.45, 4.05, 10.2, 4.05, { color: C.green, w: 2.5 });
s.tbox('c3', 10.25, 2.55, 1.7, 0.8, { fill: C.white, line: C.green, fs: 16, bold: true, color: '1E6B2B' }); s.icon('FaCheckCircle', 12.0, 2.75, 0.4, C.green);
s.tbox('restproxy', 10.25, 3.65, 1.7, 0.8, { fill: C.white, line: C.green, fs: 15, bold: true, color: '1E6B2B' }); s.icon('FaCheckCircle', 12.0, 3.85, 0.4, C.green);
s.img('ch08/02-shared-c3.png', 0.6, 5.35, 5.9, 1.2, '實測:共用憑證 → kafka.demo.local');
s.img('ch08/04-sep-c3.png', 6.8, 5.35, 5.8, 1.2, '實測:各自憑證 → c3');

// ───────── 9 Listener 與內部通道 ─────────
s = slide('Kafka 叢集與內部通道', '全部 SASL_SSL;共用憑證只做加密');
[['FaUser', '人(AD 帳密)', C.blue, 2.0], ['FaRobot', '服務(SCRAM)', C.orange, 3.4], ['FaDesktop', 'C3 / REST Proxy', C.green, 4.8]].forEach(([ic, t, col, y]) => {
  s.node(0.6, y, 2.9, 1.0, ic, t, '', { line: col, color: col, fs: 14 });
  s.arrow(3.5, y + 0.5, 4.75, 3.0, { color: col, w: 2 });
});
s.text('CLIENT :9094', 3.6, 1.7, 1.6, 0.3, { fs: 11, bold: true, color: C.blue });
s.box(4.6, 1.75, 5.0, 3.85, { fill: C.pGrey, line: C.grey, dash: 'dash' });
s.text('Kafka 叢集', 4.75, 1.8, 2, 0.35, { fs: 12, bold: true, color: C.grey });
s.tbox('broker1\n(含 MDS)', 4.85, 2.4, 1.9, 1.0, { fill: C.white, line: C.blue, lw: 2, fs: 14, bold: true, color: C.ink });
s.tbox('broker2', 7.45, 2.4, 1.9, 1.0, { fill: C.white, line: C.blue, lw: 2, fs: 14, bold: true, color: C.ink });
s.arrow(6.75, 2.9, 7.45, 2.9, { color: C.orange, w: 2.5, both: true });
s.text('INTERNAL\nSCRAM', 6.5, 3.0, 1.2, 0.5, { fs: 10, bold: true, color: C.orange, align: 'center' });
s.tbox('controller\n(KRaft)', 6.1, 4.4, 2.0, 0.95, { fill: C.white, line: C.green, lw: 2, fs: 14, bold: true, color: C.ink });
s.arrow(5.8, 3.4, 6.6, 4.4, { color: C.green, w: 2.5 }); s.arrow(8.4, 3.4, 7.7, 4.4, { color: C.green, w: 2.5 });
s.text('CONTROLLER PLAIN\n(controller 間不支援 SCRAM)', 4.7, 4.1, 1.45, 0.5, { fs: 9, bold: true, color: C.green });
s.node(10.1, 1.9, 2.5, 1.1, 'FaDatabase', 'AD(LDAP)', '', { line: C.blue, fs: 14 });
s.arrow(9.6, 2.8, 10.1, 2.6, { color: C.blue, w: 2, dash: 'dash' });
s.chip('CLIENT 9094:PLAIN+LDAP / SCRAM / OAUTH', 0.6, 5.85, 4.5, { fs: 11 });
s.chip('INTERNAL 9092:SCRAM', 5.3, 5.85, 3.3, { fs: 11, fill: C.pOrange, color: '9A5B00' });
s.chip('CONTROLLER 9093:PLAIN', 8.8, 5.85, 3.8, { fs: 11, fill: C.pGreen, color: '1E6B2B' });
s.tbox('', 0.6, 6.4, 12.0, 0.5, { fill: C.pRed, line: C.red });
s.icon('FaShieldAlt', 0.8, 6.46, 0.38, C.red);
s.text('INTERNAL / CONTROLLER 埠:防火牆只開給 broker / controller 節點', 1.35, 6.4, 11, 0.5, { fs: 14, bold: true, color: C.red });

section('線上 Demo', '14 個 Lab 循序漸進:從「沒有身分進不來」到「legacy app、C3、維運分權與 Admin REST 保護」');

// ───────── 11 Demo 路線圖 ─────────
s = slide('Demo 路線圖:14 個 Lab', '每個 Lab:問題 → 操作 → 看結果 → 一句結論');
// [圖示, 名稱, 類型]  類型:core 核心 / star 重點 / opt 選修 / adv 進階
const LABS = [['FaBan', '沒有身分\n進不來', 'core'], ['FaSignInAlt', 'AD 登入\nC3', 'core'], ['FaUsers', '群組 RBAC\n★核心', 'star'], ['FaEye', '生產環境\n只能唯讀', 'core'], ['FaPaperPlane', 'Postman\nREST Proxy', 'core'], ['FaTerminal', '維運腳本', 'core'], ['FaRobot', '服務帳號\nSCRAM', 'core'],
  ['FaKey', '共用憑證\n(選修)', 'opt'], ['FaSyncAlt', '輪替 / AD 故障\n(選修)', 'opt'], ['FaClipboardList', 'audit 稽核', 'core'], ['FaUserShield', '維運分權\n(進階)', 'adv'], ['FaPlug', 'legacy app\nREST Proxy\n(進階)', 'adv'], ['FaDesktop', 'C3 身分盤點\n(進階)', 'adv'], ['FaServer', 'Admin REST\n保護\n(進階)', 'adv']];
const kindStyle = { core: [C.pBlue, C.blue, C.blue], star: ['FFE2B8', C.orange, C.orange], opt: [C.pOrange, C.orange, C.orange], adv: [C.pGreen, C.green, C.green] };
const roadRows = [[LABS.slice(0, 7), 2.55, 1.2, 1.7], [LABS.slice(7), 5.0, 1.2, 1.7]];
roadRows.forEach(([items, cy, x0, dx], r) => {
  s.shape(SH.line, x0, cy, dx * (items.length - 1), 0, { line: C.blue, width: 3 });
  items.forEach(([ic, t, kind], i) => {
    const n = (r === 0 ? 0 : 7) + i + 1;
    const cx = x0 + i * dx; const [fill, color, num] = kindStyle[kind];
    s.badge(ic, cx, cy, 1.0, { fill, color });
    s.tbox(String(n), cx - 0.7, cy - 0.7, 0.4, 0.4, { fill: num, line: num, color: C.white, fs: 12, bold: true, shape: SH.ellipse, margin: 0 });
    s.text(t, cx - 0.85, cy + 0.6, 1.7, 0.85, { fs: 12, bold: true, align: 'center', color: C.ink, valign: 'top' });
  });
});
s.chip('核心', 0.6, 6.55, 1.0, { fill: C.pBlue, line: C.blue, color: C.blue, fs: 11, h: 0.32 });
s.chip('選修', 1.75, 6.55, 1.0, { fill: C.pOrange, line: C.orange, color: C.orange, fs: 11, h: 0.32 });
s.chip('進階', 2.9, 6.55, 1.0, { fill: C.pGreen, line: C.green, color: '1E6B2B', fs: 11, h: 0.32 });

// ───────── 12-13 Lab 3 ─────────
s = slide('Lab 3 授權跟著 AD 群組走', 'AD 加入群組 → 幾秒後生效 → Kafka 端零變更');
s.node(0.7, 1.85, 3.7, 1.2, 'FaUserPlus', 'AD:ming 加入群組', 'kafka-developers', { line: C.blue });
s.arrow(4.4, 2.45, 5.0, 2.45, { color: C.grey, w: 3 });
s.node(5.0, 1.85, 3.3, 1.2, 'FaSyncAlt', 'MDS 重讀群組', 'demo 5 秒 · 預設 60 秒', { line: C.orange, color: C.orange });
s.arrow(8.3, 2.45, 8.9, 2.45, { color: C.grey, w: 3 });
s.node(8.9, 1.85, 3.7, 1.2, 'FaCheckCircle', 'ming 寫入成功', 'Kafka 設定一個字沒改', { line: C.green, color: C.green });
s.img('ch03/c3-1-write-form.png', 0.6, 3.3, 5.9, 3.2, 'C3:把 role 指派給「AD 群組」');
s.img('ch03/ldap-add-ming-after.png', 6.8, 3.3, 5.8, 3.2, 'AD 管理介面:ming 已在群組內');

s = slide('Lab 3 實測結果', '同一個指令,群組異動前後不同');
s.tbox('之前', 0.6, 1.8, 1.0, 0.45, { fill: C.pRed, line: C.red, color: C.red, fs: 14, bold: true, r: 0.22 });
s.tbox('之後', 6.8, 1.8, 1.0, 0.45, { fill: C.pGreen, line: C.green, color: '1E6B2B', fs: 14, bold: true, r: 0.22 });
s.img('ch03/05-ming-denied.png', 0.6, 2.35, 5.9, 1.45, 'ming 不在群組:被拒');
s.img('ch03/07-ming-ok.png', 6.8, 2.35, 5.8, 1.45, 'AD 加入群組數秒後:成功');
s.img('ch03/c3-3-ming-topics.png', 0.6, 4.2, 5.9, 2.45, 'ming 的 C3:看得到 orders.*');
s.img('ch03/03-mds-api.png', 6.8, 4.2, 5.8, 1.6, 'MDS API(Postman 同一份資料)');
s.chip('C3 畫面 = MDS API = 同一份授權資料', 6.8, 6.05, 5.8, { fill: C.pBlue, line: C.blue, fs: 13, h: 0.45 });

// ───────── 14 Lab 4 ─────────
s = slide('Lab 4 正式環境:人只能唯讀', 'kafka-readonly → DeveloperRead');
s.tbox('✓ 可以讀', 0.6, 1.8, 3.8, 0.7, { fill: C.pGreen, line: C.green, color: '1E6B2B', fs: 18, bold: true });
s.tbox('✗ 不能寫', 4.7, 1.8, 3.8, 0.7, { fill: C.pRed, line: C.red, color: C.red, fs: 18, bold: true });
s.tbox('✗ 不能建 topic', 8.8, 1.8, 3.8, 0.7, { fill: C.pRed, line: C.red, color: C.red, fs: 18, bold: true });
s.img('ch04/c3-2-ming-readonly-topics.png', 0.6, 2.75, 5.6, 3.75, 'ming(唯讀)的 C3:可檢視、沒有管理按鈕');
s.img('ch04/04-ming-read.png', 6.5, 2.75, 6.1, 1.0, '讀取:成功');
s.img('ch04/05-ming-write.png', 6.5, 4.15, 6.1, 1.0, '寫入:被拒');
s.img('ch04/06-ming-create.png', 6.5, 5.55, 6.1, 1.0, '建立 topic:被拒');

// ───────── 15 Lab 5 Postman ─────────
s = slide('Lab 5 Postman / REST Proxy', '同一份 AD 身分:10 個 request、14 個 assertion 全過');
s.img('ch05/postman-0-summary.png', 0.6, 1.8, 6.9, 4.2, 'Collection Runner:Tests 全綠');
s.img('ch05/postman-5.3.png', 7.8, 1.8, 4.8, 1.85, 'yujie 寫 payments → 403');
s.img('ch05/postman-M.3.png', 7.8, 4.05, 4.8, 1.85, 'yujie 改授權 → 403');
s.tbox('⚠ 換身分前清 cookie:MDS 的 auth_token 優先於 Basic Auth', 0.6, 6.5, 12.0, 0.42, { fill: C.pOrange, line: C.orange, color: '9A5B00', fs: 14, bold: true });

// ───────── 16 Lab 6 腳本 ─────────
s = slide('Lab 6 維運腳本', '腳本共用 · 憑證各人各自 → 稽核看得到「是誰」');
s.box(0.6, 1.8, 5.9, 3.4, { fill: C.pGreen, noline: true });
s.text('各人憑證 ✓', 0.8, 1.85, 5.5, 0.5, { fs: 20, bold: true, color: C.green });
s.person('yujie', '', 1.5, 2.3, { fill: 'CBE9D1', color: C.green }); s.icon('FaKey', 1.25, 3.85, 0.5, C.blue);
s.person('ming', '', 3.0, 2.3, { fill: 'CBE9D1', color: C.green }); s.icon('FaKey', 2.75, 3.85, 0.5, C.orange);
s.arrow(3.75, 3.0, 4.35, 3.0, { color: C.green, w: 2.5 });
s.node(4.4, 2.5, 2.0, 1.0, 'FaFileCode', 'heartbeat.sh', '', { line: C.green, color: C.green, fs: 12 });
s.chip('User:yujie ✓ 成功', 1.0, 4.45, 2.3, { fill: C.pGreen, color: '1E6B2B', line: C.green }); s.chip('User:ming ✗ 唯讀被拒', 3.5, 4.45, 2.8, { fill: C.pGreen, color: '1E6B2B', line: C.green });
s.box(6.7, 1.8, 5.9, 3.4, { fill: C.pRed, noline: true });
s.text('共用帳號 ✗', 6.9, 1.85, 5.5, 0.5, { fs: 20, bold: true, color: C.red });
s.person('yujie', '', 7.6, 2.3, { fill: 'F6C9CE', color: C.red }); s.person('ming', '', 9.1, 2.3, { fill: 'F6C9CE', color: C.red });
s.icon('FaKey', 8.0, 3.85, 0.5, C.red); s.icon('FaKey', 9.5, 3.85, 0.5, C.red);
s.arrow(9.85, 3.0, 10.45, 3.0, { color: C.red, w: 2.5 });
s.node(10.5, 2.5, 2.0, 1.0, 'FaFileCode', 'heartbeat.sh', '', { line: C.red, color: C.red, fs: 12 });
s.chip('全部都是 User:shared-ops', 7.2, 4.45, 3.4, { fill: C.pRed, color: C.red, line: C.red }); s.chip('唯讀的 ming 也能寫', 10.7, 4.45, 1.9, { fill: C.pRed, color: C.red, line: C.red, fs: 10 });
s.img('ch06/06-audit.png', 0.6, 5.4, 12.0, 1.2, 'audit log:yujie / ming / shared-ops');

// ───────── 17 Lab 7 服務帳號 ─────────
s = slide('Lab 7 機器:服務帳號 + RBAC', 'AD 群組與服務帳號,同一張 role assignment 表');
s.img('ch07/c7-1-svc-saved.png', 0.6, 1.8, 7.4, 4.75, 'C3:Group 與 User(不在 AD)並列');
s.node(8.4, 1.85, 4.2, 1.1, 'FaRobot', 'svc-orders', 'SCRAM · 不在 AD', { line: C.orange, color: C.orange });
s.arrow(10.5, 2.95, 10.5, 3.45, { color: C.grey, w: 3 });
s.node(8.4, 3.5, 4.2, 1.1, 'FaShieldAlt', 'DeveloperWrite', 'orders.*', { line: C.ink, color: C.ink });
s.arrow(10.5, 4.6, 10.5, 5.05, { color: C.grey, w: 3 });
s.chip('✓ orders.*', 8.4, 5.1, 2.0, { fill: C.pGreen, color: '1E6B2B', line: C.green, h: 0.5, fs: 14 }); s.chip('✗ payments.*', 10.6, 5.1, 2.0, { fill: C.pRed, color: C.red, line: C.red, h: 0.5, fs: 14 });
s.text('最小權限', 8.4, 5.75, 4.2, 0.4, { fs: 13, color: C.grey, align: 'center' });
s.chip('只能用 HTTP 的 legacy app → 見 Lab 12', 8.4, 6.25, 4.2, { fill: C.pOrange, line: C.orange, color: '9A5B00', fs: 12, h: 0.42 });

// ───────── 20 audit ─────────
s = slide('Lab 10 audit log', '被拒絕的、被允許的、誰嘗試改授權');
s.img('ch10/01-audit-denied.png', 0.6, 1.8, 12.0, 1.95, '被 RBAC 擋下的動作');
s.img('ch10/03-audit-mgmt.png', 0.6, 4.15, 12.0, 1.95, '權限變更事件(含 yujie 的 DENIED)');
s.tbox('官方預設只記 Management + Authorize;本 demo 自訂 router 才含 produce / describe。部分拒絕(如缺 IdempotentWrite)仍查不到', 0.6, 6.55, 12.0, 0.4, { fill: C.pOrange, line: C.orange, color: '9A5B00', fs: 12, bold: true });


// ───────── 18 分權 ─────────
s = slide('正式環境:唯讀 + 分權', '平常人人唯讀;管理與授權拆開,需要時臨時加入群組');
const cols = [['FaEye', 'kafka-readonly', 'DeveloperRead', C.blue], ['FaCogs', 'kafka-ops', 'Operator + Manage', C.orange], ['FaUserCog', 'kafka-rbac-admins', 'UserAdmin', C.green], ['FaCrown', 'kafka-admins', 'SystemAdmin', C.red]];
cols.forEach(([ic, g, r, col], i) => {
  const x = 3.3 + i * 2.35;
  s.tbox('', x, 1.8, 2.2, 1.5, { fill: C.white, line: col, lw: 2 });
  s.icon(ic, x + 0.8, 1.9, 0.6, col);
  s.text(g, x, 2.55, 2.2, 0.35, { fs: 13, bold: true, align: 'center', color: C.ink });
  s.text(r, x, 2.9, 2.2, 0.3, { fs: 11, align: 'center', color: C.grey });
});
const rows = [['讀資料', [1, 0, 0, 1]], ['管 topic(建 / 刪)', [0, 1, 0, 1]], ['改授權', [0, 0, 1, 1]]];
rows.forEach(([lab, v], r) => {
  const y = 3.5 + r * 0.8;
  s.box(0.6, y, 11.95, 0.7, { fill: r % 2 ? C.white : C.pGrey, noline: true, r: 0.05 });
  s.text(lab, 0.8, y, 2.3, 0.7, { fs: 17, bold: true, color: C.ink });
  v.forEach((ok, i) => s.icon(ok ? 'FaCheckCircle' : 'FaTimesCircle', 3.3 + i * 2.35 + 0.85, y + 0.12, 0.46, ok ? C.green : 'C9A0A5'));
});
s.text('⚠ rbac-admins 可替自己授權 → 人數最少、臨時加入、audit 必看  ・  改 topic 設定另需 ResourceOwner 或 ClusterAdmin(全叢集、無讀寫)', 0.6, 5.88, 12.0, 0.25, { fs: 10, color: C.red });
['AD 加入群組', '做事', 'AD 移出群組', 'audit 留痕'].forEach((t, i) => {
  const x = 0.6 + i * 3.1;
  s.tbox(t, x, 6.1, 2.6, 0.6, { fill: i === 3 ? C.ink : C.pBlue, line: i === 3 ? C.ink : C.blue, color: i === 3 ? C.white : C.blue, fs: 15, bold: true, r: 0.3 });
  if (i < 3) s.arrow(x + 2.65, 6.4, x + 3.05, 6.4, { color: C.grey, w: 2.5 });
});

s = slide('分權實測', '臨時提權 → 做事 → 收回,Kafka 端零變更');
[['FaCogs', 'yujie 加入 kafka-ops', '✓ 可建立 topic', C.pGreen, C.green, '1E6B2B'],
  ['FaEye', '維運讀資料', '✗ TopicAuthorization', C.pRed, C.red, C.red],
  ['FaUserCog', '維運改授權', '✗ HTTP 403', C.pRed, C.red, C.red],
  ['FaHistory', '移出群組(收回)', '✗ 再操作皆被拒', C.pBlue, C.blue, C.blue]].forEach(([ic, h, r, fill, line, col], i) => {
  const y = 1.85 + i * 1.2;
  s.tbox('', 0.6, y, 4.9, 1.05, { fill, line, lw: 1.5 });
  s.icon(ic, 0.85, y + 0.28, 0.5, line);
  s.text(h, 1.6, y + 0.1, 3.8, 0.4, { fs: 14, bold: true, color: C.ink });
  s.text(r, 1.6, y + 0.52, 3.8, 0.4, { fs: 16, bold: true, color: col });
});
s.img('ch11/16-audit.png', 5.8, 1.85, 6.8, 4.6, 'audit log:誰被拒、誰改了授權(實測)');

// ───────── Lab 12 legacy app 經 REST Proxy ─────────
s = slide('Lab 12 legacy app 經 REST Proxy', '機器用 client 憑證、人用 Basic,同一個 REST Proxy 並存');
s.node(0.6, 1.85, 2.75, 1.25, 'FaFileCode', 'legacy app', '只能 HTTP · client 憑證', { line: C.orange, color: C.orange, sfs: 11 });
s.arrow(3.35, 2.47, 3.7, 2.47, { color: C.orange, w: 3 });
s.tbox('REST Proxy\n人:Basic  機器:憑證', 3.7, 1.85, 3.0, 1.25, { fill: C.white, line: C.ink, lw: 2, fs: 13, bold: true, color: C.ink });
s.arrow(6.7, 2.47, 7.05, 2.47, { color: C.grey, w: 3 });
s.tbox('MDS\n代理出 User:legacy-orders', 7.05, 1.85, 2.75, 1.25, { fill: C.white, line: C.blue, lw: 2, fs: 12, bold: true, color: C.ink });
s.arrow(9.8, 2.47, 10.15, 2.47, { color: C.grey, w: 3 });
s.tbox('broker\nRBAC 授權', 10.15, 1.85, 2.45, 1.25, { fill: C.white, line: C.green, lw: 2, fs: 13, bold: true, color: C.ink });
s.node(3.7, 3.4, 3.0, 0.8, 'FaUser', 'yujie(人)', 'Basic → MDS 查 AD', { line: C.blue, sfs: 11, fs: 14 });
s.arrow(5.2, 3.4, 5.2, 3.1, { color: C.blue, w: 2.5 });
[['✓ orders.* 寫入 200', C.pGreen, C.green, '1E6B2B'], ['✗ payments.* 403', C.pRed, C.red, C.red], ['✗ 無憑證 401', C.pRed, C.red, C.red], ['✗ 有憑證無授權 403', C.pRed, C.red, C.red], ['✗ 自簽憑證 TLS 拒絕', C.pRed, C.red, C.red]].forEach(([t, fill, line, col], i) => {
  s.chip(t, 0.6 + i * 2.42, 4.45, 2.3, { fill, line, color: col, fs: 11, h: 0.45 });
});
s.img('ch12/10-audit.png', 0.6, 5.1, 12.0, 1.5, 'audit:broker 看到的主體是 User:legacy-orders(不是 restproxy)');
s.text('官方:憑證身分只能綁 User:,不支援群組', 0.6, 6.7, 12.0, 0.3, { fs: 11, color: C.red });

// ───────── REST Proxy 身分傳遞(人 vs 機器) ─────────
s = slide('REST Proxy:身分怎麼傳到 broker', '人與機器走不同的路,最後都用 MDS 簽發的 token 連 broker');
const flowRow = (y, color, pale, title, steps) => {
  s.box(0.6, y, 12.0, 2.15, { fill: pale, noline: true });
  s.text(title, 0.8, y + 0.05, 8, 0.4, { fs: 16, bold: true, color });
  steps.forEach(([head, sub], i) => {
    const x = 0.8 + i * 2.35;
    s.tbox(head + '\n' + sub, x, y + 0.55, 1.95, 1.4, { fill: C.white, line: color, lw: 1.5, fs: 11, bold: true, color: C.ink });
    s.tbox(String(i + 1), x - 0.12, y + 0.42, 0.32, 0.32, { fill: color, line: color, color: C.white, fs: 11, bold: true, shape: SH.ellipse, margin: 0 });
    if (i < steps.length - 1) s.arrow(x + 1.95, y + 1.25, x + 2.35, y + 1.25, { color, w: 2.5 });
  });
};
flowRow(1.8, C.blue, C.pBlue, '人:Basic 帳密 → MDS 向 AD 驗證 → 直接換 token', [
  ['yujie', 'Basic 帳密\n(AD)'], ['REST Proxy', '把帳密轉給 MDS'], ['MDS /authenticate', '查 AD(LDAP)\n回 token'], ['token', 'JWT · 1 小時\nsub = yujie'], ['broker', 'OAUTHBEARER\nUser:yujie']]);
flowRow(4.15, C.orange, C.pOrange, '機器:client 憑證 → REST Proxy 向 MDS「代為申請」token', [
  ['legacy app', 'client 憑證\nCN=legacy-orders'], ['REST Proxy', 'DN → 主體\n(不問 MDS)'], ['MDS /impersonate', '用 restproxy 憑證\n代 legacy-orders'], ['token', 'sub = legacy-orders\ncp_proxy = restproxy'], ['broker', 'OAUTHBEARER\nUser:legacy-orders']]);
s.text('依據:MDS 請求日誌與手動重現(實測)。人與機器的主體都由 token 的 sub 決定。', 0.6, 6.5, 12.0, 0.3, { fs: 11, color: C.grey });

// ───────── REST Proxy 憑證能代誰(受保護清單) ─────────
s = slide('REST Proxy 憑證 = 可代任何人?', '把「特權身分」加進受保護清單(impersonation protected users)');
const panel = (x, title, fill, line, rows) => {
  s.box(x, 1.8, 5.9, 3.55, { fill, noline: true });
  s.text(title, x + 0.2, 1.85, 5.5, 0.45, { fs: 18, bold: true, color: line });
  const style = {
    normal: ['可代(一般使用者,正常)', { fill: C.pBlue, line: C.blue, color: C.blue }],
    danger: ['可代 ⚠ 可升為管理員', { fill: C.pRed, line: C.red, color: C.red }],
    blocked: ['擋下', { fill: C.white, line: C.green, color: '1E6B2B' }],
  };
  rows.forEach(([name, code, kind], i) => {
    const y = 2.4 + i * 0.5;
    s.icon('FaUser', x + 0.25, y + 0.04, 0.32, C.grey);
    s.text(name, x + 0.7, y, 2.5, 0.4, { fs: 12, bold: true, color: C.ink });
    const [label, st] = style[kind];
    s.chip(code + ' ' + label, x + 3.05, y + 0.02, 2.7, { ...st, fs: 10, h: 0.36 });
  });
};
panel(0.6, '修正前:只保護 broker 與 bootstrap', C.pRed, C.red, [['yujie / legacy-orders', '200', 'normal'], ['gary(SystemAdmin)', '200', 'danger'], ['c3(SystemAdmin)', '200', 'danger'], ['bootstrap / kafka-broker', '403', 'blocked']]);
panel(6.7, '修正後:特權身分全部列入', C.pGreen, C.green, [['yujie / legacy-orders', '200', 'normal'], ['gary', '403', 'blocked'], ['c3', '403', 'blocked'], ['bootstrap / kafka-broker / restproxy', '403', 'blocked']]);
s.chip('1  特權身分逐一以 User: 列入 protected.users(gary、c3…)', 0.6, 5.55, 5.9, { fill: C.pBlue, line: C.blue, color: C.blue, fs: 12, h: 0.42 });
s.chip('2  保護 client-restproxy 私鑰的檔案權限', 6.7, 5.55, 5.9, { fill: C.pBlue, line: C.blue, color: C.blue, fs: 12, h: 0.42 });
s.chip('3  監看 MDS 日誌中 restproxy 的 /impersonate 呼叫', 0.6, 6.05, 5.9, { fill: C.pBlue, line: C.blue, color: C.blue, fs: 12, h: 0.42 });
s.chip('⚠ 清單混入 Group: 項目 → 整份失效(實測);新增管理員要同步更新', 0.6, 6.55, 12.0, { fill: C.pRed, line: C.red, color: C.red, fs: 12, h: 0.42 });
s.chip('⚠ audit 的 actingPrincipal 為空:看不出請求經過 REST Proxy', 6.7, 6.05, 5.9, { fill: C.pRed, line: C.red, color: C.red, fs: 12, h: 0.42 });

// ───────── C3:誰連到誰(人 vs 機器) ─────────
s = slide('Control Center:誰連到誰', '人用本人身分,機器用自己的身分(憑證)');
s.node(0.6, 1.9, 2.9, 1.2, 'FaUser', 'gary / ming', '瀏覽器 · AD 帳密', { line: C.blue, sfs: 11 });
s.node(0.6, 4.7, 2.9, 1.2, 'FaFileCode', 'CI / 自動化', '憑證 → MDS token', { line: C.orange, color: C.orange, sfs: 11 });
s.tbox('Control Center', 4.7, 3.1, 3.0, 1.6, { fill: C.ink, line: C.ink, color: C.white, fs: 20, bold: true, r: 0.25 });
s.node(9.5, 1.7, 3.1, 1.1, 'FaShieldAlt', 'MDS', '驗證 + 授權', { line: C.green, color: C.green, sfs: 11 });
s.node(9.5, 3.35, 3.1, 1.1, 'FaServer', 'broker', 'RBAC', { line: C.green, color: C.green, sfs: 11 });
s.node(9.5, 5.0, 3.1, 1.1, 'FaChartLine', 'Prometheus\nAlertmanager', '', { line: C.red, color: C.red, fs: 13 });
s.arrow(3.5, 2.5, 4.7, 3.5, { color: C.blue, w: 3 });
s.text('Basic 一次 → Bearer', 3.7, 2.1, 2.4, 0.3, { fs: 10, bold: true, color: C.blue });
s.arrow(3.5, 5.3, 4.7, 4.3, { color: C.orange, w: 3 });
s.text('憑證 → token → Bearer', 3.7, 5.35, 2.5, 0.3, { fs: 10, bold: true, color: C.orange });
s.arrow(7.7, 3.4, 9.5, 2.3, { color: C.blue, w: 2.5 });
s.text('使用者 token / c3 憑證', 7.4, 2.0, 2.1, 0.3, { fs: 10, bold: true, color: C.blue });
s.arrow(7.7, 3.9, 9.5, 3.9, { color: C.blue, w: 2.5 });
s.text('OAUTHBEARER', 7.85, 3.55, 1.6, 0.3, { fs: 10, bold: true, color: C.blue });
s.arrow(7.7, 4.4, 9.5, 5.5, { color: C.red, w: 2.5, dash: 'dash' });
s.text('未認證', 8.1, 5.0, 1.0, 0.3, { fs: 10, bold: true, color: C.red });
s.tbox('使用者操作 → 帶使用者本人身分(audit:User:ming)', 0.6, 6.3, 5.9, 0.5, { fill: C.pBlue, line: C.blue, color: C.blue, fs: 12, bold: true, r: 0.25 });
s.tbox('背景串流 → User:c3(SystemAdmin,憑證換 token)', 6.7, 6.3, 5.9, 0.5, { fill: C.pOrange, line: C.orange, color: '9A5B00', fs: 12, bold: true, r: 0.25 });

// ───────── C3 的風險 ─────────
s = slide('C3 的三個風險', '都是實測發現,導入時要處理');
[['FaKey', 'c3 的憑證 = 管理員', '換到的 token 可建立 / 刪除 role binding(204)', '拿掉權限 C3 會退出,無法降權;嚴控 keystore、列入保護清單', C.red],
  ['FaChartLine', 'Prometheus 預設未認證', '本 demo 不帶憑證即可讀指標(200)', '官方支援 TLS + Basic;未啟用時網路隔離', C.orange],
  ['FaBell', 'Alertmanager 可寫', '本 demo 不帶憑證即可建立靜音(200)→ 能靜音告警', '啟用 TLS + Basic;監看靜音變更', C.red]].forEach(([ic, h, found, fix, col], k) => {
  const x = 0.6 + k * 4.1;
  s.tbox('', x, 1.85, 3.8, 4.3, { fill: C.white, line: col, lw: 1.75 });
  s.badge(ic, x + 1.9, 2.7, 1.1, { fill: C.pGrey, color: col });
  s.text(h, x + 0.2, 3.5, 3.4, 0.5, { fs: 17, bold: true, color: C.ink, align: 'center' });
  s.tbox('實測:' + found, x + 0.25, 4.1, 3.3, 0.95, { fill: C.pRed, line: col, color: col, fs: 11, bold: true, r: 0.12 });
  s.tbox('對策:' + fix, x + 0.25, 5.15, 3.3, 0.85, { fill: C.pGreen, line: C.green, color: '1E6B2B', fs: 11, bold: true, r: 0.12 });
});
s.tbox('官方 C3 頁的 MDS 範例是帳密(mTLS 頁另有憑證範例);官方未說 C3 以誰的身分查 Kafka。本環境:使用者操作帶使用者身分(實測)', 0.6, 6.3, 12.0, 0.5, { fill: C.pOrange, line: C.orange, color: '9A5B00', fs: 11, bold: true, r: 0.25 });

// ───────── broker 內建 Admin REST ─────────
s = slide('broker 內建 Admin REST', '與 MDS 共用 8091:未設定時完全無認證');
s.tbox('', 0.6, 1.85, 5.9, 3.0, { fill: C.pRed, line: C.red, lw: 1.75 });
s.text('未設定(預設)', 0.85, 1.95, 5.4, 0.45, { fs: 18, bold: true, color: C.red });
s.chip('匿名 GET /kafka/v3/clusters → 直接進入', 0.85, 2.6, 5.4, { fill: C.white, line: C.red, color: C.red, fs: 12, h: 0.42 });
s.chip('曾使 broker 記憶體耗盡而崩潰(2 次)', 0.85, 3.15, 5.4, { fill: C.white, line: C.red, color: C.red, fs: 12, h: 0.42 });
s.chip('固定 SCRAM 身分的錯誤設法 → 人人變超級使用者', 0.85, 3.7, 5.4, { fill: C.white, line: C.red, color: C.red, fs: 12, h: 0.42 });
s.tbox('', 6.7, 1.85, 5.9, 3.0, { fill: C.pGreen, line: C.green, lw: 1.75 });
s.text('依官方 kafka.rest. 設定後', 6.95, 1.95, 5.4, 0.45, { fs: 18, bold: true, color: '1E6B2B' });
s.chip('匿名 / 錯誤密碼 → 401', 6.95, 2.6, 5.4, { fill: C.white, line: C.green, color: '1E6B2B', fs: 12, h: 0.42 });
s.chip('gary(AD 帳密)→ 列 topic、produce 成功', 6.95, 3.15, 5.4, { fill: C.white, line: C.green, color: '1E6B2B', fs: 12, h: 0.42 });
s.chip('ming(無 role)→ 清單空、produce 被拒 40301', 6.95, 3.7, 5.4, { fill: C.white, line: C.green, color: '1E6B2B', fs: 12, h: 0.42 });
s.img('ch14/01-anon.png', 0.6, 5.05, 5.9, 1.0, '匿名 → 401');
s.img('ch14/05-ming-produce.png', 6.7, 5.05, 5.9, 1.0, 'ming produce:HTTP 200,內容 error_code 40301');
s.tbox('⚠ 被拒時 HTTP 狀態仍是 200,錯誤在內容裡:監控要看 error_code。8091 同時是 MDS 埠,不能整個用防火牆擋掉', 0.6, 6.3, 12.0, 0.5, { fill: C.pOrange, line: C.orange, color: '9A5B00', fs: 12, bold: true, r: 0.25 });

// ───────── 21 實測發現 ─────────
s = slide('實測發現(與預期不同)', '都在 demo 環境實際踩過,導入時預先處理');
[['FaServer', 'controller 的群組解析', '實測:controller 不需 LDAP 設定(官方:只有 MDS writer broker 連 LDAP)', C.red], ['FaDesktop', 'C3 → Kafka', 'RBAC 下只能 OAUTHBEARER(官方原句);憑證換 token', C.blue], ['FaKey', 'MDS 雙認證', '憑證認證:官方 7.8+ 支援,可與 LDAP 並存(官方有說明)', C.green],
  ['FaClock', '群組生效時間', 'demo 5 秒 · 官方預設 60 秒(persistent search 在 Java 17+ 需額外 JVM 參數)', C.orange], ['FaShieldAlt', '內部埠', '任何 SCRAM 帳號可認證 → 防火牆', C.red], ['FaUserCog', '預設 role 邊界', 'Operator 不能建 topic;改設定要 ResourceOwner 或 ClusterAdmin', C.blue]].forEach(([ic, h, sub, col], i) => {
  const x = 0.6 + (i % 3) * 4.1, y = 1.85 + Math.floor(i / 3) * 2.45;
  s.tbox('', x, y, 3.8, 2.25, { fill: C.white, line: col, lw: 1.5 });
  s.badge(ic, x + 1.9, y + 0.7, 0.95, { fill: C.pGrey, color: col });
  s.text(h, x + 0.2, y + 1.3, 3.4, 0.4, { fs: 16, bold: true, color: C.ink, align: 'center' });
  s.text(sub, x + 0.2, y + 1.7, 3.4, 0.5, { fs: 12, color: C.grey, align: 'center', valign: 'top' });
});

section('導入與結論', '客戶前提、導入階段、結論');

// ───────── 23 客戶前提 ─────────
s = slide('導入前提:請客戶回覆', '四件事');
[['FaUserShield', 'AD 唯讀查詢帳號', 'bind DN · 只讀 user / group OU · 建議 LDAPS', C.red], ['FaCertificate', '憑證來源', '有無 AD CS · 根憑證放系統信任 + Java', C.blue],
  ['FaFileContract', '授權 license', 'RBAC · LDAP · audit · C3 · REST Proxy 外掛', C.orange], ['FaSitemap', 'AD 群組結構', '是否巢狀 · 帳號大小寫 · 鎖定政策', C.green]].forEach(([ic, h, sub, col], i) => {
  const x = 0.6 + (i % 2) * 6.1, y = 1.85 + Math.floor(i / 2) * 2.45;
  s.tbox('', x, y, 5.9, 2.25, { fill: C.white, line: col, lw: 1.5 });
  s.badge(ic, x + 1.0, y + 1.12, 1.2, { fill: C.pGrey, color: col });
  s.text(h, x + 1.95, y + 0.45, 3.8, 0.55, { fs: 20, bold: true, color: C.ink });
  s.text(sub, x + 1.95, y + 1.05, 3.8, 0.9, { fs: 13, color: C.grey, valign: 'top' });
});

// ───────── 24 導入階段 ─────────
s = slide('導入階段', '沒有 Ansible:先把手動流程標準化,日後再自動化');
s.tbox('RHEL 9:controller 先 --add-scram  ·  防火牆限制 9092/9093  ·  Java 21', 0.6, 1.8, 12.0, 0.5, { fill: C.pOrange, line: C.orange, color: '9A5B00', fs: 14, bold: true });
[['起步', 'FaDesktop', 'C3 + AD 登入\n腳本讀各人設定', 'E4EFF7', 1.9], ['進階', 'FaLock', '跳板機 + 個人 AD\n密碼庫 · 憑證到期提醒', 'CFE3F2', 2.9], ['成熟', 'FaCogs', 'Ansible / IaC\n人唯讀 + break-glass', 'B7D5EC', 3.9]].forEach(([h, ic, t, fill, hh], i) => {
  const x = 0.8 + i * 4.0, y = 6.8 - hh;
  s.shape(SH.rect, x, y, 3.8, hh, { fill, noline: true, r: 0 });
  s.icon(ic, x + 0.25, y + 0.2, 0.6, C.blue);
  s.text(h, x + 1.0, y + 0.15, 2.6, 0.7, { fs: 24, bold: true, color: C.ink });
  s.text(t, x + 0.25, y + 0.95, 3.4, 0.9, { fs: 14, color: C.text, valign: 'top' });
});

// ───────── 25 結論 ─────────
s = slide('結論', '五個重點');
[['FaUsers', 'AD 管人:群組授權,異動只動 AD', C.blue], ['FaRobot', 'Kafka 管機器:SCRAM + 最小權限', C.orange], ['FaKey', '共用憑證只做加密', C.green],
  ['FaTerminal', '腳本共用 · 憑證各人 · 排程用服務身分', C.blue], ['FaUserShield', '正式環境人唯讀 · 管理與授權用群組分權', C.red]].forEach(([ic, t, col], i) => {
  const y = 1.8 + i * 1.0;
  s.badge(ic, 1.2, y + 0.42, 0.8, { fill: C.pGrey, color: col });
  s.text(t, 2.0, y, 10.5, 0.85, { fs: 22, bold: true, color: C.ink });
  s.shape(SH.line, 0.8, y + 0.92, 11.8, 0, { line: C.line, width: 0.75 });
});

back('謝謝', 'Q & A');

build(OUT).then(() => (process.env.PREVIEW ? require('./preview').renderPreview(SLIDES, ICONS, path.join(__dirname, 'preview')) : null)).catch(e => { console.error('ERR', e); process.exit(1); });
