// 探測:瀏覽器登入 C3 後,前端對 C3 後端發出哪些 API 呼叫、帶什麼認證(Authorization / Cookie)
// 用法: node probe-c3-api.mjs [user]    (只列出請求的方法、路徑與認證型態,不印 token 內容)
import { launch, c3Login, C3, CLUSTER } from './lib.mjs';
const user = process.argv[2] || 'gary';
const { browser, page } = await launch(user);
const seen = new Map();
page.on('request', req => {
  const u = new URL(req.url());
  if (!u.pathname.startsWith('/2.0') && !u.pathname.startsWith('/api') && !u.pathname.startsWith('/gateway')) return;
  const h = req.headers();
  const auth = h['authorization'] ? h['authorization'].split(' ')[0] : (h['cookie'] ? 'Cookie' : '-');
  const key = `${req.method()} ${u.pathname.replace(/[A-Za-z0-9_-]{22}/g, '<id>')}  [${auth}]`;
  seen.set(key, (seen.get(key) || 0) + 1);
});
try {
  await c3Login(page, user);
  await page.goto(`${C3}/clusters/${CLUSTER}/management/topics`); await page.waitForTimeout(6000);
  console.log(`以 ${user} 登入並開啟 Topics 頁面時,瀏覽器 → C3 的 API 呼叫:`);
  [...seen].slice(0, 14).forEach(([k, n]) => console.log(`  ${n}x ${k}`));
} finally { await browser.close(); }
