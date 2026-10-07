// 把 newman 的 JSON 報告渲染成「Postman Tests 風格」的截圖(每個 request 一張;內容為實際回應碼與斷言結果)
import { launchChromium } from './browser.mjs';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dir = path.join(root, 'evidence', 'ch05');
const run = JSON.parse(fs.readFileSync(path.join(dir, 'newman-run.json'), 'utf8')).run;
const coll = JSON.parse(fs.readFileSync(path.join(root, 'postman', 'demo.postman_collection.json'), 'utf8'));
const desc = {}; (function walk(items){ for (const i of items) { if (i.item) walk(i.item); else desc[i.name] = i.request.description || ''; } })(coll.item);
const esc = s => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const md = s => esc(s).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>');
const statusColor = c => c >= 500 ? '#c0392b' : c >= 400 ? '#d35400' : c >= 200 ? '#1e8e3e' : '#555';

const page_html = (ex) => {
  const r = ex.request, res = ex.response, code = res?.code, asserts = ex.assertions || [];
  const user = (r.auth?.basic?.find(b => b.key === 'username')?.value) || (r.auth?.type === 'bearer' ? 'Bearer token' : '(無)');
  const resolvedUser = { '{{gary_user}}': 'gary', '{{yujie_user}}': 'yujie', '{{ming_user}}': 'ming' }[user] || user;
  const url = (r.url?.protocol ? r.url.protocol + '://' : '') + (r.url?.host || []).join('.') + (r.url?.port ? ':' + r.url.port : '') + '/' + (r.url?.path || []).join('/');
  let body = ''; try { body = new TextDecoder().decode(new Uint8Array(res.stream.data)); try { body = JSON.stringify(JSON.parse(body), null, 2); } catch {} } catch {}
  return `<!doctype html><meta charset="utf-8"><style>
  body{margin:0;background:#f4f5f7;font-family:"Segoe UI","Microsoft JhengHei",sans-serif;color:#222}
  .app{width:1180px;margin:16px;background:#fff;border-radius:8px;box-shadow:0 4px 18px #0002;overflow:hidden}
  .top{background:#ff6c37;color:#fff;padding:10px 18px;font-weight:700;display:flex;justify-content:space-between}
  .url{display:flex;gap:10px;padding:14px 18px;border-bottom:1px solid #e5e7eb;align-items:center}
  .m{background:#eef;border-radius:4px;padding:6px 12px;font-weight:700;color:#0a58ca}.u{flex:1;border:1px solid #d0d5dd;border-radius:4px;padding:7px 12px;font-family:Consolas,monospace}
  .who{background:#fff3e0;border:1px solid #ffb74d;border-radius:4px;padding:6px 10px;font-size:13px}
  .doc{padding:10px 18px;background:#fffbe6;border-bottom:1px solid #eee;font-size:14px}
  .sec{padding:12px 18px}.h{font-weight:700;margin-bottom:6px;display:flex;gap:14px;align-items:center}
  .code{color:#fff;border-radius:4px;padding:2px 10px;font-weight:700;background:${statusColor(code)}}
  pre{background:#0f1117;color:#d6deeb;padding:12px;border-radius:6px;font-size:13px;margin:0;white-space:pre-wrap;word-break:break-all;max-height:230px;overflow:hidden}
  .t{padding:5px 0;font-size:14px}.pass{color:#1e8e3e;font-weight:700}.fail{color:#c0392b;font-weight:700}
  </style><div class="app"><div class="top"><span>Postman(newman 實跑結果)— ${esc(ex.item.name)}</span><span>Collection:Confluent 安全方案 Demo</span></div>
  <div class="url"><span class="m">${esc(r.method)}</span><span class="u">${esc(url)}</span><span class="who">Authorization:Basic — 使用者 <b>${esc(resolvedUser)}</b></span></div>
  <div class="doc">${md(desc[ex.item.name])}</div>
  <div class="sec"><div class="h">Response <span class="code">${code} ${esc(res?.status)}</span><span style="color:#667">${res?.responseTime} ms</span></div><pre>${esc(body).slice(0, 700)}</pre></div>
  <div class="sec"><div class="h">Test Results(${asserts.filter(a => !a.error).length}/${asserts.length} 通過)</div>
   ${asserts.map(a => `<div class="t"><span class="${a.error ? 'fail' : 'pass'}">${a.error ? 'FAIL' : 'PASS'}</span> ${esc(a.assertion)}</div>`).join('')}</div></div>`;
};
const browser = await launchChromium();
const page = await (await browser.newContext({ viewport: { width: 1220, height: 500 }, deviceScaleFactor: 1.5 })).newPage();
let n = 0;
for (const ex of run.executions) {
  await page.setContent(page_html(ex));
  const id = String(ex.item.name).split(' ')[0].replace(/[^0-9A-Za-z.]/g, '');
  await (await page.$('.app')).screenshot({ path: path.join(dir, `postman-${id}.png`) });
  n++;
}
// 總覽
const rows = run.executions.map(ex => { const a = ex.assertions || []; const ok = a.every(x => !x.error); return `<tr><td>${esc(ex.item.name)}</td><td style="color:${statusColor(ex.response?.code)};font-weight:700">${ex.response?.code}</td><td class="${ok ? 'pass' : 'fail'}">${ok ? 'PASS' : 'FAIL'} (${a.filter(x => !x.error).length}/${a.length})</td></tr>`; }).join('');
const st = run.stats;
await page.setContent(`<!doctype html><meta charset="utf-8"><style>body{margin:0;background:#f4f5f7;font-family:"Segoe UI","Microsoft JhengHei",sans-serif}.app{width:1180px;margin:16px;background:#fff;border-radius:8px;box-shadow:0 4px 18px #0002;overflow:hidden}.top{background:#ff6c37;color:#fff;padding:12px 18px;font-weight:700}table{width:100%;border-collapse:collapse}td,th{padding:9px 18px;border-bottom:1px solid #eee;text-align:left;font-size:14px}.pass{color:#1e8e3e;font-weight:700}.fail{color:#c0392b;font-weight:700}.s{padding:12px 18px;font-size:15px}</style><div class="app"><div class="top">Postman Collection Runner(newman)— 總覽</div><div class="s">requests ${st.requests.total}・assertions ${st.assertions.total}・<b class="${st.assertions.failed ? 'fail' : 'pass'}">失敗 ${st.assertions.failed}</b></div><table><tr><th>Request</th><th>HTTP</th><th>Tests</th></tr>${rows}</table></div>`);
await (await page.$('.app')).screenshot({ path: path.join(dir, 'postman-0-summary.png') });
await browser.close();
console.log('rendered', n, '+ summary');
