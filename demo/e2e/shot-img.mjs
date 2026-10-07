// 把 labguide/img-src/*.html 轉成 labguide/img/*.png(1280x720)
import { launchChromium } from './browser.mjs';
import path from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
const here = path.dirname(fileURLToPath(import.meta.url));
const src = path.resolve(here, '..', 'labguide', 'img-src'), out = path.resolve(here, '..', 'labguide', 'img');
const b = await launchChromium(); const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
for (const n of process.argv.slice(2)) {
  await p.goto(pathToFileURL(path.join(src, n + '.html')).href);
  await p.waitForTimeout(400);
  const h = await p.evaluate(() => Math.ceil((document.querySelector('.s') || document.body).getBoundingClientRect().height));   // 依內容高度裁切(Lab 地圖比 720 矮)
  await p.screenshot({ path: path.join(out, n + '.png'), clip: { x: 0, y: 0, width: 1280, height: Math.min(Math.max(h, 200), 720) } });
  console.log('ok', n);
}
await b.close();
