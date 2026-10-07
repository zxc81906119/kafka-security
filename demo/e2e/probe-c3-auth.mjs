// 探測:瀏覽器對 C3 API 的請求「實際帶了哪些認證標頭」(含 Cookie),以及 C3 伺服器實際認哪一個。
// 方法:(1) 用 allHeaders() 看實際送出的標頭 (2) 用 Node 直接對 C3 發請求,分別只帶 Bearer / 只帶 Cookie / 兩者衝突,看回應。
// 不印 token 與 cookie 值。 用法: node probe-c3-auth.mjs
import { launch, c3Login, C3, CLUSTER } from './lib.mjs';
const { browser, page } = await launch('gary');
const seen = new Map(); let lastBearer = null;
page.on('requestfinished', async req => {
  const u = new URL(req.url());
  if (!(u.pathname.startsWith('/2.0') || u.pathname.startsWith('/api'))) return;
  const h = await req.allHeaders();
  const a = h['authorization'] ? h['authorization'].split(' ')[0] : '-', c = h['cookie'] && /auth_token=/.test(h['cookie']) ? 'Cookie(auth_token)' : '-';
  if (h['authorization']?.startsWith('Bearer ')) lastBearer = h['authorization'].slice(7);
  const key = `Authorization:${a.padEnd(6)} Cookie:${c.padEnd(18)} ${u.pathname.replace(/[A-Za-z0-9_-]{22}/g, '<id>').split('/').slice(0, 3).join('/')}`;
  seen.set(key, (seen.get(key) || 0) + 1);
});
try {
  await c3Login(page, 'gary'); await page.goto(`${C3}/clusters/${CLUSTER}/management/topics`); await page.waitForTimeout(5000);
  console.log('瀏覽器實際送出的請求(含 Cookie 標頭),依路徑彙總:');
  [...seen].sort((a, b) => b[1] - a[1]).slice(0, 12).forEach(([k, n]) => console.log(`  ${String(n).padStart(3)}×  ${k}`));
  const ck = (await page.context().cookies()).find(c => c.name === 'auth_token');
  const url = `${C3.replace('localhost', '127.0.0.1')}/2.0/clusters/kafka`;
  const call = async (label, headers) => { const r = await fetch(url, { headers }); console.log(`  ${label.padEnd(44)} → HTTP ${r.status}`); };
  console.log('\n直接對 C3 發請求(GET /2.0/clusters/kafka),看伺服器認哪一個:');
  await call('不帶任何認證', {});
  await call('只帶 Authorization: Bearer(最新 token)', { Authorization: `Bearer ${lastBearer}` });
  await call('只帶 Cookie: auth_token(沒有 Authorization)', { Cookie: `auth_token=${ck.value}` });
  await call('Cookie 有效 + Bearer 是亂碼', { Cookie: `auth_token=${ck.value}`, Authorization: 'Bearer garbage' });
  await call('Bearer 有效 + Cookie 是亂碼', { Authorization: `Bearer ${lastBearer}`, Cookie: 'auth_token=garbage' });
} finally { await browser.close(); }
