// 從 stdin 讀 audit log(每行一個 JSON),統計「來源 IP × 主體 × 動作」,只列出來自 C3 或 REST Proxy 的事件。
// 用法: ... | node audit-by-source.mjs <C3 的 IP> <REST Proxy 的 IP>
import readline from 'node:readline';
const [c3, rp] = process.argv.slice(2);
const m = new Map();
for await (const line of readline.createInterface({ input: process.stdin })) {
  let e; try { e = JSON.parse(line); } catch { continue; }
  const d = e.data || {};
  const ip = (d.clientAddress && d.clientAddress[0] && d.clientAddress[0].ip) || '-';
  const src = ip === c3 ? 'C3' : ip === rp ? 'REST Proxy' : null;
  if (!src) continue;
  const k = `${src.padEnd(10)} | ${(d.authenticationInfo || {}).principal || '?'} | ${d.methodName}`;
  m.set(k, (m.get(k) || 0) + 1);
}
[...m].sort((a, b) => b[1] - a[1]).slice(0, 12).forEach(([k, n]) => console.log(`${String(n).padStart(4)}×  ${k}`));
