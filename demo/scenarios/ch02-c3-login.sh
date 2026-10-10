#!/usr/bin/env bash
# ============================================================================
# ch02-c3-login.sh — 第 2 章:人用 AD 帳號登入 C3 —— gary / yujie / ming 看到的內容不同(截圖證據由 Playwright 產生)
# ----------------------------------------------------------------------------
# 白話:示範真人用自己的 AD 帳號登入 Control Center(C3)網頁。三個人登入的是同一個畫面,
#       但因為授權不同,gary(組長)看得到全部,yujie / ming 目前還沒有資源權限。
# 前置條件:環境已建好(C3 在 https://localhost:9022)、e2e/ 底下的 Playwright(node)可用;腳本一開始會跑 scripts/reset.sh
# 用法:
#   ./demo.sh 2                     經由講解控制台跑這一章
#   ./scenarios/ch02-c3-login.sh    直接跑(DEMO_PAUSE=0 不暫停)
# 會改動什麼:跑 reset.sh(AD 群組、RBAC、服務帳號還原到第 0 章狀態);之後只是瀏覽器登入與截圖(e2e/ch02.mjs),不改授權
# 怎麼判斷成功:每一步印『✔ 符合預期』(輸出含截圖檔名 ming-5-my-roles),最後一行『第 02 章完成(失敗 0 項)』
# 實測結果摘要:
#   本章是瀏覽器操作:由 Playwright 以 gary / yujie / ming 各自登入 C3 並截圖,供人工比對;腳本只檢查最後一張截圖(ming-5-my-roles)有產生
#   登入帳號/密碼就是 AD 帳號
# ============================================================================
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch02 "人用 AD 帳號登入 Control Center"
./scripts/reset.sh >/dev/null 2>&1   # 回到「還沒有任何授權」的起點
step c3-login "三位 AD 使用者各自登入 C3(瀏覽器),截圖比對:gary(組長)看得到全部、yujie/ming 尚無資源權限" \
  "(瀏覽器)https://localhost:9022  → 帳號/密碼 = AD 帳號" \
  '(cd "$DEMO_ROOT/e2e" && node ch02.mjs 2>&1 | grep "📸" )' 'ming-5-my-roles'
ch_end
