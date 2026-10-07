#!/usr/bin/env bash
# 第 17 章(進階):傳輸加密補強 —— AD 連線走 LDAPS、監控元件(Prometheus / Alertmanager)走 HTTPS + Basic、C3 走 HTTPS
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch17 "傳輸加密補強:LDAPS、監控 HTTPS + Basic、C3 HTTPS"
DC="$DEMO_ROOT/scripts/dcurl.sh"

# ---------------- AD(LDAPS) ----------------
step ldaps-from-broker "【AD ①】broker 連 AD 走 LDAPS(636):openldap 日誌裡,來自 broker 的連線全部落在 636,389 沒有 broker 的連線" \
  "docker logs openldap | grep ACCEPT   # 依來源(broker1、broker2)與目的埠彙總" \
  'a=0; b=0; for x in broker1 broker2; do ip=$(docker inspect $x --format "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}"); n6=$(docker logs openldap 2>&1 | grep ACCEPT | grep "from IP=$ip:" | grep -c "IP=0.0.0.0:636"); n3=$(docker logs openldap 2>&1 | grep ACCEPT | grep "from IP=$ip:" | grep -c "IP=0.0.0.0:389"); echo "$x($ip): $n6 條連到 636、$n3 條連到 389"; a=$((a+n6)); b=$((b+n3)); done; [ $a -gt 0 ] && [ $b -eq 0 ] && echo "判定:broker 連 AD 只走 LDAPS(636)" || echo "判定:不符合"' '判定:broker 連 AD 只走 LDAPS'

step ldaps-trust "【AD ②】LDAPS 要信任簽發憑證的 CA:信任 demo CA 才連得上;不信任就失敗(所以連 AD 的 JVM 才需要 ldap.ssl.truststore)" \
  "ldapsearch -H ldaps://openldap:636   # 對照:信任 / 不信任 CA" \
  'ok=$(docker exec -e LDAPTLS_CACERT=/container/service/slapd/assets/certs/ca.crt openldap ldapsearch -x -H ldaps://openldap:636 -D cn=admin,dc=corp,dc=demo -w adminpw -b dc=corp,dc=demo -s base dn 2>&1 | grep -E "^result:|Can.t contact"); ng=$(docker exec -e LDAPTLS_CACERT=/etc/ssl/certs/ca-certificates.crt openldap ldapsearch -x -H ldaps://openldap:636 -D cn=admin,dc=corp,dc=demo -w adminpw -b dc=corp,dc=demo -s base dn 2>&1 | grep -E "^result:|Can.t contact" | head -1); echo "信任 demo CA:   $ok"; echo "不信任 demo CA: $ng"; echo "$ok|$ng" | grep -q "result: 0 Success|.*Can.t contact" && echo "判定:信任 CA 才連得上" || echo "判定:不符合"' '判定:信任 CA 才連得上'

step ldaps-login "【AD ③】人用 AD 帳密登入不受影響(MDS Basic 與 Kafka PLAIN 都經 LDAPS 查 AD):正確 200、錯誤密碼 401、Kafka 列 topic 成功" \
  "curl -u GARY:<密碼> https://broker1:8091/security/1.0/authenticate" \
  'out=$( { echo "--- 正確密碼"; bash "$DC" -o /dev/null -u gary:gary-pw https://broker1:8091/security/1.0/authenticate; echo "--- 錯誤密碼"; bash "$DC" -o /dev/null -u gary:wrong https://broker1:8091/security/1.0/authenticate; echo "--- Kafka PLAIN(gary)列出 topic"; as_list gary | head -5; } 2>&1 ); printf "%s\n" "$out"; printf "%s" "$out" | tr "\n" " " | grep -q "HTTP 200.*HTTP 401.*__consumer_offsets" && echo "判定:LDAPS 下登入正常" || echo "判定:不符合"' '判定:LDAPS 下登入正常'

# ---------------- 監控元件 ----------------
step prom "【監控 ①】Prometheus:HTTPS + Basic。不帶帳密 401、錯誤密碼 401、正確 200;明文 HTTP 被拒(400)" \
  "curl https://prometheus:9090/api/v1/query?query=count(up)   # 對照:無帳密 / 錯密碼 / 正確 / 明文 HTTP" \
  'Q="/api/v1/query?query=count(up)"; echo "無帳密 $(bash "$DC" https://prometheus:9090$Q | tail -1);錯誤密碼 $(bash "$DC" -u c3:wrong https://prometheus:9090$Q | tail -1);正確帳密 $(bash "$DC" -u c3:prom-pw https://prometheus:9090$Q | tail -1);明文 HTTP $(bash "$DC" http://prometheus:9090$Q | tail -1)"' '無帳密 \[HTTP 401\];錯誤密碼 \[HTTP 401\];正確帳密 \[HTTP 200\];明文 HTTP \[HTTP 400\]'

step am "【監控 ②】Alertmanager:同樣 HTTPS + Basic;不帶帳密連「建立靜音」都被擋(401),帶帳密才成功" \
  "curl https://alertmanager:9093/api/v2/status   # 對照:不帶帳密 / 錯誤密碼 / 正確帳密(不帶帳密連建立靜音都被擋,見第 13 章)" \
  'out=$( { echo "--- 不帶帳密"; bash "$DC" https://alertmanager:9093/api/v2/status | tail -2; echo "--- 錯誤密碼"; bash "$DC" -u c3:wrong https://alertmanager:9093/api/v2/status | tail -1; echo "--- 正確帳密"; bash "$DC" -u c3:am-pw https://alertmanager:9093/api/v2/status | tail -1; } 2>&1 ); printf "%s\n" "$out"; printf "%s" "$out" | tr "\n" " " | grep -q "HTTP 401.*HTTP 401.*HTTP 200" && echo "判定:Alertmanager 要帳密才能用" || echo "判定:不符合"' '判定:Alertmanager 要帳密才能用'

step telemetry "【監控 ③】broker 推送指標也走 HTTPS + Basic(api.key / api.secret 就是 Basic 帳密):broker 指標的最新一筆在 2 分鐘內" \
  "PromQL: time() - max(timestamp(io_confluent_kafka_server_request_total_time_ms_p99))" \
  'Q="https://prometheus:9090/api/v1/query?query=time()-max(timestamp(io_confluent_kafka_server_request_total_time_ms_p99))"; bash "$DC" -u c3:prom-pw "$Q"; v=$(bash "$DC" -u c3:prom-pw "$Q" | grep -o ",\"[0-9.]*\"\]" | grep -o "[0-9.]*" | head -1); echo "最新一筆指標距今 ${v:-無} 秒(小於 120 = 指標持續進來)"; if [ -n "$v" ] && [ "${v%.*}" -lt 120 ]; then echo "判定:指標持續進來"; else echo "判定:指標沒有進來"; fi' '判定:指標持續進來'

step c3-services "【監控 ④】C3 到 Prometheus 與 Alertmanager 的連線(HTTPS + Basic)狀態:兩個都是 ONLINE" \
  "GET /3.0/services/{prometheus,alertmanager}/status   # C3 API(HTTPS 9022)" \
  'o=$(bash "$DEMO_ROOT/scripts/c3-services-status.sh"); echo "$o"; echo "ONLINE 數量:$(echo "$o" | grep -c ONLINE)"' 'ONLINE 數量:2'

# ---------------- C3 ----------------
step c3-https "【C3 ①】C3 走 HTTPS(9022):憑證由 demo CA 驗證通過(主機名稱在 SAN 內)" \
  "curl --cacert ca.pem https://control-center:9022/login" \
  'bash "$DC" -o /dev/null -w "憑證驗證結果 %{ssl_verify_result}(0 = 通過) HTTP %{http_code}" https://control-center:9022/login | head -1' '憑證驗證結果 0\(0 = 通過\) HTTP 200'

step c3-badca "【C3 ②】工具(或瀏覽器)不信任簽發的 CA 時會被擋:不帶 CA 連 HTTPS 失敗(curl 錯誤 60);所以正式環境要把內部 CA 發給使用者端" \
  "curl https://control-center:9022/login   # 對照:沒有 --cacert" \
  'docker run --rm --network cpsec_default --entrypoint curl curlimages/curl:latest -sS -m 10 -o /dev/null https://control-center:9022/login 2>&1 | grep -o "curl: ([0-9]*) [^.]*" | head -1' 'curl: \(60\)'

ch_end
