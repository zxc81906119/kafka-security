// 探索:C3 畫面上「告警 / 靜音」相關頁面與 API
import { launch, c3Login, C3, CLUSTER } from './lib.mjs';
import fs from 'node:fs';
const out = '../spike/c3-monitoring-tls/evidence';
fs.mkdirSync(out, { recursive: true });
const { browser, page } = await launch('gary');
const reqs = [];
page.on('request', r => { const u = r.url(); if (/alert|silence|trigger|alertmanager/i.test(u)) reqs.push(r.method() + ' ' + u.replace(C3, '')); });
try {
  await c3Login(page, 'gary');
  // 右上角鈴鐺
  const bell = page.locator('button[aria-label*="lert" i], [data-testid*="alert" i], header button').nth(1);
  console.log('鈴鐺候選數:', await page.locator('header button, header a').count());
  for (const p of ['/home/alerts', '/alerts', `/clusters/${CLUSTER}/alerts`, '/home/clusters']) {
    await page.goto(C3 + p); await page.waitForTimeout(4000);
    const t = (await page.innerText('body')).replace(/\s+/g, ' ').slice(0, 220);
    console.log(p, '→', page.url().replace(C3, ''), '|', t);
  }
  // 試著點鈴鐺
  await page.goto(C3 + '/home/clusters'); await page.waitForTimeout(3000);
  const items = await page.locator('header >> role=button, header >> role=link').allInnerTexts().catch(() => []);
  console.log('header 項目:', JSON.stringify(items));
  const svgs = await page.locator('header svg').count();
  console.log('header svg 數:', svgs);
  await page.screenshot({ path: out + '/probe-home.png' });
} finally {
  console.log('--- 與告警相關的請求 ---');
  console.log([...new Set(reqs)].join('\n') || '(無)');
  await browser.close();
}
