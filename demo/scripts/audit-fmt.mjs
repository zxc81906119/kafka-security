// 從 stdin 讀 audit log(每行一個 JSON 事件),整理成一行一事件。
// 用法: ... | node audit-fmt.mjs [--method regex] [--topic regex] [--granted true|false] [--summary]
import readline from 'node:readline';
const arg = n => { const i = process.argv.indexOf('--' + n); return i > 0 ? process.argv[i + 1] : null; };
const mRe = new RegExp(arg('method') || '^kafka\.(Produce|Metadata|FetchConsumer|Fetch)$');
const tRe = arg('topic') ? new RegExp(arg('topic')) : null;
const g = arg('granted');
const rows = [];
for await (const line of readline.createInterface({ input: process.stdin })) {
  let e; try { e = JSON.parse(line); } catch { continue; }
  const d = e.data; if (!d || !mRe.test(d.methodName || '')) continue;
  const az = d.authorizationInfo || {};
  const res = az.resourceName || (d.resourceName || '');
  if (tRe && !tRe.test(res)) continue;
  if (g && String(!!az.granted) !== g) continue;
  rows.push({ t: (e.time || '').slice(0, 19).replace('T', ' '), p: d.authenticationInfo?.principal || '?', m: d.methodName, ok: az.granted ? 'ALLOWED' : 'DENIED', op: az.operation || '', r: res });
}
rows.sort((a, b) => a.t.localeCompare(b.t));
if (process.argv.includes('--summary')) {
  const c = new Map(); for (const r of rows) { const k = `${r.p}|${r.m}|${r.ok}|${r.r}`; c.set(k, (c.get(k) || 0) + 1); }
  for (const [k, n] of [...c].sort((a, b) => b[1] - a[1]).slice(0, +(arg('top') || 12))) { const [p, m, ok, r] = k.split('|'); console.log(`${String(n).padStart(4)}×  ${p.padEnd(18)} ${m.padEnd(19)} ${ok.padEnd(8)} ${r}`); }
} else {
  for (const r of rows.slice(-(+(arg('last') || 8)))) console.log(`${r.t.slice(11)}  ${r.p.padEnd(18)} ${r.m.padEnd(19)} ${r.ok.padEnd(8)} ${r.r}`);
}
