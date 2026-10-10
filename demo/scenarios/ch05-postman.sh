#!/usr/bin/env bash
# ============================================================================
# ch05-postman.sh — 第 5 章:工具(Postman / REST Proxy)用同一份 AD 身分 —— 以 newman 實跑整份 collection
# ----------------------------------------------------------------------------
# 白話:證明維運常用的工具(Postman、REST Proxy)和網頁、指令列用的是同一份 AD 身分與同一套 RBAC,
#       不需要另一套帳號。腳本用 newman(Postman 的命令列版)跑整份 collection,效果等同現場匯入 Postman。
# 前置條件:Docker 可用、環境已建好(docker network cpsec_default、REST Proxy、MDS 在線);通常接在第 3、4 章之後
# 用法:
#   ./demo.sh 5                      經由講解控制台跑這一章
#   ./scenarios/ch05-postman.sh      直接跑(DEMO_PAUSE=0 不暫停)
# 會改動什麼:
#   以 docker 執行 postman/newman 容器(--rm,用完即刪),結果寫到 evidence/ch05/newman-run.json
#   結束前清理殘留:移除 Group:orders-write 對 payments. 的 DeveloperRead 綁定(若 collection 誤授權會留下)
# 怎麼判斷成功:每一步印『✔ 符合預期』(newman 摘要中 assertions 為 14 項),最後一行『第 05 章完成(失敗 0 項)』
# 實測結果摘要:
#   collection 與環境檔放在 postman/ 底下(demo.postman_collection.json、demo-humans.postman_environment.json)
#   殘留清理的用意:若 M.3 誤授權(身分污染),會留下 payments. 的 binding
# ============================================================================
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
