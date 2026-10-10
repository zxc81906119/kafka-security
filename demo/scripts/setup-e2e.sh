#!/usr/bin/env bash
# ============================================================================
# setup-e2e.sh — 準備瀏覽器自動化(各章的 UI 截圖用):安裝 e2e 的 npm 套件與 Playwright 的 chromium
# ----------------------------------------------------------------------------
# 白話:各章的 UI 截圖由 Playwright 驅動 chromium。這支腳本把需要的套件裝好,可重複執行。
#   不跑 UI 自動化(只用手動指令)的人可以不做。
# 前置條件:Node.js 18 以上(建議 24)、能連網。
# 用法:
#   scripts/setup-e2e.sh
# 會改動什麼:在 demo/e2e 下安裝 npm 套件(node_modules),並下載 Playwright 的 chromium;已裝的會略過。
# 怎麼判斷成功:最後印「OK: 瀏覽器自動化可用」。
# 常見失敗:印「找不到 node」→ 沒裝 Node.js → 先安裝(建議 24)。
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/../e2e"
command -v node >/dev/null || { echo "找不到 node:請先安裝 Node.js(建議 24)"; exit 1; }
[ -d node_modules/playwright ] || npm install --no-audit --no-fund
npx playwright install chromium
node -e "import('./browser.mjs').then(async m=>{const b=await m.launchChromium();await b.close();console.log('OK: 瀏覽器自動化可用')})"
