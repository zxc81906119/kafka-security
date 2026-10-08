// 故事版手冊新增的兩個 Lab(沿用 labs.mjs 的欄位格式)。
// Lab 15:人員異動(scenarios/ch15-offboarding.sh);Lab 16:OP menu(scenarios/ch16-opmenu.sh);Lab 17:傳輸加密補強(scenarios/ch17-transport-hardening.sh);Lab 18:CyberArk 整合(scenarios/ch18-cyberark.sh)。
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
  // ───────────────────────── Lab 18 ─────────────────────────
  {
    id: 'ch18', n: 18, title: '(進階)與行內 CyberArk 整合:應用程式取密碼、輪替、設定檔密碼不落地', time: '25 分',
    goal: '用 CyberArk 的開源版秘密管理(Conjur)示範「秘密不落地」這條路:應用程式啟動時以自己的機器身分取密碼;沒被授權的拿不到;輪替後應用自己跟上;OP menu 的帳密、broker 設定檔的密碼也都不再放在檔案裡。PAM 那一側(代登入、錄影、輪替主機帳號)本機無法重現,只在簡報與附錄說明。',
    pre: ['Lab 7 的觀念(服務帳號 SCRAM)、Lab 16(OP menu)。', 'Conjur 是 profile cyberark 的 4 個容器(資料庫、伺服器、TLS 入口、管理 CLI),本 Lab 第一步會啟動;共用 server 憑證的名稱已含 conjur。', '所有 API key 與主金鑰都放在 demo/config/conjur/ 下的忽略檔或 Conjur 裡,不進版本庫。'],
    pre_cmd: [
      'hc -u gary:gary-pw "${JSON[@]}" -X POST $MDS/security/1.0/principals/User%3Asvc-orders/roles/DeveloperWrite/bindings -d \'{"scope":{"clusters":{"kafka-cluster":"' + CID + '"}},"resourcePatterns":[{"resourceType":"Topic","name":"orders.","patternType":"PREFIXED"}]}\' >/dev/null   # 起點:svc-orders 有 orders.* 的寫入權(Lab 7 的結果)',
      'bash scripts/conjur.sh up >/dev/null && bash scripts/conjur.sh set-cred svc-orders svc-orders orders-secret-v1   # 起點:Conjur 裡「現在該用的帳號與密碼」= svc-orders / 原密碼',
    ],
    autoAll: ['./demo.sh 18', './scenarios/ch18-cyberark.sh'],
    steps: [
      { t: '18.1 啟動 Conjur 並看 policy:誰(機器身分)能拿什麼(秘密)', defs: true, why: 'scripts/conjur.sh up 會產生資料金鑰、建立帳戶、載入 policy(config/conjur/policy/kafka.yml)並替每個 host 產生 API key。policy 裡:svc-orders 只能讀自己的密碼、opmenu 讀 Alertmanager 帳密、broker 讀主金鑰、rogue-app 有身分但什麼都不能讀。下面同時定義兩個小函式給後面的手動指令用。',
        manual: [R`bash scripts/conjur.sh up
CJ=https://conjur
cjtoken() { hc -X POST --data "$(cat config/conjur/keys/$1.key)" $CJ/authn/demo/host%2Fkafka%2F$1/authenticate | grep -v '^\[HTTP' | base64 -w0; }   # 以 host 的 API key 換 token(8 分鐘有效)
docker exec -i conjur-cli conjur list -k host
docker exec -i conjur-cli conjur list -k variable`],
        ev: 'policy', re: /kafka\/svc-orders\/credential/, expect: 'host:broker、legacy-orders、opmenu、rogue-app、svc-orders;variable:四個秘密(svc-orders 的是 credential)。', tip: 'macOS 的 base64 沒有 -w0,改用 base64 | tr -d "\\n"。' },
      { t: '18.2 管理員把 svc-orders 的 SCRAM 密碼存進 Conjur', why: '正式環境由 CyberArk 管理員在 PVWA 或 CLI 做,應用團隊不碰密碼本身。',
        manual: ['bash scripts/conjur.sh set-cred svc-orders svc-orders orders-secret-v1'], ev: 'admin-set', re: /已寫入 kafka\/svc-orders\/credential/, expect: '已寫入 kafka/svc-orders/credential(帳號 svc-orders)。', tip: '帳號與密碼放在同一個變數(JSON {"u":帳號,"p":密碼}):寫入是單一操作、應用一次取得,輪替時不會有「帳號換了、密碼還沒換」的空檔。若分成兩個變數,應用剛好在空檔裡讀就會拿到不配對的帳密。' },
      { t: '18.3 應用以自己的機器身分取密碼 → 200', why: '兩步:API key 換 token(POST /authn/…/authenticate),再用 token 取秘密(GET /secrets/…)。密碼只回到呼叫者的記憶體;這裡用 -o /dev/null 不把它印出來。',
        manual: [R`T=$(cjtoken svc-orders)
hc -o /dev/null -H "Authorization: Token token=\"$T\"" $CJ/secrets/demo/variable/kafka%2Fsvc-orders%2Fcredential`],
        ev: 'app-fetch', re: /HTTP 200/, expect: '[HTTP 200]。' },
      { t: '18.4 對照:有身分但沒被授權的應用(rogue-app)→ 拿不到', why: 'Conjur 回 404 而不是 403:不透露秘密是否存在。',
        manual: [R`T=$(cjtoken rogue-app)
hc -o /dev/null -H "Authorization: Token token=\"$T\"" $CJ/secrets/demo/variable/kafka%2Fsvc-orders%2Fcredential`],
        ev: 'rogue', re: /HTTP 404/, expect: '[HTTP 404]。' },
      { t: '18.5 對照:錯誤的 API key → 認證就被擋', manual: [R`hc -o /dev/null -X POST --data "wrong-api-key" $CJ/authn/demo/host%2Fkafka%2Fsvc-orders/authenticate`],
        ev: 'bad-key', re: /HTTP 401/, expect: '[HTTP 401]。' },
      { t: '18.6 應用啟動:取密碼 → 在記憶體組連線設定 → 寫入 orders.events', why: '腳本做的事:向 Conjur 取「現在該用的帳號」與密碼、在容器的 /dev/shm(記憶體)寫出連線設定、用 SCRAM 連 broker 寫入;容器結束設定就消失。主機與映像裡沒有密碼檔。正式環境的應用在啟動程式碼裡做同樣的事(或用 Summon 把秘密變成環境變數)。',
        manual: ['bash scripts/app-with-conjur.sh svc-orders orders.events hello-from-conjur'], ev: 'app-start', re: /結果:成功寫入 orders\.events/, expect: '① ② 使用帳號 svc-orders、取得密碼(長度 16 字元;不顯示)→ ③ ④ 結果:成功寫入 orders.events(以 svc-orders 身分)。' },
      { t: '18.7 輪替:改 Kafka 密碼、更新 Conjur,應用重啟就跟上;舊密碼立刻失效', why: 'CyberArk 的 CPM 沒有 Kafka 的平台定義,正式環境由 CPM 自訂平台或排程呼叫同樣的步驟。要零中斷就用 Lab 9 的「新帳號並行」,這裡用直接改密碼示範 Conjur 這段。',
        manual: [R`kc kafka-configs --bootstrap-server $BOOT --command-config /clients/token-bootstrap.properties --alter --add-config 'SCRAM-SHA-512=[password=orders-secret-v2]' --entity-type users --entity-name svc-orders
bash scripts/conjur.sh set-cred svc-orders svc-orders orders-secret-v2
bash scripts/app-with-conjur.sh svc-orders orders.events after-rotate | tail -1
kc kafka-topics --bootstrap-server $BOOT --command-config /clients/scram-svc-orders.properties --list 2>&1 | grep -m1 "Authentication failed"   # 還拿舊密碼的設定檔`],
        ev: 'rotate', re: /成功寫入[\s\S]*(Authentication failed|認證失敗)/, expect: 'Completed updating config → 已寫入 → 結果:成功寫入 → 舊設定檔 Authentication failed。' },
      { t: '18.8 還原密碼(Kafka 與 Conjur 都改回),讓其他 Lab 不受影響', manual: [R`kc kafka-configs --bootstrap-server $BOOT --command-config /clients/token-bootstrap.properties --alter --add-config 'SCRAM-SHA-512=[password=orders-secret-v1]' --entity-type users --entity-name svc-orders
bash scripts/conjur.sh set-cred svc-orders svc-orders orders-secret-v1`], ev: 'restore', re: /Completed[\s\S]*已寫入/, expect: 'Completed updating config;已寫入。' },
      { t: '18.9 零中斷輪替 ⓪:先看安全網——舊帳號沒有任何角色時,腳本拒絕往下做', why: '輪替腳本最怕「做到一半留下半成品」。所以它先確認舊帳號有角色可複製;沒有就中止,什麼都不動(Conjur 也不動)。',
        manual: ['bash scripts/rotate-with-conjur.sh start nobody svc-x 2>&1 | tail -1', 'bash scripts/app-with-conjur.sh svc-orders orders.events abort-check | tail -1   # 確認應用照常拿得到帳密'],
        ev: 'rotate2-abort', re: /沒有任何角色[\s\S]*成功寫入/, expect: '✘ 舊帳號 nobody 沒有任何角色…中止(沒有改任何東西);應用仍成功寫入。' },
      { t: '18.10 零中斷輪替 ①:建新帳號、複製角色、驗證新帳號,才把新帳密一次寫進 Conjur', why: 'Kafka 的 SCRAM 一個帳號只有一組密碼,零中斷只能靠兩個帳號並行(Lab 9)。腳本的順序是:建 svc-orders-v2(密碼隨機)→ 複製舊帳號的全部角色並逐筆檢查 → 驗證新帳號真的連得上、看到的 topic 和舊帳號一模一樣 → 才把新帳密寫進 Conjur。任何一步失敗就回滾新帳號,Conjur 完全沒動,舊帳號照常。',
        manual: ['bash scripts/rotate-with-conjur.sh start svc-orders svc-orders-v2'], ev: 'rotate2-start', re: /Conjur 已指向 svc-orders-v2/, expect: '① 建立 → ② 角色 DeveloperWrite → User:svc-orders-v2 [HTTP 204] → ③ 新舊帳號看到同樣的 N 個 topic → ④ 寫進 Conjur → 結果:Conjur 已指向 svc-orders-v2;svc-orders 仍可用。' },
      { t: '18.11 零中斷輪替 ②:應用逐批重啟,設定不用改,自動改用新帳號;還沒重啟的照常', manual: ['bash scripts/app-with-conjur.sh svc-orders orders.events after-parallel-rotate | tail -2', 'kc kafka-topics --bootstrap-server $BOOT --command-config /clients/scram-svc-orders.properties --list | grep -c "^orders"   # 還沒重啟的應用(舊帳號)'],
        ev: 'rotate2-switch', re: /以 svc-orders-v2 身分[\s\S]*[1-9]/, expect: '重啟的應用:成功寫入(以 svc-orders-v2 身分);舊帳號的設定檔仍列得出 orders topic。' },
      { t: '18.12 零中斷輪替 ③:不直接刪舊帳號,先「隔離」再看 audit', why: '隔離 = 解除舊帳號的全部角色(已存檔、可回復),SCRAM 憑證還留著。為什麼不直接刪?因為 audit 不記錄 orders.* 讀取成功(避免洗版),光看「允許」會漏掉只讀不寫的 consumer;隔離後還在用的人會變成被拒(DENIED),audit 一定記錄。check 只看隔離之後的事件。',
        manual: ['bash scripts/rotate-with-conjur.sh quarantine svc-orders | tail -1', 'sleep 3; bash scripts/rotate-with-conjur.sh check svc-orders 1'], ev: 'rotate2-quarantine', re: /判定:沒有人在用/, expect: '結果:svc-orders 已隔離;「隔離之後的 audit:允許 0 筆、被拒 0 筆」→ 判定:沒有人在用。' },
      { t: '18.13 零中斷輪替 ④:確認沒人用才停用(刪 SCRAM 憑證)', manual: ['bash scripts/rotate-with-conjur.sh finish svc-orders | tail -1', 'kc kafka-topics --bootstrap-server $BOOT --command-config /clients/scram-svc-orders.properties --list 2>&1 | grep -m1 "Authentication failed"', 'bash scripts/app-with-conjur.sh svc-orders orders.events after-finish | tail -1'],
        ev: 'rotate2-finish', re: /已停用[\s\S]*(Authentication failed|認證失敗)[\s\S]*成功寫入/, expect: '舊帳號 svc-orders 已停用 → 舊設定檔 Authentication failed → 新帳號成功寫入。' },
      { t: '18.14 還原:svc-orders 回來、Conjur 指回它、移除 svc-orders-v2', manual: ['bash scripts/rotate-with-conjur.sh restore | tail -1'], ev: 'rotate2-restore', re: /svc-orders 已還原/, expect: '結果:svc-orders 已還原;svc-orders-v2 已移除。' },
      { t: '18.15 如果有人還在用舊帳號:隔離後被抓到,rollback 後恢復', why: '模擬「有一個你不知道的應用還在用舊帳號」:隔離後它的請求被拒,audit 記下 DENIED,check 判定「還有人在用」,你 rollback 把角色綁回去,它就恢復了——沒有任何人被誤傷太久。',
        manual: [R`bash scripts/rotate-with-conjur.sh quarantine svc-orders | tail -1
sleep 4; bash scripts/app-with-conjur.sh svc-orders orders.events still-on-old | tail -1     # 還在用舊帳號的應用
sleep 5; bash scripts/rotate-with-conjur.sh check svc-orders 1 | tail -2
bash scripts/rotate-with-conjur.sh rollback svc-orders | tail -1
sleep 5; bash scripts/app-with-conjur.sh svc-orders orders.events back-to-normal | tail -1`],
        ev: 'rotate2-inuse', re: /被拒絕[\s\S]*還有人在用[\s\S]*已回復[\s\S]*成功寫入/, expect: '隔離後應用:結果:被拒絕 → check:被拒 N 筆、判定:還有人在用 → rollback:角色已回復 → 應用:成功寫入。' },
      { t: '18.16 實驗:只刪 SCRAM 憑證,擋得住已經連著的舊連線嗎?', why: '長連線 producer(svc-orders,每 2 秒寫一筆,共 14 筆)寫到一半,對舊帳號做事。這個實驗回答「為什麼一定要先解除角色」。下面跑兩次:A 先解除角色再刪憑證;B 只刪憑證、角色保留。每次約 50 秒。',
        manual: [R`bash scripts/old-connection-test.sh both | tail -5
bash scripts/rotate-with-conjur.sh restore | tail -1
echo "=== B:只刪憑證、角色保留"
bash scripts/old-connection-test.sh scram-only | tail -5
bash scripts/rotate-with-conjur.sh restore | tail -1`],
        ev: 'oldconn-both', evb: 'oldconn-scram', re: /判定:解除角色就切斷舊連線[\s\S]*判定:只刪 SCRAM 憑證擋不住/, expect: 'A:只寫進約 6 筆,之後都是授權失敗、認證失敗 0 次 → 判定:解除角色就切斷舊連線;B:14 筆全部寫入 → 判定:只刪 SCRAM 憑證擋不住已建立的連線。',
        warn: '重點:SCRAM 只在「建立連線」時驗證(connections.max.reauth.ms 預設 0 = 不重新驗證),所以刪掉憑證只擋得住新連線。要切斷已連著的舊連線,必須解除角色;所以輪替流程一律是「先隔離(解除角色)→ 看 audit → 才刪憑證」。長連線的應用也要在認證或授權失敗時重新向 Conjur 取帳密並重建連線,不能只在啟動時取一次。' },
      { t: '18.17 OP menu:維護模式的帳密改成執行時向 Conjur 取,跳板機上不放帳密檔', why: '設定 OPMENU_ALERTMANAGER_AUTH_CMD(優先於檔案):任何會印出「帳號:密碼」的指令都可以,這裡接 Conjur。沒被授權的身分取不到,維護模式就開不了。',
        manual: [R`cd opmenu
export OPMENU_USER=gary OPMENU_PASS=gary-pw OPMENU_YES=1 OPMENU_TICKET=CHG-2026-0400
export OPMENU_ALERTMANAGER_AUTH_CMD="bash $PWD/../scripts/conjur.sh get-as opmenu opmenu/alertmanager-auth"
./opmenu.sh --run 25 broker1 2 | tee log/maint18.out | tail -1
./opmenu.sh --run 26 "$(grep -o 'silence id=[0-9a-f-]*' log/maint18.out | cut -d= -f2)" | tail -1
OPMENU_ALERTMANAGER_AUTH_CMD="bash $PWD/../scripts/conjur.sh get-as rogue-app opmenu/alertmanager-auth" ./opmenu.sh --run 25 broker1 2 | grep -m1 失敗
cd ..`],
        ev: 'opmenu', re: /維護模式已結束[\s\S]*失敗/, expect: '維護模式已開始 → 維護模式已結束 → 用 rogue-app 的身分:建立 silence 失敗:Unauthorized。' },
      { t: '18.18 設定檔密碼不落地 ①:用 Confluent Secret Protection 加密、主金鑰存進 Conjur', why: '官方功能:設定檔裡的密碼換成加密佔位符,密文放在 security.properties,解密要主金鑰(環境變數 CONFLUENT_SECURITY_MASTER_KEY)。這裡主金鑰直接存進 Conjur,不寫任何檔案。',
        manual: ['bash scripts/secret-protection.sh setup', 'cat certs/security.properties | cut -c1-110'], ev: 'sp-setup', re: /主金鑰已存入 Conjur/, expect: '主金鑰已存入 Conjur;security.properties 裡 ldap.java.naming.security.credentials 是 ENC[…]。' },
      { t: '18.19 設定檔密碼不落地 ②:broker2 啟動前向 Conjur 取主金鑰,解開密文後才連 AD', why: 'docker-compose.cyberark.yml 只覆蓋 broker2:密碼改成佔位符、啟動指令先執行 fetch-secret.py(以 host/kafka/broker 的身分取主金鑰放進環境變數)再啟動。正式環境是 systemd 的包裝腳本(注意:ExecStartPre 設的環境變數不會傳給 ExecStart)。驗證:生效設定裡只有佔位符、環境裡沒有明文、人仍能經 broker2 登入(表示 AD 查詢密碼解對了)。',
        manual: [R`bash scripts/secret-protection.sh apply
bash scripts/secret-protection.sh show
hc -o /dev/null -u gary:gary-pw https://broker2:8092/security/1.0/authenticate`],
        ev: 'sp-apply', re: /securepass[\s\S]*HTTP 200/, expect: 'master key fetched from Conjur;設定裡是 ${securepass:…};環境裡 0 處明文;[HTTP 200]。', warn: '取不到主金鑰 broker 就不會啟動(這是刻意的);所以 Conjur 的可用性要跟 broker 一樣高,正式環境要有 Conjur 的高可用或在主機上留備援方案。' },
      { t: '18.20 設定檔密碼不落地 ③:同一件事改用 CyberArk 官方工具 summon', why: 'summon + summon-conjur 是 CyberArk 的開源工具:summon 以主機身分(/etc/conjur.conf + /etc/conjur.identity)向 Conjur 取 secrets.yml 列的秘密,注入成子程序的環境變數後執行啟動程式;取不到就不執行。不用自己寫取秘密的腳本,正式環境的 systemd 只要一行:ExecStart=/usr/local/bin/summon -p summon-conjur -f /etc/kafka/secrets.yml /usr/bin/kafka-server-start /etc/kafka/server.properties。驗證:程序樹 PID 1 是 summon、java 是它的子程序;其餘與上一步相同。',
        manual: [R`bash scripts/secret-protection.sh summon-setup
bash scripts/secret-protection.sh apply-summon
docker exec broker2 ps -eo pid,ppid,comm | head -3
bash scripts/secret-protection.sh show
hc -o /dev/null -u gary:gary-pw https://broker2:8092/security/1.0/authenticate`],
        ev: 'sp-apply-summon', re: /summon[\s\S]*java[\s\S]*HTTP 200/, expect: '啟動指令是 summon …;ps 裡 PID 1 = summon、java 的 PPID = 1;設定裡是 ${securepass:…};環境裡 0 處明文;[HTTP 200]。', warn: '第一次執行 summon-setup 會從 GitHub(cyberark 官方 release)下載 summon 與 summon-conjur 共約 10 MB,並比對官方 SHA256SUMS;放在 config/conjur/bin/,不進版本庫。' },
      { t: '18.21 還原 broker2(其他 Lab 不依賴 Conjur)', manual: ['bash scripts/secret-protection.sh revert'], ev: 'sp-revert', re: /已回到原本設定/, expect: 'broker2 已回到原本設定。' },
      { t: '18.22 稽核:Conjur 記錄誰取了什麼', why: '每一次取秘密與被拒都有紀錄,主體是機器身分;正式環境把這些送進 SIEM。',
        manual: [R`docker logs conjur-server 2>&1 | grep -E "demo:host:kafka/[a-z-]+ (tried to fetch|fetched)" | sed -E 's/^.*(demo:host:kafka)/\1/' | sort | uniq -c | sort -rn | head`],
        ev: 'audit', re: /rogue-app tried to fetch/, expect: 'svc-orders fetched …password;opmenu fetched …alertmanager-auth;broker fetched …master-key;rogue-app tried to fetch …: Forbidden。' },
    ],
  },
];
