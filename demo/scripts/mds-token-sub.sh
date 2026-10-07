#!/usr/bin/env bash
# 以 client 憑證(mTLS)向 MDS 要 token,回傳 token 裡的主體(sub = Kafka 看到的 principal)。
# 用法: scripts/mds-token-sub.sh <憑證檔前綴(certs/ 下,不含 .pem/.key)>
export MSYS_NO_PATHCONV=1
D="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
n="$1"
tok=$(docker run --rm --network cpsec_default -v "$D/certs:/certs:ro" --entrypoint curl curlimages/curl:latest -s \
  --cacert /certs/ca.pem --cert "/certs/$n.pem" --key "/certs/$n.key" -H 'Accept: application/json' https://broker1:8091/security/1.0/authenticate \
  | grep -o '"auth_token":"[^"]*"' | cut -d'"' -f4)
[ -z "$tok" ] && { echo "(無 token:憑證未被接受)"; exit 1; }
echo "$tok" | cut -d. -f2 | tr '_-' '/+' | awk '{ while (length($0) % 4) $0 = $0 "="; print }' | base64 -d 2>/dev/null | grep -o '"sub":"[^"]*"' | sed 's/"sub":/MDS 看到的 principal = /'
