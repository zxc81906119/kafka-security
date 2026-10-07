#!/usr/bin/env bash
# 準備瀏覽器自動化(各章的 UI 截圖用):安裝 e2e 的 npm 套件與 Playwright 的 chromium。可重複執行。
# 需要:Node.js 18 以上、能連網。不跑 UI 自動化(只用手動指令)的人可以不做。
set -euo pipefail
cd "$(dirname "$0")/../e2e"
command -v node >/dev/null || { echo "找不到 node:請先安裝 Node.js(建議 24)"; exit 1; }
[ -d node_modules/playwright ] || npm install --no-audit --no-fund
npx playwright install chromium
node -e "import('./browser.mjs').then(async m=>{const b=await m.launchChromium();await b.close();console.log('OK: 瀏覽器自動化可用')})"
