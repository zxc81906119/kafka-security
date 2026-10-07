// 探測:逐一開啟 C3 主要畫面,記錄每個畫面對 C3 後端的 API(路徑前綴、HTTP 狀態),比較 gary(管理員)與 ming(無 role)。
// 目的:判斷哪些畫面的資料是「用登入者身分」查的(ming 會被拒)、哪些是 C3 用自己的身分(ming 也看得到)。
// 用法: node probe-c3-pages.mjs [user]
import { launch, c3Login, C3, CLUSTER } from './lib.mjs';
const user = process.argv[2] || 'gary';
const { browser, page } = await launch(user);
let cur = null; const res = new Map();
page.on('response', r => {
  if (!cur) return;
  const u = new URL(r.url());
  if (!/^\/(2\.0|api)\//.test(u.pathname)) return;
  const p = u.pathname.replace(/[A-Za-z0-9_-]{22}/g, '<id>').split('/').slice(0, 5).join('/');
  const k = `${r.request().method()} ${p}`;
  const e = res.get(cur) || new Map(); const s = e.get(k) || new Set(); s.add(r.status()); e.set(k, s); res.set(cur, e);
});
try {
  await c3Login(page, user);
  await page.goto(`${C3}/clusters/${CLUSTER}`); await page.waitForTimeout(3000);
  const links = await page.$$eval('a[href]', as => [...new Set(as.map(a => a.getAttribute('href')))].filter(h => /\/clusters\/[^/]+\/[a-z-]+/.test(h)));
  const pages = [...new Set(links.map(h => h.split('?')[0]))].slice(0, 14);
  for (const h of pages) {
    cur = h.replace(CLUSTER, '<cluster>');
    await page.goto(h.startsWith('http') ? h : C3 + h); await page.waitForTimeout(4500);
  }
  console.log(`=== ${user}:各畫面的 API 結果(狀態碼)===`);
  for (const [pg, e] of res) {
    console.log(pg);
    for (const [k, s] of e) console.log(`   ${[...s].join('/')}  ${k}`);
  }
} finally { await browser.close(); }
