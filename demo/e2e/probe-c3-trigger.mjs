// 探索「新增 trigger」表單
import { launch, c3Login, C3 } from './lib.mjs';
const out = '../spike/c3-monitoring-tls/evidence';
const { browser, page } = await launch('gary');
try {
  await c3Login(page, 'gary');
  await page.goto(C3 + '/alerts/overview/triggers/new'); await page.waitForTimeout(4000);
  console.log('URL:', page.url().replace(C3, ''));
  console.log('輸入欄位:', JSON.stringify(await page.$$eval('input,select,textarea', els => els.map(e => ({ t: e.tagName, type: e.type, name: e.name || e.id || e.getAttribute('aria-label') || e.placeholder })))));
  console.log('內文:', (await page.innerText('body')).replace(/\s+/g, ' ').slice(0, 800));
  await page.screenshot({ path: out + '/probe-add-trigger.png' });
} finally { await browser.close(); }
