// 由 build.mjs 產生 build-story.mjs 的一次性修補腳本(故事版手冊)。
import fs from 'node:fs';
let s = fs.readFileSync('build-story.mjs', 'utf8');
const rep = (from, to, all = false) => {
  if (!s.includes(from)) throw new Error('找不到:' + from.slice(0, 60));
  s = all ? s.split(from).join(to) : s.replace(from, () => to);
};
const between = (a, b, to) => {
  const i = s.indexOf(a), j = s.indexOf(b);
  if (i < 0 || j < 0 || j < i) throw new Error('範圍不存在:' + a.slice(0, 40) + ' … ' + b.slice(0, 40));
  s = s.slice(0, i) + to + s.slice(j);
};

// 1. 匯入
rep("import { LABS, SETUP, IDENTITIES } from './labs.mjs';",
`import { LABS as LABS0, SETUP, IDENTITIES } from './labs.mjs';
import { LABS_EXTRA } from './labs-extra.mjs';
import * as S from './story.mjs';
const LABS = [...LABS0, ...LABS_EXTRA];
const VERIFY_NOTE = process.env.VERIFY_NOTE || '(驗證說明待填)';`);

// 2. 故事用的版面元件
rep("const H2 = t =>", `const STORY_C = '6B4FA0';
const H3 = t => new Paragraph({ heading: HeadingLevel.HEADING_3, children: [new TextRun({ text: t, font: FONT })], keepNext: true });
const H2pb = t => new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun({ text: t, font: FONT })], pageBreakBefore: true });
// 故事框:左側紫色粗線 + 淡紫底;kind 決定標籤
function storyBox(tag, paras, { fill = 'F4F0FA' } = {}) {
  const b = { style: BorderStyle.SINGLE, size: 4, color: 'DDD3EC' };
  return [new Table({
    width: { size: W, type: WidthType.DXA }, columnWidths: [W],
    rows: [new TableRow({ children: [new TableCell({
      width: { size: W, type: WidthType.DXA }, shading: { type: ShadingType.CLEAR, fill, color: 'auto' },
      margins: { top: 100, bottom: 100, left: 180, right: 180 },
      borders: { top: b, bottom: b, right: b, left: { style: BorderStyle.SINGLE, size: 30, color: STORY_C } },
      children: [
        new Paragraph({ spacing: { after: 60 }, children: [new TextRun({ text: tag, font: FONT, size: 19, bold: true, color: STORY_C })] }),
        ...paras.map(t => new Paragraph({ spacing: { after: 70, line: 312 }, children: [new TextRun({ text: t, font: FONT, size: 21, color: '2B2540' })] })),
      ],
    })] })],
  }), new Paragraph({ spacing: { after: 100 }, children: [] })];
}
const H2 = t =>`);

// 3. 封面 → 新封面與故事背景
between('// 封面', '// 目錄', `// 封面
add(
  new Paragraph({ spacing: { before: 2200, after: 160 }, children: [new TextRun({ text: 'Confluent Platform 安全方案', font: FONT, size: 44, bold: true, color: MUTE })] }),
  new Paragraph({ spacing: { after: 140 }, children: [new TextRun({ text: S.TITLE, font: FONT, size: 72, bold: true, color: STORY_C })] }),
  new Paragraph({ spacing: { after: 300 }, children: [new TextRun({ text: S.SUBTITLE, font: FONT, size: 36, bold: true, color: TEAL })] }),
  new Paragraph({ spacing: { after: 400 }, children: [new TextRun({ text: S.TAGLINE, font: FONT, size: 24, color: MUTE })] }),
  P([run('這是一個故事:新進維運工程師「明」,在前三週裡一個個處理真實會遇到的問題。每個 Lab 先說「為什麼要做這件事」,再給可直接貼上的指令,最後附上本環境實際執行的輸出與畫面。', { size: 22 })]),
  spacer(),
  ...table([
    ['項目', '內容'],
    ['平台版本', 'Confluent Platform 8.3.2(KRaft、MDS RBAC)、Control Center next-gen 2.6.1、REST Proxy 8.3.2'],
    ['目錄服務', 'OpenLDAP(以 AD 屬性模擬;非真 AD,細節見「如何使用本手冊」的限制說明)'],
    ['環境', 'Docker Compose(Windows 11 + Git Bash 驗證;Linux/macOS 指令相同)'],
    ['證據', '所有「實際輸出」與截圖均來自本環境實跑(專案 demo/evidence/)'],
    ['與舊版手冊', '本版以故事串起來,並新增 Lab 15(人員異動)與 Lab 16(OP menu);舊版 Confluent-Security-Lab-Guide.docx 保留'],
  ], [2200, 6826]),
  new Paragraph({ children: [new PageBreak()] }),
);

`);

// 4. 目錄後、「如何使用本手冊」前:故事背景
rep("// 第 1 章:如何使用本手冊", `// 故事背景與角色
add(H1('故事背景與角色'));
S.SETTING.forEach(t => add(P(t)));
add(...table([['規矩', '意思'], ...S.RULES], [2400, 6626], { size: 19 }));
add(H2('角色'));
add(...table([['角色', '在故事裡是誰', 'Demo 帳號'], ...S.CAST], [1500, 3900, 3626], { size: 18 }));
add(H2('三週的路線圖'));
add(...table([['時間', '主題', '對應 Lab'], ...S.ACTS.map(a => [a.when, a.title.replace(/^[^::]*[::]\\s*/, ''), a.labs.map(n => 'Lab ' + n).join('、')])], [1800, 4926, 2300], { size: 18 }));
add(...callout('tip', '每個 Lab 的編號就是 ./demo.sh 的章節編號(Lab 5 對應 ./demo.sh 5)。選修的 Lab 8、9 不影響後面的內容,趕時間可以跳過。'));

// 第 1 章:如何使用本手冊`);

// 5. Lab 迴圈 → 依「幕」組織
between('// ---------- Labs ----------', '// ---------- 附錄 ----------', `// ---------- Labs(依故事的幕組織)----------
const labOf = n => LABS.find(l => l.n === n);
function renderLab(lab) {
  add(H2pb(\`Lab \${lab.n}  \${lab.title}\`));
  const st = S.LAB_STORY[lab.n];
  if (st) {
    add(...storyBox('情境', st.scene));
    add(label('明的任務', STORY_C)); st.mission.forEach(t => add(bullet(t)));
  }
  add(...table([
    ['項目', '內容'],
    ['目標', lab.goal],
    ['預估時間', lab.time],
    ['前置條件', lab.pre.join('\\n')],
  ], [1700, 7326], { size: 19 }));
  if (lab.table) { add(label('盤點表', TEAL)); add(...table(lab.table.rows, lab.table.colW, { size: 17 })); }
  if (lab.pre_cmd) { add(label('開始前的起點狀態(重置)', AMBER)); add(...code(lab.pre_cmd.join('\\n'))); }
  if (lab.autoAll) { add(label('整個 Lab 一鍵跑完(專案包好的指令)', GREEN)); add(...code(lab.autoAll.join('\\n'), { bar: GREEN })); }
  for (const s of lab.steps) {
    add(H3(s.t));
    if (s.why) add(P(s.why));
    if (s.ui) { add(label('介面操作(瀏覽器 / Postman)', TEAL)); add(...numbered(s.ui)); }
    if (s.uiEq) { add(label('不用點介面的等效指令(API / CLI)', MUTE)); add(...code(s.uiEq.join('\\n'), { bar: MUTE })); }
    if (s.cfg) { add(label('設定內容(已包含在本環境的 docker-compose;客戶 VM 上寫入 kafka-rest.properties)', MUTE)); add(...code(s.cfg.join('\\n'), { bar: MUTE })); }
    if (s.manual && s.manual.length) { add(label('手動指令', TEAL)); add(...code(s.manual.join('\\n'))); }
    if (s.auto) { add(label('專案包好的指令', GREEN)); add(...code(s.auto.join('\\n'), { bar: GREEN })); }
    const outs = [];
    for (const k of ['ev', 'evb', 'evc']) if (s[k]) { const o = evidenceOut(lab.id, s[k]); if (o) outs.push(o); else missing.push(\`\${lab.id}/\${s[k]}.log\`); }
    if (s.ev0) { const o = evidenceOut('ch00', s.ev0); if (o) outs.push(o); else missing.push(\`ch00/\${s.ev0}.log\`); }
    if (outs.length) {
      add(label('預期結果(實際執行輸出)', AMBER));
      outs.forEach(o => add(...code(o, { fill: 'FBF6EC', bar: AMBER, maxLines: 14, cut: 150 })));
    }
    if (s.expect) add(P([run('預期:', { bold: true, color: AMBER }), run(s.expect)]));
    for (const [rel, cap] of s.imgs || []) add(...image(rel, cap));
    if (s.warn) add(...callout('warn', s.warn));
    if (s.tip) add(...callout('tip', s.tip));
  }
  if (st) add(...storyBox('小結:明學到了什麼', st.recap.map(t => '• ' + t), { fill: 'EEF6F1' }));
}
for (const act of S.ACTS) {
  add(H1(act.title));
  add(...storyBox(act.when, act.scene));
  for (const n of act.labs) { const lab = labOf(n); if (!lab) { missing.push('Lab ' + n); continue; } renderLab(lab); }
}

// 終章
add(H1(S.EPILOGUE.title));
add(...storyBox('一個月後', S.EPILOGUE.scene));
add(...table([['還沒驗證或要補的', '說明'], ...S.EPILOGUE.todo], [2600, 6426], { size: 18 }));

`);

// 6. 疑難排解多一列、驗證說明
rep("['記憶體不足',", `['docker 綁不上主機埠(ports are not available … forbidden by its access permissions)', 'Windows 每次開機可能保留一段埠範圍(netsh int ipv4 show excludedportrange protocol=tcp),落在範圍內的埠(例如 8086、8091、8092)docker 綁不上。在 demo/.env 設 HOST_PORT_MDS、HOST_PORT_MDS2、HOST_PORT_RESTPROXY 等覆蓋;up.sh 與 preflight.sh 會讀同一份。Postman 的 environment 也要改成同樣的埠。'],
  ['記憶體不足',`);
rep("都在本環境依 Lab 順序實際執行過(Lab 0 到 14,自動判定 0 項失敗,並人工檢視輸出);", "' + VERIFY_NOTE + '");

// 7. 附錄:專案檔案索引更新 + 附錄 D
rep("['demo/scenarios/ch01…ch14-*.sh', '各 Lab 的整章腳本(含自動驗證)'],", "['demo/scenarios/ch01…ch16-*.sh', '各 Lab 的整章腳本(含自動驗證);ch15 人員異動、ch16 OP menu'],\n  ['demo/opmenu/', 'OP menu 程式(README.md 說明項目、設定與限制;test-*.sh 回歸測試)'],\n  ['demo/spike/lb-nginx、rp-mds-failover', '負載平衡器與多台 MDS 的實驗(FINDINGS.md)'],");
rep("add(H2('client 設定檔範例'));", `add(H1('附錄 D  負載平衡器與多台 MDS(實驗摘要)'));
add(P('客戶使用 F5。以下用 nginx 模擬兩種虛擬伺服器的做法,看 legacy app 的 client 憑證身分還傳不傳得到 REST Proxy。完整過程見 demo/spike/lb-nginx/FINDINGS.md。nginx 只能驗證邏輯,F5 本身的行為(虛擬伺服器類型、persistence、TCP idle timeout、SNAT、iRule、Server SSL profile 的 session 復用)要請客戶的 F5 管理者確認。'));
add(...table([
  ['LB 設定', 'legacy-orders', 'legacy-other(無授權)', '不帶憑證'],
  ['直連(基線)', '200', '403', '401'],
  ['L4 TCP 透傳', '200', '403', '401;偽造憑證在 TLS 就被拒'],
  ['L7 終止 TLS,連後端不帶憑證', '401', '—', '401'],
  ['L7 終止 TLS,憑證資訊放 header', '401(REST Proxy 不認 header)', '—', '—'],
  ['L7 終止 TLS,LB 用固定一張 client 憑證', '200', '200(應為 403)', '200(應為 401)'],
], [3100, 1900, 2000, 2026], { size: 17 }));
[
  '要保留 legacy app 的 mTLS 身分,LB 必須是 L4 透傳;L7 終止 TLS 會讓 REST Proxy 看不到 client 憑證。',
  '「LB 用一張固定憑證連後端」是危險的修法:所有呼叫者(含沒有憑證的人)都變成同一個身分,audit 也只看得到那一個身分。',
  'L4 透傳時,server 憑證的 SAN 必須包含 LB 的主機名,否則用 LB 名稱連線會 TLS 主機名驗證失敗。',
  'REST Proxy 到 MDS 這段(/authenticate、/impersonate 認的是憑證身分)同理:L4 可,L7 終止 TLS 會 401。',
  'REST Proxy 設定兩台 MDS 時,停任一台 MDS 請求仍成功(第一個受影響的請求約 8 秒),所以 REST Proxy 到 MDS 不需要放 LB。未驗證:MDS 卡住(不回應)時的切換時間。',
  'REST Proxy 的 v2 consumer 有狀態,多台 REST Proxy 前面的 LB 需要 sticky session(官方文件;本 demo 未實測)。',
  '實驗陷阱:nginx 預設的 upstream TLS session 復用,會讓後端沿用先前連線的憑證身分,結果隨測試順序變;關掉(proxy_ssl_session_reuse off)後才穩定。',
].forEach(t => add(bullet(t)));
add(H2('client 設定檔範例'));`);

// 8. 文件資訊與輸出
rep("title: 'Confluent Platform 安全方案 手把手 Lab 手冊', description: 'AD 只放 user/group 的 Confluent 安全方案實作手冊'", "title: 'Confluent Platform 安全方案:明的前三週(故事版 Lab 手冊)', description: 'AD 只放 user/group 的 Confluent 安全方案實作手冊,以新進維運工程師的故事串起所有 Lab'");
rep("'Confluent Platform 安全方案 · Lab 手冊'", "'Confluent Platform 安全方案 · 明的前三週'");
rep("'Confluent-Security-Lab-Guide.docx'", "'Confluent-Security-Lab-Story-Guide.docx'");
// Heading3 樣式
rep("      { id: 'Heading2',", "      { id: 'Heading3', name: 'Heading 3', basedOn: 'Normal', next: 'Normal', quickFormat: true, run: { font: FONT, size: 23, bold: true, color: INK }, paragraph: { spacing: { before: 220, after: 80 }, outlineLevel: 2 } },\n      { id: 'Heading2',");

fs.writeFileSync('build-story.mjs', s);
console.log('patched build-story.mjs');
