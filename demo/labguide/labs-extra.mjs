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
      { t: '18.12 零中斷輪替 ③:不直接停用舊帳號,先「隔離」再看 audit', why: '隔離 = 解除舊帳號的全部角色(已存檔、可回復),SCRAM 憑證還留著。為什麼不直接刪?因為 audit 不記錄 orders.* 讀取成功(避免洗版),光看「允許」會漏掉只讀不寫的 consumer;隔離後還在用的人會變成被拒(DENIED),audit 一定記錄。check 只看隔離之後的事件。',
        manual: ['bash scripts/rotate-with-conjur.sh quarantine svc-orders | tail -1', 'sleep 3; bash scripts/rotate-with-conjur.sh check svc-orders 1'], ev: 'rotate2-quarantine', re: /判定:沒有人在用/, expect: '結果:svc-orders 已隔離;「隔離之後的 audit:允許 0 筆、被拒 0 筆」→ 判定:沒有人在用。' },
      { t: '18.13 零中斷輪替 ④:確認沒人用才停用(停用 SCRAM 憑證)', manual: ['bash scripts/rotate-with-conjur.sh finish svc-orders | tail -1', 'kc kafka-topics --bootstrap-server $BOOT --command-config /clients/scram-svc-orders.properties --list 2>&1 | grep -m1 "Authentication failed"', 'bash scripts/app-with-conjur.sh svc-orders orders.events after-finish | tail -1'],
        ev: 'rotate2-finish', re: /已停用[\s\S]*(Authentication failed|認證失敗)[\s\S]*成功寫入/, expect: '舊帳號 svc-orders 已停用 → 舊設定檔 Authentication failed → 新帳號成功寫入。' },
      { t: '18.14 還原:svc-orders 回來、Conjur 指回它、移除 svc-orders-v2', manual: ['bash scripts/rotate-with-conjur.sh restore | tail -1'], ev: 'rotate2-restore', re: /svc-orders 已還原/, expect: '結果:svc-orders 已還原;svc-orders-v2 已移除。' },
      { t: '18.15 如果有人還在用舊帳號:隔離後被抓到,rollback 後恢復', why: '模擬「有一個你不知道的應用還在用舊帳號」:隔離後它的請求被拒,audit 記下 DENIED,check 判定「還有人在用」,你 rollback 把角色綁回去,它就恢復了——沒有任何人被誤傷太久。',
        manual: [R`bash scripts/rotate-with-conjur.sh quarantine svc-orders | tail -1
sleep 4; bash scripts/app-with-conjur.sh svc-orders orders.events still-on-old | tail -1     # 還在用舊帳號的應用
sleep 5; bash scripts/rotate-with-conjur.sh check svc-orders 1 | tail -2
bash scripts/rotate-with-conjur.sh rollback svc-orders | tail -1
sleep 5; bash scripts/app-with-conjur.sh svc-orders orders.events back-to-normal | tail -1`],
        ev: 'rotate2-inuse', re: /被拒絕[\s\S]*還有人在用[\s\S]*已回復[\s\S]*成功寫入/, expect: '隔離後應用:結果:被拒絕 → check:被拒 N 筆、判定:還有人在用 → rollback:角色已回復 → 應用:成功寫入。' },
      { t: '18.16 實驗:只停用 SCRAM 憑證,擋得住已經連著的舊連線嗎?', why: '長連線 producer(svc-orders,每 2 秒寫一筆,共 14 筆)寫到一半,對舊帳號做事。這個實驗回答「為什麼一定要先解除角色」。下面跑兩次:A 先解除角色再停用憑證;B 只停用憑證、角色保留。每次約 50 秒。',
        manual: [R`bash scripts/old-connection-test.sh both | tail -5
bash scripts/rotate-with-conjur.sh restore | tail -1
echo "=== B:只停用憑證、角色保留"
bash scripts/old-connection-test.sh scram-only | tail -5
bash scripts/rotate-with-conjur.sh restore | tail -1`],
        ev: 'oldconn-both', evb: 'oldconn-scram', re: /判定:解除角色就切斷舊連線[\s\S]*判定:只停用 SCRAM 憑證擋不住/, expect: 'A:只寫進約 6 筆,之後都是授權失敗、認證失敗 0 次 → 判定:解除角色就切斷舊連線;B:14 筆全部寫入 → 判定:只停用 SCRAM 憑證擋不住已建立的連線。',
        warn: '重點:SCRAM 只在「建立連線」時驗證(connections.max.reauth.ms 預設 0 = 不重新驗證),所以停用憑證只擋得住新連線。要切斷已連著的舊連線,必須解除角色;所以輪替流程一律是「先隔離(解除角色)→ 看 audit → 才停用憑證」。長連線的應用也要在認證或授權失敗時重新向 Conjur 取帳密並重建連線,不能只在啟動時取一次。' },
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
  {
    id: 'ch19', n: 19, title: '(進階)帳號被偷之後:失效、告警、限速、限連線、鎖定', time: '20 分',
    goal: '第 18 章發現「只停用 SCRAM 憑證,已連著的舊連線不會斷」。這個 Lab 假設一個帳號已經被偷,逐項證明平台怎麼讓它撐不久、灌不大、被發現、而且不會連累管理員:① SASL 重新認證讓被停用的帳號在固定時間內被切斷;② 認證失敗暴增會觸發告警並送到 Alertmanager;③ TLS 只收 1.2/1.3 與 AEAD 套件;④ 單一來源的連線數上限;⑤ client quota 限制吞吐量;⑥ AD 的帳戶鎖定原則是雙面刃(攻擊者可以故意把管理員鎖住),以及緊急路徑不受影響。',
    pre: ['Lab 0 完成(含 Control Center 與 Prometheus / Alertmanager:docker compose --profile c3 …)。', '重新認證間隔(60 秒)、TLS 套件限定、telemetry 的認證失敗指標、Prometheus 規則 config/c3/security_rules.yml、AD 的密碼政策(ppolicy)都已經在 compose 與 config 裡(demo 已套用);鎖定預設關閉,第 19.7 才打開、19.8 關回去。'],
    autoAll: ['./demo.sh 19', './scenarios/ch19-stolen-account.sh'],
    steps: [
      { t: '19.1 失效 ①:基準設定——SASL 連線每 60 秒重新認證一次', why: '預設 connections.max.reauth.ms = 0,代表連線建立後就永遠有效(第 18 章實驗看到的)。設成非 0 之後,broker 會要求 client 定期重新認證;帳號被停用,下一次重新認證就失敗、連線被切斷。demo 設 60 秒讓實驗看得到效果;正式環境建議 1 小時,依 client 數量與 SCRAM 驗證負載評估。',
        manual: [R`docker exec broker1 grep connections.max.reauth.ms /etc/kafka/kafka.properties
docker exec broker2 grep connections.max.reauth.ms /etc/kafka/kafka.properties`],
        ev: 'reauth-baseline', re: /reauth\.ms=60000[\s\S]*reauth\.ms=60000/, expect: '兩台 broker 都是 listener.name.client.connections.max.reauth.ms=60000。',
        warn: '這個設定不能動態改:kafka-configs 對 connections.max.reauth.ms 回 Cannot update these configs dynamically;per-listener 的寫法(listener.name.client.…)會被接受,但實測對連線不生效。要改只能改 compose / server.properties 再滾動重啟 broker。' },
      { t: '19.2 失效 ②:停用一個「連著的」帳號,舊連線還能寫幾筆?', why: '對照第 18 章:當時只停用 SCRAM 憑證,舊連線 14 筆全寫入。現在同樣的動作(角色保留、只停用憑證),在下一次重新認證時失敗,連線被切斷。腳本用臨時帳號 svc-reauth,每 2 秒寫 1 筆、共 45 筆,第 10 秒刪它的憑證。',
        manual: ['bash scripts/reauth-test.sh run'],
        ev: 'reauth-run', re: /判定:60 秒內舊連線被切斷/, expect: '寫進 topic 的筆數少於 45;producer 的第一個錯誤是 Authentication failed during re-authentication;判定:60 秒內舊連線被切斷。',
        warn: '為什麼「停用」是覆寫成隨機密碼、不是刪除憑證:實測(CP 8.3.2、KRaft)刪除 SCRAM 憑證之後,下一次重啟 broker 會失敗(broker 啟動時向自己做 SCRAM 認證被拒);全新叢集可 100% 重現,改成覆寫隨機密碼就正常。已經刪過的帳號,事後重新建立再重啟 broker 即可救回。內部通道改成 mTLS(Lab 9.5)後 broker 不會再起不來,但重啟後 CLIENT 埠的 SCRAM 帳號會全部登入失敗(實測),所以這條規則仍然必要。這是 Apache Kafka 的已知 bug KAFKA-20774(ScramDelta.apply() 在 REMOVE 對象不存在時丟掉整組 SCRAM 使用者;修復版 4.5.0 尚未發行,CP 8.3.2 的 Kafka 4.3.x 受影響)。在升到含修復的版本之前,不要用 --delete-config 刪 SCRAM 憑證(RUNBOOK 第 19 章有重現步驟、對照表與 bug 連結)。 重新認證只擋「憑證」。這是第二道防線:要立刻切斷,仍然是解除角色(第 18 章的隔離流程);重新認證確保即使忘了,最慢也在設定的間隔內失效。' },
      { t: '19.3 發現:連續認證失敗 → 告警送到 Alertmanager', why: 'broker 的 telemetry 會送 failed_authentication_total 到 Prometheus(docker-compose.yml 的 metrics.include 已加這個指標)。規則 KafkaAuthFailuresBurst:5 分鐘內失敗超過 3 次就觸發。這裡故意製造 5 次錯誤登入(SCRAM 錯誤密碼 3 次、PLAIN 錯誤密碼 2 次),等規則評估(每 60 秒一次)。',
        manual: [R`for i in 1 2 3; do kc kafka-topics --bootstrap-server $BOOT --command-config /clients/scram-svc-orders-wrong.properties --list >/dev/null 2>&1; done
for i in 1 2; do kc kafka-topics --bootstrap-server $BOOT --command-config /clients/plain-yujie-wrong.properties --list >/dev/null 2>&1; done
for i in $(seq 1 24); do r=$(hc -u c3:prom-pw https://prometheus:9090/api/v1/alerts | head -1); echo "$r" | grep -q KafkaAuthFailuresBurst && break; sleep 15; done
echo "Prometheus: $(echo "$r" | grep -o '"alertname":"KafkaAuthFailuresBurst"\|"state":"[a-z]*"\|"listener":"[A-Z]*"' | tr '\n' ' ')"
sleep 20
echo "Alertmanager: $(hc -u c3:am-pw https://alertmanager:9093/api/v2/alerts | head -1 | grep -o '"summary":"[^"]*"' | head -1)"`],
        ev: 'alert', re: /"state":"firing"/, expect: 'Prometheus:KafkaAuthFailuresBurst、listener CLIENT、state firing;Alertmanager:摘要「5 分鐘內 SASL 認證失敗超過 3 次(listener CLIENT)」。需要 2 到 4 分鐘。',
        warn: '重點是「失敗次數的突增」而不是單次失敗:應用拿到舊密碼、攻擊者猜密碼,都會讓這個指標上升。正式環境把門檻改成客戶的基準值,並把告警轉到 SIEM 或值班群組。telemetry 的 metrics.include 每個名稱後面要加 (?!.*delta).*,同名的 delta 型態 Prometheus 不收,整批會被拒(連原本的監控指標也跟著丟)——實測踩過。' },
      { t: '19.4 傳輸:TLS 只收 1.2 / 1.3 與 AEAD 套件', why: '未設定前,broker 的 CLIENT listener 接受 ECDHE-RSA-AES128-SHA(CBC + SHA-1)這類弱套件。現在 ssl.enabled.protocols=TLSv1.3,TLSv1.2、ssl.cipher.suites 只列 GCM / ChaCha20。用 openssl 指定套件逐一嘗試。',
        manual: [R`for c in ECDHE-RSA-AES256-GCM-SHA384 ECDHE-RSA-AES128-SHA AES128-SHA; do echo "--- $c"; docker run --rm --network $NET --entrypoint sh alpine/openssl -c "echo | openssl s_client -connect broker1:9094 -tls1_2 -cipher $c 2>&1 | grep -E 'Cipher is|alert handshake' | head -1 | cut -c1-110"; done
echo "--- TLS 1.3"; docker run --rm --network $NET --entrypoint sh alpine/openssl -c "echo | openssl s_client -connect broker1:9094 -tls1_3 2>&1 | grep 'Cipher is' | head -1"`],
        ev: 'tls', re: /AES256-GCM-SHA384[\s\S]*(AES128-SHA\n[^\n]*alert handshake failure|AES128-CBC-SHA1 → 拒絕)/, expect: 'AES256-GCM 成功(Cipher is ECDHE-RSA-AES256-GCM-SHA384);AES128-SHA(CBC)與 RSA 金鑰交換被拒(alert handshake failure);TLS 1.3 成功。',
        warn: '這只設在 Kafka listener(9094 / 9092)。MDS(Jetty,8091)本來就拒絕 CBC 套件(實測);其他元件(REST Proxy、C3、Prometheus)的套件限定要各自設定,這裡沒有做。' },
      { t: '19.5 限連線:單一來源 IP 最多 2 條', why: '被偷的憑證可能被大量並行連線拿來耗盡 broker 的連線數。max.connections.per.ip 可以動態設定(不必重啟),超過的連線被 broker 直接拒絕。這裡設 2,從同一個來源開 4 條,看 broker 日誌,做完移除。',
        manual: [R`kc kafka-configs --bootstrap-server $BOOT --command-config /clients/token-bootstrap.properties --entity-type brokers --entity-default --alter --add-config max.connections.per.ip=2
sleep 3
docker run --rm --network $NET --entrypoint sh alpine/openssl -c 'for i in 1 2 3 4; do (openssl s_client -connect broker1:9094 -quiet </dev/null >/dev/null 2>&1 &); sleep 0.7; done; sleep 3'
echo "broker1 日誌:被拒絕的連線 $(docker logs broker1 --since 1m 2>&1 | grep -c 'Rejected connection.*maximum of 2') 條"
kc kafka-configs --bootstrap-server $BOOT --command-config /clients/token-bootstrap.properties --entity-type brokers --entity-default --alter --delete-config max.connections.per.ip`],
        ev: 'connlimit', re: /被拒絕的連線 [1-9]/, expect: '第三、四條連線被拒絕(日誌:Rejected connection … address already has the configured maximum of 2.0 connections);最後移除設定。',
        warn: 'kafka-configs 的 --entity-type ips 只接受連線速率配額(connection_creation_rate),不接受 max.connections.per.ip;後者要設在 brokers 層級。正式環境要注意:同一台跳板機、同一個 NAT 後面的所有 client 會共用一個來源 IP,上限不能設得太小。' },
      { t: '19.6 限速:client quota', why: '帳號被偷後,攻擊者能灌多少流量?producer_byte_rate 是以使用者(principal)為單位的上限。腳本用臨時帳號 svc-quota,同一個動作(寫 2500 筆 × 1 KB)先不限速、再套用 100 KB/s 比較吞吐量,做完移除配額、帳號與角色。',
        manual: ['bash scripts/quota-test.sh'],
        ev: 'quota', re: /判定:限速後吞吐量降為原來的 1\//, expect: '不限速約 2000 到 3000 筆/秒;限速後約 160 筆/秒(約 100 KB/s);判定:限速後吞吐量降為原來的 1/N。',
        warn: '配額是以「時間窗」計算,寫入量太小(例如幾百筆)會在窗內用完而看不出效果——實測 400 筆沒被限速,2500 筆才明顯。限速是讓影響變慢、讓告警有時間處理,不是阻止寫入;要阻止仍然是解除角色。' },
      { t: '19.7 鎖定 ①:AD 的帳戶鎖定原則是雙面刃', why: '多數 AD 都有「連續 N 次登入失敗就鎖定」。對一般使用者是好事,但攻擊者可以故意對 GARY 亂試密碼,把管理員鎖在外面(用鎖定當作阻斷服務)。demo 用 OpenLDAP 的 ppolicy 模擬(連續 5 次失敗鎖 60 秒)。同一個 AD 帳號被鎖,MDS、C3、Kafka 的 PLAIN 登入全部失敗;但機器帳號(SCRAM)與緊急路徑(bootstrap 憑證)不經過 AD,不受影響。',
        manual: [R`bash scripts/ad-lockout.sh on
for i in 1 2 3 4 5 6; do hc -o /dev/null -u gary:bad-$i $MDS/security/1.0/authenticate | tail -1; done
echo "GARY 用對的密碼:"; hc -o /dev/null -u gary:gary-pw $MDS/security/1.0/authenticate | tail -1
bash scripts/ad-lockout.sh status GARY
echo "緊急路徑(bootstrap 憑證)列 topic:"; kc kafka-topics --bootstrap-server $BOOT --command-config /clients/token-bootstrap.properties --list 2>&1 | grep -v "^WARNING\|SLF4J" | head -2`],
        ev: 'lockout-dos', re: /GARY:已鎖定/, expect: '6 次錯誤都是 401;用對的密碼也是 401;狀態:GARY 已鎖定,約 60 秒後自動解除;bootstrap 憑證仍能列出 topic。',
        warn: '設計含意:(1) 高權限 AD 帳號最容易被當成鎖定攻擊的目標,要和客戶確認 AD 的鎖定原則(次數、時間、是否由管理員解鎖);(2) 緊急路徑(bootstrap 憑證)要保留,而且要保護好;(3) 在 MDS 前面的 F5 限制每個來源的登入速率,才能不讓攻擊者輕易觸發鎖定。' },
      { t: '19.8 鎖定 ②:解鎖與恢復', why: '兩種恢復方式:管理員解鎖(對應 AD 的「解除鎖定帳戶」),或等鎖定時間過去自動解除。這裡用管理員解鎖,GARY 馬上恢復;最後把鎖定關回去,其他 Lab 不受影響。',
        manual: [R`bash scripts/ad-lockout.sh unlock GARY
echo "GARY 用對的密碼:"; hc -o /dev/null -u gary:gary-pw $MDS/security/1.0/authenticate | tail -1
bash scripts/ad-lockout.sh off
bash scripts/ad-lockout.sh status GARY`],
        ev: 'lockout-recover', re: /HTTP 200/, expect: '已解鎖;GARY 用對的密碼 [HTTP 200];鎖定已關閉;GARY 未鎖定。' },
      { t: '19.9 已知 bug:刪除 SCRAM 帳號後重啟 broker,所有 SCRAM 登入失敗(KAFKA-20774)', why: '這就是為什麼整本手冊「停用帳號」都是覆寫隨機密碼、不用 --delete-config。Apache Kafka 的 ScramDelta.apply() 在重放 metadata 時,遇到對象不在目前 image 裡的 REMOVE 紀錄,會把整個 SCRAM 機制的使用者表丟掉(連 kafka-broker 這種應該存在的帳號也消失);修復在 Kafka 4.5.0,尚未發行,CP 8.3.2 的 Kafka 4.3.x 受影響。實驗:新建一個帳號再刪掉,重啟 broker1,svc-orders 用 SCRAM 登入 broker1 失敗(沒重啟的 broker2 正常);把被刪的帳號重新建立,再重啟 broker1,恢復。內部通道已改 mTLS(Lab 9.5),所以 broker 本身起得來;改之前 broker 會直接起不來。',
        manual: ['bash scripts/scram-delete-bug.sh'],
        ev: 'scram-bug', re: /判定:(已重現 KAFKA-20774|這次沒有重現)/, expect: '全新叢集:② 重啟後 svc-orders 登入 broker1 失敗、broker2 成功;③ 重建帳號再重啟後 broker1 成功;判定:已重現 KAFKA-20774…。跑過很多章節的環境可能是「判定:這次沒有重現」(bug 取決於 metadata 重放狀態),兩種都屬正常。約 3 到 4 分鐘。',
        warn: '對客戶的說法:升到含修復的版本前,不要用 --delete-config 刪 SCRAM 帳號;停用 = 覆寫隨機密碼 + 解除 role binding;已經刪過就重建同名帳號再滾動重啟。對不存在的帳號執行刪除也會觸發(本專案舊版 reset.sh 就是這樣中的)。bug 連結與對照表在 RUNBOOK 第 19 章。' },
    ],
  },
  {
    id: 'ch20', n: 20, title: '(進階)Schema Registry 與欄位級加密(CSFLE):同一套授權,與授權限制', time: '15 分',
    goal: '前面的 Lab 管 Kafka 的 topic 與資料;這個 Lab 把 Schema Registry(schema 與資料合約)納入同一套身分與授權,並檢查欄位級加密(CSFLE)能不能在這個環境驗證。證明四件事:① Schema Registry 的 REST 要帳密,授權由 MDS 依 AD 群組判斷(不另外維護一套帳號);② subject 的權限跟群組走:orders-write 只能碰 orders. 開頭的 subject;③ 加密金鑰(KEK)的管理權限只給 security 群組,一般開發者只能讀、沒有 role 的人連讀都不行;④ 欄位級加密本身需要企業版加上 CSFLE 加購授權——試用授權註冊帶加密規則的 schema 會被拒(402),所以加密與解密在這個環境「沒有驗證」。',
    pre: ['Lab 0 完成;Lab 3 的 AD 群組(orders-write 有 yujie,topic-admin、security 有 gary)。', 'Schema Registry 是 profile sr 的一個容器(約 768 MB 記憶體),本 Lab 第一步會啟動;它用 client 憑證(CN=schema-registry)向 MDS 換 token 連 Kafka,與 REST Proxy 同一種做法。SR 需要的授權(_schemas、_dek_registry 開頭的 topic、SR 叢集範圍的 SecurityAdmin 等)由 scripts/sr-setup.sh 一次補齊。'],
    autoAll: ['./demo.sh 20', './scenarios/ch20-schema-registry.sh'],
    steps: [
      { t: '20.1 啟動 Schema Registry 並完成授權', why: '兩件事:讓 SR 自己能存取 Kafka(它的身分是憑證 CN=schema-registry,不是 AD 帳號),以及依 AD 群組給人授權。SR 在 compose 裡要開三個 resource extension:安全(RBAC)、DEK Registry(KEK / DEK 管理)、RuleSet(資料合約的規則)。少一個就會有不同的問題,見下面的警告。',
        manual: ['bash scripts/sr-setup.sh'],
        ev: 'sr-setup', re: /就緒/, expect: '授權逐項 [HTTP 204];Schema Registry Healthy;最後印「就緒(gary 可列 KEK)」。',
        warn: '實測踩到的坑(都已在 compose 與 sr-setup.sh 處理):① 只開 HTTPS 時要設 inter.instance.protocol=https,否則啟動失敗;② 啟動前檢查要有 CUB_CLASSPATH(含 confluent-security 的 jar),否則找不到 TokenCertificateLoginCallbackHandler;③ DEK Registry 要自己的 topic(_dek_registry_keys),SR 的身分要有 _dek_registry 開頭的 ResourceOwner,否則啟動失敗;④ 要開 dek.registry.rbac.enable=true,否則 KEK 端點對所有人 403(日誌:Couldn\'t find a corresponding operation to authorize);⑤ SR 的身分要有 SR 叢集範圍的 SecurityAdmin 才能代使用者向 MDS 查授權,否則 KEK 端點回 500;⑥ 沒有開 RuleSet extension 時,註冊帶規則的 schema 會「默默丟掉規則、不報錯」(第 20.5 說明為什麼危險)。' },
      { t: '20.2 認證:不帶帳密與密碼錯誤都被擋', why: 'Schema Registry 的 REST 和 MDS、REST Proxy 一樣:不帶帳密 401、密碼錯 401。帳密就是 AD 帳密(Basic),SR 把它交給 MDS 驗證,SR 自己不存任何帳號。',
        manual: [R`hc https://schema-registry:8081/subjects
hc -u gary:bad https://schema-registry:8081/subjects
hc -u gary:gary-pw https://schema-registry:8081/subjects`],
        ev: 'sr-auth', re: /HTTP 401\][\s\S]*HTTP 401\][\s\S]*HTTP 200\]/, expect: '不帶帳密 [HTTP 401];密碼錯 [HTTP 401];gary 正確 [HTTP 200]。' },
      { t: '20.3 subject 授權:跟著 AD 群組走', why: 'topic-admin(gary)對所有 subject 是 ResourceOwner;orders-write(yujie)只對 orders. 開頭的 subject 有讀寫。所以 yujie 可以註冊 orders.events-value,註冊 payments.events-value 被拒;列出 subject 時,每個人只看到自己有權限的;沒有任何群組的 ming 什麼都看不到。',
        manual: [R`J='Content-Type: application/vnd.schemaregistry.v1+json'
ORDER_BODY='{"schemaType":"AVRO","schema":"{\"type\":\"record\",\"name\":\"Order\",\"namespace\":\"demo\",\"fields\":[{\"name\":\"id\",\"type\":\"string\"},{\"name\":\"amount\",\"type\":\"int\"},{\"name\":\"card_no\",\"type\":\"string\",\"confluent:tags\":[\"PII\"]}]}"}'
hc -u gary:gary-pw -X POST -H "$J" -d "$ORDER_BODY" https://schema-registry:8081/subjects/payments.events-value/versions | tail -1
hc -u yujie:yujie-pw -X POST -H "$J" -d "$ORDER_BODY" https://schema-registry:8081/subjects/orders.events-value/versions | tail -1
hc -u yujie:yujie-pw -X POST -H "$J" -d "$ORDER_BODY" https://schema-registry:8081/subjects/payments.events-value/versions | tail -1
echo "gary 列 subject:"; hc -u gary:gary-pw https://schema-registry:8081/subjects
echo "yujie 列 subject:"; hc -u yujie:yujie-pw https://schema-registry:8081/subjects
echo "ming 列 subject:"; hc -u ming:ming-pw https://schema-registry:8081/subjects`],
        ev: 'sr-subject', re: /HTTP 403\][\s\S]*\["orders\.events-value"\]\n\[HTTP 200\]|判定:yujie 只能碰 orders/, expect: 'gary 註冊 payments 200;yujie 註冊 orders 200;yujie 註冊 payments [HTTP 403];gary 看到兩個 subject;yujie 只看到 ["orders.events-value"];ming 看到 []。',
        tip: '這個 schema 的 card_no 欄位標了 PII(Avro 的 confluent:tags)。標籤本身不加密任何東西——它只是讓「規則」知道要加密哪些欄位。' },
      { t: '20.4 KEK 授權:誰能建金鑰、誰能讀', why: 'KEK(key encryption key)是欄位加密的根。資源名稱是 Kek:<名稱>,授權也走 role:security 群組(gary)是 ResourceOwner,可以建;orders-write(yujie)只被授權讀 orders-kek,建別的 KEK 被拒;沒有任何 role 的 ming 連讀都被拒。這裡用 local-kms(Confluent 提供的「僅供測試」KMS 型態),正式環境要接 KMS / HSM。',
        manual: [R`J='Content-Type: application/vnd.schemaregistry.v1+json'
echo "gary 建立 orders-kek(200 = 新建,409 = 已存在):"; hc -u gary:gary-pw -X POST -H "$J" -d '{"name":"orders-kek","kmsType":"local-kms","kmsKeyId":"demo-local-key","shared":false,"doc":"CSFLE demo (local-kms)"}' https://schema-registry:8081/dek-registry/v1/keks | tail -1
echo "yujie 建立 x-kek:"; hc -u yujie:yujie-pw -X POST -H "$J" -d '{"name":"x-kek","kmsType":"local-kms","kmsKeyId":"k","shared":false}' https://schema-registry:8081/dek-registry/v1/keks
echo "yujie 讀 orders-kek:"; hc -u yujie:yujie-pw https://schema-registry:8081/dek-registry/v1/keks/orders-kek
echo "ming 讀 orders-kek:"; hc -u ming:ming-pw https://schema-registry:8081/dek-registry/v1/keks/orders-kek`],
        ev: 'sr-kek', re: /denied operation Register on Kek[\s\S]*"name":"orders-kek"[\s\S]*denied operation Read on Kek|判定:只有被授權的人能建或讀 KEK/, expect: 'yujie 建 x-kek:User is denied operation Register on Kek,403;yujie 讀 orders-kek:回 KEK 內容 200;ming 讀:User is denied operation Read on Kek,403。',
        warn: '金鑰的「解密能力」不由 RBAC 控制:官方文件寫明,能不能解開 DEK 取決於 KMS(雲端 KMS 的 IAM、Vault 的 token 等),不是 Confluent 的 role。RBAC 只管「誰能建、改、讀 KEK 的中繼資料」。本機的 local-kms 把金鑰衍生自一個環境變數(LOCAL_SECRET),任何拿到這個值的 client 都能解密,所以只能拿來測試。' },
      { t: '20.5 欄位級加密(CSFLE):授權限制,這個環境無法驗證加密與解密', why: '同一份 schema 加上 ENCRYPT 規則(PII 標籤的欄位用 orders-kek 加密)去註冊。官方文件的 CSFLE 屬於企業版再加購授權的功能。demo 用的是試用授權,註冊時被拒絕:402「Both enterprise and add-on CSFLE licenses are required」。',
        manual: [R`J='Content-Type: application/vnd.schemaregistry.v1+json'
ORDER_ENC_BODY='{"schemaType":"AVRO","schema":"{\"type\":\"record\",\"name\":\"Order\",\"namespace\":\"demo\",\"fields\":[{\"name\":\"id\",\"type\":\"string\"},{\"name\":\"amount\",\"type\":\"int\"},{\"name\":\"card_no\",\"type\":\"string\",\"confluent:tags\":[\"PII\"]}]}","ruleSet":{"domainRules":[{"name":"encryptPII","kind":"TRANSFORM","type":"ENCRYPT","mode":"WRITEREAD","tags":["PII"],"params":{"encrypt.kek.name":"orders-kek"},"onFailure":"ERROR,ERROR"}]}}'
hc -u gary:gary-pw -X POST -H "$J" -d "$ORDER_ENC_BODY" https://schema-registry:8081/subjects/orders.events-value/versions`],
        ev: 'sr-csfle', re: /add-on CSFLE licenses are required/, expect: '{"error_code":40201,"message":"Both enterprise and add-on CSFLE licenses are required."} [HTTP 402]。',
        warn: '三個重點:① 沒有驗證:ENCRYPT 規則的實際加密、解密、金鑰輪替、效能,以及 KMS 對接(AWS / Azure / GCP / HashiCorp Vault 是官方支援的型態;沒有看到 CyberArk Conjur 或其他地端 KMS 的內建型態,地端要用自訂 KMS driver 或 Vault),都要在有授權的環境另外驗。② 要評估授權:企業版之外的加購授權,屬商務問題,不是技術設定。③ 危險的靜默失敗(測試時觀察到):如果 Schema Registry 沒有開 RuleSet extension,註冊帶規則的 schema 不會報錯,而是默默丟掉規則;之後 producer 照常寫入,卡號以明文落在 topic 裡(用一般 console consumer 讀原始位元組就看得到)。所以上線前一定要用「讀原始位元組」的方式確認欄位真的是密文,不能只看 producer 沒報錯。' },
      { t: '20.6 上線前的檢查習慣:讀 topic 的原始位元組,確認欄位到底有沒有被加密', why: '不要只看 producer 沒報錯。yujie 用 Avro(orders.events-value v1)寫一筆含卡號的訂單,再以一般 console consumer(bootstrap 身分)讀原始位元組找卡號。這個環境會看到明文——因為沒有 CSFLE 授權、規則不存在;正式環境若看到明文,就代表加密規則沒生效(例如 20.1 警告裡的靜默失敗)。',
        manual: ['bash scripts/sr-raw-check.sh'],
        ev: 'sr-raw', re: /判定:topic 裡的卡號是明文/, expect: '① 寫入完成(producer 沒有報錯);② od -c 看得到卡號字串;判定:topic 裡的卡號是明文。',
        warn: '把這個檢查做成上線前與每次改 schema 規則後的固定步驟;有授權的環境應該看到密文(base64 的 ciphertext),看到明文就是事故。' },
    ],
  },
];
