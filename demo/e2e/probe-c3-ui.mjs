import { launch, c3Login, C3, CLUSTER } from './lib.mjs';
const { browser, page } = await launch('gary');
try {
  await c3Login(page, 'gary');
  await page.goto(`${C3}/clusters/${CLUSTER}/management/topics/orders.events/message-viewer`); await page.waitForTimeout(5000);
  console.log('URL:', page.url());
  const btns = await page.getByRole('button').allInnerTexts();
  console.log('buttons:', [...new Set(btns.map(s => s.trim()).filter(Boolean))].slice(0, 30).join(' | '));
  const tabs = await page.getByRole('tab').allInnerTexts(); console.log('tabs:', tabs.join(' | '));
  const links = await page.getByRole('link').allInnerTexts(); console.log('links:', [...new Set(links.map(s => s.trim()).filter(Boolean))].slice(0, 25).join(' | '));
} finally { await browser.close(); }
