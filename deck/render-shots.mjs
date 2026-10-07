// 方案簡報 Live Demo 用:把 evidence 的 log 渲染成窄版終端截圖(字級放大,投影片上可讀)
import { chromium } from '../demo/e2e/node_modules/playwright/index.mjs';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const here = path.dirname(fileURLToPath(import.meta.url));
const ev = path.join(here, '..', 'demo', 'evidence');
const SHOTS = ['ch01/04-valid-no-perm', 'ch03/05-ming-denied', 'ch04/05-ming-write', 'ch07/05-svc-denied', 'ch11/07-ops-noread', 'ch12/04-ok', 'ch13/02-mds-as-user', 'ch14/04-ming-topics'];
const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const colorize = l => { const e = esc(l);
  if (l.startsWith('$ ')) return `<span class="cmd"><span class="p">$</span> ${e.slice(2)}</span>`;
  if (/(Authorization failed|Not authorized|TopicAuthorization|TOPIC_AUTHORIZATION|HTTP 40[0-9]|HTTP 000|ERROR|被拒)/.test(l)) return `<span class="bad">${e}</span>`;
  if (/(HTTP 200|offset|成功|ming POST|ming PUT|ming GET)/.test(l)) return `<span class="ok">${e}</span>`;
  return e; };
const browser = await chromium.launch();
const page = await (await browser.newContext({ viewport: { width: 760, height: 300 }, deviceScaleFactor: 2 })).newPage();
for (const s of SHOTS) {
  const raw = fs.readFileSync(path.join(ev, s + '.log'), 'utf8').replace(/\r/g, '').split('\n');
  const lines = raw.slice(1).filter((l, i, a) => l.trim() || i < a.length - 1); while (lines.length && !lines[lines.length - 1].trim()) lines.pop();
  await page.setContent(`<!doctype html><meta charset="utf-8"><style>body{margin:0;background:#fff;font-family:Consolas,"Courier New",monospace}
.win{width:740px;border-radius:8px;overflow:hidden;margin:10px;background:#0f1117}
.bar{background:#2b2f3a;padding:8px 12px;display:flex;gap:7px}.d{width:11px;height:11px;border-radius:50%}
pre{margin:0;padding:14px 16px;color:#d6deeb;font-size:14.5px;line-height:1.5;white-space:pre-wrap;word-break:break-all}
.cmd{color:#fff;font-weight:700}.p,.ok{color:#7ee787}.bad{color:#ff7b72}</style>
<div class="win"><div class="bar"><span class="d" style="background:#ff5f56"></span><span class="d" style="background:#ffbd2e"></span><span class="d" style="background:#27c93f"></span></div><pre>${lines.map(colorize).join('\n')}</pre></div>`);
  await (await page.$('.win')).screenshot({ path: path.join(here, 'demo-shots', s.replace('/', '-') + '.png') });
}
await browser.close(); console.log('ok');
