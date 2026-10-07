import { launch, C3 } from './lib.mjs';
const { browser, page } = await launch();
const errs = [];
page.on('console', m => { if (m.type() === 'error') errs.push('console: ' + m.text().slice(0, 200)); });
page.on('requestfailed', r => errs.push('failed: ' + r.url() + ' ' + r.failure()?.errorText));
page.on('response', r => { if (r.status() >= 400) errs.push(r.status() + ' ' + r.url()); });
for (const wait of [1500, 5000, 10000]) {
  await page.goto(`${C3}/login`); await page.waitForTimeout(wait);
  const n = await page.locator('input[type=password]').count();
  console.log(`wait ${wait}ms → password inputs: ${n}, body chars: ${(await page.innerText('body')).length}`);
}
console.log(errs.slice(0, 12).join('\n'));
await browser.close();
