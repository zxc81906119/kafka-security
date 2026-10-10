#!/usr/bin/env bash
# ============================================================================
# preflight.sh — 開場前自檢:容器、端點、登入、記憶體;可加 --full 跑完所有章節(含 newman)確認「全部符合預期」
# ----------------------------------------------------------------------------
# 白話:示範前先跑一次,確認環境真的可用,避免在客戶面前才發現容器沒起來或登入失敗。
# 前置條件:demo 環境已啟動(scripts/up.sh --with-restproxy --with-c3,並已啟動 Prometheus 與 Alertmanager)。
# 用法:
#   ./preflight.sh           檢查容器是否執行中、MDS/REST Proxy/C3/Prometheus 端點與登入、AD 連線是否走 LDAPS、
#                            LDAP 管理介面、瀏覽器自動化是否可用,並顯示 Docker 可用記憶體(建議 >= 10GB)
#   ./preflight.sh --full    除上述自檢外,先執行 scripts/reset.sh,再實跑第 1~14、17~20 章(結果寫入 evidence/)
# 會改動什麼:基本自檢只查詢;--full 會先重置環境(scripts/reset.sh)再跑各章,各章會改動環境並寫入 evidence/。
# 怎麼判斷成功:每項印「✔」或「✘」,最後「── 結果:通過 N / 失敗 M ──」;結束碼 0 = 全部通過
#   (--full 另印「章節失敗數: N」,N 不為 0 則結束碼 1)。
# 常見失敗:「✘ 瀏覽器自動化可用」→ 缺 Playwright chromium → 執行 scripts/setup-e2e.sh。
# ============================================================================
cd "$(dirname "$0")"
export MSYS_NO_PATHCONV=1
hp() { local v; v=$(sed -n "s/^HOST_PORT_$1=//p" .env 2>/dev/null | tail -1); echo "${v:-$2}"; }   # 主機埠:.env 的 HOST_PORT_* 覆蓋,預設同 docker-compose.yml
MDSP=$(hp MDS 8091); RPP=$(hp RESTPROXY 8086)
ok=0; bad=0
chk() { if eval "$2" >/dev/null 2>&1; then echo "  ✔ $1"; ok=$((ok+1)); else echo "  ✘ $1"; bad=$((bad+1)); fi; }
echo "── 容器 ──"
for c in openldap ldapadmin controller1 broker1 broker2 restproxy control-center prometheus alertmanager; do
  chk "$c 執行中" "[ \"\$(docker inspect -f '{{.State.Running}}' $c)\" = true ]"
done
echo "── 端點與登入 ──"
chk "MDS(8091)"                         "[ \"\$(curl -sk -o /dev/null -w '%{http_code}' https://localhost:$MDSP/security/1.0/features)\" = 200 ]"
chk "AD 帳號 gary 可登入 MDS"            "[ \"\$(curl -sk -o /dev/null -w '%{http_code}' -u gary:gary-pw https://localhost:$MDSP/security/1.0/authenticate)\" = 200 ]"
chk "錯誤密碼被拒(401)"                  "[ \"\$(curl -sk -o /dev/null -w '%{http_code}' -u gary:bad https://localhost:$MDSP/security/1.0/authenticate)\" = 401 ]"
chk "REST Proxy(8086)未帶帳密 401"       "[ \"\$(curl -sk -o /dev/null -w '%{http_code}' https://localhost:$RPP/topics)\" = 401 ]"
chk "C3 登入頁(HTTPS 9022,憑證驗證)"      "[ \"\$(curl -s --ssl-no-revoke --cacert certs/ca.pem -o /dev/null -w '%{http_code}' https://localhost:9022/login)\" = 200 ]"
chk "Prometheus:不帶帳密 401、帶帳密 200"   "[ \"\$(bash scripts/dcurl.sh https://prometheus:9090/-/healthy | tail -1)\" = '[HTTP 401]' ] && [ \"\$(bash scripts/dcurl.sh -u c3:prom-pw https://prometheus:9090/-/healthy | tail -1)\" = '[HTTP 200]' ]"
chk "AD 連線走 LDAPS(broker 沒連到 389)"    "( for b in broker1 broker2; do ip=\$(docker inspect \$b --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'); docker logs openldap 2>&1 | grep ACCEPT | grep \"from IP=\$ip:\" | grep -q 'IP=0.0.0.0:389' && exit 1; done; exit 0 )"
chk "LDAP 管理介面(8081)"                "[ \"\$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/)\" = 200 ]"
chk "瀏覽器自動化可用(Playwright chromium;缺少時會自動下載,或執行 scripts/setup-e2e.sh)" "(cd e2e && node -e \"import('./browser.mjs').then(async m=>{const b=await m.launchChromium();await b.close()})\")"
echo "── 資源 ──"
mem=$(docker info --format '{{.MemTotal}}' 2>/dev/null); echo "  Docker 可用記憶體: $((mem/1024/1024/1024)) GB(建議 ≥ 10GB)"
echo "── 結果:通過 $ok / 失敗 $bad ──"
if [ "$1" = "--full" ]; then
  echo; echo "══ 全章節實跑(結果寫入 evidence/)══"
  ./scripts/reset.sh >/dev/null 2>&1
  fails=0
  for s in scenarios/ch0[12345679]-*.sh scenarios/ch08-*.sh scenarios/ch10-*.sh scenarios/ch11-*.sh scenarios/ch12-*.sh scenarios/ch13-*.sh scenarios/ch14-*.sh scenarios/ch17-*.sh scenarios/ch18-*.sh scenarios/ch19-*.sh scenarios/ch20-*.sh; do
    r=$(EV_SHOW=0 ./"$s" 2>&1 | grep -E "完成\(失敗" | sed 's/\x1b\[[0-9;]*m//g'); echo "  $(basename $s): $r"
    echo "$r" | grep -q "失敗 0 項" || fails=$((fails+1))
  done
  echo "章節失敗數: $fails"; [ "$fails" = 0 ] || exit 1
fi
[ "$bad" = 0 ]
