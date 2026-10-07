// 故事版手冊新增的兩個 Lab(沿用 labs.mjs 的欄位格式)。
// Lab 15:人員異動(scenarios/ch15-offboarding.sh);Lab 16:OP menu(scenarios/ch16-opmenu.sh);Lab 17:傳輸加密補強(scenarios/ch17-transport-hardening.sh)。
// 手動指令只依賴 labs.mjs 的 SETUP 定義的 kc / hc 函式與環境變數($MDS、$RP、$JSON、$CL)。
import { CID, USER_DN } from './labs.mjs';

const R = String.raw;
const ldapMod = (op, user, grp) => R`printf 'dn: cn=${grp},ou=groups,dc=corp,dc=demo\nchangetype: modify\n${op}: member\nmember: ${USER_DN[user]}\n' | docker exec -i openldap ldapmodify -x -D cn=admin,dc=corp,dc=demo -w adminpw`;
const HDR = '-H "Accept: application/vnd.kafka.v2+json" -H "Content-Type: application/vnd.kafka.json.v2+json"';
const bindGroup = (role) => `hc -u gary:gary-pw "\${JSON[@]}" -X POST $MDS/security/1.0/principals/Group%3Aorders-write/roles/${role}/bindings -d '{"scope":{"clusters":{"kafka-cluster":"${CID}"}},"resourcePatterns":[{"resourceType":"Topic","name":"orders.","patternType":"PREFIXED"}]}'`;
const unbindGroup = (role) => `hc -u gary:gary-pw "\${JSON[@]}" -X DELETE $MDS/security/1.0/principals/Group%3Aorders-write/roles/${role}/bindings -d '{"scope":{"clusters":{"kafka-cluster":"${CID}"}},"resourcePatterns":[{"resourceType":"Topic","name":"orders.","patternType":"PREFIXED"}]}'`;
const OPM = 'cd <你的路徑>/untitled6/demo/opmenu';
const OPENV = 'OPMENU_USER=gary OPMENU_PASS=gary-pw OPMENU_YES=1 OPMENU_TICKET=CHG-2026-0001';

export const LABS_EXTRA = [
  // ───────────────────────── Lab 15 ─────────────────────────
  {
    id: 'ch15', n: 15, title: '(進階)人員異動:AD 收回群組,已發出的 token 立刻失去權限', time: '10 分',
    goal: '證明:人員調動或離職時只要改 AD。Kafka 端不用動,連已經發出、還沒到期的 MDS token 都會在 AD 收回群組的當下失去權限(授權依「現在的群組」判斷)。',
    pre: ['Lab 3 完成(AD 群組 orders-write 與 orders.* 的授權概念)。', '起點狀態:yujie 在 orders-write,且該群組有 orders.* 的讀寫 role(見下方指令)。'],
    pre_cmd: [
      ldapMod('add', 'yujie', 'orders-write') + ' 2>&1 | tail -1',
      bindGroup('DeveloperWrite'),
      bindGroup('DeveloperRead'),
      'sleep 12   # 等群組快取',
    ],
    autoAll: ['./scenarios/ch15-offboarding.sh'],
    steps: [
      { t: '15.1 發 token:yujie 以 AD 帳密向 MDS 登入', defs: true, why: 'MDS 驗證 AD 之後回一個 JWT,效期 1 小時。之後他可以拿這個 token 當 Bearer 呼叫 REST Proxy,不必再送密碼。',
        manual: [R`T=$(hc -u yujie:yujie-pw -H "Accept: application/json" $MDS/security/1.0/authenticate | grep -o '"auth_token":"[^"]*"' | cut -d'"' -f4)
echo "token 前 20 字元:${'$'}{T:0:20}…(JWT,效期 1 小時)"`],
        ev: 'issue', re: /token 前 20|"sub":"YUJIE"/, expect: '取得 token(內容是長長的一串 JWT,此處只顯示前綴)。' },
      { t: '15.2 收回前:拿 token 寫入 → 成功', why: '他的權限來自 AD 群組 orders-write 的 role binding。',
        manual: [`hc -H "Authorization: Bearer $T" ${HDR} -X POST $RP/topics/orders.events -d '{"records":[{"value":{"order":"offboard-1"}}]}'`],
        ev: 'ok', re: /HTTP 200/, expect: '[HTTP 200],offsets 有值。' },
      { t: '15.3 AD 收回:把 yujie 移出 orders-write(只在 AD 操作)', why: 'Kafka 與 token 都沒動。真實 AD 用 AD 管理工具移出群組;demo 用 LDAP 指令。MDS 以 ldap.refresh.interval.ms 週期重讀群組(demo 5 秒),所以多等幾秒。',
        uiEq: [ldapMod('delete', 'yujie', 'orders-write')], manual: ['sleep 12   # 等群組快取刷新'],
        auto: ['./scripts/ldap-group.sh remove yujie orders-write'], ev: 'revoke', re: /modifying entry|已移出群組/, expect: '已移出群組並等待群組快取刷新。' },
      { t: '15.4 收回後:同一個 token(還沒到期)再寫入 → 403', why: '授權依「現在的群組」判斷,不是依發 token 當下。所以離職或調動不需要去「作廢」token。',
        manual: [`hc -H "Authorization: Bearer $T" ${HDR} -X POST $RP/topics/orders.events -d '{"records":[{"value":{"order":"offboard-1"}}]}'`],
        ev: 'denied', re: /HTTP 403/, expect: 'error_code 40301 / [HTTP 403]。', warn: '離職時請務必同時停用 AD 帳號:AD 帳號被停用或刪除之前,已發出的 token 在到期前仍可通過「認證」(只是沒有任何權限)。實測:刪除 AD 使用者後,舊 token 仍有效到到期。' },
      { t: '15.5 帳號仍在 AD:他還是能登入,只是什麼都看不到', manual: [R`hc -u yujie:yujie-pw $RP/topics | grep -o '"orders[^"]*"\|\[HTTP [0-9]*\]'`],
        ev: 'login', re: /HTTP 200/, expect: '[HTTP 200],但清單裡沒有 orders.* 之類的業務 topic。' },
      { t: '15.6 清理:恢復起點(讓後面的 Lab 不受影響)', re: /HTTP 204[\s\S]*HTTP 204/, manual: [ldapMod('add', 'yujie', 'orders-write') + ' 2>&1 | tail -1', unbindGroup('DeveloperWrite'), unbindGroup('DeveloperRead')], expect: '群組與 role binding 回到起點。' },
    ],
  },
  // ───────────────────────── Lab 16 ─────────────────────────
  {
    id: 'ch16', n: 16, title: '(進階)OP menu:日常維運選單', time: '25 分(含滾動重啟約 3 分)',
    goal: '把日常維運做成一支選單:操作者用自己的 AD 身分登入,Kafka 的動作由 RBAC 判斷、主機的動作由 sudo 判斷、選單本身不判斷權限;每個動作都留紀錄。並體驗維護模式、權限覆核匯出、audit 查詢、變更時窗與並行鎖。',
    pre: ['Lab 0 完成(叢集在跑;demo 的 Alertmanager 在跑)。', '本 Lab 用 docker 後端(選單程式在 demo/opmenu/);正式環境是 vm 後端,在跳板機上以登入殼層執行,指令相同。', '帳密與核准單號用環境變數帶入只是為了讓這份手冊可重現:正式環境一律忽略環境變數,一定要互動輸入密碼。'],
    pre_cmd: [OPM, 'ls log/ 2>/dev/null | head -2   # 紀錄與匯出檔都放在這裡(demo);正式環境放 /var/log/opmenu'],
    autoAll: ['./scenarios/ch16-opmenu.sh   # 設 CH16_SKIP_ROLLING=1 可略過會重啟 broker 的滾動重啟'],
    steps: [
      { t: '16.1 互動進入選單(以及列出所有項目)', why: '直接執行 ./opmenu.sh 會要你輸入 AD 帳號與密碼,然後出現分四層的選單,輸入編號即可。下面用 --list 與 --run N 讓步驟可以重現。編號第一位是層級:1 值班查看、2 服務操作、3 變更作業、4 授權與緊急。',
        manual: ['# ./opmenu.sh   (互動:輸入 AD 帳號與密碼,選編號,0 離開;下面的指令用 --list 與 --run 讓步驟可以重現)', `${OPENV} ./opmenu.sh --list | cut -f1,2,5`],
        ev: 'list', re: /91\s+授權與緊急/, expect: '列出 10 到 19、21 到 27、31 到 37、41 到 45、91 號項目。', tip: '登入畫面只問密碼的情況:跳板機把作業系統帳號綁 AD 時(OPMENU_USER_FROM_OS=1),操作者帳號固定取登入者,不能輸入別人的帳號。' },
      { t: '16.2 值班查看:cluster 與身分鏈健康(項目 11)', why: '一次看完 under-replicated 與 offline partition、broker 是否在線,以及 MDS 各台的狀態與延遲、你的 token 還剩多久、controller quorum(需 ClusterAdmin)。',
        manual: [`${OPENV} ./opmenu.sh --run 11`], ev: 'health', re: /broker 在線/, expect: '兩個 partition 清單都是空的;broker 在線 2 / 2;MDS 正常。', tip: '這個項目要能 describe topic:gary 屬於 topic-admin(ResourceOwner)所以可以。只屬於 ops(Operator)的人跑會被拒,Lab 11 實測過:Operator 連 kafka-topics --describe 都做不了。' },
      { t: '16.3 生效設定(項目 19):每個值從哪來', why: '設定檔只需要填「無法推算」的值,其餘登入後自動推算:MDS 位址由 bootstrap 推算、cluster ID 向 MDS 取、節點清單由 broker 與輔助服務清單合併。選單顯示每個值的來源(conf、derived 或 default)。broker 清單與節點清單刻意不從叢集推算:它們是重啟與 ssh 的允許清單,必須是人工審過的固定設定,而且 broker 掛掉後會從叢集清單消失。',
        manual: [`${OPENV} ./opmenu.sh --run 19`], ev: 'effconf', re: /derived/, expect: 'MDS_URL、KAFKA_CLUSTER_ID、HOSTS、REPLICATION 的來源是 derived。' },
      { t: '16.4 維護模式:開始(項目 25)', why: '要維護 broker1 之前,先對它靜音告警(Alertmanager silence),避免一堆無意義的告警。最長時間由 OPMENU_MAINT_MAX_MIN 限制。',
        manual: [`${OPENV} ./opmenu.sh --run 25 broker1 30 | tee log/maint.out`], ev: 'maint-on', re: /維護模式已開始/, expect: '維護模式已開始,並給 silence id。' },
      { t: '16.5 維護模式:結束(項目 26)', why: '維護做完提前結束。選單只允許結束「由 opmenu 建立」的 silence,不會誤砍別人的。',
        manual: ['ID=$(grep -o "silence id=[0-9a-f-]*" log/maint.out | cut -d= -f2)   # 取出上一步的 silence id', `${OPENV} ./opmenu.sh --run 26 "$ID"`], ev: 'maint-off', re: /維護模式已結束/, expect: '維護模式已結束。' },
      { t: '16.6 權限覆核:匯出權限清單(項目 44)', why: '依 role 列出所有 principal 與資源範圍,輸出 CSV 交給定期覆核。需要 SecurityAdmin 或 UserAdmin。',
        manual: [`${OPENV} ./opmenu.sh --run 44`, 'head log/permission-review-*.csv'], ev: 'review', re: /已匯出/, expect: '已匯出 N 筆,CSV 表頭是 role、principal、resource_type…' },
      { t: '16.7 選單不判斷權限:Ming 用同一個選單匯出 → 被 Kafka 拒絕', why: '選單沒有任何「誰能按這個」的判斷,真正的門是 Kafka RBAC(與主機的 sudo)。Ming 是唯讀,沒有 SecurityAdmin 或 UserAdmin,所以被拒。',
        manual: ['OPMENU_USER=ming OPMENU_PASS=ming-pw OPMENU_YES=1 ./opmenu.sh --run 44'], ev: 'ming-denied', re: /403/, expect: '查詢 role 失敗(HTTP 403);需要 SecurityAdmin 或 UserAdmin。' },
      { t: '16.8 audit 查詢(項目 45)', why: '最近 N 分鐘的 audit 事件,可依主體與結果篩選。這裡找最近 4 小時被拒絕的事件,正好是前面 Lab 的足跡。需要 audit topic 與 audit-* consumer group 的 DeveloperRead。',
        manual: [`${OPENV} ./opmenu.sh --run 45 240 '' DENIED`], ev: 'audit', re: /符合/, expect: '符合 N 筆,並列出時間、主體、操作、資源、結果。' },
      { t: '16.9 變更時窗:時窗外的變更被擋', why: '需要核准的變更類項目只能在時窗內執行;唯讀項目與緊急模式不受限。時窗由 OPMENU_CHANGE_WINDOW 設定,空白表示不限制。這裡用測試用變數模擬「週三中午」。',
        manual: [`${OPENV} OPMENU_CHANGE_WINDOW='Mon 00:00-00:01' OPMENU_NOW_OVERRIDE='3 12:00' ./opmenu.sh --run 25 broker1 5`], ev: 'window', re: /不在允許變更的時窗內/, expect: '目前不在允許變更的時窗內。', tip: 'OPMENU_NOW_OVERRIDE 只在設定檔明確允許環境變數覆蓋時才有效(demo 用);正式環境操作者無法繞過時窗。' },
      { t: '16.10 並行鎖:別人正在變更時,我的變更被擋', why: '需要核准的項目同一時間只允許一個人執行,避免兩個人同時重啟或改授權。鎖只在同一台跳板機有效;持有者的行程不在了就視為過期。這裡手動放一個「別人持有」的鎖來示範。',
        manual: [`mkdir -p log/opmenu.lock.d; sleep 120 & HP=$!; echo "$HP gary 27 滾動重啟所有 broker | $(date '+%F %T')" > log/opmenu.lock.d/info`, `${OPENV} ./opmenu.sh --run 25 broker1 5`, 'kill $HP; rm -rf log/opmenu.lock.d'],
        ev: 'lock', re: /其他變更作業進行中/, expect: '目前有其他變更作業進行中(誰、做什麼、什麼時候)。' },
      { t: '16.11 滾動重啟所有 broker(項目 27,會真的重啟,約 3 分鐘)', why: '一次一台。每台重啟後先等 45 秒,再連續兩次確認「全部 broker 在線、under-replicated 與 offline 都是 0」才換下一台;任何一步失敗就停止。這個等待不能省:剛重啟的頭幾秒,舊 broker 還在叢集清單、ISR 也還沒縮減,under-replicated 看起來是 0,其實是假象(實測踩過)。',
        manual: [`${OPENV} ./opmenu.sh --run 27`], ev: 'rolling', re: /完成滾動重啟/, expect: '兩台依序完成,最後「全部 2 台 broker 已完成滾動重啟」。', warn: '滾動重啟不含 controller(controller 的服務名與重啟順序尚未在真實 CP 節點驗證)。實測遇過一次:叢集連續跑了一整天、metadata 累積到約 13000 筆後,broker1 重啟時因 SCRAM 憑證還沒載入、authorizer 連自己失敗而啟動退出(推測原因,未確認)。這時滾動重啟會等到逾時就停止,不會動後面的 broker;處理方式是看 docker logs / journalctl 找原因,再決定重啟或重建。', tip: '這正是「一次一台、每台確認恢復才換下一台」的價值:第一台出問題時,第二台還在服務,不會造成中斷。' },
    ],
  },
  // ───────────────────────── Lab 17 ─────────────────────────
  {
    id: 'ch17', n: 17, title: '(進階)傳輸加密補強:AD 走 LDAPS、監控 HTTPS + Basic、C3 HTTPS', time: '15 分',
    goal: '前面的 Lab 處理「誰能做什麼」;這個 Lab 處理「線上傳輸有沒有被看光」。證明三件事:① broker 連 AD 走 LDAPS(636),登入密碼不再明文;② Prometheus、Alertmanager 要 HTTPS + Basic 帳密才能讀寫,而且 C3 與 broker 的指標推送仍然正常;③ 使用者連 C3 走 HTTPS。',
    pre: ['Lab 0 完成(含 Control Center:docker compose --profile c3 …)。', '這些設定都已經在 compose 與 config/c3/ 裡(demo 已套用):broker 的 ldap.* 改 ldaps:// 加信任庫、web-config-prom.yml 與 web-config-am.yml(TLS 加 Basic 帳密)、C3 與 broker 的監控連線改 https 並帶 Basic 帳密、共用 server 憑證補上 prometheus 與 alertmanager 的名稱(同一把 key、同一個 CA 重簽)。', 'demo 帳密都是測試值:Prometheus c3 / prom-pw、Alertmanager c3 / am-pw。'],
    autoAll: ['./demo.sh 17', './scenarios/ch17-transport-hardening.sh'],
    steps: [
      { t: '17.1 AD ①:broker 連 AD 走 LDAPS(636),389 沒有 broker 的連線', why: '模擬 AD 的 OpenLDAP 同時開 389(明文)與 636(LDAPS)。看它的日誌:來自 broker 的連線都應該落在 636。(389 上只會有容器內部的健康檢查,來源是 127.0.0.1。)',
        manual: [R`for x in broker1 broker2; do ip=$(docker inspect $x --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'); echo "$x($ip): $(docker logs openldap 2>&1 | grep ACCEPT | grep "from IP=$ip:" | grep -c "IP=0.0.0.0:636") 條連到 636、$(docker logs openldap 2>&1 | grep ACCEPT | grep "from IP=$ip:" | grep -c "IP=0.0.0.0:389") 條連到 389"; done`],
        ev: 'ldaps-from-broker', re: /[1-9][0-9]* 條連到 636、0 條連到 389/, expect: '至少一台 broker 有連到 636 的紀錄,連到 389 的是 0 條(另一台 broker 若還沒查過 AD,兩個都是 0 屬正常)。判定:broker 連 AD 只走 LDAPS。',
        tip: '設定:ldap.java.naming.provider.url=ldaps://openldap:636、ldap.java.naming.security.protocol=SSL、ldap.ssl.truststore.location(與 type、password)。只有連 AD 的 JVM(兩台 broker)需要這份信任庫;controller 不連 AD。' },
      { t: '17.2 AD ②:信任簽發憑證的 CA 才連得上 LDAPS', why: 'LDAPS 的 TLS 憑證是 demo CA 簽的,所以用戶端必須信任這個 CA:信任就成功,不信任就失敗。這正是 broker 需要 ldap.ssl.truststore 的原因。',
        manual: [R`echo "--- 信任 demo CA"; docker exec -e LDAPTLS_CACERT=/container/service/slapd/assets/certs/ca.crt openldap ldapsearch -x -H ldaps://openldap:636 -D cn=admin,dc=corp,dc=demo -w adminpw -b dc=corp,dc=demo -s base dn 2>&1 | grep -E "^dn:|^result:|Can.t contact"
echo "--- 不信任 demo CA(只用系統預設的 CA)"; docker exec -e LDAPTLS_CACERT=/etc/ssl/certs/ca-certificates.crt openldap ldapsearch -x -H ldaps://openldap:636 -D cn=admin,dc=corp,dc=demo -w adminpw -b dc=corp,dc=demo -s base dn 2>&1 | grep -E "^dn:|^result:|Can.t contact" | head -2`],
        ev: 'ldaps-trust', re: /result: 0 Success[\s\S]*Can.t contact LDAP server/, expect: '信任 demo CA:dn 與 result: 0 Success;不信任:Can\'t contact LDAP server。',
        warn: '真實 AD 的 LDAPS 憑證若是多層 CA(根 CA 加中繼 CA)簽的,信任庫必須放進中繼 CA:實測只放根 CA 會 PKIX path building failed(見 spike/ldaps-intermediate)。這裡 demo 是單層 CA,所以沒有這個問題。' },
      { t: '17.3 AD ③:人用 AD 帳密登入不受影響', why: 'MDS 的 Basic 登入與 Kafka 的 PLAIN 登入都要查 AD,現在全部經過 LDAPS。使用者端完全沒有變化。',
        manual: [R`echo "--- 正確密碼"; hc -o /dev/null -u gary:gary-pw $MDS/security/1.0/authenticate
echo "--- 錯誤密碼"; hc -o /dev/null -u gary:wrong $MDS/security/1.0/authenticate
echo "--- Kafka PLAIN(gary)列出 topic"; kc kafka-topics --bootstrap-server $BOOT --command-config /clients/plain-gary.properties --list | head -5`],
        ev: 'ldaps-login', re: /HTTP 200[\s\S]*HTTP 401[\s\S]*__consumer_offsets/, expect: '正確密碼 [HTTP 200];錯誤密碼 [HTTP 401];Kafka PLAIN 列出 topic。' },
      { t: '17.4 監控 ①:Prometheus 要 HTTPS + Basic', why: '不帶帳密與錯誤密碼都是 401;正確帳密 200;用明文 HTTP 連則被拒(400,Prometheus 回「Client sent an HTTP request to an HTTPS server」)。',
        manual: [R`Q="/api/v1/query?query=count(up)"
echo "--- 不帶帳密"; hc https://prometheus:9090$Q
echo "--- 錯誤密碼"; hc -u c3:wrong https://prometheus:9090$Q
echo "--- 正確帳密"; hc -u c3:prom-pw https://prometheus:9090$Q
echo "--- 明文 HTTP"; hc http://prometheus:9090$Q`],
        ev: 'prom', re: /HTTP 401[\s\S]*HTTP 401[\s\S]*HTTP 200[\s\S]*HTTP 400/, expect: '依序:[HTTP 401]、[HTTP 401]、{"status":"success",…} 與 [HTTP 200]、[HTTP 400]。',
        tip: '設定放在 config/c3/web-config-prom.yml:tls_server_config(憑證與私鑰)加 basic_auth_users(bcrypt 雜湊,用 htpasswd -nbBC 10 產生);Prometheus 以 --web.config.file 讀取。' },
      { t: '17.5 監控 ②:Alertmanager 要 HTTPS + Basic', why: '同樣的做法。要注意:Prometheus 把告警送給 Alertmanager 這一段,也要改設定(Prometheus 設定檔的 alerting.alertmanagers 加 scheme: https、basic_auth、tls_config.ca_file)。官方的 TLS + Basic 頁沒有寫這一段,實測不改的話告警送不到(Alertmanager 回 400)。',
        manual: [R`echo "--- 不帶帳密"; hc https://alertmanager:9093/api/v2/status | tail -2
echo "--- 錯誤密碼"; hc -u c3:wrong https://alertmanager:9093/api/v2/status | tail -1
echo "--- 正確帳密"; hc -u c3:am-pw https://alertmanager:9093/api/v2/status | tail -1`],
        auto: ['bash scripts/dcurl.sh https://alertmanager:9093/api/v2/status   # 不帶帳密', 'bash scripts/dcurl.sh -u c3:wrong https://alertmanager:9093/api/v2/status', 'bash scripts/dcurl.sh -u c3:am-pw https://alertmanager:9093/api/v2/status'], ev: 'am', re: /HTTP 401[\s\S]*HTTP 401[\s\S]*HTTP 200/, expect: '不帶帳密與錯誤密碼都是 [HTTP 401];正確帳密 [HTTP 200]。(建立靜音的對照見 Lab 13.8。)',
        warn: 'Basic 沒有細部授權:持有帳密就能對 Alertmanager 寫入(建立或刪除靜音、改設定)。所以不同用途的帳號要分開(C3 一組、OP menu 維護模式另一組),帳密檔限縮權限。' },
      { t: '17.6 監控 ③:broker 推送指標也走 HTTPS + Basic', why: 'broker 把指標推給 Prometheus 的 OTLP 端點:設定裡 api.key 與 api.secret 就是 Basic 帳密,信任庫用 …https.ssl.truststore.*。如果帳密或信任庫錯了,日誌會出現 Telemetry Metrics Failure(401 或憑證錯誤),Prometheus 裡的指標就不再更新。下面問 Prometheus:broker 指標的最新一筆距今幾秒。',
        manual: [R`Q="https://prometheus:9090/api/v1/query?query=time()-max(timestamp(io_confluent_kafka_server_request_total_time_ms_p99))"
hc -u c3:prom-pw "$Q"
v=$(hc -u c3:prom-pw "$Q" | grep -o ',"[0-9.]*"\]' | grep -o '[0-9.]*' | head -1); echo "最新一筆指標距今 ${'$'}{v:-無} 秒(小於 120 = 指標持續進來)"`],
        ev: 'telemetry', re: /"value":\[[0-9.]+,"[0-9.]+"\]/, expect: '距今秒數小於 120(指標每 60 秒送一次)。判定:指標持續進來。' },
      { t: '17.7 監控 ④:C3 到 Prometheus、Alertmanager 的連線狀態', why: 'C3 自己有 API 回報它跟這兩個元件的連線狀態(用 Lab 13.6 的做法:憑證向 MDS 換 token,帶 Bearer)。把 C3 的帳密改錯,這裡就會變成 OFFLINE(實測)。',
        manual: [R`T=$(hc --cert /certs/client-legacy-orders.pem --key /certs/client-legacy-orders.key -H "Accept: application/json" $MDS/security/1.0/authenticate | grep -o '"auth_token":"[^"]*"' | cut -d'"' -f4)
hc -H "Authorization: Bearer $T" https://control-center:9022/3.0/services/prometheus/status
hc -H "Authorization: Bearer $T" https://control-center:9022/3.0/services/alertmanager/status`],
        ev: 'c3-services', re: /"PROMETHEUS","componentStatus":"ONLINE"[\s\S]*"ALERT_MANAGER","componentStatus":"ONLINE"/, expect: '兩個元件都是 "componentStatus":"ONLINE"。' },
      { t: '17.8 C3 ①:使用者連 C3 走 HTTPS,憑證驗證通過', why: 'C3 的 HTTPS 用共用 server 憑證,主機名稱(control-center、localhost)都在憑證的 SAN 內。curl 的憑證驗證結果 0 代表通過。',
        manual: [R`hc -o /dev/null -w "憑證驗證結果 %{ssl_verify_result}(0 = 通過) HTTP %{http_code}\n" https://control-center:9022/login`],
        ev: 'c3-https', re: /憑證驗證結果 0\(0 = 通過\) HTTP 200/, expect: '憑證驗證結果 0(0 = 通過) HTTP 200。',
        tip: '瀏覽器要信任簽發憑證的內部 CA 才不會跳警告:正式環境由 AD 群組原則或管理工具把 CA 發到使用者電腦。demo 的 HTTP 9021 只留給容器內部的健康檢查,正式環境不要開。Windows 的 curl 若出現「無法檢查憑證撤銷」,加 --ssl-no-revoke(內部 CA 沒有撤銷清單,不是憑證有問題)。' },
      { t: '17.9 C3 ②:不信任簽發的 CA,連線就被擋', why: '同一個網址,這次不帶 demo CA:curl 回錯誤 60(憑證無法驗證)。瀏覽器遇到同樣情況會顯示「不安全」警告。所以導入時要規劃 CA 的發放。',
        manual: [R`docker run --rm --network $NET --entrypoint curl curlimages/curl:latest -sS -m 10 -o /dev/null https://control-center:9022/login 2>&1 | grep -o "curl: ([0-9]*) [^.]*" | head -1`],
        ev: 'c3-badca', re: /curl: \(60\)/, expect: 'curl: (60) SSL certificate …(不信任的憑證鏈)。' },
    ],
  },
];
