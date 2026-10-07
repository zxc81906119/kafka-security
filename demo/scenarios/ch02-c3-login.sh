#!/usr/bin/env bash
# 第 2 章:人用 AD 帳號登入 C3 —— gary / yujie / ming 看到的內容不同(截圖證據由 Playwright 產生)
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch02 "人用 AD 帳號登入 Control Center"
./scripts/reset.sh >/dev/null 2>&1   # 回到「還沒有任何授權」的起點
step c3-login "三位 AD 使用者各自登入 C3(瀏覽器),截圖比對:gary(組長)看得到全部、yujie/ming 尚無資源權限" \
  "(瀏覽器)https://localhost:9022  → 帳號/密碼 = AD 帳號" \
  '(cd "$DEMO_ROOT/e2e" && node ch02.mjs 2>&1 | grep "📸" )' 'ming-5-my-roles'
ch_end
