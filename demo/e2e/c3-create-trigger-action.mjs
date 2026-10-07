// 在 C3 畫面建立 trigger 與 action,觀察 C3 → Alertmanager(TLS + Basic)是否成功
// 用法:node c3-create-trigger-action.mjs <標籤>
import { launch, c3Login, C3 } from './lib.mjs';
import fs from 'node:fs';
const tag = process.argv[2] || 'run';
const out = '../spike/c3-monitoring-tls/evidence';
fs.mkdirSync(out, { recursive: true });
const { browser, page } = await launch('gary');
const calls = [];
page.on('response', async r => {
  const q = r.request();
  if (q.method() !== 'GET' && /\/3\.0\/alerts/.test(q.url())) calls.push(`${q.method()} ${q.url().replace(C3, '')} → ${r.status()} ${(await r.text().catch(() => '')).slice(0, 200)}`);
});
async function selectFirst(loc) {
  await loc.click(); await page.waitForTimeout(500);
  await page.keyboard.press('Enter'); await page.waitForTimeout(700);
}
try {
  await c3Login(page, 'gary');
  console.log('== 建立 trigger');
  await page.goto(C3 + '/alerts/overview/triggers/new'); await page.waitForTimeout(3500);
  await page.fill('input[name=TRIGGER_NAME]', `demo-trigger-${tag}`);
  const combos = page.locator('input[role=combobox]');
  await selectFirst(combos.nth(0));          // Component type(第一項 = Broker)
  for (let i = 0; i < 3; i++) {              // 其餘下拉:依序選第一項(metric、condition 等)
    const n = await combos.count();
    if (i + 1 >= n) break;
    await selectFirst(combos.nth(i + 1));
  }
  await page.fill('input[name=VALUE]', '0').catch(() => {});
  await page.fill('input[name=BUFFER]', '60').catch(() => {});
  await page.screenshot({ path: `${out}/trigger-form-${tag}.png` });
  await page.getByRole('button', { name: 'Save' }).click();
  await page.waitForTimeout(5000);
  console.log('  之後:', page.url().replace(C3, ''));

  console.log('== 建立 action(Send email)');
  await page.goto(C3 + '/alerts/overview/actions/new'); await page.waitForTimeout(3500);
  await page.fill('input[name=ACTION_NAME]', `demo-action-${tag}`);
  const c2 = page.locator('input[role=combobox]');
  await selectFirst(c2.first());             // Triggers(選剛建的第一個)
  await page.keyboard.press('Escape');
  await page.fill('input[name=SUBJECT]', `demo-subject-${tag}`).catch(() => {});
  await page.fill('input[name=EMAIL]', 'ops@example.test').catch(() => {});
  await page.screenshot({ path: `${out}/action-form-${tag}.png` });
  await page.getByRole('button', { name: 'Save' }).click();
  await page.waitForTimeout(6000);
  console.log('  之後:', page.url().replace(C3, ''), '|', (await page.innerText('body')).replace(/\s+/g, ' ').slice(0, 220));
} finally {
  console.log('--- 非 GET 的告警 API ---'); console.log(calls.join('\n') || '(無)');
  await browser.close();
}
