// 簡報基礎建設(套用 IISI template):以「圖」為主的繪圖元件 + pptx-automizer 組裝
// 座標一律使用 template 的實際尺寸(13.33 x 7.5 吋);內容區約 x 0.6–12.6、y 1.7–6.9
const pptxgen = require('pptxgenjs');
const fs = require('fs');
const path = require('path');
const JSZip = require('jszip');
const React = require('react');
const { renderToStaticMarkup } = require('react-dom/server');
const sharp = require('sharp');
const FA = require('react-icons/fa');
const { Automizer, modify } = require('pptx-automizer');

const EV = path.resolve(__dirname, '..', 'demo', 'evidence');
const SH = new pptxgen().ShapeType;
const FONT = '微軟正黑體';
const C = {
  ink: '0E2841', blue: '155C91', orange: 'E58A17', green: '2F9E3F', red: 'C0192A', grey: '5B6B7A', white: 'FFFFFF', line: 'C9D3DC',
  pBlue: 'E4EFF7', pOrange: 'FDF0DC', pGreen: 'E3F3E6', pRed: 'FBE6E8', pGrey: 'F1F4F7', text: '22313F',
};

// ---------- 圖示(react-icons → PNG) ----------
const iconKeys = new Set();
const ICONS = {};
const ikey = (name, color) => `${name}|${color}`;
async function renderIcons() {
  for (const k of iconKeys) {
    const [name, color] = k.split('|');
    const Comp = FA[name];
    if (!Comp) throw new Error('unknown icon ' + name);
    const svg = renderToStaticMarkup(React.createElement(Comp, { color: '#' + color, size: 256 }));
    ICONS[k] = 'image/png;base64,' + (await sharp(Buffer.from(svg)).png().toBuffer()).toString('base64');
  }
}

// ---------- 錄製投影片 ----------
function pngSize(f) { const b = fs.readFileSync(f); return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) }; }
class Rec {
  constructor(meta) { this.meta = meta; this.ops = []; }
  // 文字(無外框)
  text(str, x, y, w, h, o = {}) {
    this.ops.push(['text', str, { x, y, w, h, fontFace: FONT, fontSize: o.fs || 14, color: o.color || C.text, bold: !!o.bold, italic: !!o.italic, align: o.align || 'left', valign: o.valign || 'middle', margin: 0, isTextBox: true, paraSpaceAfter: o.gap || 0, ...(o.extra || {}) }]);
    return this;
  }
  // 帶底色/外框的文字框(圓角)
  tbox(str, x, y, w, h, o = {}) {
    this.ops.push(['text', str, {
      x, y, w, h, shape: o.shape || SH.roundRect, rectRadius: o.r == null ? 0.12 : o.r, fontFace: FONT, fontSize: o.fs || 14, color: o.color || C.text, bold: !!o.bold,
      align: o.align || 'center', valign: o.valign || 'middle', margin: o.margin == null ? 4 : o.margin,
      fill: { color: o.fill || C.white }, line: o.noline ? { type: 'none' } : { color: o.line || C.line, width: o.lw || 1, dashType: o.dash || 'solid' },
    }]);
    return this;
  }
  // 純形狀
  shape(kind, x, y, w, h, o = {}) {
    this.ops.push(['shape', kind, { x, y, w, h, rectRadius: o.r == null ? 0.12 : o.r, fill: o.fill ? { color: o.fill, transparency: o.tr || 0 } : { type: 'none' }, line: o.noline ? { type: 'none' } : { color: o.line || C.line, width: o.lw || 1, dashType: o.dash || 'solid' }, flipH: o.flipH, flipV: o.flipV }]);
    return this;
  }
  box(x, y, w, h, o = {}) { return this.shape(SH.roundRect, x, y, w, h, o); }
  // 箭頭(含雙向、虛線)
  arrow(x1, y1, x2, y2, o = {}) {
    const x = Math.min(x1, x2), y = Math.min(y1, y2), w = Math.abs(x2 - x1), h = Math.abs(y2 - y1);
    this.ops.push(['shape', SH.line, { x, y, w, h, flipH: x2 < x1, flipV: y2 < y1, line: { color: o.color || C.grey, width: o.w || 2, dashType: o.dash || 'solid', endArrowType: o.noHead ? undefined : 'triangle', beginArrowType: o.both ? 'triangle' : undefined } }]);
    return this;
  }
  icon(name, x, y, size, color = C.blue) {
    iconKeys.add(ikey(name, color));
    this.ops.push(['icon', ikey(name, color), { x, y, w: size, h: size }]);
    return this;
  }
  // 圓形底 + 圖示
  badge(name, cx, cy, d, o = {}) {
    this.shape(SH.ellipse, cx - d / 2, cy - d / 2, d, d, { fill: o.fill || C.pBlue, noline: true });
    return this.icon(name, cx - d * 0.3, cy - d * 0.3, d * 0.6, o.color || C.blue);
  }
  // 截圖(等比縮放置中,加細框)
  img(rel, x, y, w, h, cap, capFs = 11) {
    const f = path.join(EV, rel);
    if (!fs.existsSync(f)) { console.warn('missing image', rel); return this; }
    const s = pngSize(f), r = Math.min(w / s.w, h / s.h), iw = s.w * r, ih = s.h * r, ix = x + (w - iw) / 2, iy = y + (h - ih) / 2;
    this.ops.push(['image', { path: f, x: ix, y: iy, w: iw, h: ih, altText: cap || rel }]);
    this.shape(SH.rect, ix, iy, iw, ih, { r: 0, line: C.line, lw: 0.75 });
    if (cap) this.text(cap, x, y + h + 0.04, w, 0.28, { fs: capFs, color: C.grey, align: 'center' });
    return this;
  }
  // 常用組件:人物
  person(name, sub, cx, y, o = {}) {
    this.badge('FaUser', cx, y + 0.45, 0.9, o);
    this.text(name, cx - 1, y + 0.98, 2, 0.3, { fs: 15, bold: true, align: 'center', color: C.ink });
    if (sub) this.text(sub, cx - 1.2, y + 1.26, 2.4, 0.26, { fs: 11, align: 'center', color: C.grey });
    return this;
  }
  // 常用組件:帶圖示的節點卡片
  node(x, y, w, h, icon, head, sub, o = {}) {
    this.tbox('', x, y, w, h, { fill: o.fill || C.white, line: o.line || C.line, lw: o.lw || 1.25 });
    this.icon(icon, x + 0.2, y + h / 2 - 0.28, 0.56, o.color || C.blue);
    this.text(head, x + 0.9, y + (sub ? 0.1 : 0), w - 1.0, sub ? h * 0.5 : h, { fs: o.fs || 16, bold: true, color: C.ink, valign: sub ? 'bottom' : 'middle' });
    if (sub) this.text(sub, x + 0.9, y + h * 0.55, w - 1.0, h * 0.4, { fs: o.sfs || 12, color: C.grey, valign: 'top' });
    return this;
  }
  chip(str, x, y, w, o = {}) { return this.tbox(str, x, y, w, o.h || 0.38, { fill: o.fill || C.pBlue, line: o.line || o.fill || C.pBlue, fs: o.fs || 12, color: o.color || C.blue, bold: true, r: 0.19, margin: 2 }); }
}

const SLIDES = [];
const slide = (title, sub) => { const r = new Rec({ kind: 'content', title, sub: sub || '' }); SLIDES.push(r); return r; };
const cover = (title, sub) => { const r = new Rec({ kind: 'cover', title, sub }); SLIDES.push(r); return r; };
const section = (title, sub) => SLIDES.push(new Rec({ kind: 'section', title, sub }));
const back = (title, sub) => SLIDES.push(new Rec({ kind: 'back', title, sub }));

function replay(g, rec) {
  for (const [k, a, b] of rec.ops) {
    if (k === 'text') g.addText(a, b);
    else if (k === 'shape') g.addShape(a, b);
    else if (k === 'image') g.addImage(a);
    else if (k === 'icon') g.addImage({ data: ICONS[a], ...b });
  }
}

// ---------- 組裝(複製 template 的版面,填入標題/副標題) ----------
const TPL = path.join(__dirname, 'tpl');
const SZ = { content: [2800, 1600], cover: [null, 2000], section: [null, 2000], back: [null, 2000] };
async function prepTemplate() {
  const zip = await JSZip.loadAsync(fs.readFileSync(path.join(TPL, 'IISI.pptx')));
  const fill = (xml, shapeName, text, sz) => {
    const parts = xml.split('<p:sp>');
    for (let i = 1; i < parts.length; i++) {
      if (!parts[i].includes(`name="${shapeName}"`)) continue;
      parts[i] = parts[i].replace(/<a:p><a:endParaRPr[^>]*\/><\/a:p>/, `<a:p><a:r><a:rPr lang="zh-TW" altLang="en-US"${sz ? ` sz="${sz}"` : ''} dirty="0"/><a:t>TEXT</a:t></a:r></a:p>`);
    }
    return parts.join('<p:sp>');
  };
  const spec = [[1, '標題 1', '文字版面配置區 2', 'cover'], [3, '標題 1', '文字版面配置區 4', 'section'], [4, '標題 5', '文字版面配置區 7', 'content'], [7, '標題 1', '文字版面配置區 2', 'back']];
  for (const [n, tn, sn, kind] of spec) {
    const f = `ppt/slides/slide${n}.xml`;
    let xml = await zip.file(f).async('string');
    xml = fill(xml, tn, 'TITLE', SZ[kind][0]);
    xml = fill(xml, sn, 'SUB', SZ[kind][1]);
    zip.file(f, xml);
  }
  fs.writeFileSync(path.join(TPL, 'IISI-prepped.pptx'), await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' }));
}
async function cleanPackage(file) {
  const zip = await JSZip.loadAsync(fs.readFileSync(file));
  for (const n of Object.keys(zip.files)) {
    const m = n.match(/^ppt\/slides\/_rels\/(slide\d+\.xml)\.rels$/);
    if (m && !zip.file(`ppt/slides/${m[1]}`)) zip.remove(n);
    if (n.startsWith('[trash]')) zip.remove(n);
  }
  fs.writeFileSync(file, await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' }));
}
async function build(outFile) {
  await renderIcons();
  await prepTemplate();
  const a = new Automizer({ templateDir: TPL, outputDir: TPL, removeExistingSlides: true, cleanup: true });
  const p = a.loadRoot('IISI-prepped.pptx').load('IISI-prepped.pptx', 't');
  for (const r of SLIDES) {
    const m = r.meta;
    if (m.kind === 'cover') p.addSlide('t', 1, sl => { sl.modifyElement('標題 1', [modify.setText(m.title)]); sl.modifyElement('文字版面配置區 2', [modify.setText(m.sub)]); sl.generate(g => replay(g, r)); });
    else if (m.kind === 'section') p.addSlide('t', 3, sl => { sl.modifyElement('標題 1', [modify.setText(m.title)]); sl.modifyElement('文字版面配置區 4', [modify.setText(m.sub)]); });
    else if (m.kind === 'back') p.addSlide('t', 7, sl => { sl.modifyElement('標題 1', [modify.setText(m.title)]); sl.modifyElement('文字版面配置區 2', [modify.setText(m.sub)]); });
    else p.addSlide('t', 4, sl => {
      sl.modifyElement('標題 5', [modify.setText(m.title)]);
      sl.modifyElement('文字版面配置區 7', [modify.setText(m.sub)]);
      sl.removeElement('內容版面配置區 6');
      sl.generate(g => replay(g, r));
    });
  }
  const res = await p.write('deck-iisi.pptx');
  console.log(res.status, 'slides:', res.slides);
  await cleanPackage(path.join(TPL, 'deck-iisi.pptx'));
  fs.copyFileSync(path.join(TPL, 'deck-iisi.pptx'), outFile);
  console.log('wrote', outFile);
}
module.exports = { C, SH, FONT, slide, cover, section, back, build, SLIDES, ICONS, prepTemplate, cleanPackage, TPL };
