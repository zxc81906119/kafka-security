#!/usr/bin/env bash
# ============================================================================
# c3-services-status.sh — 看 C3 到 Prometheus / Alertmanager 的連線狀態
# ----------------------------------------------------------------------------
# 白話:C3 的監控與告警要靠 Prometheus 與 Alertmanager。這支腳本呼叫 C3 自己的 API 查它對這兩個服務的連線狀態;
#   呼叫時帶 client 憑證換來的 token。
# 前置條件:demo 環境已啟動(scripts/up.sh),certs/ 內有 client-<憑證名稱> 憑證
# 用法:
#   scripts/c3-services-status.sh [憑證名稱]      預設 legacy-orders
# 會改動什麼:什麼都不改(只查詢)。
# 怎麼判斷成功:每個服務印一行 "componentName":"…","componentStatus":"…"(狀態值由 C3 回傳)。
# 常見失敗:印「(取得 token 失敗)」→ 該憑證不存在或 MDS 不接受
# ============================================================================
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
T=$(./scripts/mds-token.sh "${1:-legacy-orders}") || exit 1
for s in prometheus alertmanager; do
  ./scripts/dcurl.sh -H "Authorization: Bearer $T" https://control-center:9022/3.0/services/$s/status | tr '\n' ' ' | grep -o '"componentName":"[A-Z_]*","componentStatus":"[A-Z]*"'
done
