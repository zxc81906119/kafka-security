// 探測:瀏覽器端的 token —— (1) 登入呼叫的認證型態與 MDS 回應 (2) 之後帶的 Bearer 是不是同一個 token、是否為 MDS 簽發(用 MDS 公鑰驗章)
// (3) 存在哪裡(localStorage / sessionStorage / cookie / 只在記憶體)。不印 token 本身。
// 用法: node probe-c3-token.mjs [user]
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { launch, c3Login, C3, CLUSTER, root } from './lib.mjs';
const user = process.argv[2] || 'gary';
const { browser, page } = await launch(user);
const calls = [];            // 依序記錄 authenticate 呼叫:認證型態
const bearers = new Map();   // 不同的 Bearer token → 使用次數與出現的路徑
let loginToken = null;
page.on('request', req => {
  const h = req.headers(); const u = new URL(req.url());
  if (/security\/1\.0\/authenticate/.test(u.pathname)) calls.push((h['authorization'] || '-').split(' ')[0]);
  if (h['authorization']?.startsWith('Bearer ')) {
    const t = h['authorization'].slice(7); const e = bearers.get(t) || { n: 0, paths: new Set() };
    e.n++; e.paths.add(u.pathname.replace(/[A-Za-z0-9_-]{22}/g, '<id>').split('/').slice(0, 3).join('/')); bearers.set(t, e);
  }
});
page.on('response', async res => {
  const rq = res.request();
  if (/security\/1\.0\/authenticate/.test(res.url()) && rq.headers()['authorization']?.startsWith('Basic')) { try { loginToken = (await res.json()).auth_token; } catch {} }
});
const b64 = s => Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
const pub = fs.readFileSync(path.join(root, 'certs', 'public.pem'));
try {
  await c3Login(page, user);
  await page.goto(`${C3}/clusters/${CLUSTER}/management/topics`); await page.waitForTimeout(5000);
  console.log('authenticate 呼叫的認證型態(依序):', calls.join(' → '));
  console.log('登入(Basic)那次呼叫,MDS 是否回了 auth_token:', loginToken ? '是' : '否/未攔到');
  console.log(`瀏覽器之後帶過 ${bearers.size} 種不同的 Bearer token:`);
  let i = 0;
  for (const [t, e] of bearers) {
    i++; const parts = t.split('.');
    let line = `  token#${i}:${e.n} 次,段數 ${parts.length}`;
    if (parts.length === 3) {
      const c = JSON.parse(b64(parts[1]).toString());
      const ok = crypto.createVerify('RSA-SHA256').update(`${parts[0]}.${parts[1]}`).verify(pub, b64(parts[2]));
      line += `,iss=${c.iss} sub=${c.sub} 有效 ${c.exp - c.iat} 秒,MDS 公鑰驗章:${ok ? '通過' : '失敗'}`;
    } else line += '(不是三段式 JWT)';
    line += `,與登入回應的 token ${loginToken === t ? '相同' : '不同'}`;
    console.log(line + ` | 用在:${[...e.paths].join(' ')}`);
  }
  const first = [...bearers.keys()][0];
  const where = await page.evaluate(toks => {
    const found = [];
    for (const [name, st] of [['localStorage', localStorage], ['sessionStorage', sessionStorage]])
      for (let k = 0; k < st.length; k++) { const key = st.key(k); const v = st.getItem(key) || ''; if (toks.some(t => v.includes(t.slice(0, 40)))) found.push(`${name}["${key}"]`); }
    if (toks.some(t => document.cookie.includes(t.slice(0, 40)))) found.push('document.cookie');
    return { found, ls: Object.keys(localStorage), ss: Object.keys(sessionStorage) };
  }, [...bearers.keys()]);
  console.log('token 存放位置:', where.found.length ? where.found.join(', ') : '不在 localStorage / sessionStorage / 可讀 cookie(推測只在頁面記憶體)');
  console.log('localStorage keys:', where.ls.join(', ') || '(無)', '| sessionStorage keys:', where.ss.join(', ') || '(無)');
  const ck = await page.context().cookies(); console.log('cookies:', ck.map(c => `${c.name}${c.httpOnly ? '(HttpOnly)' : ''}`).join(', ') || '(無)');
} finally { await browser.close(); }
