// 啟動 Playwright chromium;瀏覽器執行檔不存在(新環境、Playwright 升級後)時,自動下載一次再重試,讓每個人 clone 專案後都能直接跑。
import { chromium } from 'playwright';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const here = path.dirname(fileURLToPath(import.meta.url));

export async function launchChromium(opts = {}) {
  try { return await chromium.launch(opts); }
  catch (e) {
    if (!/Executable doesn't exist|playwright install/i.test(String(e.message))) throw e;
    console.error('[e2e] 找不到 Playwright 的 chromium,自動下載(只有第一次需要,約 100~200 MB)…');
    const r = spawnSync('npx', ['playwright', 'install', 'chromium'], { cwd: here, stdio: 'inherit', shell: true });
    if (r.status !== 0) throw new Error('自動下載 chromium 失敗,請手動執行:cd demo/e2e && npm install && npx playwright install chromium(需要能連網)');
    return await chromium.launch(opts);
  }
}
