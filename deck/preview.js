// 版面預覽(近似):把 deck-lib 錄製的投影片畫成 HTML,再用 Playwright 截圖,供人工檢查重疊/溢出。
// 這不是 PowerPoint 的真實渲染,字型與換行會有些差異,但能抓出座標與大小的明顯問題。
// 用法:node preview.js   → deck/preview/slide-NN.png
const fs = require('fs');
const path = require('path');

const PX = 96; // 1 吋 = 96 px
const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\n/g, '<br>');

function slideHtml(rec, ICONS, idx) {
  const parts = [];
  const bgMap = { content: '#fff', cover: '#fff', section: '#fff', back: '#fff' };
  const m = rec.meta;
  // 標題區(template 版面的近似)
  if (m.kind === 'content') {
    parts.push(`<div style="position:absolute;left:${0.54 * PX}px;top:${0.34 * PX}px;width:${11.1 * PX}px;height:${0.67 * PX}px;font:700 ${28 * 1.333}px 'Microsoft JhengHei';color:#000;display:flex;align-items:center">${esc(m.title)}</div>`);
    parts.push(`<div style="position:absolute;left:${0.54 * PX}px;top:${1.02 * PX}px;width:${11.1 * PX}px;height:${0.54 * PX}px;font:700 ${16 * 1.333}px 'Microsoft JhengHei';color:#000;display:flex;align-items:center">${esc(m.sub)}</div>`);
    parts.push(`<div style="position:absolute;left:0;top:0;width:${13.33 * PX}px;height:${7.5 * PX}px;border-right:16px solid #c0192a22;pointer-events:none"></div>`);
  } else if (m.kind === 'section' || m.kind === 'back') {
    parts.push(`<div style="position:absolute;left:${1.17 * PX}px;top:${1.7 * PX}px;width:${5.86 * PX}px;font:700 ${44 * 1.333}px 'Microsoft JhengHei'">${esc(m.title)}</div><div style="position:absolute;left:${1.9 * PX}px;top:${2.88 * PX}px;width:${5.13 * PX}px;font:700 ${20 * 1.333}px 'Microsoft JhengHei'">${esc(m.sub)}</div>`);
  } else if (m.kind === 'cover') {
    parts.push(`<div style="position:absolute;left:${0.5 * PX}px;top:${2.72 * PX}px;font:700 ${50 * 1.333}px 'Microsoft JhengHei'">${esc(m.title)}</div><div style="position:absolute;left:${0.5 * PX}px;top:${3.86 * PX}px;font:700 ${20 * 1.333}px 'Microsoft JhengHei'">${esc(m.sub)}</div>`);
  }
  let svg = '';
  for (const [k, a, b] of rec.ops) {
    if (k === 'shape' && a === 'line') {
      const x1 = (b.flipH ? b.x + b.w : b.x) * PX, x2 = (b.flipH ? b.x : b.x + b.w) * PX;
      const y1 = (b.flipV ? b.y + b.h : b.y) * PX, y2 = (b.flipV ? b.y : b.y + b.h) * PX;
      const col = '#' + (b.line.color || '888'); const head = b.line.endArrowType ? 'marker-end="url(#ah' + col.slice(1) + ')"' : ''; const tail = b.line.beginArrowType ? 'marker-start="url(#ah' + col.slice(1) + ')"' : '';
      parts.push(`<svg style="position:absolute;left:0;top:0" width="${13.33 * PX}" height="${7.5 * PX}"><defs><marker id="ah${col.slice(1)}" markerWidth="8" markerHeight="8" refX="6" refY="4" orient="auto-start-reverse"><path d="M0,0 L8,4 L0,8 z" fill="${col}"/></marker></defs><line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="${col}" stroke-width="${(b.line.width || 1) * 1.333}" ${b.line.dashType === 'dash' ? 'stroke-dasharray="6 4"' : ''} ${head} ${tail}/></svg>`);
    } else if (k === 'shape') {
      const fill = b.fill && b.fill.color ? '#' + b.fill.color : 'transparent';
      const ln = b.line && b.line.color ? `${(b.line.width || 1) * 1.333}px ${b.line.dashType === 'dash' ? 'dashed' : 'solid'} #${b.line.color}` : 'none';
      const rad = a === 'ellipse' ? '50%' : a === 'rect' ? '0' : `${(b.rectRadius || 0.1) * PX}px`;
      parts.push(`<div style="position:absolute;box-sizing:border-box;left:${b.x * PX}px;top:${b.y * PX}px;width:${b.w * PX}px;height:${b.h * PX}px;background:${fill};border:${ln};border-radius:${rad}"></div>`);
    } else if (k === 'text') {
      const shaped = !!b.shape;
      const fill = shaped && b.fill && b.fill.color ? '#' + b.fill.color : 'transparent';
      const ln = shaped && b.line && b.line.color ? `${(b.line.width || 1) * 1.333}px ${b.line.dashType === 'dash' ? 'dashed' : 'solid'} #${b.line.color}` : 'none';
      const rad = !shaped ? '0' : b.shape === 'ellipse' ? '50%' : `${(b.rectRadius || 0.1) * PX}px`;
      const jc = b.align === 'center' ? 'center' : b.align === 'right' ? 'flex-end' : 'flex-start';
      const ai = b.valign === 'top' ? 'flex-start' : b.valign === 'bottom' ? 'flex-end' : 'center';
      parts.push(`<div data-t="1" style="position:absolute;box-sizing:border-box;left:${b.x * PX}px;top:${b.y * PX}px;width:${b.w * PX}px;height:${b.h * PX}px;background:${fill};border:${ln};border-radius:${rad};display:flex;justify-content:${jc};align-items:${ai};text-align:${b.align};padding:${shaped ? (b.margin || 4) : 0}px;font:${b.bold ? 700 : 400} ${b.fontSize * 1.333}px 'Microsoft JhengHei';color:#${b.color};line-height:1.2;overflow:visible"><span>${esc(a)}</span></div>`);
    } else if (k === 'image') {
      parts.push(`<img src="file:///${a.path.replace(/\\/g, '/')}" style="position:absolute;left:${a.x * PX}px;top:${a.y * PX}px;width:${a.w * PX}px;height:${a.h * PX}px">`);
    } else if (k === 'icon') {
      parts.push(`<img src="data:${ICONS[a]}" style="position:absolute;left:${b.x * PX}px;top:${b.y * PX}px;width:${b.w * PX}px;height:${b.h * PX}px">`);
    }
  }
  return `<!doctype html><meta charset="utf-8"><body style="margin:0"><div style="position:relative;width:${13.33 * PX}px;height:${7.5 * PX}px;background:${bgMap[m.kind]};overflow:hidden;outline:1px solid #ddd"><svg style="position:absolute;left:0;top:0" width="${13.33 * PX}" height="${7.5 * PX}">${svg}</svg>${parts.join('')}<div style="position:absolute;right:8px;bottom:4px;font:12px sans-serif;color:#999">${idx}</div></div>`;
}

async function renderPreview(SLIDES, ICONS, outDir) {
  fs.mkdirSync(outDir, { recursive: true });
  const { chromium } = require(path.resolve(__dirname, '..', 'demo', 'e2e', 'node_modules', 'playwright'));
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: Math.round(13.33 * PX), height: Math.round(7.5 * PX) } });
  let i = 0;
  for (const rec of SLIDES) {
    i++;
    const f = path.join(outDir, `slide-${String(i).padStart(2, '0')}.html`);
    fs.writeFileSync(f, slideHtml(rec, ICONS, i));
    await page.goto('file:///' + f.replace(/\\/g, '/'));
    await page.waitForTimeout(150);
    const over = await page.evaluate(() => [...document.querySelectorAll('[data-t]')].map(d => {
      const s = d.querySelector('span'); if (!s || !s.textContent.trim()) return null;
      const a = d.getBoundingClientRect(), b = s.getBoundingClientRect();
      const pad = parseFloat(getComputedStyle(d).paddingLeft) * 2;
      const hi = b.height - a.height, wi = b.width - (a.width - pad);
      return (hi > 2 || wi > 2) ? { txt: s.textContent.trim().slice(0, 24), dh: Math.round(hi), dw: Math.round(wi), box: [Math.round(a.width), Math.round(a.height)] } : null;
    }).filter(Boolean));
    over.forEach(o => console.log('  ⚠ 第 ' + i + ' 頁 文字超出外框:「' + o.txt + '」(多 ' + o.dh + 'px 高、' + o.dw + 'px 寬;框 ' + o.box.join('x') + ')'));
    await page.screenshot({ path: f.replace('.html', '.png') });
    fs.unlinkSync(f);
  }
  await browser.close();
  console.log('preview:', i, 'slides →', outDir);
}
module.exports = { renderPreview };
