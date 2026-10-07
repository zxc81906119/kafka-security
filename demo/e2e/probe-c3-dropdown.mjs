import { launch, c3Login, C3 } from './lib.mjs';
const { browser, page } = await launch('gary');
try {
  await c3Login(page, 'gary');
  await page.goto(C3 + '/alerts/overview/triggers/new'); await page.waitForTimeout(3500);
  const box = page.locator('input[type=text]').nth(1);
  await box.click(); await page.waitForTimeout(800);
  const html = await page.evaluate(() => {
    const el = document.activeElement; let p = el;
    for (let i = 0; i < 4 && p.parentElement; i++) p = p.parentElement;
    return p.outerHTML.slice(0, 1800);
  });
  console.log(html);
  console.log('---- 頁面上含 Cluster/Broker/Topic 的元素:');
  console.log(JSON.stringify(await page.evaluate(() => [...document.querySelectorAll('li,div,span,button,a')].filter(e => /^(Cluster|Broker|Topic|Consumer group)$/i.test(e.textContent.trim()) && e.children.length === 0).slice(0, 8).map(e => e.tagName + '.' + e.className + '|role=' + e.getAttribute('role')))));
} finally { await browser.close(); }
