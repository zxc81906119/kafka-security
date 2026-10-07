// 產生 Word 手冊:Confluent Platform 安全方案 —— 手把手 Lab 手冊
// 內容來自 labs.mjs;「實際輸出」來自 evidence/*/NN-slug.log(實跑結果);圖片來自 evidence/**.png
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  Document, Packer, Paragraph, TextRun, HeadingLevel, Table, TableRow, TableCell, WidthType, ShadingType, BorderStyle,
  AlignmentType, ImageRun, LevelFormat, PageBreak, TableOfContents, Footer, Header, PageNumber, TabStopType,
} from 'docx';
import { LABS, SETUP, IDENTITIES } from './labs.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const EV = path.resolve(here, '..', 'evidence');
const FONT = 'Microsoft JhengHei', MONO = 'Consolas';
const INK = '12263A', TEAL = '1F7A8C', AMBER = 'B7791F', RED = 'B03A2E', GREEN = '1E7B3A', MUTE = '5B6B7A';
const W = 9026; // A4、邊界 1 吋後的內容寬度(DXA)
const missing = [];

// ---------- 基本元件 ----------
const run = (text, o = {}) => new TextRun({ text, font: FONT, size: 21, ...o });
const P = (children, o = {}) => new Paragraph({ spacing: { after: 100, line: 300 }, ...o, children: Array.isArray(children) ? children : [run(children)] });
const H1 = t => new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun({ text: t, font: FONT })], pageBreakBefore: true });
const H1n = t => new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun({ text: t, font: FONT })] });
const H2 = t => new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun({ text: t, font: FONT })], keepNext: true });
const label = (t, color = TEAL) => new Paragraph({ keepNext: true, spacing: { before: 120, after: 60 }, children: [new TextRun({ text: t, font: FONT, size: 20, bold: true, color })] });
const bullet = (t, o = {}) => new Paragraph({ numbering: { reference: 'bullets', level: 0 }, spacing: { after: 60, line: 288 }, children: [run(t, o)] });
let inst = 0;
const numbered = items => { inst++; return items.map(t => new Paragraph({ numbering: { reference: 'nums', level: 0, instance: inst }, spacing: { after: 60, line: 288 }, children: [run(t)] })); };

const codeBorder = c => ({ top: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' }, bottom: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' }, right: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' }, left: { style: BorderStyle.SINGLE, size: 18, color: c, space: 6 } });
function codeLines(text, { fill = 'F1F4F7', bar = TEAL, maxLines = 0, cut = 0 } = {}) {
  let lines = String(text).replace(/\r/g, '').split('\n');
  if (maxLines && lines.length > maxLines) lines = [...lines.slice(0, maxLines), '…(以下略,完整內容見 evidence 檔)'];
  if (cut) lines = lines.map(l => (l.length > cut ? l.slice(0, cut) + '…' : l));
  return lines.map(l => new Paragraph({
    spacing: { after: 0, line: 252 }, shading: { type: ShadingType.CLEAR, fill, color: 'auto' }, border: codeBorder(bar), indent: { left: 140, right: 60 },
    children: [new TextRun({ text: l === '' ? ' ' : l, font: MONO, size: 17, color: '1B2733' })],
  }));
}
const spacer = () => new Paragraph({ spacing: { after: 80 }, children: [] });
const code = (text, o) => [...codeLines(text, o), spacer()];

function callout(kind, text) {
  const cfg = { tip: ['提示', 'E8F4F7', TEAL], warn: ['注意', 'FDECEA', RED], key: ['重點', 'FFF4E0', AMBER] }[kind];
  const b = { style: BorderStyle.SINGLE, size: 4, color: 'D5DEE6' };
  return [new Table({
    width: { size: W, type: WidthType.DXA }, columnWidths: [W],
    rows: [new TableRow({ children: [new TableCell({
      width: { size: W, type: WidthType.DXA }, shading: { type: ShadingType.CLEAR, fill: cfg[1], color: 'auto' },
      margins: { top: 80, bottom: 80, left: 140, right: 140 },
      borders: { top: b, bottom: b, right: b, left: { style: BorderStyle.SINGLE, size: 24, color: cfg[2] } },
      children: [new Paragraph({ spacing: { after: 0, line: 288 }, children: [new TextRun({ text: cfg[0] + ':', font: FONT, size: 20, bold: true, color: cfg[2] }), run(text, { size: 20 })] })],
    })] })],
  }), spacer()];
}

function table(rows, colW, { head = true, size = 19 } = {}) {
  const b = { style: BorderStyle.SINGLE, size: 4, color: 'C9D3DC' };
  const total = colW.reduce((a, c) => a + c, 0);
  return [new Table({
    width: { size: total, type: WidthType.DXA }, columnWidths: colW,
    rows: rows.map((r, ri) => new TableRow({ tableHeader: head && ri === 0, cantSplit: true, children: r.map((c, ci) => new TableCell({
      width: { size: colW[ci], type: WidthType.DXA }, margins: { top: 60, bottom: 60, left: 100, right: 100 },
      borders: { top: b, bottom: b, left: b, right: b },
      shading: { type: ShadingType.CLEAR, fill: head && ri === 0 ? INK : (ri % 2 ? 'FFFFFF' : 'F1F5F8'), color: 'auto' },
      children: [new Paragraph({ spacing: { after: 0, line: 276 }, children: [new TextRun({ text: String(c), font: FONT, size, bold: head && ri === 0, color: head && ri === 0 ? 'FFFFFF' : '22313F' })] })],
    })) })),
  }), spacer()];
}

function pngSize(f) { const b = fs.readFileSync(f); return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) }; }
function image(rel, cap) {
  const f = path.join(EV, rel);
  if (!fs.existsSync(f)) { missing.push(rel); return [P([run(`[缺圖:${rel}]`, { color: RED })])]; }
  const s = pngSize(f);
  const maxW = 590, maxH = 430;
  const r = Math.min(maxW / s.w, maxH / s.h, 1.0);
  const w = Math.round(s.w * r), h = Math.round(s.h * r);
  return [
    new Paragraph({ alignment: AlignmentType.CENTER, keepNext: true, spacing: { before: 80, after: 40 }, border: { top: { style: BorderStyle.SINGLE, size: 4, color: 'C9D3DC', space: 4 }, bottom: { style: BorderStyle.SINGLE, size: 4, color: 'C9D3DC', space: 4 }, left: { style: BorderStyle.SINGLE, size: 4, color: 'C9D3DC', space: 4 }, right: { style: BorderStyle.SINGLE, size: 4, color: 'C9D3DC', space: 4 } },
      children: [new ImageRun({ type: 'png', data: fs.readFileSync(f), transformation: { width: w, height: h }, altText: { title: cap, description: cap, name: path.basename(rel) } })] }),
    new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 140 }, children: [new TextRun({ text: '▲ ' + cap, font: FONT, size: 18, color: MUTE, italics: true })] }),
  ];
}

// 讀取證據 log(去掉前兩行:標題與指令);ch00 的自備 log 同格式
function evidenceOut(ch, slug) {
  const dir = path.join(EV, ch);
  if (!fs.existsSync(dir)) return null;
  const f = fs.readdirSync(dir).find(n => new RegExp(`^\\d\\d-${slug}\\.log$`).test(n));
  if (!f) return null;
  return fs.readFileSync(path.join(dir, f), 'utf8').split('\n').slice(2).join('\n').trim();
}

// ---------- 內容 ----------
const kids = [];
const add = (...x) => x.flat().forEach(e => kids.push(e));

// 封面
add(
  new Paragraph({ spacing: { before: 2400, after: 200 }, children: [new TextRun({ text: 'Confluent Platform 安全方案', font: FONT, size: 60, bold: true, color: INK })] }),
  new Paragraph({ spacing: { after: 160 }, children: [new TextRun({ text: '手把手 Lab 手冊', font: FONT, size: 48, bold: true, color: TEAL })] }),
  new Paragraph({ spacing: { after: 400 }, children: [new TextRun({ text: 'AD 只放 user / group 時:人與服務如何串接 Kafka、REST Proxy、Control Center', font: FONT, size: 26, color: MUTE })] }),
  P([run('每個 Lab 都提供「純手動指令」與「專案包好的指令」兩條路,並附上實際執行的輸出、Control Center / LDAP 管理介面 / Postman 的操作截圖。', { size: 22 })]),
  spacer(),
  ...table([
    ['項目', '內容'],
    ['平台版本', 'Confluent Platform 8.3.2(KRaft、MDS RBAC)、Control Center next-gen 2.6.1、REST Proxy 8.3.2'],
    ['目錄服務', 'OpenLDAP(以 AD 屬性模擬;非真 AD,細節見「如何使用本手冊」的限制說明)'],
    ['環境', 'Docker Compose(Windows 11 + Git Bash 驗證;Linux/macOS 指令相同)'],
    ['證據', '所有「實際輸出」與截圖均來自本環境實跑(專案 demo/evidence/)'],
  ], [2200, 6826]),
  new Paragraph({ children: [new PageBreak()] }),
);

// 目錄
add(new Paragraph({ children: [new TextRun({ text: '目錄', font: FONT, size: 36, bold: true, color: INK })], spacing: { after: 160 } }),
  new TableOfContents('目錄', { hyperlink: true, headingStyleRange: '1-2' }),
  P([run('(第一次開啟若目錄是空白:在目錄上按右鍵 → 更新功能變數 → 更新整個目錄。)', { size: 18, color: MUTE })]));

// 第 1 章:如何使用本手冊
add(H1('如何使用本手冊'));
add(H2('兩條路徑:手動 vs 一鍵'));
add(P('每個 Lab 的每個步驟都有兩種做法,你可以依目的選擇:'));
add(...table([
  ['', '手動指令(建議先做)', '專案包好的指令(建議反覆練習/現場 demo)'],
  ['做法', '直接用 docker run、curl 執行 Kafka CLI 與 REST 呼叫;只用到本手冊第 0.1 節貼上的 kc、hc 兩個函式', '用專案內建的腳本:./demo.sh N、./scenarios/*.sh、scripts/*.sh;包含等待、驗證、截圖'],
  ['好處', '看得見每個參數,理解「為什麼」,可直接搬到客戶現場(RHEL 9 VM 上對應成 kafka-topics 等原生指令)', '一鍵可重複、結果自動比對預期、可逐步按 Enter 講解;出錯時不容易手滑'],
  ['何時用', '第一次學習、要自己解釋給別人聽、要改成客戶環境的指令', '重複演練、現場展示、回歸測試(./preflight.sh --full)'],
], [1300, 3900, 3826], { size: 18 }));
add(...callout('key', '建議的學習順序:第 0 章用一鍵建好環境(或照手動步驟自己建一次)→ 每個 Lab 先看「預期結果」→ 自己用手動指令做一次 → 之後用 ./demo.sh N 反覆演練。介面操作(C3、LDAP 管理介面、Postman)則照「介面操作」步驟點,截圖是你應該看到的畫面。'));
add(H2('每個步驟的版面'));
add(...table([
  ['區塊', '說明'],
  ['介面操作', '要在瀏覽器(C3、phpLDAPadmin)或 Postman 點選的步驟,一步一行。'],
  ['不用點介面的等效指令', '同一個動作用 API / CLI 完成(例如角色指派、AD 群組異動)。不想開瀏覽器或要寫腳本時使用。'],
  ['手動指令', '可直接貼進終端機的指令,只依賴 kc / hc 兩個函式。'],
  ['專案包好的指令', '同一件事,用專案腳本一行完成。'],
  ['預期結果(實際執行輸出)', '來自本環境實跑的真實輸出(已過濾 JVM 警告雜訊),你的結果應與其一致(時間與亂數 ID 會不同)。'],
  ['截圖', 'C3、LDAP 管理介面、Postman 在該步驟的實際畫面。'],
], [2400, 6626], { size: 18 }));
add(H2('本手冊的角色(Demo 專用帳密)'));
add(...table([['身分', '類型', '帳號 / 密碼', '說明'], ...IDENTITIES], [1500, 2300, 2700, 2526], { size: 17 }));
add(P([run('入口:', { bold: true }), run('C3 http://localhost:9021、LDAP 管理介面 http://localhost:8081、REST Proxy https://localhost:8086、MDS https://localhost:8091。')]));
add(H2('設計重點(兩個身分平面)'));
[
  '人(AD user / group):登入走 AD(經 MDS 的 LDAP simple bind;直連 broker 為 SASL/PLAIN + LDAP callback);授權用 MDS RBAC,role 綁在「AD 群組」,人員異動只改 AD。',
  '機器(不在 AD):Kafka 內建的 SASL/SCRAM-SHA-512 服務帳號,授權同樣走 RBAC(User:svc-xxx)並採最小權限。',
  '共用的單一 server 憑證只做傳輸加密(ssl.client.auth=none);它不能當身分(第 8 章證明)。',
  '平台元件(C3、REST Proxy、bootstrap)各用一張 client 憑證向 MDS 認證,不需要 AD 服務帳號。',
  'Control Center:人用本人身分(瀏覽器登入 → 使用者 token),機器用自己的憑證身分(C3 自己是 User:c3、SystemAdmin);Prometheus / Alertmanager 在本 demo 未啟用認證(官方支援 TLS + Basic,正式環境應啟用;Lab 13);broker 內建 Admin REST 依官方 kafka.rest. 設定保護(Lab 14)。',
  'legacy app 只能用 HTTP:改走 REST Proxy,機器出示 client 憑證(CN = 主體)、人仍用 Basic,兩者並存(Lab 12);服務帳號(SCRAM)不能直接進 REST Proxy。',
  'KRaft 內部通道:CONTROLLER 用 SASL/PLAIN;broker↔broker 用 SCRAM;INTERNAL/CONTROLLER 埠必須以防火牆限制。',
].forEach(t => add(bullet(t)));
add(H2('限制與如實說明'));
[
  'OpenLDAP 不是 AD:屬性以 AD 慣例仿造(member、groupOfNames…)。巢狀群組、UPN、帳號大小寫(RBAC 區分大小寫)等行為必須以客戶真實 AD 驗證。',
  '群組異動不是即時:demo 設 5 秒(ldap.refresh.interval.ms),官方預設 60 秒;實機請預留約 1 分鐘。',
  'audit log:官方預設只擷取 Management 與 Authorize 類事件;本 demo 另以自訂 router 開啟 produce/consume/describe。即便如此,部分拒絕(例如缺叢集層級 IdempotentWrite 的 produce)仍查不到,稽核需求要另外盤點。',
  '映像的 Java 為 25;客戶現場建議 Java 21(CP 8.3 官方建議版本)。',
  '本環境為 1 個 controller + 2 個 broker(節省記憶體);正式環境請用 3 個 controller。',
  'RBAC、LDAP、audit log、REST Proxy 安全外掛屬 Confluent Enterprise 商用功能(官方授權文件),demo 使用 30 天試用。',
  '驗證方式:本手冊的每一條「手動指令」都在本環境依 Lab 順序實際執行過(Lab 0 到 14,自動判定 0 項失敗,並人工檢視輸出);有介面操作的步驟以等效 API/CLI 驗證,截圖來自 Playwright 自動化。',
  '官方文件核對:角色權限(Operator、DeveloperManage、UserAdmin)、C3 在 RBAC 下僅支援 OAUTHBEARER、KRaft controller 之間不支援 SCRAM、MDS 自 7.8 起支援憑證認證、LDAP 群組快取預設 60 秒、Java 21 為 8.3 建議版本,均已對照 docs.confluent.io。controller 不需要 LDAP 設定(官方:只有 MDS writer broker 連 LDAP;本專案實測無 LDAP 的 controller 仍能依群組授權)。',
  'Postman 截圖是 newman(命令列版)結果渲染成 Postman 風格;終端輸出是實際輸出文字(本手冊以文字呈現)。若要真 Postman 視窗畫面,請依 Lab 5 自行操作截圖。',
].forEach(t => add(bullet(t)));

// ---------- Labs ----------
for (const lab of LABS) {
  add(H1(`Lab ${lab.n}  ${lab.title}`));
  add(...table([
    ['項目', '內容'],
    ['目標', lab.goal],
    ['預估時間', lab.time],
    ['前置條件', lab.pre.join('\n')],
  ], [1700, 7326], { size: 19 }));
  if (lab.table) { add(label('盤點表', TEAL)); add(...table(lab.table.rows, lab.table.colW, { size: 17 })); }
  if (lab.pre_cmd) { add(label('開始前的起點狀態(重置)', AMBER)); add(...code(lab.pre_cmd.join('\n'))); }
  if (lab.autoAll) { add(label('整個 Lab 一鍵跑完(專案包好的指令)', GREEN)); add(...code(lab.autoAll.join('\n'), { bar: GREEN })); }
  for (const s of lab.steps) {
    add(H2(s.t));
    if (s.why) add(P(s.why));
    if (s.ui) { add(label('介面操作(瀏覽器 / Postman)', TEAL)); add(...numbered(s.ui)); }
    if (s.uiEq) { add(label('不用點介面的等效指令(API / CLI)', MUTE)); add(...code(s.uiEq.join('\n'), { bar: MUTE })); }
    if (s.cfg) { add(label('設定內容(已包含在本環境的 docker-compose;客戶 VM 上寫入 kafka-rest.properties)', MUTE)); add(...code(s.cfg.join('\n'), { bar: MUTE })); }
    if (s.manual && s.manual.length) {
      add(label('手動指令', TEAL));
      add(...code(s.manual.join('\n')));
    }
    if (s.auto) { add(label('專案包好的指令', GREEN)); add(...code(s.auto.join('\n'), { bar: GREEN })); }
    // 預期結果:實際輸出
    const outs = [];
    for (const k of ['ev', 'evb', 'evc']) if (s[k]) { const o = evidenceOut(lab.id, s[k]); if (o) outs.push(o); else missing.push(`${lab.id}/${s[k]}.log`); }
    if (s.ev0) { const o = evidenceOut('ch00', s.ev0); if (o) outs.push(o); else missing.push(`ch00/${s.ev0}.log`); }
    if (outs.length) {
      add(label('預期結果(實際執行輸出)', AMBER));
      outs.forEach(o => add(...code(o, { fill: 'FBF6EC', bar: AMBER, maxLines: 14, cut: 150 })));
    }
    if (s.expect) add(P([run('預期:', { bold: true, color: AMBER }), run(s.expect)]));
    for (const [rel, cap] of s.imgs || []) add(...image(rel, cap));
    if (s.warn) add(...callout('warn', s.warn));
    if (s.tip) add(...callout('tip', s.tip));
  }
}

// ---------- 附錄 ----------
add(H1('附錄 A  重置、清理與疑難排解'));
add(H2('重置到起點'));
add(...code(`./scripts/reset.sh      # LDAP 群組、示範用 role binding、服務帳號回到起點(不重建叢集)
./demo.sh reset         # 同上
docker compose --profile c3 --profile restproxy down      # 關閉並移除全部容器(資料一併清除)
bash scripts/up.sh --with-restproxy --with-c3             # 重新建置`));
add(H2('疑難排解'));
add(...table([
  ['現象', '原因 / 處理'],
  ['Authentication failed(密碼正確)', '1) openldap 容器沒起來;2) bind DN 的 ACL 沒套用(Lab 0.4);3) 帳號大小寫與 AD 不一致(RBAC 的 principal 區分大小寫)。'],
  ['群組異動後權限沒變', 'MDS 以 ldap.refresh.interval.ms 週期重讀(demo 5 秒,預設 60 秒);多等幾秒再試。'],
  ['AD 群組的 role 在建立 topic 時不生效', '先檢查:1) controller 是否使用 ConfluentServerAuthorizer 並設了 MDS / audit 連線;2) controller 是否依官方設定 confluent.metadata.server.kraft.controller.enabled=true 與 token key;3) 群組快取是否已刷新(預設 60 秒);4) role 是否綁在正確的資源前綴。注意:本專案先前曾記錄「controller 需要 ldap.*」,重建環境後重測已推翻(無 LDAP 的 controller 仍能依群組授權),目前不給 controller 任何 ldap.*。'],
  ['Postman 換身分仍是前一個人', 'MDS 回的 auth_token cookie 優先於 Basic Auth;清除 localhost 的 cookie(collection 已加 pre-request 清除)。'],
  ['MDS 回 406', '請求要加 Accept: application/json。'],
  ['REST v2 GET /topics/{topic} 對唯讀者回 403', '該 API 需要 DescribeConfigs;唯讀者請改用 GET /topics。'],
  ['C3 看不到資料 / 重啟 broker 後 C3 異常', 'C3 與 MDS 的連線是舊的:docker restart control-center。'],
  ['producer 退出碼為 0 但其實被拒', 'console producer 的授權失敗只印錯誤訊息;請看輸出,不要只看退出碼(專案的 send_result 會判斷)。'],
  ['Git Bash 路徑被改寫', 'export MSYS_NO_PATHCONV=1;D 用 pwd -W。'],
  ['記憶體不足', 'Docker Desktop 配置 ≥ 10GB;不需要 C3 的 Lab 可不啟動 c3 profile。'],
  ['broker 啟動即退出:Authentication failed … Invalid user credentials(SCRAM-SHA-512)', '實測遇過:改設定時 docker 連動重建 controller,逾時強制終止留下 10 位元組的空 KRaft snapshot(__cluster_metadata-0/*.snapshot),controller 重啟後遺失 SCRAM 憑證(含 kafka-broker),broker 無法啟動;還原設定無效,只能 docker compose down -v 後重建。預防:compose 已為 controller、broker 設 stop_grace_period: 60s;改設定只重建 broker;實機用 systemctl 逐台滾動重啟,避免強制終止 controller。'],
  ['匿名呼叫 broker 的 /kafka/v3 沒被擋、甚至 broker 崩潰', 'broker 內建 Admin REST(與 MDS 共用 8091)未設定 kafka.rest. 安全擴充時完全無認證。依 Lab 14 套用官方設定。'],
  ['改了 broker 設定後 C3 或 REST Proxy 登入逾時', 'broker 被重建後,C3 與 REST Proxy 仍連著舊連線:docker restart control-center restproxy。'],
], [3000, 6026], { size: 18 }));
add(H1('附錄 B  對應到客戶 RHEL 9 VM'));
add(P('demo 用 docker-compose 的環境變數設定 Kafka;在 VM 上改成設定檔,規則是「KAFKA_ 前綴 + 全大寫 + 底線」對應「小寫 + 句點」。'));
add(...table([
  ['demo(docker-compose)', 'RHEL 9 VM'],
  ['KAFKA_* 環境變數', '/etc/kafka/server.properties(broker)、controller.properties;KAFKA_LISTENER_NAME_CLIENT_… → listener.name.client.…'],
  ['certs/', '/etc/kafka/secrets/(權限 600、owner cp-kafka);AD CS 根憑證同時放系統信任(update-ca-trust)與 Java truststore'],
  ['各元件 SCRAM 密碼', 'Secret Protection / 檔案權限 600 + systemd 獨立使用者;Vault 為後續'],
  ['ensure-controller.sh(--add-scram)', '每個 controller 節點首次啟動前:kafka-storage format --cluster-id <id> -c controller.properties --add-scram \'…\'(順序錯誤需重新 format)'],
  ['.env 的 audit router', 'server.properties:confluent.security.event.router.config=<JSON 單行>'],
  ['LDAP 設定(x-ldap-env)', 'broker 設定 ldap.*(官方:MDS 叢集所有 broker 都需要;只有 MDS writer broker 向 LDAP 取群組)。controller 不設 ldap.*,改設 kraft.controller.enabled=true 與 token key(官方做法,實測通過)'],
  ['kc / hc 函式', '在 VM 上直接用 kafka-topics、kafka-configs、curl,參數相同(--command-config 指向各人的 client.properties)'],
  ['防火牆', '9092(INTERNAL)、9093(CONTROLLER)只對 broker/controller 節點開放;Prometheus(9090)、Alertmanager(9093,若在另一台主機)只對 C3 與必要的監控來源開放,除非已啟用其 TLS + Basic;8091 是 MDS 與 Admin REST 共用,必須對使用者與元件開放,保護靠 Lab 14 的安全擴充,不能靠防火牆整個擋掉'],
], [3000, 6026], { size: 18 }));
add(H1('附錄 C  專案檔案索引'));
add(...table([
  ['路徑', '用途'],
  ['demo/docker-compose.yml', '全部容器定義(broker 使用 x-ldap-env;broker/controller 共用 x-common-ssl)'],
  ['demo/scripts/up.sh、reset.sh、bootstrap-rbac.sh', '一鍵建置、重置、第一批授權'],
  ['demo/scripts/k.sh、rp.sh、mds.sh、ldap-group.sh、create-service-account.sh、as-user.sh', '包好的單項指令(對應手動的 kc、hc、ldapmodify…)'],
  ['demo/scenarios/ch01…ch14-*.sh', '各 Lab 的整章腳本(含自動驗證)'],
  ['demo/e2e/*.mjs', 'Playwright:C3 / LDAP 介面自動化與截圖;terminal 與 newman 渲染'],
  ['demo/postman/', 'Postman collection 與環境(demo-humans、demo-service)'],
  ['demo/config/clients/*.properties', '各身分的 client 設定(plain-*、scram-*、ssl-only)'],
  ['demo/evidence/chNN/', '每個 Lab 的實際輸出與截圖'],
  ['demo/RUNBOOK.md、spike/SPIKE-FINDINGS.md、C3-FLOWS.md', '講稿、實測發現、C3 全流程與客戶環境限制'],
  ['demo/labguide/', '本手冊的產生程式(labs.mjs 內容、build.mjs 產生、verify.mjs 驗證手動指令)'],
], [4300, 4726], { size: 18 }));
add(H2('client 設定檔範例'));
const readCfg = n => fs.readFileSync(path.resolve(here, '..', 'config', 'clients', n), 'utf8').trim();
for (const [n, d] of [['plain-yujie.properties', '人(AD 帳密,SASL/PLAIN + LDAP)'], ['scram-svc-orders.properties', '服務(SCRAM-SHA-512)']]) {
  add(label(`${n} —— ${d}`)); add(...code(readCfg(n)));
}

// ---------- 文件 ----------
const doc = new Document({
  creator: 'Claude', title: 'Confluent Platform 安全方案 手把手 Lab 手冊', description: 'AD 只放 user/group 的 Confluent 安全方案實作手冊',
  features: { updateFields: true },
  styles: {
    default: { document: { run: { font: FONT, size: 21 } } },
    paragraphStyles: [
      { id: 'Heading1', name: 'Heading 1', basedOn: 'Normal', next: 'Normal', quickFormat: true, run: { font: FONT, size: 36, bold: true, color: INK }, paragraph: { spacing: { before: 120, after: 200 }, outlineLevel: 0 } },
      { id: 'Heading2', name: 'Heading 2', basedOn: 'Normal', next: 'Normal', quickFormat: true, run: { font: FONT, size: 26, bold: true, color: TEAL }, paragraph: { spacing: { before: 280, after: 100 }, outlineLevel: 1 } },
    ],
  },
  numbering: { config: [
    { reference: 'bullets', levels: [{ level: 0, format: LevelFormat.BULLET, text: '•', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 540, hanging: 270 } } } }] },
    { reference: 'nums', levels: [{ level: 0, format: LevelFormat.DECIMAL, text: '%1.', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 540, hanging: 340 } } } }] },
  ] },
  sections: [{
    properties: { page: { size: { width: 11906, height: 16838 }, margin: { top: 1300, bottom: 1200, left: 1440, right: 1440 } } },
    headers: { default: new Header({ children: [new Paragraph({ alignment: AlignmentType.RIGHT, children: [new TextRun({ text: 'Confluent Platform 安全方案 · Lab 手冊', font: FONT, size: 16, color: MUTE })] })] }) },
    footers: { default: new Footer({ children: [new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ children: ['第 ', PageNumber.CURRENT, ' 頁 / 共 ', PageNumber.TOTAL_PAGES, ' 頁'], font: FONT, size: 16, color: MUTE })] })] }) },
    children: kids,
  }],
});
const out = path.resolve(here, '..', '..', 'Confluent-Security-Lab-Guide.docx');
fs.writeFileSync(out, await Packer.toBuffer(doc));
console.log('wrote', out, (fs.statSync(out).size / 1048576).toFixed(1) + ' MB');
if (missing.length) console.log('缺少的證據:', [...new Set(missing)].join(', '));
