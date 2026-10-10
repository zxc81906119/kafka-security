#!/usr/bin/env bash
# ============================================================================
# mds-token-sub.sh — 以 client 憑證向 MDS 要 token,印出 token 裡的主體
# ----------------------------------------------------------------------------
# 白話:token 的 sub 欄位就是 Kafka 看到的 principal。用來確認某張憑證最後會被當成誰。
# 前置條件:demo 環境已啟動(scripts/up.sh)
# 用法:
#   scripts/mds-token-sub.sh <憑證檔前綴>      certs/ 下的檔名,不含 .pem/.key(例 client-c3)
# 會改動什麼:什麼都不改(只向 MDS 要 token)。
# 怎麼判斷成功:印「MDS 看到的 principal = <sub>」。
# 常見失敗:印「(無 token:憑證未被接受)」(結束碼 1)→ 憑證不被 MDS 接受(例如非本 CA 簽發)
# ============================================================================
export MSYS_NO_PATHCONV=1
D="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
n="$1"
tok=$(docker run --rm --network cpsec_default -v "$D/certs:/certs:ro" --entrypoint curl curlimages/curl:latest -s \
  --cacert /certs/ca.pem --cert "/certs/$n.pem" --key "/certs/$n.key" -H 'Accept: application/json' https://broker1:8091/security/1.0/authenticate \
  | grep -o '"auth_token":"[^"]*"' | cut -d'"' -f4)
[ -z "$tok" ] && { echo "(無 token:憑證未被接受)"; exit 1; }
echo "$tok" | cut -d. -f2 | tr '_-' '/+' | awk '{ while (length($0) % 4) $0 = $0 "="; print }' | base64 -d 2>/dev/null | grep -o '"sub":"[^"]*"' | sed 's/"sub":/MDS 看到的 principal = /'
