// 把 evidence/**/NN-*.log 渲染成終端風格 PNG(內容為實際輸出)。
// 用法: node render-terminal.mjs [chapter-id ...]   不帶參數 = 全部章節
import { launchChromium } from './browser.mjs';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'evidence');
const only = process.argv.slice(2);
const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

function colorize(line) {
  const e = esc(line);
  if (line.startsWith('$ ')) return `<span class="cmd"><span class="prompt">$</span> ${e.slice(2)}</span>`;
  if (/(Authorization failed|Not authorized|TopicAuthorization|TOPIC_AUTHORIZATION|Authentication failed|HTTP 40[0-9]|\[HTTP 40[0-9]\]|"granted":false|DENIED|✘|被拒|拒絕)/.test(line)) return `<span class="bad">${e}</span>`;
  if (/(Created|Completed|\[HTTP 20[0-9]\]|HTTP 20[0-9]|"granted":true|ALLOWED|✔|Processed a total|offset|成功)/.test(line)) return `<span class="ok">${e}</span>`;
  return e;
}

const html = (title, who, lines) => `<!doctype html><meta charset="utf-8"><style>
body{margin:0;background:#0f1117;font-family:"Cascadia Mono",Consolas,"Courier New",monospace}
.win{width:1180px;border-radius:10px;overflow:hidden;box-shadow:0 8px 30px #0008;margin:18px}
.bar{background:#2b2f3a;color:#c9d1d9;padding:9px 14px;font:13px "Segoe UI",sans-serif;display:flex;align-items:center;gap:8px}
.dot{width:12px;height:12px;border-radius:50%;display:inline-block}
.title{padding:10px 18px;background:#1a2230;color:#8fb8ff;font:600 14px "Segoe UI","Microsoft JhengHei",sans-serif;border-bottom:1px solid #2b3445}
pre{margin:0;padding:14px 18px 18px;color:#d6deeb;font-size:13.5px;line-height:1.5;white-space:pre-wrap;word-break:break-all}
.cmd{color:#e6edf3;font-weight:600}.prompt{color:#7ee787}.ok{color:#7ee787}.bad{color:#ff7b72}
</style><div class="win"><div class="bar"><span class="dot" style="background:#ff5f56"></span><span class="dot" style="background:#ffbd2e"></span><span class="dot" style="background:#27c93f"></span><span style="margin-left:10px">${esc(who)} — demo terminal</span></div>
<div class="title">${esc(title)}</div><pre>${lines.map(colorize).join('\n')}</pre></div>`;

const chapters = fs.readdirSync(root).filter(d => /^ch\d+/.test(d) && (!only.length || only.includes(d)));
const browser = await launchChromium();
const page = await (await browser.newContext({ viewport: { width: 1230, height: 400 }, deviceScaleFactor: 1.5 })).newPage();
let n = 0;
for (const ch of chapters) {
  const dir = path.join(root, ch);
  for (const f of fs.readdirSync(dir).filter(f => f.endsWith('.log'))) {
    const raw = fs.readFileSync(path.join(dir, f), 'utf8').replace(/\r/g, '').split('\n');
    const title = (raw[0] || '').replace(/^# /, '');
    const cmd = raw.find(l => l.startsWith('$ ')) || '';
    const who = (cmd.match(/(?:plain-|-u |[ /_-])(gary|yujie|ming|svc-orders)(?=[^a-z]|$)/) || [0, 'operator'])[1];
    const lines = raw.slice(1);
    while (lines.length && !lines[lines.length - 1].trim()) lines.pop();
    await page.setContent(html(title, who + '@demo', lines));
    const el = await page.$('.win');
    await el.screenshot({ path: path.join(dir, f.replace(/\.log$/, '.png')) });
    n++;
  }
}
await browser.close();
console.log(`rendered ${n} terminal screenshots`);
