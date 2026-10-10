#!/usr/bin/env bash
# ============================================================================
# ch13-c3-inventory.sh — 第 13 章:Control Center(C3)身分盤點:人與機器各走哪條路
# ----------------------------------------------------------------------------
# 白話:盤點 C3 周邊每一種呼叫用什麼身分、什麼認證方式:瀏覽器登入的人、C3 自己、自動化(CI)、Prometheus、Alertmanager。
#   重點是人的操作在 MDS 與 audit log 裡是本人(ming、gary),不是 c3;而 c3 的憑證換到的 token 是管理員,要小心保管。
# 前置條件:環境已建好(C3 走 HTTPS、Prometheus、Alertmanager 已啟用);用瀏覽器自動化(e2e/probe-c3-api.mjs)模擬登入
# 用法:
#   ./demo.sh 13                  經由講解控制台跑這一章
#   ./scenarios/ch13-c3-inventory.sh      直接跑(DEMO_PAUSE=0 不暫停)
# 會改動什麼:以唯讀檢查為主。c3-admin 那步對 User:probe-user 建立再刪除 DeveloperRead 的 role binding(c3-admin-proof.sh);alertmanager 那步建立再清除一個靜音(alertmanager-probe.sh)。
# 怎麼判斷成功:每一步印『✔ 符合預期』,最後一行『第 13 章完成(失敗 0 項)』
# 實測結果摘要:人:第一個呼叫帶 Basic(AD 帳密,經 C3 轉給 MDS 換 token),之後全是 Bearer;MDS 日誌的呼叫主體是登入者本人;audit log 中來自 C3 的使用者操作主體是使用者,c3 自己的背景操作不在預設 audit 範圍
#   機器:C3 用 client 憑證(CN=c3)換 token,sub = c3;此 token 就是管理員,能建立/刪除 role binding(官方要求 C3 主體必須是 SystemAdmin)
#   自動化用憑證換 token 後帶 Bearer 得 200,沒 token 401
#   Prometheus、Alertmanager:HTTPS + Basic,不帶帳密 401;沒保護的 Alertmanager 攻擊者能靜音告警(詳見第 17 章)
# ============================================================================
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch13 "Control Center 身分盤點:人與機器各走哪條路"
DC="$DEMO_ROOT/scripts/dcurl.sh"
E2E() { (cd "$DEMO_ROOT/e2e" && node "$@" 2>&1 | grep -v '^$'); }

# ---------------- 人 ----------------
step browser "【人 ①】gary 用瀏覽器登入 C3:第一個呼叫帶 Basic(AD 帳密,經 C3 轉給 MDS 換 token),之後全部是 Bearer token" \
  "(瀏覽器開發者工具)Network → Authorization 標頭型態" \
  'E2E probe-c3-api.mjs gary' 'security/1.0/authenticate +\[Basic\]'

step mds-as-user "【人 ②】ming 開 C3 後,MDS 日誌裡的呼叫主體是「ming 本人」(authenticate / visibility / authorize),不是 c3" \
  "docker logs broker | grep \"User Principal: MING\"" \
  'E2E probe-c3-api.mjs ming >/dev/null; sleep 2; bash "$DEMO_ROOT/scripts/mds-calls-by.sh" MING 60' 'MING +(GET|POST|PUT) +/security/1.0/(lookup|authorize|authenticate)'

step audit-source "【人 ③】broker 的 audit log:來自 C3 的使用者操作,主體是登入的使用者(ming、gary),不是 User:c3(c3 自己的背景操作不在預設 audit 範圍)" \
  "kafka-console-consumer --topic confluent-audit-log-events | 依來源 IP 彙總" \
  'C3IP=$(docker inspect control-center --format "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}"); RPIP=$(docker inspect restproxy --format "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}"); K kafka-console-consumer --bootstrap-server $BOOT --command-config /clients/token-bootstrap.properties --topic confluent-audit-log-events --from-beginning --timeout-ms 12000 2>/dev/null | node "$DEMO_ROOT_W/scripts/audit-by-source.mjs" $C3IP $RPIP' 'C3 +| User:(MING|GARY)| User:(ming|gary)'

# ---------------- 機器 ----------------
step c3-token "【機器 ①】C3 自己的服務身分:用 client 憑證(CN=c3)向 MDS 換 token,sub = c3(C3 背景串流、內部 topic 都用這個)" \
  "GET /security/1.0/authenticate  (憑證 CN=c3)  → token claims" \
  'bash "$DEMO_ROOT/scripts/mds-token.sh" c3 claims' '"sub":"c3"'

step c3-admin "【機器 ①-風險】c3 的憑證換到的 token 就是管理員:可以建立、刪除 role binding(官方要求 C3 主體必須是 SystemAdmin)" \
  "POST / DELETE /security/1.0/principals/User:probe-user/roles/DeveloperRead/bindings   (Bearer c3 token)" \
  'bash "$DEMO_ROOT/scripts/c3-admin-proof.sh"' 'binding → \[HTTP 204\] ;清除 → \[HTTP 204\]'

step automation "【機器 ②】自動化(例如 CI)呼叫 C3 API:用憑證向 MDS 換 token 後帶 Bearer → 200;沒有 token → 401" \
  "curl -H \"Authorization: Bearer <憑證換來的 token>\" https://control-center:9022/2.0/clusters/kafka" \
  'bash "$DEMO_ROOT/scripts/c3-api-check.sh" legacy-orders' '\[HTTP 200\] ;沒有 token → \[HTTP 401\]'

step prometheus "【機器 ③】Prometheus:HTTPS + Basic(C3 與 broker 用 c3 帳密);不帶帳密讀不到指標(401),帶帳密才行(詳見第 17 章)" \
  "curl https://prometheus:9090/api/v1/query?query=count(up)    # 對照:不帶帳密 / 帶 Basic 帳密" \
  'echo "不帶帳密 $(bash "$DC" "https://prometheus:9090/api/v1/query?query=count(up)" | tail -1);帶帳密 $(bash "$DC" -u c3:prom-pw "https://prometheus:9090/api/v1/query?query=count(up)" | tail -1)"' '不帶帳密 \[HTTP 401\];帶帳密 \[HTTP 200\]'

step alertmanager "【機器 ④】Alertmanager:HTTPS + Basic;不帶帳密連「建立靜音」都被擋(401),帶帳密才行(沒保護的 Alertmanager,攻擊者能靜音告警)" \
  "curl -X POST https://alertmanager:9093/api/v2/silences ...   # 對照:不帶憑證 / 帶 Basic 帳密" \
  'bash "$DEMO_ROOT/scripts/alertmanager-probe.sh"' '不帶憑證建立靜音 → \[HTTP 401\] ;帶 Basic 帳密建立 → \[HTTP 200\] ;清除 → \[HTTP 200\]'

ch_end
