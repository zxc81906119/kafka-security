// 探索 C3 Actions 頁:有哪些按鈕、新增 action 的表單與 API
import { launch, c3Login, C3 } from './lib.mjs';
import fs from 'node:fs';
const out = '../spike/c3-monitoring-tls/evidence';
fs.mkdirSync(out, { recursive: true });
const { browser, page } = await launch('gary');
const reqs = [];
page.on('request', r => { const u = r.url(); if (/\/3\.0\/alerts|alertmanager/i.test(u) && r.method() !== 'GET') reqs.push(r.method() + ' ' + u.replace(C3, '') + ' :: ' + (r.postData() || '').slice(0, 400)); });
try {
  await c3Login(page, 'gary');
  await page.goto(C3 + '/alerts/overview/actions'); await page.waitForTimeout(4000);
  console.log('URL:', page.url().replace(C3, ''));
  console.log('可見按鈕:', JSON.stringify(await page.getByRole('button').allInnerTexts()));
  console.log('可見連結:', JSON.stringify((await page.getByRole('link').allInnerTexts()).slice(0, 25)));
  await page.screenshot({ path: out + '/probe-actions.png' });
  console.log('內文:', (await page.innerText('body')).replace(/\s+/g, ' ').slice(0, 500));
} finally {
  console.log('--- 非 GET 請求 ---'); console.log(reqs.join('\n') || '(無)');
  await browser.close();
}
