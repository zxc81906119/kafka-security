#!/usr/bin/env bash
# ============================================================================
# c3-admin-proof.sh — 證明 C3 的服務身分擁有管理員權限
# ----------------------------------------------------------------------------
# 白話:C3 用 client 憑證(CN=c3)向 MDS 換到的 token 代表它自己的服務身分。這支腳本用該 token
#   嘗試建立、再刪除一筆 role binding,能做到就證明它有管理員權限。測試用,做完即清除。
# 前置條件:demo 環境已啟動,且已執行 scripts/bootstrap-rbac.sh(User:c3 有 SystemAdmin)
# 用法:
#   scripts/c3-admin-proof.sh      不需參數
# 會改動什麼:對 User:probe-user 暫時綁 DeveloperRead(Topic「probe-」前綴),隨即刪除,做完已還原。
# 怎麼判斷成功:最後一行「用 c3 的 token 建立 role binding → [HTTP 碼] ;清除 → [HTTP 碼]」,兩個碼都應是 2xx。
# 常見失敗:印「(取得 token 失敗)」→ 憑證 client-c3 不存在或 MDS 不接受
# ============================================================================
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
T=$(./scripts/mds-token.sh c3) || exit 1
BODY='{"scope":{"clusters":{"kafka-cluster":"XyZBQ3-GTvKH2qNfP7X33A"}},"resourcePatterns":[{"resourceType":"Topic","name":"probe-","patternType":"PREFIXED"}]}'
URL="https://broker1:8091/security/1.0/principals/User%3Aprobe-user/roles/DeveloperRead/bindings"
H=(-H "Authorization: Bearer $T" -H "Content-Type: application/json" -H "Accept: application/json")
A=$(./scripts/dcurl.sh -X POST "${H[@]}" "$URL" -d "$BODY" | tail -1)
B=$(./scripts/dcurl.sh -X DELETE "${H[@]}" "$URL" -d "$BODY" | tail -1)
echo "用 c3 的 token 建立 role binding → $A ;清除 → $B"
