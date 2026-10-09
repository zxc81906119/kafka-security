// 產生 Word 手冊:Confluent Platform 安全方案 —— 手把手 Lab 手冊
// 內容來自 labs.mjs;「實際輸出」來自 evidence/*/NN-slug.log(實跑結果);圖片來自 evidence/**.png
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  Document, Packer, Paragraph, TextRun, HeadingLevel, Table, TableRow, TableCell, WidthType, ShadingType, BorderStyle,
  AlignmentType, ImageRun, LevelFormat, PageBreak, TableOfContents, Footer, Header, PageNumber, TabStopType,
} from 'docx';
import { LABS as LABS0, SETUP, IDENTITIES } from './labs.mjs';
import { LABS_EXTRA } from './labs-extra.mjs';
import * as S from './story.mjs';
const LABS = [...LABS0, ...LABS_EXTRA];
const VERIFY_NOTE = process.env.VERIFY_NOTE || '(驗證說明待填)';

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
const STORY_C = '6B4FA0';
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
const H2 = t => new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun({ text: t, font: FONT })], keepNext: true });
const label = (t, color = TEAL) => new Paragraph({ keepNext: true, spacing: { before: 120, after: 60 }, children: [new TextRun({ text: t, font: FONT, size: 20, bold: true, color })] });
const bullet = (t, o = {}) => new Paragraph({ numbering: { reference: 'bullets', level: 0 }, spacing: { after: 60, line: 288 }, children: [run(t, o)] });
let inst = 0;
const numbered = items => { inst++; return items.map(t => new Paragraph({ numbering: { reference: 'nums', level: 0, instance: inst }, spacing: { after: 60, line: 288 }, children: [run(t)] })); };

const codeBorder = c => ({ top: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' }, bottom: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' }, right: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' }, left: { style: BorderStyle.SINGLE, size: 18, color: c, space: 6 } });
function codeLines(text, { fill = 'F1F4F7', bar = TEAL, maxLines = 0, cut = 0 } = {}) {
  let lines = String(text).replace(/\r/g, '').split('\n');
  if (maxLines && lines.length > maxLines) lines = [...lines.slice(0, maxLines), '…(以下略,完整內容見 evidence 檔)'];
  if (cut) lines = lines.flatMap(l => { const r = []; while (l.length > cut) { r.push(l.slice(0, cut)); l = '  ' + l.slice(cut); } r.push(l); return r; });   // 太長的行折行(不截斷:關鍵字常在行尾,例如 TOPIC_AUTHORIZATION_FAILED)
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
  return fs.readFileSync(path.join(dir, f), 'utf8').split('\n').slice(2).join('\n')
    .replace(/\x1b\[[0-9;?]*[A-Za-z]/g, '')                    // 去掉終端機顏色控制碼(例如 OP menu 的輸出):XML 不允許 ESC 字元,Word 會打不開
    .replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, '').trim();
}

// ---------- 內容 ----------
const kids = [];
// 精簡版開關:BRIEF=out,auto,img,termimg,appendix,optional(逗號分隔)
//   out = 不放「實際執行輸出」;auto = 不放「專案包好的指令」;img = 不放步驟截圖(Lab 地圖與架構圖仍放);termimg = 只拿掉終端機截圖;
//   appendix = 不放附錄 B 到 D;optional = 不放選修 Lab 8、9
const BRIEF = new Set((process.env.BRIEF || '').split(',').map(s => s.trim()).filter(Boolean));
let SKIP = false;
const add = (...x) => { if (SKIP) return; x.flat().forEach(e => kids.push(e)); };

// 封面
add(
  new Paragraph({ spacing: { before: 2200, after: 160 }, children: [new TextRun({ text: 'Confluent Platform 安全方案', font: FONT, size: 44, bold: true, color: MUTE })] }),
  new Paragraph({ spacing: { after: 140 }, children: [new TextRun({ text: S.TITLE, font: FONT, size: 72, bold: true, color: STORY_C })] }),
  new Paragraph({ spacing: { after: 300 }, children: [new TextRun({ text: S.SUBTITLE + (BRIEF.size ? '(精簡版)' : ''), font: FONT, size: 36, bold: true, color: TEAL })] }),
  ...(BRIEF.size ? [P([run('精簡版:只留每步的指令、預期結果與 Lab 地圖,拿掉實際輸出、截圖、專案包好的指令、附錄 B 到 D 與選修 Lab 8、9。上課時放在手邊照做;要對照輸出與畫面請翻完整版(Confluent-Security-Lab-Story-Guide-v2.docx)。', { size: 20, color: MUTE })])] : []),
  new Paragraph({ spacing: { after: 400 }, children: [new TextRun({ text: BRIEF.size ? S.TAGLINE.replace('每個 Lab 都附可直接貼上的指令與實際執行的輸出', '每個 Lab 都附可直接貼上的指令與預期結果') : S.TAGLINE, font: FONT, size: 24, color: MUTE })] }),
  P([run('這是一個故事:新進維運工程師「Ming」,在前三週裡一個個處理真實會遇到的問題。每個 Lab 先說「為什麼要做這件事」,再給可直接貼上的指令,' + (BRIEF.size ? '並寫明預期結果(實際輸出與畫面見完整版)。' : '最後附上本環境實際執行的輸出與畫面。'), { size: 22 })]),
  spacer(),
  ...table([
    ['項目', '內容'],
    ['平台版本', 'Confluent Platform 8.3.2(KRaft、MDS RBAC)、Control Center next-gen 2.6.1、REST Proxy 8.3.2'],
    ['目錄服務', 'OpenLDAP(以 AD 屬性模擬;非真 AD,細節見「如何使用本手冊」的限制說明)'],
    ['環境', 'Docker Compose(Windows 11 + Git Bash 驗證;Linux/macOS 指令相同)'],
    ['證據', '所有「實際輸出」與截圖均來自本環境實跑(專案 demo/evidence/)'],
    ['與舊版手冊', '本版以故事串起來,並新增 Lab 15(人員異動)、Lab 16(OP menu)、Lab 17(傳輸加密補強)、Lab 18(CyberArk 整合)、Lab 19(帳號被偷之後)與 Lab 20(Schema Registry 與欄位級加密);舊版 Confluent-Security-Lab-Guide.docx 保留'],
  ], [2200, 6826]),
  new Paragraph({ children: [new PageBreak()] }),
);

// 目錄
add(new Paragraph({ children: [new TextRun({ text: '目錄', font: FONT, size: 36, bold: true, color: INK })], spacing: { after: 160 } }),
  new TableOfContents('目錄', { hyperlink: true, headingStyleRange: '1-2' }),
  P([run('(第一次開啟若目錄是空白:在目錄上按右鍵 → 更新功能變數 → 更新整個目錄。)', { size: 18, color: MUTE })]));

// 課前準備
add(H1('課前準備(開課前一天完成)'));
add(P('目標:上課當天每個人的電腦都能在 5 分鐘內把環境建起來。最花時間的是下載映像(約 7 GB),請提前做。全部做完預估 30 到 60 分鐘(視網速)。'));
add(H2('要安裝的軟體'));
add(...table([
  ['軟體', '版本 / 設定', '用途'],
  ['Docker Desktop', '最新版;Settings → Resources 記憶體 ≥ 10 GB', '跑全部 9 個容器(實測全部啟動約 3.5 GB)'],
  ['Git for Windows(Git Bash)', '最新版', '所有指令都在 Git Bash 執行(Linux / macOS 用內建終端機即可)'],
  ['Node.js', '24(LTS 亦可)', 'UI 自動化截圖、Postman 批次測試(newman)、產生本手冊'],
  ['Postman 桌面版', '最新版(選裝)', '只有 Lab 5 用;不裝可改用 newman'],
  ['瀏覽器', 'Chrome / Edge', '登入 Control Center、phpLDAPadmin'],
], [2300, 3000, 3726], { size: 18 }));
add(H2('課前步驟(打勾清單)'));
[
  ['取得專案目錄(含 demo/),確認磁碟剩餘空間 ≥ 15 GB;不要放在有中文或空白的路徑。', null, null],
  ['第一次建置:會下載映像(約 7 GB),最後印出「[up] 完成。」', 'cd demo\nbash scripts/up.sh --with-restproxy --with-c3', '約 5 到 30 分鐘(視網速);中途失敗可以重跑同一指令'],
  ['自檢:容器、端點、登入、瀏覽器自動化都通過', './preflight.sh', '通過 18 / 失敗 0'],
  ['瀏覽器自動化(各 Lab 的 C3、phpLDAPadmin 截圖用;需要連網,約 150 MB)', 'bash scripts/setup-e2e.sh', 'OK: 瀏覽器自動化可用'],
  ['瀏覽器開 Control Center 登入頁(demo 的 CA 是自簽的:按「進階」繼續,或把 demo/certs/ca.pem 匯入「受信任的根憑證授權單位」)', '瀏覽器:https://localhost:9022/login', '看到 Welcome to Confluent Platform 登入畫面(載入需數秒)'],
  ['(選做)Postman:匯入 demo/postman/ 的 collection 與環境,並信任 demo CA(做法見 Lab 5.1)', null, null],
  ['清掉環境,Lab 0 上課時從零建(映像保留在本機,不會重新下載;第二次建置約 3 分鐘)', 'docker compose --profile c3 --profile restproxy down -v', '容器與資料全部移除'],
].forEach(([t, cmd, exp], i) => {
  add(P([run('☐  ', { color: STORY_C, bold: true }), run(`${i + 1}. ${t}`)], { indent: { left: 360 } }));
  if (cmd) add(...code(cmd, { bar: MUTE }));
  if (exp) add(P([run('預期:', { bold: true, color: AMBER }), run(exp)], { indent: { left: 360 } }));
});
add(H2('會下載的映像(課前先拉好)'));
add(...table([
  ['映像', '大小(約)', '用途'],
  ['confluentinc/cp-server:8.3.2', '2.2 GB', 'controller、broker(含 MDS);kc 函式的 Kafka CLI 也用它'],
  ['confluentinc/cp-kafka-rest:8.3.2', '1.4 GB', 'REST Proxy'],
  ['confluentinc/cp-enterprise-control-center-next-gen:2.6.1', '1.4 GB', 'Control Center'],
  ['confluentinc/cp-enterprise-prometheus:2.6.1、cp-enterprise-alertmanager:2.6.1', '0.4 GB + 0.2 GB', '監控(C3 需要)'],
  ['osixia/openldap:1.5.0、osixia/phpldapadmin:0.9.0', '0.4 GB + 0.4 GB', '模擬 AD 與管理介面'],
  ['curlimages/curl、alpine/openssl', '50 MB', 'hc 函式的 curl、產生憑證'],
  ['postman/newman:alpine', '0.3 GB', 'Lab 5 的批次測試(第一次跑 Lab 5 時才下載)'],
  ['cyberark/conjur、cyberark/conjur-cli:9、postgres:15、nginx:stable、confluentinc/confluent-cli', '約 1.2 GB', 'Lab 18(CyberArk 整合;第一次跑 Lab 18 時才下載)'],
  ['confluentinc/cp-schema-registry:8.3.2', '1.5 GB', 'Lab 20(Schema Registry;第一次跑 Lab 20 時才下載)'],
], [4200, 1500, 3326], { size: 17 }));
add(H2('課前常見問題'));
add(...table([
  ['現象', '處理'],
  ['docker 綁不上主機埠(ports are not available … forbidden by its access permissions)', 'Windows 開機後會保留一段埠範圍。在 demo/.env 加 HOST_PORT_MDS=18091 之類的覆蓋(變數名稱見 docker-compose.yml 的 ${HOST_PORT_*}),再重跑 up.sh;手冊裡的 localhost 埠要跟著換。'],
  ['映像下載失敗或很慢', '公司網路可能擋 Docker Hub:請 IT 開通,或在能連網的電腦 docker save 後帶進來 docker load。'],
  ['記憶體不足、容器一直重啟', 'Docker Desktop → Settings → Resources 把記憶體調到 10 GB 以上;關掉其他容器。'],
  ['controller 或 broker 起不來', '一律用 bash scripts/up.sh 啟動(controller 要先 healthy),不要直接 docker compose up。'],
  ['preflight 的「瀏覽器自動化」失敗', '需要連網下載 chromium;執行 bash scripts/setup-e2e.sh 看錯誤訊息。'],
], [3600, 5426], { size: 17 }));

// Demo 架構
add(H1('Demo 架構'));
add(P('先看兩張圖:第一張是「有哪些東西、在哪個埠」,第二張是「誰用什麼身分進來」。之後每個 Lab 開頭都有一張「Lab 地圖」,把這堂用到的元件打亮、標出走的路與結果。'));
add(...image('../labguide/img/arch-deploy.png', 'Demo 部署元件:9 個容器 + 你電腦上的工具'));
add(...table([
  ['元件', '主機埠(容器埠)', '協定 / 身分'],
  ['模擬 AD(openldap)', '389;636 只在容器內(broker 走 LDAPS)', 'bind DN 唯讀查詢帳號;使用者名稱 = CN'],
  ['phpLDAPadmin', '8081', 'cn=admin,dc=corp,dc=demo / adminpw'],
  ['controller1', '9093 只在容器內', 'mTLS(與 broker 共用憑證 CN=kafka-internal)'],
  ['broker1 / broker2(Kafka)', '9094 / 19194(容器內都是 9094)', 'CLIENT:人 PLAIN+AD、服務 SCRAM、元件 OAUTHBEARER;INTERNAL 9092(mTLS,共用內部憑證)只在容器內'],
  ['broker1 / broker2(MDS)', '8091 / 8092', 'HTTPS;Basic(AD)或 client 憑證;Admin REST(/kafka/v3)共用此埠'],
  ['REST Proxy', '8086', 'HTTPS;人 Basic、legacy app client 憑證'],
  ['Control Center', '9022(9021 只給容器內健康檢查)', 'HTTPS;人用 AD 帳密;C3 自己用 CN=c3 憑證'],
  ['Prometheus / Alertmanager', '只在容器內(9090 / 9093)', 'HTTPS + Basic(c3 / prom-pw、c3 / am-pw;測試值)'],
], [2600, 2900, 3526], { size: 17 }));
add(...image('../labguide/img/arch-identity.png', '身分路徑:人走 AD、服務走 SCRAM、元件走憑證換 token、legacy app 經 REST Proxy'));

// 故事背景與角色
add(H1('故事背景與角色'));
S.SETTING.forEach(t => add(P(t)));
add(...table([['規矩', '意思'], ...S.RULES], [2400, 6626], { size: 19 }));
add(H2('角色'));
add(...table([['角色', '在故事裡是誰', 'Demo 帳號'], ...S.CAST], [1500, 3900, 3626], { size: 18 }));
add(H2('三週的路線圖'));
add(...table([['時間', '主題', '對應 Lab'], ...S.ACTS.map(a => [a.when, a.title.replace(/^[^::]*[::]\s*/, ''), a.labs.map(n => 'Lab ' + n).join('、')])], [1800, 4926, 2300], { size: 18 }));
add(...callout('tip', '每個 Lab 的編號就是 ./demo.sh 的章節編號(Lab 5 對應 ./demo.sh 5)。選修的 Lab 8、9 不影響後面的內容,趕時間可以跳過。'));

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
add(P([run('入口:', { bold: true }), run('C3 https://localhost:9022(瀏覽器第一次會警告憑證不受信任,見 Lab 2.1)、LDAP 管理介面 http://localhost:8081、REST Proxy https://localhost:8086、MDS https://localhost:8091。')]));
add(H2('設計重點(兩個身分平面)'));
[
  '人(AD user / group):登入走 AD(經 MDS 的 LDAP simple bind;直連 broker 為 SASL/PLAIN + LDAP callback);授權用 MDS RBAC,role 綁在「AD 群組」,人員異動只改 AD。',
  '機器(不在 AD):Kafka 內建的 SASL/SCRAM-SHA-512 服務帳號,授權同樣走 RBAC(User:svc-xxx)並採最小權限。',
  '共用的單一 server 憑證只做傳輸加密(ssl.client.auth=none);它不能當身分(第 8 章證明)。',
  '平台元件(C3、REST Proxy、bootstrap)各用一張 client 憑證向 MDS 認證,不需要 AD 服務帳號。',
  'Control Center:人用本人身分(瀏覽器登入 → 使用者 token),機器用自己的憑證身分(C3 自己是 User:c3、SystemAdmin);Prometheus / Alertmanager 以 HTTPS + Basic 保護(Lab 13、Lab 17);C3 與 AD 連線也都走加密(HTTPS、LDAPS;Lab 17);broker 內建 Admin REST 依官方 kafka.rest. 設定保護(Lab 14)。',
  'legacy app 只能用 HTTP:改走 REST Proxy,機器出示 client 憑證(CN = 主體)、人仍用 Basic,兩者並存(Lab 12);服務帳號(SCRAM)不能直接進 REST Proxy。',
  'KRaft 內部通道:CONTROLLER 與 INTERNAL 都是 mTLS,broker 與 controller 共用一張憑證(CN=kafka-internal);不用 SCRAM(刪除過 SCRAM 憑證後重啟 broker 會失敗,Lab 19);INTERNAL/CONTROLLER 埠必須以防火牆限制。',
].forEach(t => add(bullet(t)));
add(H2('限制與如實說明'));
[
  'OpenLDAP 不是 AD:屬性以 AD 慣例仿造(member、groupOfNames…)。巢狀群組、UPN、帳號大小寫(RBAC 區分大小寫)等行為必須以客戶真實 AD 驗證。',
  '群組異動不是即時:demo 設 5 秒(ldap.refresh.interval.ms),官方預設 60 秒;實機請預留約 1 分鐘。',
  'audit log:官方預設只擷取 Management 與 Authorize 類事件;本 demo 另以自訂 router 開啟 produce/consume/describe。即便如此,部分拒絕(例如缺叢集層級 IdempotentWrite 的 produce)仍查不到,稽核需求要另外盤點。',
  '映像的 Java 為 25;客戶現場建議 Java 21(CP 8.3 官方建議版本)。',
  '本環境為 1 個 controller + 2 個 broker(節省記憶體);正式環境請用 3 個 controller。',
  'RBAC、LDAP、audit log、REST Proxy 安全外掛屬 Confluent Enterprise 商用功能(官方授權文件),demo 使用 30 天試用。',
  '驗證方式:本手冊的每一條「手動指令」' + VERIFY_NOTE + '有介面操作的步驟以等效 API/CLI 驗證,截圖來自 Playwright 自動化。',
  '官方文件核對:角色權限(Operator、DeveloperManage、UserAdmin)、C3 在 RBAC 下僅支援 OAUTHBEARER、KRaft controller 之間不支援 SCRAM、MDS 自 7.8 起支援憑證認證、LDAP 群組快取預設 60 秒、Java 21 為 8.3 建議版本,均已對照 docs.confluent.io。controller 不需要 LDAP 設定(官方:只有 MDS writer broker 連 LDAP;本專案實測無 LDAP 的 controller 仍能依群組授權)。',
  'Postman 截圖是 newman(命令列版)結果渲染成 Postman 風格;終端輸出是實際輸出文字(本手冊以文字呈現)。若要真 Postman 視窗畫面,請依 Lab 5 自行操作截圖。',
].forEach(t => add(bullet(t)));

// ---------- Labs(依故事的幕組織)----------
const labOf = n => LABS.find(l => l.n === n);
function renderLab(lab) {
  add(H2pb(`Lab ${lab.n}  ${lab.title}`));
  add(...image(`../labguide/img/labmap-${String(lab.n).padStart(2, '0')}.png`, `Lab ${lab.n} 地圖:這堂要證明的事、動到的元件(打亮)、走的路與結果(✔ 允許 / ✘ 拒絕)`));
  const st = S.LAB_STORY[lab.n];
  if (st) {
    if (!BRIEF.has('story')) add(...storyBox('情境', st.scene));
    add(label('Ming 的任務(做完請自己對照)', STORY_C)); st.mission.forEach(t => add(P([run('☐  ', { color: STORY_C, bold: true }), run(t)], { indent: { left: 360 } })));
  }
  add(...table([
    ['項目', '內容'],
    ['目標', lab.goal],
    ['預估時間', lab.time],
    ['前置條件', [...lab.pre, ...(lab.n >= 3 ? ['起點狀態:Lab 之間會留下權限與群組;重做這個 Lab、或指令結果與「預期結果」不同時(例如應該被拒卻靜默成功),先在 demo 目錄執行 ./demo.sh reset 回到起點,再從本 Lab 開始。'] : [])].join('\n')],
  ], [1700, 7326], { size: 19 }));
  if (lab.table) { add(label('盤點表', TEAL)); add(...table(lab.table.rows, lab.table.colW, { size: 17 })); }
  if (lab.pre_cmd) { add(label('開始前的起點狀態(重置)', AMBER)); add(...code(lab.pre_cmd.join('\n'))); }
  if (lab.autoAll) { add(label('整個 Lab 一鍵跑完(專案包好的指令)', GREEN)); add(...code(lab.autoAll.join('\n'), { bar: GREEN })); }
  for (const s of lab.steps) {
    add(H3(s.t));
    if (s.why && !BRIEF.has('notes')) add(P(s.why));
    if (s.ui) { add(label('介面操作(瀏覽器 / Postman)', TEAL)); add(...numbered(s.ui)); }
    if (s.uiEq) { add(label('不用點介面的等效指令(API / CLI)', MUTE)); add(...code(s.uiEq.join('\n'), { bar: MUTE })); }
    if (s.cfg) { add(label('設定內容(已包含在本環境的 docker-compose;客戶 VM 上寫入 kafka-rest.properties)', MUTE)); add(...code(s.cfg.join('\n'), { bar: MUTE })); }
    if (s.manual && s.manual.length) { add(label('手動指令', TEAL)); add(...code(s.manual.join('\n'))); }
    if (s.auto && !BRIEF.has('auto')) { add(label('專案包好的指令', GREEN)); add(...code(s.auto.join('\n'), { bar: GREEN })); }
    const outs = [];
    // 優先用 verify-doc.mjs 存下的「手動指令實跑輸出」(manual-out/):手冊顯示的輸出 = 手冊顯示的指令跑出來的;沒有才用整章腳本的證據檔
    const mo = path.resolve(here, 'manual-out', lab.id, String(lab.steps.indexOf(s) + 1).padStart(2, '0') + '.log');
    let outLabel = '實際執行輸出(上方手動指令 / 等效指令實跑的結果)';
    if (fs.existsSync(mo) && fs.readFileSync(mo, 'utf8').trim()) outs.push(fs.readFileSync(mo, 'utf8').replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, '').trim());
    else {
      outLabel = '實際執行輸出(專案腳本實跑的結果)';
      for (const k of ['ev', 'evb', 'evc']) if (s[k]) { const o = evidenceOut(lab.id, s[k]); if (o) outs.push(o); else missing.push(`${lab.id}/${s[k]}.log`); }
    }
    if (s.ev0) { const o = evidenceOut('ch00', s.ev0); if (o) outs.push(o); else missing.push(`ch00/${s.ev0}.log`); }
    if (outs.length && !BRIEF.has('out')) {
      add(label(outLabel, AMBER));
      outs.forEach(o => add(...code(o, { fill: 'FBF6EC', bar: AMBER, maxLines: 40, cut: 110 })));
    }
    if (s.expect) add(P([run('預期:', { bold: true, color: AMBER }), run(s.expect)]));
    for (const [rel, cap] of s.imgs || []) {
      if (BRIEF.has('img')) continue;
      if (BRIEF.has('termimg') && /^ch\d\d\/\d\d-/.test(rel)) continue;   // 終端機截圖(evidence/chNN/NN-*.png)
      add(...image(rel, cap));
    }
    if (s.warn && !BRIEF.has('notes')) add(...callout('warn', s.warn));
    if (s.tip && !BRIEF.has('notes')) add(...callout('tip', s.tip));
  }
  if (st && !BRIEF.has('story')) add(...storyBox('小結:Ming 學到了什麼', st.recap.map(t => '• ' + t), { fill: 'EEF6F1' }));
}
for (const act of S.ACTS) {
  add(H1(act.title));
  add(...storyBox(act.when, act.scene));
  for (const n of act.labs) {
    if (BRIEF.has('optional') && [8, 9].includes(n)) { add(P([run(`Lab ${n}(選修)在精簡版省略,見完整版。`, { color: MUTE })])); continue; }
    const lab = labOf(n); if (!lab) { missing.push('Lab ' + n); continue; } renderLab(lab);
  }
}

// 終章
add(H1(S.EPILOGUE.title));
add(...storyBox('一個月後', S.EPILOGUE.scene));
add(...table([['還沒驗證或要補的', '說明'], ...S.EPILOGUE.todo], [2600, 6426], { size: 18 }));

// ---------- 附錄 ----------
add(H1('附錄 A  重置、清理與疑難排解'));
add(H2('重置到起點'));
add(...code(`./scripts/reset.sh      # LDAP 群組、示範用 role binding、服務帳號回到起點(不重建叢集)
./demo.sh reset         # 同上
docker compose --profile c3 --profile restproxy down -v   # 關閉並移除全部容器與資料(冷啟動重建前用)
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
  ['docker 綁不上主機埠(ports are not available … forbidden by its access permissions)', 'Windows 每次開機可能保留一段埠範圍(netsh int ipv4 show excludedportrange protocol=tcp),落在範圍內的埠(例如 8086、8091、8092)docker 綁不上。在 demo/.env 設 HOST_PORT_MDS、HOST_PORT_MDS2、HOST_PORT_RESTPROXY 等覆蓋;up.sh 與 preflight.sh 會讀同一份。Postman 的 environment 也要改成同樣的埠。'],
  ['記憶體不足', 'Docker Desktop 配置 ≥ 10GB;不需要 C3 的 Lab 可不啟動 c3 profile。'],
  ['瀏覽器連 C3 出現「連線不是私人連線」', 'demo 的 CA 是自簽的,瀏覽器預設不信任:按「進階」繼續,或把 demo/certs/ca.pem 匯入「受信任的根憑證授權單位」。正式環境由 AD 群組原則把內部 CA 發給使用者電腦。'],
  ['Windows 的 curl 連 HTTPS 失敗(CRYPT_E_NO_REVOCATION_CHECK)', '加 --ssl-no-revoke。內部 CA 沒有憑證撤銷清單,curl(schannel)無法檢查撤銷就會拒絕,不是憑證有問題。'],
  ['Prometheus 日誌出現 TLS handshake error … EOF', '容器的健康檢查只打開 TCP 埠就關閉,不是真正的 HTTPS 請求,可忽略。'],
  ['broker 日誌出現 Telemetry Metrics Failure(401 Unauthorized)', 'broker 推指標到 Prometheus 的 Basic 帳密(api.key / api.secret)與 web-config-prom.yml 的 bcrypt 雜湊不一致;兩個監控元件的雜湊不要貼反(Prometheus 與 Alertmanager 各一份)。'],
  ['冷啟動:controller 或 broker 起不來', '一律用 bash scripts/up.sh --with-restproxy --with-c3 啟動,不要直接 docker compose up:controller 要先起來並 healthy,broker 才起得來(controller 的 authorizer 在等 broker 時會逾時退出)。Docker Desktop 重新啟動後所有容器都是停止狀態,同樣用 up.sh。'],
  ['broker 重啟後起不來:SaslAuthenticationException … SCRAM-SHA-512', '實測遇過(叢集連續跑了一整天、metadata 約 13000 筆之後):broker 重啟時 authorizer 用 SCRAM 連自己,但 SCRAM 憑證還沒從 metadata 載入,錯誤是致命的,容器退出,再啟動也一樣。原因是推測、未確認。OP menu 的滾動重啟(Lab 16)遇到這種情況會等到逾時就停止,不會動下一台。demo 的處理:冷啟動重建(down -v 後 up.sh)。'],
  ['broker 啟動即退出:Authentication failed … Invalid user credentials(SCRAM-SHA-512)', '實測遇過:改設定時 docker 連動重建 controller,逾時強制終止留下 10 位元組的空 KRaft snapshot(__cluster_metadata-0/*.snapshot),controller 重啟後遺失 SCRAM 憑證(含 kafka-broker),broker 無法啟動;還原設定無效,只能 docker compose down -v 後重建。預防:compose 已為 controller、broker 設 stop_grace_period: 60s;改設定只重建 broker;實機用 systemctl 逐台滾動重啟,避免強制終止 controller。'],
  ['匿名呼叫 broker 的 /kafka/v3 沒被擋、甚至 broker 崩潰', 'broker 內建 Admin REST(與 MDS 共用 8091)未設定 kafka.rest. 安全擴充時完全無認證。依 Lab 14 套用官方設定。'],
  ['改了 broker 設定後 C3 或 REST Proxy 登入逾時', 'broker 被重建後,C3 與 REST Proxy 仍連著舊連線:docker restart control-center restproxy。'],
], [3000, 6026], { size: 18 }));
SKIP = BRIEF.has('appendix');   // 精簡版:附錄 B 到 D 不放(附錄 A 的重置與疑難排解保留)
add(H1('附錄 B  對應到客戶 RHEL 9 VM'));
add(P('demo 用 docker-compose 的環境變數設定 Kafka;在 VM 上改成設定檔,規則是「KAFKA_ 前綴 + 全大寫 + 底線」對應「小寫 + 句點」。'));
add(...table([
  ['demo(docker-compose)', 'RHEL 9 VM'],
  ['KAFKA_* 環境變數', '/etc/kafka/server.properties(broker)、controller.properties;KAFKA_LISTENER_NAME_CLIENT_… → listener.name.client.…'],
  ['certs/', '/etc/kafka/secrets/(權限 600、owner cp-kafka);AD CS 根憑證同時放系統信任(update-ca-trust)與 Java truststore'],
  ['各元件 SCRAM 密碼', 'Secret Protection / 檔案權限 600 + systemd 獨立使用者;Vault 為後續'],
  ['controller 的設定', 'demo 的 controller 在 CONTROLLER 埠(9093)用 mTLS(與 broker 共用憑證 CN=kafka-internal),設定在 docker-compose 的環境變數;VM 上寫在 controller.properties,並以防火牆只對 broker 與 controller 節點開放 9093'],
  ['.env 的 audit router', 'server.properties:confluent.security.event.router.config=<JSON 單行>'],
  ['LDAP 設定(x-ldap-env)', 'broker 設定 ldap.*(官方:MDS 叢集所有 broker 都需要;只有 MDS writer broker 向 LDAP 取群組)。controller 不設 ldap.*,改設 kraft.controller.enabled=true 與 token key(官方做法,實測通過)'],
  ['kc / hc 函式', '在 VM 上直接用 kafka-topics、kafka-configs、curl,參數相同(--command-config 指向各人的 client.properties)'],
  ['防火牆', '9092(INTERNAL)、9093(CONTROLLER)只對 broker/controller 節點開放;Prometheus(9090)、Alertmanager(9093,若在另一台主機)只對 C3、broker 與必要的監控來源開放(demo 已啟用 TLS + Basic,防火牆是第二層);8091 是 MDS 與 Admin REST 共用,必須對使用者與元件開放,保護靠 Lab 14 的安全擴充,不能靠防火牆整個擋掉'],
], [3000, 6026], { size: 18 }));
add(H1('附錄 C  專案檔案索引'));
add(...table([
  ['路徑', '用途'],
  ['demo/docker-compose.yml', '全部容器定義(broker 使用 x-ldap-env;broker/controller 共用 x-common-ssl)'],
  ['demo/scripts/up.sh、reset.sh、bootstrap-rbac.sh', '一鍵建置、重置、第一批授權'],
  ['demo/scripts/k.sh、rp.sh、mds.sh、ldap-group.sh、create-service-account.sh、as-user.sh', '包好的單項指令(對應手動的 kc、hc、ldapmodify…)'],
  ['demo/scenarios/ch01…ch20-*.sh', '各 Lab 的整章腳本(含自動驗證);ch15 人員異動、ch16 OP menu、ch17 傳輸加密補強、ch18 CyberArk 整合、ch19 帳號被偷之後、ch20 Schema Registry'],
  ['demo/config/conjur/、scripts/conjur.sh、scripts/app-with-conjur.sh、scripts/secret-protection.sh、scripts/rolling-rotate-test.sh、docker-compose.cyberark.yml、docker-compose.cyberark-summon.yml', 'Lab 18:Conjur 的 policy、TLS 入口、取秘密腳本、應用啟動示範、Secret Protection 與 broker2 覆蓋設定(自寫腳本版與 summon 版)'],
  ['demo/scripts/reauth-test.sh、quota-test.sh、ad-lockout.sh、config/c3/security_rules.yml、ldap-config/ppolicy-*.ldif', 'Lab 19:重新認證、配額、AD 鎖定實驗與認證失敗告警規則'],
  ['demo/scripts/sr-setup.sh、scenarios/ch20-schema-registry.sh', 'Lab 20:Schema Registry(profile sr)的啟動與授權'],
  ['demo/opmenu/', 'OP menu 程式(README.md 說明項目、設定與限制;test-*.sh 回歸測試)'],
  ['demo/spike/lb-nginx、rp-mds-failover', '負載平衡器與多台 MDS 的實驗(FINDINGS.md)'],
  ['demo/e2e/*.mjs', 'Playwright:C3 / LDAP 介面自動化與截圖;terminal 與 newman 渲染'],
  ['demo/postman/', 'Postman collection 與環境(demo-humans、demo-service)'],
  ['demo/config/clients/*.properties', '各身分的 client 設定(plain-*、scram-*、ssl-only)'],
  ['demo/evidence/chNN/', '每個 Lab 的實際輸出與截圖'],
  ['demo/RUNBOOK.md、spike/SPIKE-FINDINGS.md、C3-FLOWS.md', '講稿、實測發現、C3 全流程與客戶環境限制'],
  ['demo/labguide/', '本手冊的產生程式:story.mjs(故事)、labs.mjs 與 labs-extra.mjs(Lab 內容與指令)、build-story.mjs(產生 Word)、verify0.mjs 與 verify-story.mjs(驗證手動指令)'],
], [4300, 4726], { size: 18 }));
add(H1('附錄 D  負載平衡器與多台 MDS(實驗摘要)'));
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
add(H2('client 設定檔範例'));
const readCfg = n => fs.readFileSync(path.resolve(here, '..', 'config', 'clients', n), 'utf8').trim();
for (const [n, d] of [['plain-yujie.properties', '人(AD 帳密,SASL/PLAIN + LDAP)'], ['scram-svc-orders.properties', '服務(SCRAM-SHA-512)']]) {
  add(label(`${n} —— ${d}`)); add(...code(readCfg(n)));
}

SKIP = false;
// 附錄 E:Lab 18 沒有示範、或本機無法驗證的部分(完整版與精簡版都放)
add(H1('附錄 E  CyberArk 整合:實測發現、沒示範的限制與要確認的事'));
add(H2('Lab 18 實測發現(都有實跑證據)'));
add(...table([
  ['發現', '意義'],
  ['只停用 SCRAM 憑證,已連著的舊連線不受影響(14 筆全寫完);解除角色後,同一條連線的每個請求都被授權擋下', '輪替一定要「先隔離(解除角色)、看 audit、才停用憑證」;SCRAM 只在建立連線時驗證(connections.max.reauth.ms 預設 0)'],
  ['audit 不記錄 orders.* 讀取成功', '只看 audit 的「允許」會漏掉只讀的 consumer;隔離後還在用的人會變成被拒(DENIED),一定記錄'],
  ['帳號與密碼放兩個 Conjur 變數,輪替時有空檔', '放同一個變數(JSON {"u","p"}),寫入與讀取都是單一操作'],
  ['輪替腳本複製角色失敗時若繼續往下做,應用會全部拿到沒權限的帳號', '腳本逐筆檢查、驗證新帳號連得上且看到同樣的 topic,才寫 Conjur;失敗回滾新帳號'],
  ['Conjur 對沒被授權的身分回 404,不是 403', '不透露秘密是否存在;錯的 API key 在認證就被擋(401)'],
  ['設定檔密碼加密後,取不到主金鑰 broker 就不啟動', '刻意的;所以 Conjur 的可用性要和 broker 同級'],
  ['confluent secret 的 --passphrase 不會讀檔:--passphrase @/路徑 會把 @/路徑 這串字當成密碼(用另一個檔案內容去解會失敗)', 'passphrase 只能直接放在指令列,輪替要在受控的管理主機上做;不要以為 @檔案 在讀檔'],
  ['主金鑰輪替只重包資料金鑰,值的密文不變;新檔必須和新主金鑰成對(新檔配舊金鑰、舊檔配新金鑰都解不開)', '成對才能啟動:不成對時 broker 起不來(Failed to unwrap the data key)。輪替前先備好舊檔與舊主金鑰,以便退回'],
  ['輪替主金鑰需要「目前的 passphrase」與「新的 passphrase」,新主金鑰只印一次', 'passphrase 也要保存(demo 放 Conjur 只有管理員能讀的變數,broker 讀不到),新主金鑰要立刻寫進 Conjur'],
  ['兩台 broker 滾動重啟(依序一台一台)期間,背景 producer(acks=all、冪等)送出 1200 筆 = topic 1200 筆,零送出失敗', '重啟不等於停機。只證明這個條件:2 台 broker、副本 2、min.isr 1;正式環境副本 3、min.isr 2,controller 也要一台一台重啟'],
  ['CyberArk 官方 summon + summon-conjur 對開源版 Conjur 可用:主金鑰只在 java 程序的環境(容器環境、/tmp 都沒有),錯 API key 回 401、啟動程式不執行', '正式環境 systemd 只要 ExecStart=summon -p summon-conjur -f secrets.yml kafka-server-start … 一行;不要用 ExecStartPre 取秘密(它設的環境變數不會傳給 ExecStart)'],
], [4600, 4426], { size: 17 }));
add(H2('沒有示範的限制(要在客戶環境處理)'));
add(...table([
  ['項目', '說明'],
  ['長時間執行的應用', 'Kafka client 的 sasl.jaas.config 在建立 client 時讀一次。要不重啟就換帳密,應用要在認證或授權失敗時重新向 Conjur 取並重建 client;demo 的示範是重啟才換'],
  ['Conjur 的可用性', '取不到帳密,應用與 broker 起不來。需要高可用、重試,以及短暫的加密快取(記憶體)這類取捨'],
  ['根的秘密(secret zero)', '機器的 API key 放在主機檔案,被偷就等於那個身分。商業版 CCP 用 AppID + 主機 IP 或憑證認證;API key 本身的輪替也要規劃;demo 沒有示範'],
  ['API token 只有 8 分鐘', '啟動時取一次沒問題;執行中要再取就要重新認證'],
  ['換帳號名稱的後續影響', '監控、告警、配額、audit 查詢都以帳號名稱為準;svc-orders → svc-orders-v2 會讓它們失效。命名要預先設計(例如 a / b 輪流)'],
  ['角色複製只涵蓋「綁在 User 上、有資源範圍」的角色', '叢集層級角色、KRaft ACL、配額不會複製;腳本會驗證複製後的角色與舊帳號一致,不一致就中止'],
  ['demo 與正式環境的差異', 'demo 以容器的 stdin 傳帳密;正式環境的應用在自己的程序內取用。demo 的 API key 在檔案裡,正式環境對應 CCP 的 AppID 認證'],
  ['商業版 CCP 對應', 'CCP 一筆帳號物件就是「帳號 + 密碼」,概念與單一 credential 變數一致,但回傳格式與認證方式不同,正式環境要改寫取密碼那一段'],
  ['Conjur 本身的維運', '資料金鑰、admin key、資料庫備份、日誌保留期限'],
], [2800, 6226], { size: 17 }));
add(H2('PAM 側(PSM、CPM、PVWA):本機無法驗證'));
add(P('代登入與錄影、主機帳號自動輪替、依單借出私鑰,需在客戶環境 PoC。要先確認:跳板機與各主機是否加入 AD;人連主機是否一律經 PSM;主機 22 埠允許哪些來源;CPM 輪替 ssh key 時 OP menu 正在連線的作業怎麼處理。'));
// ---------- 文件 ----------
const doc = new Document({
  creator: 'Claude', title: 'Confluent Platform 安全方案:Ming 的前三週(故事版 Lab 手冊)', description: 'AD 只放 user/group 的 Confluent 安全方案實作手冊,以新進維運工程師的故事串起所有 Lab',
  features: { updateFields: true },
  styles: {
    default: { document: { run: { font: FONT, size: 21 } } },
    paragraphStyles: [
      { id: 'Heading1', name: 'Heading 1', basedOn: 'Normal', next: 'Normal', quickFormat: true, run: { font: FONT, size: 36, bold: true, color: INK }, paragraph: { spacing: { before: 120, after: 200 }, outlineLevel: 0 } },
      { id: 'Heading3', name: 'Heading 3', basedOn: 'Normal', next: 'Normal', quickFormat: true, run: { font: FONT, size: 23, bold: true, color: INK }, paragraph: { spacing: { before: 220, after: 80 }, outlineLevel: 2 } },
      { id: 'Heading2', name: 'Heading 2', basedOn: 'Normal', next: 'Normal', quickFormat: true, run: { font: FONT, size: 26, bold: true, color: TEAL }, paragraph: { spacing: { before: 280, after: 100 }, outlineLevel: 1 } },
    ],
  },
  numbering: { config: [
    { reference: 'bullets', levels: [{ level: 0, format: LevelFormat.BULLET, text: '•', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 540, hanging: 270 } } } }] },
    { reference: 'nums', levels: [{ level: 0, format: LevelFormat.DECIMAL, text: '%1.', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 540, hanging: 340 } } } }] },
  ] },
  sections: [{
    properties: { page: { size: { width: 11906, height: 16838 }, margin: { top: 1300, bottom: 1200, left: 1440, right: 1440 } } },
    headers: { default: new Header({ children: [new Paragraph({ alignment: AlignmentType.RIGHT, children: [new TextRun({ text: 'Confluent Platform 安全方案 · Ming 的前三週', font: FONT, size: 16, color: MUTE })] })] }) },
    footers: { default: new Footer({ children: [new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ children: ['第 ', PageNumber.CURRENT, ' 頁 / 共 ', PageNumber.TOTAL_PAGES, ' 頁'], font: FONT, size: 16, color: MUTE })] })] }) },
    children: kids,
  }],
});
const out = path.resolve(here, '..', '..', process.env.OUT_NAME || 'Confluent-Security-Lab-Story-Guide.docx');   // 原檔被 Word 開著時用 OUT_NAME 另存
fs.writeFileSync(out, await Packer.toBuffer(doc));
console.log('wrote', out, (fs.statSync(out).size / 1048576).toFixed(1) + ' MB');
if (missing.length) console.log('缺少的證據:', [...new Set(missing)].join(', '));
