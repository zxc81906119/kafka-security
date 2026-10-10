#!/usr/bin/env bash
# ============================================================================
# c3-api-check.sh — 機器(自動化)用 client 憑證呼叫 C3 API
# ----------------------------------------------------------------------------
# 白話:自動化程式不能走登入畫面。這支腳本示範機器的做法:用 client 憑證向 MDS 換 token,
#   再帶 Bearer 呼叫 C3 API;對照不帶 token。
# 前置條件:demo 環境已啟動(scripts/up.sh),certs/ 內有 client-<憑證名稱> 憑證
# 用法:
#   scripts/c3-api-check.sh [憑證名稱]      預設 legacy-orders
# 會改動什麼:什麼都不改(只查詢)。
# 怎麼判斷成功:最後一行「帶 token(<憑證>)→ [HTTP 碼] ;沒有 token → [HTTP 碼]」,
#   帶 token 應成功(2xx)、沒有 token 應被拒絕。
# 常見失敗:印「(取得 token 失敗)」→ 該憑證不存在或 MDS 不接受
# ============================================================================
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
cert="${1:-legacy-orders}"
T=$(./scripts/mds-token.sh "$cert") || exit 1
A=$(./scripts/dcurl.sh -H "Authorization: Bearer $T" https://control-center:9022/2.0/clusters/kafka | tail -1)
B=$(./scripts/dcurl.sh https://control-center:9022/2.0/clusters/kafka | tail -1)
echo "帶 token($cert)→ $A ;沒有 token → $B"
