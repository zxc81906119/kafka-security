// 點「Add an action」看表單
import { launch, c3Login, C3 } from './lib.mjs';
const out = '../spike/c3-monitoring-tls/evidence';
const { browser, page } = await launch('gary');
try {
  await c3Login(page, 'gary');
  await page.goto(C3 + '/alerts/overview/actions'); await page.waitForTimeout(3500);
  await page.getByRole('link', { name: 'Add an action' }).first().click().catch(async () => { await page.getByRole('button', { name: 'Add an action' }).click(); });
  await page.waitForTimeout(3000);
  console.log('URL:', page.url().replace(C3, ''));
  console.log('輸入欄位:', JSON.stringify(await page.$$eval('input,select,textarea', els => els.map(e => ({ t: e.tagName, type: e.type, name: e.name || e.id || e.getAttribute('aria-label') || e.placeholder })))));
  console.log('按鈕:', JSON.stringify(await page.getByRole('button').allInnerTexts()));
  console.log('內文:', (await page.innerText('body')).replace(/\s+/g, ' ').slice(0, 700));
  await page.screenshot({ path: out + '/probe-add-action.png' });
} finally { await browser.close(); }
