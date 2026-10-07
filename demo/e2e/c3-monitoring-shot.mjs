// 驗證 C3 在「Prometheus / Alertmanager 啟用 TLS + Basic」後,畫面仍看得到指標。
// 用法:node c3-monitoring-shot.mjs <輸出資料夾>
import { launch, c3Login, C3, CLUSTER } from './lib.mjs';
import fs from 'node:fs';

const out = process.argv[2] || '../spike/c3-monitoring-tls/evidence';
fs.mkdirSync(out, { recursive: true });
const { browser, page } = await launch('gary');
try {
  await c3Login(page, 'gary');
  for (const [name, p] of [['overview', ''], ['brokers', '/management/brokers'], ['topics', '/management/topics']]) {
    await page.goto(`${C3}/clusters/${CLUSTER}${p}`);
    await page.waitForTimeout(9000);
    const f = `${out}/${name}.png`;
    await page.screenshot({ path: f });
    const txt = (await page.innerText('body')).replace(/\s+/g, ' ').slice(0, 400);
    console.log(name, '→', f, '|', txt);
  }
} finally {
  await browser.close();
}
