#!/usr/bin/env bash
# ============================================================================
# check.sh — 檢查腳本有沒有語法錯誤(改完腳本先跑這個)
# ----------------------------------------------------------------------------
# 白話:對 scripts/、scenarios/ 底下的 .sh 逐一做語法檢查(bash -n),再用 shellcheck(常見錯誤掃描,
#   透過官方映像 koalaman/shellcheck 執行)掃新風格的檔案。語法錯誤曾讓一支腳本整個跑不起來,這一步能提早抓到。
# 用法:
#   scripts/check.sh            全部檢查
#   scripts/check.sh --no-lint  只做語法檢查(不跑 shellcheck)
# 會改動什麼:什麼都不改(只讀檔案;shellcheck 第一次會拉映像)。
# 怎麼判斷成功:最後一行印「判定:…」,有錯誤時結束碼為 1。
# 常見失敗:syntax error → 通常是引號沒成對,或 $(...) 裡有沒加引號的括號(例如 echo 沒有變(沒重啟))。
# ============================================================================
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR" || exit 1

say "逐一檢查 scripts/ 與 scenarios/ 底下 .sh 的語法(bash -n)"
bad=0; n=0
for f in scripts/*.sh scripts/lib/*.sh scenarios/*.sh opmenu/lib/*.sh opmenu/lib/*/*.sh; do
  [ -f "$f" ] || continue
  n=$((n + 1))
  err=$(bash -n "$f" 2>&1) || { note "語法錯誤:$f"; echo "$err" | head -3 | sed 's/^/      /'; bad=1; }
done
note "已檢查 $n 個檔案"

if [ "${1:-}" != "--no-lint" ]; then
  # 新風格的檔案(有 lib/ 與標頭樣板)用 shellcheck 掃;舊腳本寫法較舊,先不掃,避免產生一堆不相干的警告
  NEW="scripts/lib/common.sh scripts/lib/prom.sh scripts/lib/kafka.sh scripts/check.sh"
  say "用 shellcheck 掃新風格的檔案:$NEW"
  if command -v docker >/dev/null 2>&1; then
    out=$(docker run --rm -v "$DEMO_DIR:/mnt" -w /mnt koalaman/shellcheck:stable -S warning -x $NEW 2>&1) || { echo "$out" | head -30; bad=1; }
  else
    note "沒有 docker,略過 shellcheck"
  fi
fi

if [ "$bad" = 0 ]; then verdict "語法與常見錯誤檢查通過"; else verdict "發現問題(上面列出的檔案)"; exit 1; fi
