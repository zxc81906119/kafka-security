#!/usr/bin/env bash
# 第 5 章:工具(Postman / REST Proxy)用同一份 AD 身分 —— 以 newman 實跑整份 collection
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch05 "工具怎麼用同樣的身分:Postman / REST Proxy"
D="$(cd "$DEMO_ROOT" && pwd -W 2>/dev/null || pwd)"
step newman "以 newman 執行 Postman collection(與現場 Postman 匯入同一份檔案)" \
  "newman run demo.postman_collection.json -e demo-humans.postman_environment.json" \
  "docker run --rm --network cpsec_default -v '$D/postman:/etc/newman' -v '$D/certs:/certs:ro' -v '$D/evidence/ch05:/out' postman/newman:alpine run /etc/newman/demo.postman_collection.json -e /etc/newman/demo-humans.postman_environment.json --env-var rest_proxy=https://restproxy:8086 --env-var mds=https://broker1:8091 --ssl-extra-ca-certs /certs/ca.pem --reporters cli,json --reporter-json-export /out/newman-run.json --color off 2>&1 | grep -E '^↳|\[[0-9]{3} |✓|[0-9]+\. |requests|assertions' | sed -E 's/^( *)\│? */\1/' " 'assertions +\│? *14 +\│ +0'
EV_SHOW=40 true
( cd "$DEMO_ROOT/e2e" && node render-newman.mjs ) | sed 's/^/    /'
# 殘留清理:若 M.3 誤授權(身分污染)會留下 payments. 的 binding
source "$DEMO_ROOT/scripts/rbac-lib.sh"
rbac_unbind cert bootstrap Group:orders-write DeveloperRead Topic payments. PREFIXED >/dev/null
ch_end
