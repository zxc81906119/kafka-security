// 方案簡報套用 IISI 公司模板:讀 build-solution-deck.js 的版面規格(SLIDES),
// 以 pptx-automizer 複製 IISI template 的版面(封面 / 章節 / 內容 / 結尾),再把圖形疊在內容頁上。
// 用法: NODE_PATH=deck/node_modules node build-solution-iisi.js   (OUT 環境變數可改輸出檔)
const fs = require('fs');
const path = require('path');
const React = require('react');
const { renderToStaticMarkup } = require('react-dom/server');
const sharp = require('sharp');
const FA = require('react-icons/fa');
const pptxgen = require('pptxgenjs');
const { Automizer, modify } = require('pptx-automizer');
const { SLIDES, HEX, NO_END, NO_NOTES } = require(process.env.SPEC || './build-solution-deck.js');   // SPEC=./build-solution-short.js 可產生簡化版
const { prepTemplate, cleanPackage, TPL, FONT } = require('./deck-lib');

const OUT = process.env.OUT || path.join(__dirname, 'Confluent-Security-Solution-IISI.pptx');
const SH = new pptxgen().ShapeType;
const col = k => HEX[k] || k;
// 版面座標:原規格內容區 y 1.4–6.95 → 公司模板內容區 y 1.75–6.9
const KY = (6.9 - 1.75) / (6.95 - 1.4), Y = y => 1.75 + (y - 1.4) * KY, H = h => h * KY;

const SUBS = {
  '客戶前提': '六個前提決定了方案的形狀', '設計原則:兩個身分平面': '人走 AD,機器走 SCRAM 或 client 憑證', '方案總覽:組件與安全機制': '各組件怎麼認證、授權,以及貫穿全案的機制',
  'TLS 與憑證:共用 1 組,只做加密': '共用 server 憑證只加密;平台元件的 client 憑證用來換 token', '憑證更換:三種情境,順序不能錯': '依單節點實驗結果整理', '元件更換順序:先信任、後出示、最後移除': 'CA 換金鑰的情境:依 demo 實際環境演練整理', 'Controller(KRaft)': '只認內部帳號,人與服務都不直接連',
  'Broker:三個入口,各管一件事': '人 PLAIN + AD、服務 SCRAM、平台 OAUTHBEARER', 'MDS:RBAC 的中樞(內嵌於 broker)': '換 token、管 RBAC、向 AD 查群組',
  'AD 群組 → role:依職責分層授權': '同一個 AD,不同群組 = 不同權限層級', 'Confluent 內建角色與 scope': '十個內建角色,依「綁在叢集」或「綁在資源」分兩類', '服務帳號:SCRAM,不放 AD': 'AD 沒有服務帳號 → SCRAM + 最小權限 + 輪替', '特例:不能有失敗窗口的服務': '新帳號並行:新舊同時有效,代價是 client 要改帳號、role 要重綁',
  'REST Proxy:legacy app 的入口': '人用 Basic、機器用 client 憑證,身分一路傳到 broker', 'Control Center:人用本人身分': 'C3 自己的背景工作才用憑證',
  'C3 周邊:Prometheus · Alertmanager': '指標與告警的四條連線,都要 TLS + Basic(實測通過)', 'Audit log:誰被拒、誰改了授權': '預設只記錄 Management 與 Authorize',
  '全景整合圖': '人與機器如何進入,由 MDS 的 RBAC 集中判斷', '人的完整路徑': '三條路徑,同一套 AD 群組授權', '機器的完整路徑': '身分在 Kafka 內或憑證,RBAC 綁 User:', '要管理的憑證與帳號': '客戶實際要維運的清單', '導入步驟(RHEL 9 手動部署)': '沒有 Ansible:先標準化手動流程',
  '風險與對策': '六個主要風險', '風險與對策(續)': '兩個操作陷阱和一項待驗證', '已驗證 vs 待驗證': '誠實呈現目前的驗證範圍', '導入前請客戶確認': '八件需要客戶回覆的事', '下一步': '接下來的三件事',
};
const DEMO_SUB = '左:指令與預期結果 · 右:實際執行畫面';


// 封面副標:範本版面區的拉丁字型是 Arial Black,英文與冒號會變粗;改用內文字型讓整句一致
async function patchCoverSubtitle(file, subText) {
  const JSZip = require('jszip');
  const zip = await JSZip.loadAsync(fs.readFileSync(file));
  const from = '<a:rPr lang="zh-TW" altLang="en-US" sz="2000" dirty="0"/><a:t>' + subText;
  const to = '<a:rPr lang="zh-TW" altLang="en-US" sz="2000" dirty="0"><a:latin typeface="' + FONT + '"/><a:ea typeface="' + FONT + '"/></a:rPr><a:t>' + subText;
  let hit = 0;
  for (const n of Object.keys(zip.files).filter(n => /^ppt\/slides\/slide\d+\.xml$/.test(n))) {
    const x = await zip.file(n).async('string');
    if (x.includes(from)) { zip.file(n, x.split(from).join(to)); hit++; }
  }
  if (hit !== 1) throw new Error('封面副標字型修正:預期 1 張,實際 ' + hit);
  fs.writeFileSync(file, await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' }));
}

// 依投影片順序補寫講者備忘稿(pptx-automizer 產生的投影片不含 notes)
async function addNotes(file, notes) {
  const JSZip = require('jszip');
  const zip = await JSZip.loadAsync(fs.readFileSync(file));
  const rels = await zip.file('ppt/_rels/presentation.xml.rels').async('string');
  const pres = await zip.file('ppt/presentation.xml').async('string');
  const target = {}; for (const m of rels.matchAll(/<Relationship [^>]*>/g)) { const id = (m[0].match(/Id="([^"]+)"/) || [])[1], tg = (m[0].match(/Target="([^"]+)"/) || [])[1]; if (id && tg) target[id] = tg; }
  const order = [...pres.matchAll(/<p:sldId [^>]*r:id="([^"]+)"/g)].map(m => path.posix.basename(target[m[1]]));
  const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  let ct = await zip.file('[Content_Types].xml').async('string'), n = 0;
  for (let i = 0; i < order.length && i < notes.length; i++) {
    if (!notes[i]) continue;
    const slideFile = order[i], base = path.basename(slideFile), nf = 'notesSlide' + (i + 1) + '.xml';
    const xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:notes xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/><p:sp><p:nvSpPr><p:cNvPr id="2" name="Slide Image Placeholder 1"/><p:cNvSpPr><a:spLocks noGrp="1" noRot="1" noChangeAspect="1"/></p:cNvSpPr><p:nvPr><p:ph type="sldImg"/></p:nvPr></p:nvSpPr><p:spPr/></p:sp><p:sp><p:nvSpPr><p:cNvPr id="3" name="Notes Placeholder 2"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr><p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="zh-TW" dirty="0"/><a:t>' + esc(notes[i]) + '</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>';
    zip.file('ppt/notesSlides/' + nf, xml);
    zip.file('ppt/notesSlides/_rels/' + nf + '.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster" Target="../notesMasters/notesMaster1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="../slides/' + base + '"/></Relationships>');
    const rp = 'ppt/slides/_rels/' + base + '.rels';
    let sr = await zip.file(rp).async('string');
    sr = sr.replace('</Relationships>', '<Relationship Id="rIdNotes1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide" Target="../notesSlides/' + nf + '"/></Relationships>');
    zip.file(rp, sr);
    ct = ct.replace('</Types>', '<Override PartName="/ppt/notesSlides/' + nf + '" ContentType="application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml"/></Types>');
    n++;
  }
  zip.file('[Content_Types].xml', ct);
  fs.writeFileSync(file, await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' }));
  console.log('notes written:', n);
}

(async () => {
  const ICON = {};
  const need = new Set();
  SLIDES.forEach(s => s.items.forEach(it => { if (it.k === 'icon') need.add(it.name + '|' + it.col); }));
  for (const k of need) {
    const [name, c] = k.split('|');
    const svg = renderToStaticMarkup(React.createElement(FA[name], { color: '#' + col(c), size: 256 }));
    ICON[k] = 'image/png;base64,' + (await sharp(Buffer.from(svg)).png().toBuffer()).toString('base64');
  }

  const replay = (g, s) => {
    for (const it of s.items) {
      if (it.k === 'icon') { g.addImage({ data: ICON[it.name + '|' + it.col], x: it.x, y: Y(it.y), w: it.s, h: it.s * KY > it.s ? it.s : it.s }); continue; }
      if (it.k === 'img') { g.addImage({ path: it.file, x: it.x, y: Y(it.y), w: it.w, h: it.h }); continue; }
      if (it.k === 'arrow') {
        const y1 = Y(it.y1), y2 = Y(it.y2), x = Math.min(it.x1, it.x2), y = Math.min(y1, y2);
        g.addShape(SH.line, { x, y, w: Math.abs(it.x2 - it.x1), h: Math.abs(y2 - y1), flipH: it.x2 < it.x1, flipV: y2 < y1, line: { color: col(it.col), width: it.w, endArrowType: 'triangle', dashType: it.dash ? 'dash' : 'solid' } });
        continue;
      }
      if (it.k === 'table') {
        const rows = it.rows.map((r, ri) => r.map((c, ci) => ({ text: c, options: { bold: ri === 0 || ci === 0, fontSize: it.sz, fontFace: FONT, color: ri === 0 ? 'FFFFFF' : (ci === 0 && it.rowCols && it.rowCols[ri - 1] ? col(it.rowCols[ri - 1]) : col('text1')), fill: { color: ri === 0 ? col(it.col) : (ci === 0 ? 'E9EEF3' : (ri % 2 ? 'FFFFFF' : col('background2'))) }, valign: 'middle', lang: 'zh-TW' } })));
        g.addTable(rows, { x: it.x, y: Y(it.y), colW: it.colW, rowH: it.rows.map((_, i) => (i === 0 ? it.hdrH : it.rowH) * KY), border: { type: 'solid', pt: 0.75, color: 'BFBFBF' }, margin: [0.04, 0.08, 0.04, 0.08] });
        continue;
      }
      const hasFill = !!it.fill, o = { x: it.x, y: Y(it.y), w: it.w, h: H(it.h) };
      if (hasFill) o.fill = { color: col(it.fill), transparency: Math.round(it.tint * 100) };
      if (it.line) o.line = { color: col(it.line), width: it.lw };
      if (it.round > 0) o.rectRadius = Math.min(it.round, 0.5) * Math.min(it.w, H(it.h)) * 0.9;
      const shape = it.round > 0 ? SH.roundRect : SH.rect;
      if (!it.paras.length) { g.addShape(shape, o); continue; }
      const runs = [];
      it.paras.forEach((p, pi) => p.runs.forEach((r, ri) => {
        const lines = r.t.split('\n');
        lines.forEach((ln, li) => runs.push({ text: ln, options: { fontSize: r.sz, fontFace: FONT, bold: r.b, color: col(r.c), transparency: r.a !== undefined ? Math.round((1 - r.a) * 100) : undefined, align: p.algn === 'ctr' ? 'center' : (p.algn === 'r' ? 'right' : 'left'), paraSpaceAfter: p.after, breakLine: (li < lines.length - 1) || (ri === p.runs.length - 1 && pi < it.paras.length - 1), lang: 'zh-TW' } }));
      }));
      const to = { ...o, margin: it.ins * 72, valign: it.anchor === 'ctr' ? 'middle' : 'top' };
      if (hasFill || it.line) to.shape = shape;
      g.addText(runs, to);
    }
  };

  await prepTemplate();
  const a = new Automizer({ templateDir: TPL, outputDir: TPL, removeExistingSlides: true, cleanup: true });
  const p = a.loadRoot('IISI-prepped.pptx').load('IISI-prepped.pptx', 't');
  for (const s of SLIDES) {
    if (s.layout === 'TITLE') {
      p.addSlide('t', 1, sl => {
        sl.modifyElement('標題 1', [modify.setText(s.coverTitle || 'Confluent 安全解決方案')]);
        sl.modifyElement('文字版面配置區 2', [modify.setText(s.coverSub || '依客戶前提設計:AD 僅有 user / group')]);
        if (!s.noCoverLines) sl.generate(g => g.addText([{ text: 'Confluent Platform 8.3 · RHEL 9 手動部署', options: { fontSize: 14, fontFace: FONT, color: col('text2'), breakLine: true, lang: 'zh-TW' } }, { text: '範圍:Kafka · REST Proxy · Control Center', options: { fontSize: 14, fontFace: FONT, color: col('text2'), lang: 'zh-TW' } }], { x: 0.65, y: 4.75, w: 5.7, h: 0.8, margin: 0, valign: 'top' }));
      });
    } else if (s.layout === 'SECTION') {
      p.addSlide('t', 3, sl => { sl.modifyElement('標題 1', [modify.setText(s.title)]); sl.modifyElement('文字版面配置區 4', [modify.setText(s.subtitle || '')]); });
    } else {
      const sub = s.sub !== undefined ? s.sub : (/^Demo \d/.test(s.title) ? DEMO_SUB : (SUBS[s.title] || ''));
      p.addSlide('t', 4, sl => {
        sl.modifyElement('標題 5', [modify.setText(s.title)]);
        if (sub) sl.modifyElement('文字版面配置區 7', [modify.setText(sub)]); else sl.removeElement('文字版面配置區 7');
        sl.removeElement('內容版面配置區 6');
        sl.generate(g => { replay(g, s); if (!NO_NOTES && s.notes && g.addNotes) g.addNotes(s.notes); });
      });
    }
  }
  if (!NO_END) p.addSlide('t', 7, sl => { sl.modifyElement('標題 1', [modify.setText('Q & A')]); sl.modifyElement('文字版面配置區 2', [modify.setText('Confluent Platform 安全解決方案')]); });
  const res = await p.write('deck-iisi-solution.pptx');
  console.log(res.status, 'slides:', res.slides);
  await cleanPackage(path.join(TPL, 'deck-iisi-solution.pptx'));
  await addNotes(path.join(TPL, 'deck-iisi-solution.pptx'), SLIDES.map(s => NO_NOTES ? '' : (s.notes || '')));
  await patchCoverSubtitle(path.join(TPL, 'deck-iisi-solution.pptx'), (SLIDES.find(s => s.layout === 'TITLE') || {}).coverSub || '依客戶前提設計');
  fs.copyFileSync(path.join(TPL, 'deck-iisi-solution.pptx'), OUT);
  console.log('wrote', OUT);
})().catch(e => { console.error('ERR', e); process.exit(1); });
