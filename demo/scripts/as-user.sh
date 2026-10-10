#!/usr/bin/env bash
# ============================================================================
# as-user.sh — 以某個人的家目錄身分執行維運腳本
# ----------------------------------------------------------------------------
# 白話:模擬各個維運人員登入跳板機後,各自擁有不同的 ~/.kafka/client.properties(不同帳密、不同權限)。
#   這支腳本開一個臨時容器,把該人的家目錄掛進去,再執行 scripts/ops/ 底下指定的維運腳本。
# 用法:
#   scripts/as-user.sh <user|shared> <ops 腳本檔名> [args...]
#   <user|shared> 對應 config/home/<名稱>/.kafka;<ops 腳本檔名> 是 scripts/ops/ 下的檔名,[args...] 原樣傳給它。
# 會改動什麼:什麼都不改(只啟動 --rm 的臨時容器);ops 腳本本身做什麼,看該腳本的標頭。
# 怎麼判斷成功:結束碼等於被執行的 ops 腳本的結束碼(exec 取代本行程)。
# ============================================================================
export MSYS_NO_PATHCONV=1
D="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
u="$1"; s="$2"; shift 2
exec docker run --rm -i --network cpsec_default -e DEMO_USER="$u" -e KAFKA_HEAP_OPTS="-Xmx256m" \
  -v "$D/certs:/etc/kafka/secrets:ro" -v "$D/scripts/ops:/ops:ro" -v "$D/config/home/$u/.kafka:/home/appuser/.kafka:ro" \
  --entrypoint bash confluentinc/cp-server:8.3.2 "/ops/$s" "$@"
