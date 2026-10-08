#!/usr/bin/env bash
# 第 18 章(進階):與行內 CyberArk 整合 —— 以 Conjur(CyberArk 的開源秘密管理)示範「應用程式取密碼、輪替、OP menu 取帳密、設定檔密碼不落地」
# 需要:profile cyberark(scripts/conjur.sh up 會啟動)。PAM 那一側(PSM 代登入、CPM 輪替主機帳號)無法在本機重現,只在文件說明。
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch18 "與行內 CyberArk 整合:應用程式取密碼、輪替、設定檔密碼不落地"
CJ="$DEMO_ROOT/scripts/conjur.sh"
OPM="$DEMO_ROOT/opmenu"
G="OPMENU_USER=gary OPMENU_PASS=gary-pw OPMENU_YES=1 OPMENU_TICKET=CHG-2026-0400 OPMENU_REASON=ch18"
AUTH_CMD="bash $DEMO_ROOT/scripts/conjur.sh get-as opmenu opmenu/alertmanager-auth"

# ---------------- 起點 ----------------
bash "$CJ" up >/dev/null 2>&1 || { echo "Conjur 啟動失敗"; exit 1; }
mds basic gary:gary-pw POST /security/1.0/principals/User:svc-orders/roles/DeveloperWrite/bindings "{\"scope\":{\"clusters\":{\"kafka-cluster\":\"XyZBQ3-GTvKH2qNfP7X33A\"}},\"resourcePatterns\":[{\"resourceType\":\"Topic\",\"name\":\"orders.\",\"patternType\":\"PREFIXED\"}]}" >/dev/null 2>&1
bash "$CJ" set opmenu/alertmanager-auth "opmenu:am-opmenu-pw" >/dev/null
bash "$CJ" set-cred svc-orders svc-orders orders-secret-v1 >/dev/null   # 起點:Conjur 裡「現在該用的帳號與密碼」= svc-orders / 原密碼
rm -rf "$OPM/log/opmenu.lock.d"

# ---------------- 應用程式取密碼 ----------------
step policy "【policy】Conjur 裡定義了誰(機器身分)能拿什麼(秘密):svc-orders 只能拿自己的密碼;OP menu 拿 Alertmanager 帳密;broker 拿主金鑰" \
  "conjur list -k host; conjur list -k variable   # 來自 config/conjur/policy/kafka.yml" \
  'export MSYS_NO_PATHCONV=1; echo "-- host(機器身分)"; docker exec -i conjur-cli conjur list -k host | tr -d "[]\",\r" | sed "/^\s*$/d"; echo "-- variable(秘密)"; docker exec -i conjur-cli conjur list -k variable | tr -d "[]\",\r" | sed "/^\s*$/d"' 'kafka/svc-orders/credential'

step admin-set "【管理員】把 svc-orders 的 SCRAM 密碼存進 Conjur(正式環境由 CyberArk 管理員在 PVWA 或 CLI 做)" \
  "conjur variable set -i kafka/svc-orders/credential -v '{\"u\":\"svc-orders\",\"p\":\"****\"}'   # 帳號與密碼放同一個變數,輪替時一次換、一次取" \
  'bash "$CJ" set-cred svc-orders svc-orders orders-secret-v1' '已寫入 kafka/svc-orders/credential'

step app-fetch "【應用】svc-orders 以自己的機器身分(API key)向 Conjur 換 token,再取密碼 → 200;密碼只回到呼叫者的記憶體" \
  "POST /authn/demo/host%2Fkafka%2Fsvc-orders/authenticate → token;GET /secrets/demo/variable/kafka%2Fsvc-orders%2Fpassword" \
  'bash "$CJ" probe-as svc-orders svc-orders/credential' 'authenticate → \[HTTP 200\];取 svc-orders/credential → \[HTTP 200\]'

step rogue "【對照】另一個應用(rogue-app)有身分但沒被授權 → 拿不到(Conjur 回 404,不透露秘密是否存在)" \
  "同上,但以 host/kafka/rogue-app 的 API key" \
  'bash "$CJ" probe-as rogue-app svc-orders/credential' 'authenticate → \[HTTP 200\];取 svc-orders/credential → \[HTTP 404\]'

step bad-key "【對照】錯誤的 API key → 認證就被擋(401)" \
  "POST .../authenticate(錯的 API key)" \
  'bash "$CJ" probe-bad svc-orders' '\[HTTP 401\]'

step app-start "【應用啟動】取密碼 → 在記憶體(tmpfs)組連線設定 → 以 SCRAM 連 broker 寫入 orders.events;主機與映像裡沒有密碼檔" \
  "scripts/app-with-conjur.sh svc-orders orders.events hello-from-conjur" \
  'bash "$DEMO_ROOT/scripts/app-with-conjur.sh" svc-orders orders.events hello-from-conjur' '結果:成功寫入 orders.events'

# ---------------- 輪替 ----------------
step rotate "【輪替】改 Kafka 的 SCRAM 密碼 → 更新 Conjur 的秘密 → 應用重新啟動就拿到新密碼;還拿舊密碼的設定檔立刻失效(正式環境由 CPM 自訂平台或排程觸發同一支腳本)" \
  "kafka-configs --alter --add-config 'SCRAM-SHA-512=[password=新密碼]' --entity-type users --entity-name svc-orders; conjur variable set ...; 應用重啟" \
  'K kafka-configs --bootstrap-server $BOOT --command-config /clients/token-bootstrap.properties --alter --add-config "SCRAM-SHA-512=[password=orders-secret-v2]" --entity-type users --entity-name svc-orders 2>&1 | grep Completed; bash "$CJ" set-cred svc-orders svc-orders orders-secret-v2; new=$(bash "$DEMO_ROOT/scripts/app-with-conjur.sh" svc-orders orders.events after-rotate 2>&1 | tail -1); echo "應用重啟:$new"; old=$(K kafka-topics --bootstrap-server $BOOT --command-config /clients/scram-svc-orders.properties --list 2>&1 | grep -ciE "Authentication failed"); echo "舊密碼的設定檔:$([ "$old" -gt 0 ] && echo 認證失敗 || echo 仍可用)"; if echo "$new" | grep -q 成功 && [ "$old" -gt 0 ]; then echo "判定:輪替後新密碼可用、舊密碼失效"; else echo "判定:不符合"; fi' '判定:輪替後新密碼可用、舊密碼失效'

step restore "【還原】把密碼改回原值(Kafka 與 Conjur 都改),讓其他章節不受影響" \
  "kafka-configs --alter ...(原密碼);conjur variable set ...(原密碼)" \
  'K kafka-configs --bootstrap-server $BOOT --command-config /clients/token-bootstrap.properties --alter --add-config "SCRAM-SHA-512=[password=orders-secret-v1]" --entity-type users --entity-name svc-orders 2>&1 | grep Completed; bash "$CJ" set-cred svc-orders svc-orders orders-secret-v1' '已寫入'

# ---------------- 輪替(零中斷):新舊並行 ----------------
ROT="$DEMO_ROOT/scripts/rotate-with-conjur.sh"

step rotate2-abort "【並行輪替 ⓪】先看安全網:舊帳號沒有任何角色時,腳本拒絕往下做(不知道要複製什麼),什麼都不動;應用照常能取到帳密" \
  "scripts/rotate-with-conjur.sh start nobody svc-x" \
  'echo "$(bash "$ROT" start nobody svc-x 2>&1 | tail -1)"; echo "Conjur 沒有被動:$(bash "$DEMO_ROOT/scripts/app-with-conjur.sh" svc-orders orders.events abort-check 2>&1 | tail -1)"' '沒有任何角色'

step rotate2-start "【並行輪替 ①】建新帳號 svc-orders-v2(密碼隨機)→ 複製角色(逐筆檢查)→ 驗證新帳號真的連得上、看到和舊帳號同樣的 topic → 才把新帳密一次寫進 Conjur;任何一步失敗就回滾新帳號、Conjur 不動;舊帳號仍可用,沒有中斷" \
  "scripts/rotate-with-conjur.sh start svc-orders svc-orders-v2   # 正式環境:CPM 自訂平台或排程呼叫" \
  'bash "$ROT" start svc-orders svc-orders-v2' 'Conjur 已指向 svc-orders-v2'

step rotate2-switch "【並行輪替 ②】應用逐批重啟:設定完全不用改,啟動時從 Conjur 一次拿到新帳密;還沒重啟的應用照常用舊帳號" \
  "scripts/app-with-conjur.sh svc-orders orders.events after-parallel-rotate" \
  'bash "$DEMO_ROOT/scripts/app-with-conjur.sh" svc-orders orders.events after-parallel-rotate | tail -2; echo "-- 還沒重啟的應用(舊帳號 svc-orders 的設定檔):"; K kafka-topics --bootstrap-server $BOOT --command-config /clients/scram-svc-orders.properties --list 2>&1 | grep -c "^orders" | sed "s/^/  仍可列出 orders topic:/"' '以 svc-orders-v2 身分'

step rotate2-quarantine "【並行輪替 ③】不直接刪舊帳號,先「隔離」:解除它的全部角色(可逆)、憑證留著;再看 audit。還有人在用的話,隔離後他的請求會變成被拒(DENIED)而被看見——只看「允許」不夠,因為 audit 不記 orders.* 的讀取成功" \
  "scripts/rotate-with-conjur.sh quarantine svc-orders; scripts/rotate-with-conjur.sh check svc-orders 1" \
  'bash "$ROT" quarantine svc-orders | tail -1; sleep 3; bash "$ROT" check svc-orders 1' '判定:沒有人在用'

step rotate2-finish "【並行輪替 ④】確認沒人用才停用(刪 SCRAM 憑證);舊設定檔認證失敗,新帳號照常" \
  "scripts/rotate-with-conjur.sh finish svc-orders" \
  'bash "$ROT" finish svc-orders | tail -1; old=$(K kafka-topics --bootstrap-server $BOOT --command-config /clients/scram-svc-orders.properties --list 2>&1 | grep -ciE "Authentication failed"); new=$(bash "$DEMO_ROOT/scripts/app-with-conjur.sh" svc-orders orders.events after-finish 2>&1 | tail -1); echo "舊帳號:$([ "$old" -gt 0 ] && echo 認證失敗 || echo 仍可用);新帳號:$new"; if [ "$old" -gt 0 ] && echo "$new" | grep -q 成功; then echo "判定:零中斷輪替完成,舊帳號已失效"; else echo "判定:不符合"; fi' '判定:零中斷輪替完成,舊帳號已失效'

step rotate2-restore "【還原】svc-orders(原密碼與原角色)回來、Conjur 指回它、移除 svc-orders-v2" \
  "scripts/rotate-with-conjur.sh restore" \
  'bash "$ROT" restore | tail -1' 'svc-orders 已還原'

step rotate2-inuse "【若有人還在用舊帳號】隔離後他的請求被拒,audit 看得到(DENIED)→ check 判定「還有人在用」→ rollback 把角色綁回去 → 他恢復正常。這就是不直接刪帳號的原因" \
  "quarantine → (有人用舊帳號)→ check → rollback" \
  'bash "$ROT" quarantine svc-orders >/dev/null; sleep 4; r=$(bash "$DEMO_ROOT/scripts/app-with-conjur.sh" svc-orders orders.events still-on-old 2>&1 | tail -1); echo "隔離後還在用舊帳號的應用:$r"; sleep 5; chk=$(bash "$ROT" check svc-orders 1 | tail -2); echo "$chk"; bash "$ROT" rollback svc-orders | tail -1; sleep 5; r2=$(bash "$DEMO_ROOT/scripts/app-with-conjur.sh" svc-orders orders.events back-to-normal 2>&1 | tail -1); echo "回復後:$r2"; if echo "$r" | grep -q 被拒絕 && echo "$chk" | grep -q 還有人在用 && echo "$r2" | grep -q 成功; then echo "判定:隔離期有人還在用 → 被抓到 → rollback 後恢復正常"; else echo "判定:不符合"; fi' '判定:隔離期有人還在用 → 被抓到 → rollback 後恢復正常'

step oldconn-both "【實驗:舊連線①】長連線 producer 一直在寫,中途「隔離(解除角色)」再「停用(刪 SCRAM)」:已建立的連線不會被踢,但解除角色後它的每個請求都被授權擋下" \
  "scripts/old-connection-test.sh both" \
  'bash "$DEMO_ROOT/scripts/old-connection-test.sh" both 2>&1 | tail -8; bash "$ROT" restore | tail -1' '判定:解除角色就切斷舊連線'

step oldconn-scram "【實驗:舊連線②】同樣的長連線 producer,但只刪 SCRAM 憑證、角色保留:舊連線完全不受影響,繼續寫完。SCRAM 只在「建立連線」時驗證,所以只刪憑證擋不住已連著的人" \
  "scripts/old-connection-test.sh scram-only" \
  'bash "$DEMO_ROOT/scripts/old-connection-test.sh" scram-only 2>&1 | tail -8; bash "$ROT" restore | tail -1' '判定:只刪 SCRAM 憑證擋不住已建立的連線'

# ---------------- OP menu ----------------
step opmenu "【OP menu】維護模式的 Alertmanager 帳密改成執行時向 Conjur 取(OPMENU_ALERTMANAGER_AUTH_CMD),跳板機上不再放帳密檔;沒被授權的身分取不到就開不了" \
  "OPMENU_ALERTMANAGER_AUTH_CMD='scripts/conjur.sh get-as opmenu opmenu/alertmanager-auth' ./opmenu.sh --run 25 broker1 2 → --run 26 <id>" \
  'cd "$OPM"; out=$(env $G OPMENU_ALERTMANAGER_AUTH_CMD="$AUTH_CMD" ./opmenu.sh --run 25 broker1 2 </dev/null 2>&1 | sed "s/\x1b\[[0-9;]*m//g"); echo "$out" | tail -1; id=$(echo "$out" | grep -o "silence id=[0-9a-f-]*" | cut -d= -f2); env $G OPMENU_ALERTMANAGER_AUTH_CMD="$AUTH_CMD" ./opmenu.sh --run 26 "$id" </dev/null 2>&1 | sed "s/\x1b\[[0-9;]*m//g" | tail -1; echo "-- 沒被授權的身分(rogue-app)取帳密:"; env $G OPMENU_ALERTMANAGER_AUTH_CMD="bash $DEMO_ROOT/scripts/conjur.sh get-as rogue-app opmenu/alertmanager-auth" ./opmenu.sh --run 25 broker1 2 </dev/null 2>&1 | sed "s/\x1b\[[0-9;]*m//g" | grep -m1 "失敗"; rm -rf log/opmenu.lock.d' '維護模式已結束'

# ---------------- 設定檔密碼不落地(Confluent Secret Protection) ----------------
step sp-setup "【設定檔】Confluent Secret Protection:AD 查詢帳號的密碼在設定檔裡改成加密佔位符;主金鑰存進 Conjur,不在任何檔案" \
  "confluent secret master-key generate → conjur variable set kafka/broker/master-key;confluent secret file encrypt --config ldap.java.naming.security.credentials" \
  'bash "$DEMO_ROOT/scripts/secret-protection.sh" setup' '主金鑰已存入 Conjur'

step sp-apply "【broker 啟動】broker2 啟動前以自己的機器身分向 Conjur 取主金鑰(正式環境 = systemd ExecStartPre),解開密文後才連 AD;生效設定裡只有佔位符、環境裡沒有明文密碼;人用 AD 帳密登入照常" \
  "docker compose -f docker-compose.yml -f docker-compose.cyberark.yml up -d broker2;curl -u gary https://broker2:8092/security/1.0/authenticate" \
  'bash "$DEMO_ROOT/scripts/secret-protection.sh" apply 2>&1 | grep secret-protection; bash "$DEMO_ROOT/scripts/secret-protection.sh" show; code=$(bash "$DEMO_ROOT/scripts/dcurl.sh" -o /dev/null -u gary:gary-pw https://broker2:8092/security/1.0/authenticate | tail -1); echo "gary 經 broker2 登入 → $code"; [ "$code" = "[HTTP 200]" ] && echo "判定:設定檔只有密文與佔位符,broker 仍能查 AD" || echo "判定:不符合"' '判定:設定檔只有密文與佔位符,broker 仍能查 AD'

step sp-revert "【還原】broker2 回到原本設定(其他章節不依賴 Conjur)" \
  "docker compose up -d broker2" \
  'bash "$DEMO_ROOT/scripts/secret-protection.sh" revert 2>&1 | tail -1' '已回到原本設定'

# ---------------- 稽核 ----------------
step audit "【稽核】Conjur 記錄誰取了什麼:被拒的嘗試(rogue-app)清楚可查" \
  "docker logs conjur-server | grep 'demo:host:kafka'" \
  'docker logs conjur-server 2>&1 | grep -E "demo:host:kafka/[a-z-]+ (tried to fetch|fetched)" | sed -E "s/^.*(demo:host:kafka)/\1/" | sort | uniq -c | sort -rn | head -6' 'rogue-app tried to fetch'

ch_end
