// 方案簡報的預覽與檢查(近似,非 PowerPoint 真實渲染):規格 → HTML → Playwright 截圖 + 溢出偵測
// 用法: node preview-solution.js [頁碼...]   → deck/preview-sol/sNN.png
const fs = require('fs');
const path = require('path');
const React = require('react');
const { renderToStaticMarkup } = require('react-dom/server');
const sharp = require('sharp');
const FA = require('react-icons/fa');
const { chromium } = require('../demo/e2e/node_modules/playwright');
const { SLIDES, HEX } = require('./build-solution-deck.js');

const X = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const px = v => (v * 96).toFixed(1) + 'px';
const rgba = (key, a) => { const h = HEX[key]; const r = parseInt(h.slice(0, 2), 16), g = parseInt(h.slice(2, 4), 16), b = parseInt(h.slice(4, 6), 16); return `rgba(${r},${g},${b},${a})`; };
const ICON = {};
async function icons() {
  const need = new Set(); SLIDES.forEach(s => s.items.forEach(it => { if (it.k === 'icon') need.add(it.name + '|' + it.col); }));
  for (const k of need) { const [n, c] = k.split('|'); const svg = renderToStaticMarkup(React.createElement(FA[n], { color: '#' + HEX[c], size: 256 })); ICON[k] = (await sharp(Buffer.from(svg)).png().toBuffer()).toString('base64'); }
}
function html(it) {
  if (it.k === 'img') return `<img src="file:///${it.file.split(String.fromCharCode(92)).join('/')}" style="position:absolute;left:${px(it.x)};top:${px(it.y)};width:${px(it.w)};height:${px(it.h)}">`;
  if (it.k === 'icon') return `<img src="data:image/png;base64,${ICON[it.name + '|' + it.col]}" style="position:absolute;left:${px(it.x)};top:${px(it.y)};width:${px(it.s)};height:${px(it.s)}">`;
  if (it.k === 'arrow') {
    const dx = it.x2 - it.x1, dy = it.y2 - it.y1, len = Math.hypot(dx, dy) * 96, ang = Math.atan2(dy, dx) * 180 / Math.PI;
    return `<div class="arr" style="left:${px(it.x1)};top:${px(it.y1)};width:${len}px;transform:rotate(${ang}deg);border-top:${it.w * 1.33}px ${it.dash ? 'dashed' : 'solid'} ${rgba(it.col, 1)}"><i style="border-left-color:${rgba(it.col, 1)}"></i></div>`;
  }
  if (it.k === 'table') {
    const rows = it.rows.map((r, ri) => `<tr style="height:${px(ri === 0 ? it.hdrH : it.rowH)}">${r.map((c, ci) => { const bg = ri === 0 ? rgba(it.col, 1) : (ci === 0 ? rgba(it.col, 0.15) : (ri % 2 ? '#fff' : '#' + HEX.background2)); return `<td style="background:${bg};color:${ri === 0 ? '#fff' : '#' + HEX.text1};font-weight:${ri === 0 || ci === 0 ? 700 : 400};font-size:${it.sz * 1.333}px">${X(c)}</td>`; }).join('')}</tr>`).join('');
    return `<table class="tb" style="left:${px(it.x)};top:${px(it.y)};width:${px(it.colW.reduce((a, b) => a + b, 0))}"><colgroup>${it.colW.map(w => `<col style="width:${px(w)}">`).join('')}</colgroup>${rows}</table>`;
  }
  const ps = it.paras.map(p => `<p style="text-align:${p.algn === 'ctr' ? 'center' : (p.algn === 'r' ? 'right' : 'left')};margin:0 0 ${p.after * 1.33}px">${p.runs.map(r => `<span style="font-size:${r.sz * 1.333}px;font-weight:${r.b ? 700 : 400};color:${rgba(r.c, r.a === undefined ? 1 : r.a)}">${X(r.t).replace(/\n/g, '<br>')}</span>`).join('')}</p>`).join('');
  const bg = it.fill ? `background:${rgba(it.fill, 1 - it.tint)};` : '';
  const bd = it.line ? `border:${it.lw * 1.33}px solid ${rgba(it.line, 1)};` : '';
  const rad = it.round > 0 ? Math.min(it.round, 0.5) * Math.min(it.w, it.h) * 96 * 0.9 + 'px' : '0';
  return `<div class="bx" style="left:${px(it.x)};top:${px(it.y)};width:${px(it.w)};height:${px(it.h)};padding:${px(it.ins)};${bg}${bd}border-radius:${rad};justify-content:${it.anchor === 'ctr' ? 'center' : 'flex-start'}">${ps}</div>`;
}
function slideHtml(s, n) {
  let bg = '#fff', head = '';
  if (s.layout === 'TITLE') head = `<div style="position:absolute;left:0;top:0;width:${px(0.35)};height:100%;background:${rgba('accent1', 1)}"></div><div class="ph" style="left:${px(0.9)};top:${px(2.2)};width:${px(8.4)};height:${px(1.6)};font-size:${38 * 1.333}px;font-weight:700;color:${rgba('text2', 1)};justify-content:flex-end">${X(s.title)}</div><div class="ph" style="left:${px(0.9)};top:${px(4.0)};width:${px(8.4)};height:${px(1.2)};font-size:${18 * 1.333}px;color:${rgba('text1', 1)}">${X(s.subtitle || '')}</div>`;
  else if (s.layout === 'SECTION') { bg = '#' + HEX.text2; head = `<div class="ph" style="left:${px(0.9)};top:${px(2.5)};width:${px(11.5)};height:${px(1.2)};font-size:${38 * 1.333}px;font-weight:700;color:#fff;justify-content:flex-end">${X(s.title)}</div><div class="ph" style="left:${px(0.9)};top:${px(3.85)};width:${px(11.5)};height:${px(0.9)};font-size:${18 * 1.333}px;color:#${HEX.background2}">${X(s.subtitle || '')}</div>`; }
  else head = `<div class="ph" style="left:${px(0.6)};top:${px(0.3)};width:${px(12.13)};height:${px(0.95)};font-size:${28 * 1.333}px;font-weight:700;color:${rgba('text2', 1)};justify-content:center">${X(s.title)}</div><div style="position:absolute;left:${px(0.6)};top:${px(7.08)};font-size:${10 * 1.333}px;opacity:.5">Confluent Platform 安全解決方案 · 草稿</div><div style="position:absolute;right:${px(0.5)};top:${px(7.08)};font-size:${10 * 1.333}px">${n}</div>`;
  return `<div class="sl" data-n="${n}" style="background:${bg}">${head}${s.items.map(html).join('')}</div>`;
}
const CSS = `<meta charset="utf-8"><style>body{margin:0;background:#777}.sl{position:relative;width:1280px;height:720px;overflow:hidden;margin:0 0 8px;font-family:'Microsoft JhengHei','Noto Sans CJK TC',sans-serif;line-height:1.2;color:#1a1a1a}
.ph{position:absolute;display:flex;flex-direction:column}.bx{position:absolute;box-sizing:border-box;display:flex;flex-direction:column;overflow:hidden}.arr{position:absolute;height:0;transform-origin:0 0}.arr i{position:absolute;right:-2px;top:-7px;border:7px solid transparent;border-left:12px solid}
.tb{position:absolute;border-collapse:collapse;table-layout:fixed}.tb td{border:1px solid #BFBFBF;padding:3px 8px;vertical-align:middle}</style>`;

(async () => {
  await icons();
  const only = process.argv.slice(2).map(Number);
  const page_html = `<!doctype html><html><head>${CSS}</head><body>${SLIDES.map((s, i) => slideHtml(s, i + 1)).join('')}</body></html>`;
  const f = path.join(__dirname, 'preview-solution.html'); fs.writeFileSync(f, page_html);
  const b = await chromium.launch(); const pg = await b.newPage({ viewport: { width: 1280, height: 720 } });
  await pg.goto('file:///' + f.replace(/\\/g, '/'));
  const problems = await pg.evaluate(() => {
    const out = [];
    document.querySelectorAll('.sl').forEach(sl => {
      const n = sl.dataset.n, sr = sl.getBoundingClientRect();
      sl.querySelectorAll('.bx').forEach(bx => {
        if (bx.scrollHeight > bx.clientHeight + 2 || bx.scrollWidth > bx.clientWidth + 2) out.push(`#${n} 溢出 (${bx.scrollHeight}>${bx.clientHeight}) "${bx.textContent.slice(0, 30)}"`);
        const r = bx.getBoundingClientRect(); if (r.bottom > sr.bottom + 1 || r.right > sr.right + 1) out.push(`#${n} 超出頁面 "${bx.textContent.slice(0, 20)}"`);
      });
      sl.querySelectorAll('.tb').forEach(t => { const r = t.getBoundingClientRect(); if (r.bottom > sr.bottom - 10) out.push(`#${n} 表格底部 ${Math.round(r.bottom - sr.top)}px`); });
    });
    return out;
  });
  console.log(problems.length ? problems.join('\n') : '預覽:無溢出');
  fs.mkdirSync(path.join(__dirname, 'preview-sol'), { recursive: true });
  const sls = await pg.$$('.sl');
  for (let i = 0; i < sls.length; i++) if (!only.length || only.includes(i + 1)) await sls[i].screenshot({ path: path.join(__dirname, 'preview-sol', `s${String(i + 1).padStart(2, '0')}.png`) });
  console.log('預覽圖', only.length || sls.length, '張');
  await b.close();
})();
