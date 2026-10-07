// 從 C3 介面(Messages → Produce a new message)送一筆訊息,觀察:C3 對後端發了什麼請求、帶什麼認證、結果,以及 broker audit 的主體。
// 用法: node probe-c3-produce.mjs [user] [topic]   例: node probe-c3-produce.mjs gary orders.events
import { launch, c3Login, C3, CLUSTER, shot } from './lib.mjs';
const user = process.argv[2] || 'gary', topic = process.argv[3] || 'orders.events';
const { browser, page } = await launch(user);
const reqs = [];
page.on('requestfinished', async req => {
  const u = new URL(req.url());
  if (req.method() !== 'POST' || !(u.pathname.startsWith('/api') || u.pathname.startsWith('/2.0'))) return;
  const h = await req.allHeaders(); const res = await req.response();
  reqs.push({ m: req.method(), p: u.pathname.replace(/[A-Za-z0-9_-]{22}/g, '<id>'), auth: (h['authorization'] || '-').split(' ')[0], cookie: /auth_token=/.test(h['cookie'] || '') ? 'yes' : 'no', status: res ? res.status() : '?' });
});
try {
  await c3Login(page, user);
  await page.goto(`${C3}/clusters/${CLUSTER}/management/topics/${topic}/message-viewer`); await page.waitForTimeout(4000);
  await page.getByRole('button', { name: 'Produce a new message' }).first().click(); await page.waitForTimeout(1500);
  reqs.length = 0;
  await page.getByRole('button', { name: 'Produce', exact: true }).click(); await page.waitForTimeout(4000);
  console.log(`以 ${user} 在 C3 對 ${topic} 按下 Produce 後,瀏覽器送出的 POST 請求:`);
  reqs.forEach(r => console.log(`  ${r.m} ${r.p}  [Authorization:${r.auth} Cookie:${r.cookie}] → HTTP ${r.status}`));
  const txt = (await page.locator('body').innerText()).split('\n').filter(l => /success|fail|error|authoriz|denied|produced/i.test(l)).slice(0, 4);
  console.log('畫面訊息:', txt.join(' / ') || '(無明顯訊息)');
} finally { await browser.close(); }
