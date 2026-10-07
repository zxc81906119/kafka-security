// Lab 手冊內容(資料驅動):build.mjs 產生 Word;verify.mjs 用同一份資料實際執行「手動指令」驗證正確性。
// step 欄位:t 標題;why 說明;ui 介面操作步驟(陣列);uiEq 不想點介面時的等效指令(驗證時也用它取代介面);
//           manual 純手動指令;auto 專案包好的指令;ev 取哪個證據 log 當「實際輸出」;re 驗證用正規式;
//           expect 預期結果說明;imgs [[相對 evidence 的路徑, 圖說]];warn/tip 提示框
const R = String.raw;
export const CID = 'XyZBQ3-GTvKH2qNfP7X33A';

// 每個終端機都要貼的「手動模式」輔助函式(完全不依賴專案腳本)
export const SETUP = R`cd <你的路徑>/untitled6/demo
export MSYS_NO_PATHCONV=1                 # Git Bash 專用:避免路徑被轉換(Linux/macOS 可省略)
export D="$(pwd -W 2>/dev/null || pwd)"   # Windows 取得 C:/... 路徑;Linux/macOS 為 pwd
export NET=cpsec_default                  # docker compose 建立的網路名稱
BOOT=broker1:9094                         # 供「人與服務」連線的 CLIENT listener

# kc:在 demo 網路內執行 Kafka CLI(使用 cp-server 映像內的工具)
kc() { docker run --rm -i --network $NET -v "$D/certs:/etc/kafka/secrets:ro" -v "$D/config/clients:/clients:ro" \
  -e KAFKA_OPTS="" -e KAFKA_HEAP_OPTS="-Xmx256m" --entrypoint "$1" confluentinc/cp-server:8.3.2 "${'$'}{@:2}"; }

# hc:在 demo 網路內執行 curl(信任 demo CA;結尾印出 HTTP 狀態碼)
hc() { docker run --rm --network $NET -v "$D/certs:/certs:ro" --entrypoint curl curlimages/curl:latest \
  -s --cacert /certs/ca.pem -w "\n[HTTP %{http_code}]\n" "$@"; }

# 以下常數與簡寫(方便後面指令閱讀)
MDS=https://broker1:8091                  # MDS(授權與驗證中樞)
RP=https://restproxy:8086                 # REST Proxy
JSON=(-H "Content-Type: application/json" -H "Accept: application/json")
CL='{"clusters":{"kafka-cluster":"${CID}"}}'`.replace(/\$\{CID\}/g, CID);

// LDAP(模擬 AD)群組成員異動的等效指令(UI 做不到或不想點時使用)
// 使用者名稱 = CN(大寫),分散在多層 OU;群組 member 要用完整 DN
export const USER_DN = { gary: "CN=GARY,OU=platform,OU=it,OU=users,dc=corp,dc=demo", yujie: "CN=YUJIE,OU=orders,OU=dev,OU=users,dc=corp,dc=demo", ming: "CN=MING,OU=platform,OU=it,OU=users,dc=corp,dc=demo" };
const ldapMod = (op, user, grp) => R`printf 'dn: cn=${grp},ou=groups,dc=corp,dc=demo\nchangetype: modify\n${op}: member\nmember: ${USER_DN[user]}\n' | docker exec -i openldap ldapmodify -x -D cn=admin,dc=corp,dc=demo -w adminpw`;
const bindRes = (principal, role, rtype, rname, ptype = 'PREFIXED', who = 'gary:gary-pw') =>
  `hc -u ${who} "\${JSON[@]}" -X POST ${'$MDS'}/security/1.0/principals/${principal.replace(':', '%3A')}/roles/${role}/bindings -d '{"scope":{"clusters":{"kafka-cluster":"${CID}"}},"resourcePatterns":[{"resourceType":"${rtype}","name":"${rname}","patternType":"${ptype}"}]}'`;
const bindCluster = (principal, role, who = 'gary:gary-pw') =>
  `hc -u ${who} "\${JSON[@]}" -X POST ${'$MDS'}/security/1.0/principals/${principal.replace(':', '%3A')}/roles/${role} -d "$CL"`;
const produce = (props, topic, msg) => `echo ${msg} | kc kafka-console-producer --bootstrap-server $BOOT --command-config /clients/${props}.properties --topic ${topic}`;
const consume = (props, topic, grp) => `kc kafka-console-consumer --bootstrap-server $BOOT --command-config /clients/${props}.properties --topic ${topic} --group ${grp} --from-beginning --max-messages 3 --timeout-ms 15000`;
const AUDIT = (flags) => `kc kafka-console-consumer --bootstrap-server $BOOT --command-config /clients/token-bootstrap.properties --topic confluent-audit-log-events --from-beginning --timeout-ms 12000 2>/dev/null | node scripts/audit-fmt.mjs ${flags}`;
const DENY = 'not authorized|Not authorized|TopicAuthorization|Authorization failed|authorization failed';

// 以 bootstrap 憑證移除 binding(Lab 起點/清理用);quiet=true 時不印輸出
const unbindBoot = (principal, role, rtype, rname, quiet = true) =>
  `hc --cert /certs/client-bootstrap.pem --key /certs/client-bootstrap.key "\${JSON[@]}" -X DELETE ${'$MDS'}/security/1.0/principals/${principal.replace(':', '%3A')}/roles/${role}/bindings -d '{"scope":{"clusters":{"kafka-cluster":"${CID}"}},"resourcePatterns":[{"resourceType":"${rtype}","name":"${rname}","patternType":"PREFIXED"}]}'${quiet ? ' >/dev/null' : ''}`;
// legacy app 以 client 憑證呼叫 REST Proxy produce
const legacyPost = (cert, topic) =>
  `hc --cert /certs/client-${cert}.pem --key /certs/client-${cert}.key -H "Accept: application/vnd.kafka.v2+json" -H "Content-Type: application/vnd.kafka.json.v2+json" -X POST ${'$RP'}/topics/${topic} -d '{"records":[{"value":{"order":"L-1","by":"legacy-app"}}]}'`;

export const IDENTITIES = [
  ['GARY(登入輸入 gary 也可以)', '人(AD)', 'gary / gary-pw', '組長;AD 群組 cluster-admin、topic-admin、rbac-admin、security(沒有 SystemAdmin)'],
  ['YUJIE', '人(AD)', 'yujie / yujie-pw', '組員;AD 群組 orders-write(demo 示範用,正式環境人只能唯讀)'],
  ['ming', '人(AD)', 'ming / ming-pw', '新進組員,起初不在任何群組'],
  ['svc-orders', '服務(Kafka SCRAM)', 'svc-orders / orders-secret-v1', '不在 AD;應用程式用'],
  ['bootstrap', '平台(client 憑證 CN=bootstrap)', '憑證,無密碼', 'MDS 初始管理員(break-glass)'],
  ['c3 / restproxy', '平台(client 憑證)', 'CN=c3 / CN=restproxy', '向 MDS 認證用,不是 AD 帳號'],
  ['LDAP 管理員', 'AD 管理介面登入', 'cn=admin,dc=corp,dc=demo / adminpw', 'phpLDAPadmin(模擬 AD 管理員操作)'],
];

export const LABS = [
  // ───────────────────────── Lab 0 ─────────────────────────
  {
    id: 'ch00', n: 0, title: '建立實驗環境', time: '15–30 分(首次含映像下載)',
    goal: '在本機用 Docker 建出:OpenLDAP(模擬 AD)、1 個 KRaft controller、2 個 broker(含 MDS/RBAC)、REST Proxy、Control Center,並完成初始授權。',
    pre: ['Windows 11 + Docker Desktop(建議配置 ≥ 10GB 記憶體)、Git Bash;Node.js 24(只有跑 UI 自動化/newman 才需要;第一次執行 UI 章節時會自動下載 Playwright 的 chromium,也可先執行 bash scripts/setup-e2e.sh,需要能連網)。', '連接埠未被占用:8081(LDAP 介面)、8086(REST Proxy)、8091(MDS)、9022(C3,HTTPS)。', '首次需下載約數 GB 映像(cp-server、cp-kafka-rest、C3、Prometheus、Alertmanager、OpenLDAP、phpLDAPadmin)。'],
    autoAll: ['bash scripts/up.sh --with-restproxy --with-c3   # 一鍵:憑證 → LDAP → controller → brokers → 初始授權 → 服務帳號與 topics → C3/REST Proxy', './preflight.sh                                  # 開場前自檢(容器、端點、登入、記憶體)'],
    steps: [
      { t: '0.1 準備終端機與輔助函式', why: '之後所有「手動指令」都用 kc(Kafka CLI)與 hc(curl)兩個函式,它們只是 docker run 的簡寫,不依賴專案腳本。每開一個新終端機都要重貼一次。', manual: [SETUP], expect: '沒有輸出。可用 type kc 確認函式已定義。' },
      { t: '0.2 產生憑證(CA、單一共用 server 憑證、client 憑證、MDS token 金鑰)', why: '客戶情境:所有元件共用「同一張 server 憑證」(同一把 private key、同一個 DN),憑證只做傳輸加密。另外產生 3 張 client 憑證(CN=c3、restproxy、bootstrap),供平台元件向 MDS 以 mTLS 認證,以及第 8 章對照。',
        manual: [R`mkdir -p certs
docker run --rm -v "$D/certs:/certs" --entrypoint sh alpine/openssl -c '
set -e; cd /certs
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 -subj "/CN=Demo Private CA/O=Demo" -out ca.pem
cat > san.cnf <<EOF
[req]
distinguished_name=dn
req_extensions=v3
prompt=no
[dn]
CN=kafka.demo.local
O=Demo
[v3]
subjectAltName=DNS:kafka.demo.local,DNS:localhost,DNS:controller1,DNS:broker1,DNS:broker2,DNS:restproxy,DNS:control-center,DNS:openldap,IP:127.0.0.1
extendedKeyUsage=serverAuth,clientAuth
EOF
openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr -config san.cnf
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out server.pem -days 825 -sha256 -extfile san.cnf -extensions v3
openssl pkcs12 -export -in server.pem -inkey server.key -certfile ca.pem -name server -out server.keystore.p12 -passout pass:changeit
for n in c3 restproxy bootstrap; do
  openssl genrsa -out client-$n.key 2048
  openssl req -new -key client-$n.key -subj "/CN=$n/O=Demo" -out client-$n.csr
  openssl x509 -req -in client-$n.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out client-$n.pem -days 825 -sha256
  openssl pkcs12 -export -in client-$n.pem -inkey client-$n.key -certfile ca.pem -name $n -out client-$n.keystore.p12 -passout pass:changeit
done
openssl genrsa -out keypair.pem 2048
openssl rsa -in keypair.pem -outform PEM -pubout -out public.pem
chmod 644 *.pem *.p12 *.key'
docker run --rm -v "$D/certs:/certs" --entrypoint bash confluentinc/cp-server:8.3.2 -c "rm -f /certs/truststore.p12; keytool -importcert -noprompt -alias demo-ca -file /certs/ca.pem -keystore /certs/truststore.p12 -storetype PKCS12 -storepass changeit; chmod 644 /certs/truststore.p12"
# 容器要求的密碼檔(cp-server 以檔名約定讀取)
printf changeit > certs/keystore_creds; printf changeit > certs/sslkey_creds; printf changeit > certs/truststore_creds`],
        auto: ['bash scripts/make-certs.sh'], ev0: 'certs-ls', expect: 'certs/ 內有 ca.pem、server.keystore.p12、client-c3/restproxy/bootstrap.*、keypair.pem、public.pem、truststore.p12。', tip: '客戶現場:有 AD CS 就用 AD CS 簽發,並把根憑證同時放進 RHEL 系統信任(update-ca-trust)與 Java truststore。' },
      { t: '0.3 啟動 LDAP(模擬 AD)與 KRaft controller', why: 'OpenLDAP 啟動時匯入 users(GARY、YUJIE、MING;使用者名稱 = CN,分散在多層 OU)與 8 個 groups(orders-read、orders-write、ops、topic-admin、cluster-admin、rbac-admin、security、breakglass)。Controller 啟動時由 ensure 腳本以 kafka-storage format --add-scram 預建 broker 間的 SCRAM 憑證。',
        manual: [R`docker compose up -d openldap ldapadmin controller1
# 等 LDAP 種子資料匯入完成(看到 cn=GARY 即可)
until docker exec openldap ldapsearch -x -H ldap://localhost -b dc=corp,dc=demo -D cn=admin,dc=corp,dc=demo -w adminpw "(cn=GARY)" dn 2>/dev/null | grep -qi "cn=GARY"; do sleep 2; done; echo LDAP-ready`], auto: ['(包含在 scripts/up.sh)'], expect: '最後印出 LDAP-ready。' },
      { t: '0.4 授權「bind DN 唯讀查詢帳號」', why: 'MDS / broker 查 AD 需要一個唯讀查詢帳號(bind DN:cn=svc-kafka-ldap)。它只負責搜尋使用者與群組成員,不參與驗證使用者密碼。正式環境請客戶提供專用唯讀帳號並建議 LDAPS。',
        manual: [R`docker cp ldap-config/acl-bind-dn.ldif openldap:/tmp/acl.ldif
docker exec openldap ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/acl.ldif`], auto: ['(包含在 scripts/up.sh)'], expect: '顯示 modifying entry "olcDatabase={1}mdb,cn=config"。' },
      { t: '0.5 啟動 brokers(MDS 內建於 broker)並等待 MDS 就緒', why: 'broker 同時是 MDS 伺服器(8091)。MDS 回 200 代表 RBAC 與 LDAP 設定載入成功。',
        manual: [R`docker compose up -d broker1 broker2
until [ "$(curl -sk -o /dev/null -w '%{http_code}' https://localhost:8091/security/1.0/features)" = 200 ]; do sleep 4; done; echo MDS-ready; sleep 8`], auto: ['(包含在 scripts/up.sh)'], expect: '印出 MDS-ready。' },
      { t: '0.6 用 bootstrap 憑證建立第一批 role binding', why: '新叢集沒有任何 role binding,只有 super.users 能建第一批。bootstrap 身分是 client 憑證 CN=bootstrap(非 AD 帳號),建完後管理權交給 AD 群組(依職責分成 7 組,沒有人日常是 SystemAdmin;SystemAdmin 只給 breakglass 群組,平常是空的),之後 bootstrap 只作 break-glass。role binding 的 scope 需要 Kafka cluster ID(本手冊以 CID 代入,demo 為 XyZBQ3-GTvKH2qNfP7X33A);實機自己取得,兩種方式皆已實測:kafka-cluster cluster-id --bootstrap-server <broker>:9094 --command-config <client.properties>(--config 已被標為棄用),或 curl https://<broker>:8091/v1/metadata/id(匿名可讀)。',
        manual: [R`B=(--cert /certs/client-bootstrap.pem --key /certs/client-bootstrap.key "${'$'}{JSON[@]}")
# 叢集層級的 role(沒有資源範圍)
for g in breakglass:SystemAdmin cluster-admin:ClusterAdmin rbac-admin:UserAdmin security:SecurityAdmin security:AuditAdmin ops:Operator; do
  hc "${'$'}{B[@]}" -X POST $MDS/security/1.0/principals/Group%3A${'$'}{g%%:*}/roles/${'$'}{g#*:} -d "$CL"
done
# 資源層級的 role:topic-admin 管全部 Topic 與 Group;security 讀 audit topic 與 audit- 開頭的 consumer group
rb() { hc "${'$'}{B[@]}" -X POST $MDS/security/1.0/principals/$1/roles/$2/bindings -d '{"scope":{"clusters":{"kafka-cluster":"${CID}"}},"resourcePatterns":[{"resourceType":"'"$3"'","name":"'"$4"'","patternType":"'"$5"'"}]}'; }
rb Group%3Atopic-admin ResourceOwner Topic '*' LITERAL
rb Group%3Atopic-admin ResourceOwner Group '*' LITERAL
rb Group%3Asecurity DeveloperRead Topic confluent-audit-log-events LITERAL
rb Group%3Asecurity DeveloperRead Group audit- PREFIXED
# 平台元件(憑證身分)
hc "${'$'}{B[@]}" -X POST $MDS/security/1.0/principals/User%3Ac3/roles/SystemAdmin -d "$CL"                # C3 向 MDS 的身分(官方要求 SystemAdmin)
for r in DeveloperRead DeveloperWrite; do rb User%3Arestproxy $r Topic _confluent-command LITERAL; done`.replace(/\$\{CID\}/g, CID)], auto: ['bash scripts/bootstrap-rbac.sh'], expect: '每個請求回 [HTTP 204]。' },
      { t: '0.7 建立服務帳號(SCRAM)與示範 topics', why: '服務身分不放 AD:在 Kafka 內建立 SCRAM-SHA-512 帳號(svc-orders;REST Proxy 與 C3 用憑證換 token,不用 SCRAM)。這兩步都用 bootstrap 的 client 憑證:先向 MDS 換 token,再以 OAUTHBEARER 連 broker(跟 C3、REST Proxy 同一條路,bootstrap 不建 SCRAM 帳號),建立 SCRAM 帳號與 orders.events、orders.payments、payments.events。',
        manual: [R`for p in svc-orders:orders-secret-v1; do
  kc kafka-configs --bootstrap-server $BOOT --command-config /clients/token-bootstrap.properties --alter --add-config "SCRAM-SHA-512=[password=${'$'}{p#*:}]" --entity-type users --entity-name ${'$'}{p%%:*}
done
for t in orders.events orders.payments payments.events; do
  kc kafka-topics --bootstrap-server $BOOT --command-config /clients/token-bootstrap.properties --create --if-not-exists --topic $t --partitions 1 --replication-factor 2
done`], auto: ['(包含在 scripts/up.sh)'], expect: '每個帳號印出 Completed updating config for user …;三個 topic 顯示 Created topic。' },
      { t: '0.8 啟動 Control Center 與 REST Proxy,並自檢', why: 'C3(next-gen)需要 Prometheus + Alertmanager,三個容器放在 c3 profile。啟動後用 preflight 自檢所有端點與登入。',
        manual: [R`docker compose --profile c3 --profile restproxy up -d
curl -sk -o /dev/null -w "REST Proxy no-credentials: %{http_code}\n" https://localhost:8086/topics
curl -s --ssl-no-revoke --cacert certs/ca.pem -o /dev/null -w "C3 login page (HTTPS): %{http_code}\n" https://localhost:9022/login
docker ps --format "table {{.Names}}\t{{.Status}}"`], auto: ['./preflight.sh'], ev0: 'preflight', expect: 'REST Proxy no-credentials: 401(代表已要求驗證);C3 login page (HTTPS): 200;所有容器 Up。preflight 結果 通過 18 / 失敗 0。' },
    ],
  },

  // ───────────────────────── Lab 1 ─────────────────────────
  {
    id: 'ch01', n: 1, title: '沒有身分就進不來(預設全拒絕)', time: '5 分',
    goal: '證明:沒有身分、密碼錯、或「認證成功但沒授權」都看不到、做不到任何事。',
    pre: ['Lab 0 完成。', '回到起點狀態:./scripts/reset.sh(清除示範用 role binding 與群組異動)。'],
    pre_cmd: ['./scripts/reset.sh', 'sleep 12   # 等 MDS 重讀 LDAP 群組(demo 為 5 秒)'],
    autoAll: ['./demo.sh 1                     # 逐步按 Enter 的講解模式', './scenarios/ch01-no-identity.sh      # 一次跑完並自動驗證'],
    steps: [
      { t: '1.1 未帶帳密呼叫 REST Proxy', manual: ['hc $RP/topics'], auto: ['./scripts/rp.sh none GET /topics'], ev: 'no-cred-rest', re: /HTTP 401/, expect: '回應內容是一頁 HTML 的 401 錯誤頁,最後一行 [HTTP 401]。REST Proxy 要求驗證,匿名一律拒絕。', imgs: [['ch05/postman-1.1.png', 'Postman 版本:1.1 未帶帳密 → 401(Tests 綠色)']] },
      { t: '1.2 帳號正確、密碼錯誤', why: '密碼由 MDS 去 AD(LDAP)以使用者自己的 DN 做 simple bind 驗證,驗證失敗回 401。', manual: ['hc -u yujie:bad-password $RP/topics'], auto: ['./scripts/rp.sh yujie:bad GET /topics'], ev: 'wrong-pw-rest', re: /HTTP 401/, expect: 'HTTP 401。', imgs: [['ch05/postman-1.2.png', 'Postman 版本:1.2 密碼錯誤 → 401']] },
      { t: '1.3 用 AD 帳號直連 broker,密碼錯誤', why: '直連 broker(Kafka 協定)走 SASL/PLAIN,broker 內的 LdapAuthenticateCallbackHandler 會去 AD 驗證。client 設定檔 plain-yujie-wrong.properties 內是錯誤密碼。', manual: ['kc kafka-topics --bootstrap-server $BOOT --command-config /clients/plain-yujie-wrong.properties --list'], auto: ['./scripts/k.sh kafka-topics --bootstrap-server broker1:9094 --command-config /clients/plain-yujie-wrong.properties --list'], ev: 'wrong-pw-broker', re: /Authentication failed/, expect: '出現 Authentication failed(SASL 驗證失敗)。' },
      { t: '1.4 帳密正確(AD 登入成功)但尚未授權', why: '認證(你是誰)與授權(你能做什麼)是兩件事。ming 密碼正確,但沒有任何 role,所以看不到任何業務 topic(Kafka 對無權限的資源直接隱藏)。', manual: [R`kc kafka-topics --bootstrap-server $BOOT --command-config /clients/plain-ming.properties --list | grep -v -E '^(__|_confluent)' | wc -l | sed 's/^/可見的業務 topic 數: /'`], auto: ['source scripts/lib-ev.sh; as_list ming | grep -v -E "^(__|_confluent)" | wc -l | sed "s/^/可見的業務 topic 數: /"'], ev: 'valid-no-perm', re: /topic 數: 0/, expect: '可見的業務 topic 數: 0(看不到任何業務 topic)。', tip: '一句結論:預設全拒絕,先有身分、再談授權。' },
    ],
  },

  // ───────────────────────── Lab 2 ─────────────────────────
  {
    id: 'ch02', n: 2, title: '人用 AD 帳號登入 Control Center', time: '8 分',
    goal: '用 AD 帳號登入 C3;看見「同一個 C3,三個人看到的不同」。',
    pre: ['Lab 1 完成(尚無任何授權)。', '瀏覽器:建議為 gary、yujie、ming 各開一個無痕視窗或瀏覽器 profile。'],
    autoAll: ['(cd e2e && node ch02.mjs)    # Playwright 自動登入三人並截圖到 evidence/ch02/'],
    steps: [
      { t: '2.1 gary(組長:cluster-admin、topic-admin、rbac-admin、security)登入', ui: ['瀏覽器開 https://localhost:9022(第一次會警告憑證不受信任:demo 的 CA 是自簽的,按「進階」繼續,或把 demo/certs/ca.pem 匯入信任)', '帳號 gary、密碼 gary-pw(就是 AD 的帳密)→ Log in', '左側選叢集 → Topics:可看到全部 topic;右上 Administration 選單有 Manage role assignments。'], expect: 'gary 看得到全部資源與管理功能(他屬於 cluster-admin、topic-admin、rbac-admin、security 四個群組,沒有 SystemAdmin)。', imgs: [['ch02/gary-1-login.png', 'gary:C3 登入畫面(帳密就是 AD 的)'], ['ch02/gary-3-topics.png', 'gary:Topics 清單(全部可見)'], ['ch02/gary-4-admin-menu.png', 'gary:Administration 選單(有 Manage role assignments)']] },
      { t: '2.2 yujie 登入', ui: ['用 yujie / yujie-pw 登入(另一個無痕視窗)', 'Topics 頁面:看不到任何業務 topic;Administration 選單沒有 Manage role assignments。'], expect: 'yujie 屬於 orders-write 群組,但群組還沒有任何 role → 登入成功卻看不到資源。', imgs: [['ch02/yujie-3-topics.png', 'yujie:Topics(尚無授權)'], ['ch02/yujie-4-admin-menu.png', 'yujie:Administration 選單(沒有管理項目)']] },
      { t: '2.3 ming 登入', ui: ['用 ming / ming-pw 登入', '同樣看不到資源。'], expect: 'ming 登入成功,但沒有任何授權。C3 自己雖是最高權限,使用者只看得到「自己」被授權的。', imgs: [['ch02/ming-3-topics.png', 'ming:Topics(尚無授權)'], ['ch02/ming-5-my-roles.png', 'ming:View my role assignments(無)']] },
    ],
  },

  // ───────────────────────── Lab 3 ─────────────────────────
  {
    id: 'ch03', n: 3, title: 'RBAC 與 AD 群組:授權跟著群組走', time: '12 分',
    goal: '把 role 綁在「AD 群組」;人員異動只改 AD,Kafka 端零變更、數秒內生效。★ 本 Lab 是整個方案的核心。',
    pre: ['Lab 2 完成。'],
    autoAll: ['./demo.sh 3                       # 講解模式', './scenarios/ch03-rbac-ad-group.sh    # 一次跑完(含 UI 自動化與截圖)'],
    steps: [
      { t: '3.1 授權前:yujie 在群組內,但沒有 role → 寫入被拒', manual: [produce('plain-yujie', 'orders.events', 'before-rbac')], auto: ['source scripts/lib-ev.sh; as_produce yujie orders.events before-rbac'], ev: 'before', re: new RegExp(DENY), expect: '出現 TopicAuthorizationException / Not authorized。群組成員資格 ≠ 權限,權限來自 role binding。', warn: '如果這個指令沒有印出任何東西,代表寫入成功:yujie 已經有權限了(之前做過 3.2,或叢集不是剛建好)。先執行 ./demo.sh reset 再重做;否則看不到「被拒」。' },
      { t: '3.2 C3 操作:把 orders.* 的讀寫權指派給 AD 群組 orders-write', re: /HTTP 204[\s\S]*HTTP 204/, why: '這是 Confluent RBAC 的核心操作。注意 Principal name 的下拉清單會直接列出 AD 的使用者與群組。需做兩次(DeveloperWrite、DeveloperRead)。',
        ui: ['以 gary 登入 C3 → 右上 Administration → Manage role assignments → 選叢集(XyZBQ3-…)', '分頁 Topic → Add role assignment', 'Principal type 選 Group;Principal name 輸入 orders-write 並從下拉選取', 'Role 選 DeveloperWrite;Pattern type 選 Prefixed;Resource ID 填 orders. → Save', '重複一次:Role 改 DeveloperRead,其餘相同 → Save'],
        uiEq: [bindRes('Group:orders-write', 'DeveloperWrite', 'Topic', 'orders.'), bindRes('Group:orders-write', 'DeveloperRead', 'Topic', 'orders.')],
        expect: 'Topic 分頁列表出現兩列:orders-write / DeveloperWrite / orders.* 與 DeveloperRead / orders.*。等效 API 回 [HTTP 204]。',
        imgs: [['ch03/c3-1-write-form.png', 'C3:Add role assignment(Group / orders-write / DeveloperWrite / Prefixed orders.)'], ['ch03/c3-1-write-saved.png', 'C3:儲存後 Topic 範圍列表'], ['ch03/c3-2-read-form.png', 'C3:再加 DeveloperRead']] },
      { t: '3.3 MDS API(Postman 同一份資料)印證', why: 'C3 畫面背後就是 MDS REST API。用 API 查同一個群組的授權,結果與 C3 畫面一致。', manual: ['hc -u gary:gary-pw "${JSON[@]}" -X POST $MDS/security/1.0/lookup/principal/Group%3Aorders-write/resources -d "$CL"'], auto: ['./scripts/mds.sh basic gary:gary-pw POST /security/1.0/lookup/principal/Group%3Aorders-write/resources \'{"clusters":{"kafka-cluster":"' + CID + '"}}\''], ev: 'mds-api', re: /DeveloperWrite.*orders/, expect: '{"Group:orders-write":{"DeveloperRead":[{…"orders."…}],"DeveloperWrite":[…]}} [HTTP 200]。', imgs: [['ch05/postman-M.2.png', 'Postman 版本:M.2 列出 Group:orders-write 的 role binding']] },
      { t: '3.4 授權後:yujie 寫入成功;ming(不在群組)被拒', manual: ['sleep 5   # 等 broker 讀到新的 role binding', produce('plain-yujie', 'orders.events', 'order-A-1001'), produce('plain-ming', 'orders.events', 'hi-from-ming')], auto: ['source scripts/lib-ev.sh; send_result as_produce yujie orders.events order-A-1001; as_produce ming orders.events hi'], ev: 'yujie-ok', re: /./, expect: 'yujie 的 producer 無錯誤(成功);ming 的 producer 出現 TopicAuthorizationException。他的權限來自 AD 群組,不是個人帳號。', evb: 'ming-denied' },
      { t: '3.5 AD 端操作:把 ming 加進 orders-write —— Kafka 這邊完全不動', re: /modifying entry/, why: '這一步在 AD(此處用 LDAP 管理介面模擬 AD 管理員)操作;Kafka / RBAC 設定一個字都不改。',
        ui: ['瀏覽器開 http://localhost:8081(phpLDAPadmin),登入 DN:cn=admin,dc=corp,dc=demo / adminpw', '左側展開 dc=corp,dc=demo → ou=groups → cn=orders-write', '點 member 欄位的 add value → 輸入 CN=MING,OU=platform,OU=it,OU=users,dc=corp,dc=demo → Add → 確認頁按 Update Object'],
        uiEq: [ldapMod('add', 'ming', 'orders-write')],
        expect: '群組頁面 member 清單多出 uid=ming。', imgs: [['ch03/ldap-add-ming-before.png', 'LDAP(模擬 AD)群組 orders-write:加入 ming 之前'], ['ch03/ldap-add-ming-form.png', '新增 member 值'], ['ch03/ldap-add-ming-after.png', '加入之後(member 多了 ming)']] },
      { t: '3.6 數秒後:ming 取得權限,同一個指令這次成功', why: 'MDS 以 ldap.refresh.interval.ms 週期重讀群組(demo 設 5 秒;官方預設 60000 即 60 秒,不是即時,實機請預留約 1 分鐘)。', manual: ['sleep 8', produce('plain-ming', 'orders.events', 'hello-from-ming')], auto: ['source scripts/lib-ev.sh; as_produce ming orders.events hello-from-ming'], ev: 'ming-ok', reNot: /Exception|authorization failed|Authentication failed/i, expect: 'producer 這次沒有任何錯誤訊息(console producer 成功時不印東西)。實測約 4 秒內生效。' },
      { t: '3.7 ming 重新整理 C3:看得到 orders.*', ui: ['以 ming 登入 C3 → Topics'], expect: 'Topics 清單出現 orders.events、orders.payments。', imgs: [['ch03/c3-3-ming-topics.png', 'ming 加入群組後,C3 Topics 出現 orders.*']] },
    ],
  },

  // ───────────────────────── Lab 4 ─────────────────────────
  {
    id: 'ch04', n: 4, title: '生產環境「人只能唯讀」', time: '10 分',
    goal: '建立唯讀群組 orders-read:只能看資料,不能寫、不能建 topic。並把 ming 從開發者移到唯讀。',
    pre: ['Lab 3 完成(ming 目前在 orders-write)。'],
    autoAll: ['./demo.sh 4', './scenarios/ch04-readonly.sh'],
    steps: [
      { t: '4.1 C3 操作:建立唯讀授權(群組 orders-read → DeveloperRead)', re: /HTTP 204/, why: '需要兩條:Topic(orders.* 讀取)與 Consumer Group(demo- 讀取,因為 console consumer 需要讀自己的 consumer group)。只有 Read,沒有 Write / Manage。',
        ui: ['gary 登入 C3 → Administration → Manage role assignments → 叢集', '分頁 Topic → Add role assignment:Group / orders-read / DeveloperRead / Prefixed / orders. → Save', '分頁 Consumer Group → Add role assignment:Group / orders-read / DeveloperRead / Prefixed / demo- → Save'],
        uiEq: [bindRes('Group:orders-read', 'DeveloperRead', 'Topic', 'orders.'), bindRes('Group:orders-read', 'DeveloperRead', 'Group', 'demo-')],
        expect: '等效 API 回 [HTTP 204];C3 列表出現 orders-read / DeveloperRead。', imgs: [['ch04/c3-1-readonly-form.png', 'C3:Group / orders-read / DeveloperRead / orders.'], ['ch04/c3-1-readonly-saved.png', 'C3:儲存後列表']] },
      { t: '4.2 AD 端操作:ming 從 orders-write 移到 orders-read', re: /modifying entry[\s\S]*modifying entry/, ui: ['phpLDAPadmin:cn=orders-read 的 member 加入 CN=MING,OU=platform,OU=it,OU=users,dc=corp,dc=demo → Update Object', '再開 cn=orders-write:把 uid=ming 那一欄清空 → Update Object → 確認'], uiEq: [ldapMod('add', 'ming', 'orders-read'), ldapMod('delete', 'ming', 'orders-write')], manual: [], expect: '兩個群組的 member 清單各自更新。', imgs: [['ch04/ldap-ming-to-readonly-after.png', 'orders-read 加入 ming 之後'], ['ch04/ldap-ming-from-developers-after.png', 'orders-write 移除 ming 之後']] },
      { t: '4.3 ming(唯讀)可以讀', manual: ['sleep 10   # 等群組快取更新', consume('plain-ming', 'orders.events', 'demo-ming')], auto: ['source scripts/lib-ev.sh; as_consume ming orders.events'], ev: 'ming-read', re: /order|Processed a total/, expect: '印出先前寫入的訊息,結尾 Processed a total of N messages。(console consumer 用 --max-messages 3 --timeout-ms 15000:資料不足 3 筆時,等到逾時才結束,逾時訊息屬正常。)' },
      { t: '4.4 ming(唯讀)寫入 → 被拒', manual: [produce('plain-ming', 'orders.events', 'oops')], auto: ['source scripts/lib-ev.sh; as_produce ming orders.events oops'], ev: 'ming-write', re: new RegExp(DENY), expect: '被拒(Cluster authorization failed / TopicAuthorization):唯讀沒有 Write,連 IdempotentWrite 都沒有。' },
      { t: '4.5 ming(唯讀)想建立 topic → 被拒', manual: ['kc kafka-topics --bootstrap-server $BOOT --command-config /clients/plain-ming.properties --create --topic ming-test --partitions 1 --replication-factor 2'], ev: 'ming-create', re: new RegExp(DENY), expect: 'Authorization failed。' },
      { t: '4.6 yujie 不受影響', manual: [produce('plain-yujie', 'orders.events', 'still-ok')], ev: 'yujie-unaffected', reNot: /Exception|authorization failed|Authentication failed/i, expect: 'yujie 仍在 orders-write,可寫入(沒有任何錯誤訊息就是成功)。' },
      { t: '4.7 ming 的 C3 畫面:可檢視,沒有管理按鈕', ui: ['ming 登入 C3 → Topics'], expect: '看得到 orders.*,但沒有 Add topic 等管理功能。', imgs: [['ch04/c3-2-ming-readonly-topics.png', 'ming(orders-read)的 C3 Topics:可檢視']] },
    ],
  },

  // ───────────────────────── Lab 5 ─────────────────────────
  {
    id: 'ch05', n: 5, title: 'Postman / REST Proxy:工具用同一份 AD 身分', time: '12 分',
    goal: '用 Postman(人手動測試)呼叫 REST Proxy 與 MDS API,驗證與 CLI、C3 相同的身分與授權結果。',
    pre: ['Lab 4 完成(yujie 在 orders-write;ming 在 orders-read)。', '已安裝 Postman 桌面版(或只用 newman / curl)。'],
    autoAll: ['./demo.sh 5      # 以 newman(Postman 的命令列版)跑同一份 collection,並產生報告與截圖'],
    steps: [
      { t: '5.1 匯入檔案並信任 demo CA(Postman 桌面版)', ui: ['Postman → Import:選 demo/postman/demo.postman_collection.json 與 demo-humans.postman_environment.json', '右上環境下拉選 demo-humans(rest_proxy=https://localhost:8086、mds=https://localhost:8091)', 'Settings → Certificates → CA certificates → 開啟,選 demo/certs/ca.pem(不要關閉 SSL 驗證)'], expect: 'Collection 出現三個資料夾:1 沒有身分進不來、5 人:同一份 AD 身分用在工具上、M MDS API。', warn: 'Postman 在不同身分間切換時,MDS 驗證成功後會設定 auth_token cookie,且 cookie 優先於 Basic Auth,導致後續請求仍以前一個人的身分執行(實測 yujie 竟新增了 role binding)。collection 已加 pre-request 清 cookie;手動測試換身分前請清除 localhost 的 cookie。' },
      { t: '5.2 無身分 / 密碼錯 → 401', ui: ['執行 1.1、1.2,看 Tests 分頁'], manual: ['hc -H "Accept: application/vnd.kafka.v2+json" $RP/topics', 'hc -u yujie:bad -H "Accept: application/vnd.kafka.v2+json" $RP/topics'], re: /HTTP 401/, expect: '兩個都是 401;Postman Tests 綠色。', imgs: [['ch05/postman-1.1.png', '1.1 未帶帳密 → 401'], ['ch05/postman-1.2.png', '1.2 密碼錯誤 → 401']] },
      { t: '5.3 三個人各自的結果', why: '5.1 gary 列 topics;5.2 yujie 寫 orders.events;5.3 yujie 寫 payments.events(無權);5.4 ming(唯讀)寫 orders.events(無權);5.5 ming 仍可列 topics。',
        ui: ['依序執行 5.1 ~ 5.5(Basic Auth 已設好)'],
        manual: [R`hc -u gary:gary-pw -H "Accept: application/vnd.kafka.v2+json" $RP/topics
hc -u yujie:yujie-pw -H "Accept: application/vnd.kafka.v2+json" -H "Content-Type: application/vnd.kafka.json.v2+json" -X POST $RP/topics/orders.events -d '{"records":[{"value":{"order":"A-3001","by":"yujie"}}]}'
hc -u yujie:yujie-pw -H "Accept: application/vnd.kafka.v2+json" -H "Content-Type: application/vnd.kafka.json.v2+json" -X POST $RP/topics/payments.events -d '{"records":[{"value":{"order":"A-3001","by":"yujie"}}]}'
hc -u ming:ming-pw -H "Accept: application/vnd.kafka.v2+json" -H "Content-Type: application/vnd.kafka.json.v2+json" -X POST $RP/topics/orders.events -d '{"records":[{"value":{"order":"A-3001","by":"ming"}}]}'
hc -u ming:ming-pw -H "Accept: application/vnd.kafka.v2+json" $RP/topics`],
        re: /HTTP 200[\s\S]*HTTP 200[\s\S]*HTTP 403[\s\S]*HTTP 403[\s\S]*HTTP 200/, expect: '依序:200、200、403、403、200。403 的內文會是 error_code 40301。',
        imgs: [['ch05/postman-5.1.png', '5.1 gary 列出 topics → 200'], ['ch05/postman-5.2.png', '5.2 yujie 寫 orders.events → 200'], ['ch05/postman-5.3.png', '5.3 yujie 寫 payments.events → 403'], ['ch05/postman-5.4.png', '5.4 ming(唯讀)寫 orders.events → 403'], ['ch05/postman-5.5.png', '5.5 ming 仍看得到 topics → 200']] },
      { t: '5.4 MDS API(與 C3 同一份資料)', why: 'M.1 以 gary 取得 token(Basic 登入 MDS);M.2 列出群組的 role binding;M.3 yujie 嘗試新增 role binding → 403。',
        manual: [R`hc -u gary:gary-pw -H "Accept: application/json" $MDS/security/1.0/authenticate
hc -u gary:gary-pw "${'$'}{JSON[@]}" -X POST $MDS/security/1.0/lookup/principal/Group%3Aorders-write/resources -d "$CL"
hc -u yujie:yujie-pw "${'$'}{JSON[@]}" -X POST $MDS/security/1.0/principals/Group%3Aorders-write/roles/DeveloperRead/bindings -d '{"scope":{"clusters":{"kafka-cluster":"${CID}"}},"resourcePatterns":[{"resourceType":"Topic","name":"payments.","patternType":"PREFIXED"}]}'`.replace(/\$\{CID\}/g, CID)],
        re: /auth_token[\s\S]*DeveloperWrite[\s\S]*HTTP 403/, expect: 'M.1 回含 auth_token 的 JSON(200);M.2 回 role binding(200);M.3 回 403(error_code 40301,operation=AlterAccess)。', imgs: [['ch05/postman-M.1.png', 'M.1 gary 取得 MDS token'], ['ch05/postman-M.2.png', 'M.2 列出 role binding'], ['ch05/postman-M.3.png', 'M.3 yujie 改授權 → 403']] },
      { t: '5.5 一次跑完整份 collection(Collection Runner / newman)', ui: ['Postman → 右鍵 collection → Run collection → Run'], auto: ['./demo.sh 5'], ev: 'newman', re: /assertions/, expect: '10 requests、14 assertions 全過、0 failed。', imgs: [['ch05/postman-0-summary.png', 'Collection Runner 總覽(Tests 全綠)']], tip: '服務身分(newman/CI)用 demo-service 環境,密碼從密碼庫注入,不要寫進 collection。' },
    ],
  },

  // ───────────────────────── Lab 6 ─────────────────────────
  {
    id: 'ch06', n: 6, title: '維運腳本:腳本共用、憑證各人各自', time: '10 分',
    goal: '同一支腳本,每個人用自己的憑證執行,權限與稽核各自獨立;反例:共用帳號會讓稽核看不到「是誰」。',
    pre: ['Lab 5 完成(yujie 可寫 orders.*;ming 唯讀)。', '準備:每個人在自己的家目錄有 ~/.kafka/client.properties(demo 以 config/home/<user>/.kafka/ 模擬)。', '實機注意:這個檔案內是 AD 密碼的明文,權限必須是 600(chmod 600);AD 密碼到期或變更後腳本會失敗,要同步更新;密碼錯誤重試太多次會鎖定 AD 帳號(鎖定門檻請向客戶確認);腳本若要轉成排程或 CI,必須改用服務身分,不可借用人的帳號。'],
    autoAll: ['./demo.sh 6'],
    steps: [
      { defs: true, t: '6.1 定義 asuser 函式(模擬各人登入跳板機後執行腳本)', manual: [R`asuser() { u=$1; s=$2; docker run --rm -i --network $NET -e DEMO_USER=$u -e KAFKA_HEAP_OPTS="-Xmx256m" \
  -v "$D/certs:/etc/kafka/secrets:ro" -v "$D/scripts/ops:/ops:ro" -v "$D/config/home/$u/.kafka:/home/appuser/.kafka:ro" \
  --entrypoint bash confluentinc/cp-server:8.3.2 /ops/$s; }
grep -v '^#' scripts/ops/orders-heartbeat.sh`], ev: 'script-content', re: /CFG=/, expect: '看到腳本內容:連線設定來自 $HOME/.kafka/client.properties,腳本內沒有任何帳號密碼。', tip: '腳本寫死吃某個 client properties 的問題:解法是腳本只讀「執行者自己家目錄」的設定。人要操作,就用自己的 AD 身分。' },
      { t: '6.2 yujie 執行 → 成功', manual: ['asuser yujie orders-heartbeat.sh'], auto: ['./scripts/as-user.sh yujie orders-heartbeat.sh'], ev: 'yujie-run', re: /OK/, expect: 'OK: 已送出 heartbeat(使用 /home/appuser/.kafka/client.properties)。' },
      { t: '6.3 ming 執行同一支腳本 → 被拒(他是唯讀)', manual: ['asuser ming orders-heartbeat.sh'], auto: ['./scripts/as-user.sh ming orders-heartbeat.sh'], ev: 'ming-run', re: /FAILED/, expect: 'FAILED: 沒有權限。同一支腳本,結果由「誰執行」決定。' },
      { t: '6.4 反面教材:全組共用一個帳號(shared-ops)', why: '建立 SCRAM 帳號 shared-ops 並授權 orders.* 寫入;全組共用 config/home/shared/.kafka/client.properties。', manual: [R`kc kafka-configs --bootstrap-server $BOOT --command-config /clients/token-bootstrap.properties --alter --add-config 'SCRAM-SHA-512=[password=shared-ops-secret]' --entity-type users --entity-name shared-ops`, bindRes('User:shared-ops', 'DeveloperWrite', 'Topic', 'orders.'), 'sleep 5', 'asuser shared orders-heartbeat.sh    # 假設 yujie 執行', 'asuser shared orders-heartbeat.sh    # 假設 ming 執行(他本來是唯讀!)'], ev: 'shared-ming', re: /OK/, expect: '兩次都成功 —— 連唯讀的 ming 都能寫了。共用帳號 = 放棄最小權限。' },
      { t: '6.5 稽核:誰做了什麼', manual: [AUDIT(R`--method '^kafka\.Produce$' --topic '^orders\.events$' --last 7`)], auto: ['source scripts/lib-ev.sh; audit_events --method "^kafka\\.Produce$" --topic "^orders\\.events$" --last 7'], ev: 'audit', re: /shared-ops.*ALLOWED/, expect: '個人身分的事件是 User:YUJIE;共用帳號的事件全部是 User:shared-ops,看不出是 yujie 還是 ming。', imgs: [['ch06/06-audit.png', 'audit log:yujie / ming / shared-ops']], tip: '規範:腳本由手動轉成排程/CI → 必須改用服務身分,不可借用人的帳號(AD 密碼到期或鎖定會讓排程失敗,甚至鎖帳號)。' },
      { t: '6.6 清理反面教材', re: /HTTP 204[\s\S]*Completed updating config/, manual: [R`hc -u gary:gary-pw "${'$'}{JSON[@]}" -X DELETE $MDS/security/1.0/principals/User%3Ashared-ops/roles/DeveloperWrite/bindings -d '{"scope":{"clusters":{"kafka-cluster":"${CID}"}},"resourcePatterns":[{"resourceType":"Topic","name":"orders.","patternType":"PREFIXED"}]}'`.replace(/\$\{CID\}/g, CID), `kc kafka-configs --bootstrap-server $BOOT --command-config /clients/token-bootstrap.properties --alter --delete-config SCRAM-SHA-512 --entity-type users --entity-name shared-ops`], expect: '[HTTP 204] 與 Completed updating config。' },
    ],
  },

  // ───────────────────────── Lab 7 ─────────────────────────
  {
    id: 'ch07', n: 7, title: '機器(不在 AD):服務帳號 SCRAM + RBAC', time: '12 分',
    goal: '服務身分不放 AD:在 Kafka 建 SCRAM 帳號,授權仍走 RBAC,且最小權限。',
    pre: ['Lab 6 完成。'],
    autoAll: ['./demo.sh 7'],
    steps: [
      { t: '7.1 建立服務帳號 svc-orders', manual: [`kc kafka-configs --bootstrap-server $BOOT --command-config /clients/token-bootstrap.properties --alter --add-config 'SCRAM-SHA-512=[password=orders-secret-v1]' --entity-type users --entity-name svc-orders`], auto: ['./scripts/create-service-account.sh svc-orders orders-secret-v1'], ev: 'create-svc', re: /Completed updating config/, expect: 'Completed updating config for user svc-orders。密碼存密碼庫,不是 AD。' },
      { t: '7.2 授權前:svc-orders 認證成功但沒有 role → 寫入被拒', manual: [produce('scram-svc-orders', 'orders.events', 'order-S-0')], auto: ['source scripts/lib-ev.sh; svc_produce scram-svc-orders orders.events x'], ev: 'svc-before', re: new RegExp(DENY), expect: 'TopicAuthorizationException。' },
      { t: '7.3 C3 操作:把 orders.* 寫入權限指派給 User:svc-orders', re: /HTTP 204/, why: 'C3 的 Principal name 允許輸入不在 AD 的名稱:下拉選單最後選 Create "svc-orders"。同一張 role assignment 表同時有 AD 群組與服務帳號。', ui: ['gary 登入 C3 → Manage role assignments → Topic → Add role assignment', 'Principal type 選 User;Principal name 輸入 svc-orders,選下拉的 Create "svc-orders"', 'Role = DeveloperWrite;Pattern = Prefixed;Resource ID = orders. → Save'], uiEq: [bindRes('User:svc-orders', 'DeveloperWrite', 'Topic', 'orders.')], expect: '列表出現 svc-orders / DeveloperWrite / orders.*,與 Group:orders-write 並列。', imgs: [['ch07/c7-1-svc-form.png', 'C3:User / svc-orders / DeveloperWrite / orders.'], ['ch07/c7-1-svc-saved.png', 'C3:AD 群組與服務帳號並列在同一張表']] },
      { t: '7.4 授權後:可寫 orders.*;碰 payments.* 被拒(最小權限)', manual: ['sleep 5', produce('scram-svc-orders', 'orders.events', 'order-S-1'), produce('scram-svc-orders', 'payments.events', 'x')], ev: 'svc-ok', re: /./, evb: 'svc-denied', expect: '第一個成功;第二個 TopicAuthorizationException。' },
      { t: '7.5 密碼錯誤 → SCRAM 認證失敗', manual: ['kc kafka-topics --bootstrap-server $BOOT --command-config /clients/scram-svc-orders-wrong.properties --list'], ev: 'svc-wrongpw', re: /Authentication failed/, expect: 'Authentication failed。' },
      { t: '7.6 不在 AD:用 AD 的方式(PLAIN→LDAP)驗證 svc-orders → 失敗', manual: ['kc kafka-topics --bootstrap-server $BOOT --command-config /clients/plain-svc-orders.properties --list'], ev: 'svc-not-ad', re: /Authentication failed/, expect: 'Authentication failed:服務身分與人完全分開。' },
      { t: '7.7 稽核:服務的行為也看得到', manual: [AUDIT(R`--topic '^(orders|payments)\.' --last 60 | grep svc-orders | tail -5`)], ev: 'audit', re: /svc-orders/, expect: 'principal = User:svc-orders 的 ALLOWED / DENIED 事件。' },
    ],
  },

  // ───────────────────────── Lab 8 ─────────────────────────
  {
    id: 'ch08', n: 8, title: '(選修)為什麼不用共用憑證做 mTLS 身分', time: '8 分',
    goal: '證明:所有元件共用同一張憑證時,Kafka 眼中全是「同一個人」,無法分權、稽核分不出來。',
    pre: ['Lab 0 完成(certs/ 內有共用 server 憑證與 c3、restproxy 的 client 憑證)。'],
    autoAll: ['./demo.sh 8'],
    steps: [
      { defs: true, t: '8.1 定義 tokensub 函式:拿憑證向 MDS 要 token,看 Kafka 認得的 principal', re: /^\s*$/, manual: [R`tokensub() { tok=$(docker run --rm --network $NET -v "$D/certs:/certs:ro" --entrypoint curl curlimages/curl:latest -s --cacert /certs/ca.pem --cert /certs/$1.pem --key /certs/$1.key -H 'Accept: application/json' https://broker1:8091/security/1.0/authenticate | grep -o '"auth_token":"[^"]*"' | cut -d'"' -f4)
  [ -z "$tok" ] && { echo "(無 token:憑證未被接受)"; return 1; }
  echo "$tok" | cut -d. -f2 | tr '_-' '/+' | awk '{ while (length($0) % 4) $0 = $0 "="; print }' | base64 -d 2>/dev/null | grep -o '"sub":"[^"]*"' | sed 's/"sub":/MDS 看到的 principal = /'; }`], expect: '沒有輸出(函式定義)。' },
      { t: '8.2 客戶的做法:共用 server 憑證(C3 與 REST Proxy 出示同一張)', manual: [R`docker run --rm -v "$D/certs:/certs:ro" --entrypoint sh alpine/openssl -c "openssl x509 -in /certs/server.pem -noout -subject"`, 'tokensub server    # 假設這是 C3 出示的', 'tokensub server    # 假設這是 REST Proxy 出示的'], ev: 'shared-c3', re: /kafka.demo.local/, expect: '兩次都是 principal = "kafka.demo.local":Kafka 眼中是同一個人,無法分別授權、audit 分不出誰、一台被入侵 = 全部淪陷。' },
      { t: '8.3 對照:每個元件各一張憑證(不同 DN)', manual: ['tokensub client-c3', 'tokensub client-restproxy'], ev: 'sep-c3', re: /principal = "c3"[\s\S]*principal = "restproxy"/, evb: 'sep-rp', expect: '分別是 c3 與 restproxy,可以各自授權。', tip: '結論:共用 server 憑證「只做加密」(ssl.client.auth=none);服務身分用 SCRAM(帳號密碼,免憑證);平台元件(C3、REST Proxy)各自需要一張 client 憑證向 MDS 認證。這與客戶「不想管憑證、全部共用一張」的前提有衝突:憑證總數 = c3、restproxy、bootstrap,再加上每個經 REST Proxy 的 legacy app 各一張(Lab 12),會隨 app 增加。這是與客戶取捨的重點,須請客戶確認可接受。' },
    ],
  },

  // ───────────────────────── Lab 9 ─────────────────────────
  {
    id: 'ch09', n: 9, title: '(選修)密碼輪替、內部通道、AD 故障', time: '15 分',
    goal: '1) 服務密碼不中斷輪替;2) 內部通道(CONTROLLER/INTERNAL)的行為;3) AD 掛掉時誰受影響。',
    pre: ['Lab 7 完成(svc-orders 存在且已授權寫 orders.*)。'],
    autoAll: ['./demo.sh 9'],
    steps: [
      { t: '9.1 輪替 1/4:建立新帳號 svc-orders-v2 並給同樣權限(新舊並行)', manual: [`kc kafka-configs --bootstrap-server $BOOT --command-config /clients/token-bootstrap.properties --alter --add-config 'SCRAM-SHA-512=[password=orders-secret-v2]' --entity-type users --entity-name svc-orders-v2`, bindRes('User:svc-orders-v2', 'DeveloperWrite', 'Topic', 'orders.', 'PREFIXED', 'gary:gary-pw'), 'sed \'s/svc-orders" password="orders-secret-v1/svc-orders-v2" password="orders-secret-v2/\' config/clients/scram-svc-orders.properties > config/clients/scram-svc-orders-v2.properties'], ev: 'rot-new', re: /HTTP 204/, expect: '[HTTP 204]。' },
      { t: '9.2 輪替 2/4:新舊帳號同時可用', manual: ['sleep 5', produce('scram-svc-orders', 'orders.events', 'old-pw'), produce('scram-svc-orders-v2', 'orders.events', 'new-pw')], ev: 'rot-both', reNot: /Exception|authorization failed|Authentication failed/i, expect: '兩個 producer 都成功(沒有任何錯誤訊息;應用逐步切換期間不中斷)。' },
      { t: '9.3 輪替 3/4:全部切換完 → 停用舊帳號', manual: ['kc kafka-configs --bootstrap-server $BOOT --command-config /clients/token-bootstrap.properties --alter --delete-config SCRAM-SHA-512 --entity-type users --entity-name svc-orders'], ev: 'rot-stop-old', re: /Completed updating config/, expect: 'Completed updating config for user svc-orders。' },
      { t: '9.4 輪替 4/4:舊密碼立刻失效;新帳號照常', manual: [produce('scram-svc-orders', 'orders.events', 'old-pw'), produce('scram-svc-orders-v2', 'orders.events', 'new-pw'), '# 還原:重建 svc-orders 並刪除 v2', `kc kafka-configs --bootstrap-server $BOOT --command-config /clients/token-bootstrap.properties --alter --add-config 'SCRAM-SHA-512=[password=orders-secret-v1]' --entity-type users --entity-name svc-orders`, 'kc kafka-configs --bootstrap-server $BOOT --command-config /clients/token-bootstrap.properties --alter --delete-config SCRAM-SHA-512 --entity-type users --entity-name svc-orders-v2', `hc -u gary:gary-pw "\${JSON[@]}" -X DELETE $MDS/security/1.0/principals/User%3Asvc-orders-v2/roles/DeveloperWrite/bindings -d '{"scope":{"clusters":{"kafka-cluster":"${CID}"}},"resourcePatterns":[{"resourceType":"Topic","name":"orders.","patternType":"PREFIXED"}]}'`], ev: 'rot-old-dead', re: /Authentication failed|authentication/i, expect: '舊密碼:Authentication failed;新帳號:成功。' },
      { t: '9.5 內部通道:CONTROLLER 埠(9093)', why: 'CONTROLLER 埠只認內部靜態帳號(SASL/PLAIN),不查 AD。', manual: ['kc kafka-broker-api-versions --bootstrap-server controller1:9093 --command-config /clients/ssl-only.properties 2>&1 | head -3', 'kc kafka-broker-api-versions --bootstrap-server controller1:9093 --command-config /clients/plain-yujie.properties 2>&1 | head -3'], ev: 'ctl-anon', re: /isconnected|failed|uthentication/, evb: 'ctl-ad', expect: '無 SASL 身分的連線被拒;用 AD 帳密也被拒(Authentication failed)。' },
      { t: '9.6 內部通道:INTERNAL 埠(9092)', why: '誠實說明:INTERNAL 埠只是另一個 SASL 埠,任何有效 SCRAM 帳號都能「認證」進去,但授權仍生效 → 必須以防火牆限制 9092/9093 只開給 broker 與 controller 節點。', manual: ['kc kafka-topics --bootstrap-server broker1:9092 --command-config /clients/scram-svc-orders.properties --list', 'kc kafka-topics --bootstrap-server broker1:9092 --command-config /clients/scram-svc-orders.properties --create --topic hack --partitions 1 --replication-factor 2'], ev: 'int-svc', re: /./, evb: 'int-svc-authz', expect: '第一個能列出(認證通過);第二個建立 topic 被拒(授權擋住)。', warn: '防火牆:9092(INTERNAL)、9093(CONTROLLER)只對 broker/controller 節點開放(RHEL 9 以 firewalld 的 rich rule 或 zone 限制來源位址;本專案未在 RHEL 實機驗證,指令請依客戶環境調整)。這是本專案的設計選擇;官方只建議內部通道避免使用 SASL/PLAIN + LDAP,並未規定埠隔離方式。' },
      { t: '9.7 AD 故障演練', manual: ['docker stop openldap; sleep 3', produce('scram-svc-orders', 'orders.events', 'during-ad-outage') + '    # 服務:照常', produce('plain-yujie', 'orders.events', 'during-ad-outage') + '    # 人:新登入失敗', 'docker start openldap; sleep 15', produce('plain-yujie', 'orders.events', 'after-ad-recovery') + '    # 恢復'], ev: 'ad-down-svc', re: /./, evb: 'ad-down-human', expect: 'AD 掛掉:服務(SCRAM)照常;人的新登入失敗;AD 恢復後人恢復。', tip: '韌性差異:服務與內部通道不依賴 AD;AD 故障只影響人的新登入與群組更新。' },
    ],
  },

  // ───────────────────────── Lab 10 ─────────────────────────
  {
    id: 'ch10', n: 10, title: '收尾:audit log 彙整', time: '5 分',
    goal: '用 audit log 回顧整場:誰被拒、誰被允許、誰嘗試改授權。',
    pre: ['已跑過前面的 Lab(audit log 內有事件)。', '官方預設的 audit log 只擷取 Management 與 Authorize 兩類事件(含 allowed 與 denied);produce、consume、describe 預設關閉。本 demo 由自訂路由 config/audit-router.json 開啟(經 .env 注入 broker)。'],
    autoAll: ['./demo.sh 10'],
    steps: [
      { t: '10.1 被拒絕的事件', manual: [AUDIT(R`--topic '^(orders|payments)\.' --granted false --summary --top 10`)], ev: 'audit-denied', re: /DENIED/, expect: '次數 / principal / 動作 / 資源的彙總,例如 ming、yujie、svc-orders 的 Metadata/Produce 被拒。', imgs: [['ch10/01-audit-denied.png', '被 RBAC 擋下的動作']] },
      { t: '10.2 被允許的事件', manual: [AUDIT(R`--topic '^orders\.events$' --granted true --summary --top 10`)], ev: 'audit-allowed', re: /ALLOWED/, expect: '誰實際寫入/讀取了 orders.events。' },
      { t: '10.3 權限變更紀錄', manual: [AUDIT(R`--method '^mds\.Authorize$' --topic '^(orders|payments|kafka-cluster|security-metadata)' --summary --top 8`)], ev: 'audit-mgmt', re: /mds.Authorize/, expect: 'mds.Authorize(AlterAccess)事件:非管理員(yujie)的改授權嘗試也被記錄為 DENIED。', imgs: [['ch10/03-audit-mgmt.png', '權限變更事件(含 yujie 的 DENIED)']], tip: '未授權者多半在 Metadata/Describe 就被擋,所以 audit 路由要包含 describe-denied 才看得到。', warn: '不是所有拒絕都查得到:例如只有 DeveloperRead 的 ming produce 被拒(叢集層級 IdempotentWrite,官方歸為 PRODUCE 類 kafka.InitProducerId),在本 demo 的 audit 中找不到對應事件(原因未明)。稽核需求要另外盤點。' },
    ],
  },

  // ───────────────────────── Lab 11 ─────────────────────────
  {
    id: 'ch11', n: 11, title: '(進階)維運分權:唯讀 / ops / topic-admin / rbac-admin', time: '20 分',
    goal: '正式環境「人只能唯讀」,但仍要有人看叢集、有人管 topic、有人管授權:用 AD 群組拆成不同角色,需要時經核准臨時加入、做完收回。並且看清楚每個角色「真正能做什麼」,包含強角色的風險(實測結果,不是推論)。',
    pre: ['Lab 4 完成(ming 在 orders-read)。', '三個維運群組(ops、topic-admin、rbac-admin)的 role 在 Lab 0 就綁好了,日常這三個群組是空的;臨時提權 = 只在 AD 把人加進群組,Kafka 端零變更。', '若之前跑過本 Lab:先清掉殘留的群組成員、role binding 與 infra.ops-demo topic(見下方「起點狀態」指令)。'],
    pre_cmd: [
      ldapMod('delete', 'yujie', 'ops') + ' 2>/dev/null',
      ldapMod('delete', 'yujie', 'topic-admin') + ' 2>/dev/null',
      ldapMod('delete', 'yujie', 'rbac-admin') + ' 2>/dev/null',
      ldapMod('delete', 'ming', 'ops') + ' 2>/dev/null',
      ldapMod('delete', 'ming', 'topic-admin') + ' 2>/dev/null',
      ldapMod('delete', 'ming', 'rbac-admin') + ' 2>/dev/null',
      "hc --cert /certs/client-bootstrap.pem --key /certs/client-bootstrap.key \"${JSON[@]}\" -X DELETE $MDS/security/1.0/principals/Group%3Aorders-write/roles/DeveloperRead/bindings -d '{\"scope\":{\"clusters\":{\"kafka-cluster\":\"" + CID + "\"}},\"resourcePatterns\":[{\"resourceType\":\"Topic\",\"name\":\"infra.\",\"patternType\":\"PREFIXED\"}]}' >/dev/null",
      bindRes('Group:orders-write', 'DeveloperRead', 'Group', 'demo-', 'PREFIXED') + ' >/dev/null   # consumer group 的讀取權:console consumer 需要它;讓下面「讀得到/讀不到」只取決於 topic 權限',
      bindRes('Group:orders-read', 'DeveloperRead', 'Group', 'demo-', 'PREFIXED') + ' >/dev/null',
      'kc kafka-topics --bootstrap-server $BOOT --command-config /clients/token-bootstrap.properties --delete --topic infra.ops-demo 2>/dev/null; sleep 12   # 等群組快取與 topic 刪除完成',
    ],
    autoAll: ['./demo.sh 11', './scenarios/ch11-separation.sh'],
    steps: [
      { t: '11.1 角色對照:三個維運群組的 role 平常就綁好了', why: 'bootstrap 時已經把這三組綁好:ops = Operator(叢集層級)、topic-admin = ResourceOwner(所有 Topic 與 Consumer Group)、rbac-admin = UserAdmin(只管授權)。平常這三個 AD 群組沒有人,所以沒有人有這些權限。',
        manual: ["for g in ops topic-admin rbac-admin; do hc -u gary:gary-pw \"${JSON[@]}\" -X POST $MDS/security/1.0/lookup/rolebindings/principal/Group%3A$g -d \"$CL\" | grep -o '\"Group:[a-z-]*\":{\"[A-Za-z]*\"'; done"],
        ev: 'matrix', re: /Operator|ResourceOwner|UserAdmin/, expect: '三行:Group:ops → Operator、Group:topic-admin → ResourceOwner、Group:rbac-admin → UserAdmin。' },
      { t: '11.2 在 C3 檢視角色對照', ui: ['瀏覽器開 https://localhost:9022,以 gary 登入', 'Administration → Manage role assignments → Cluster:看 ops、rbac-admin 等群組', '切到 Topic:看 topic-admin 的 ResourceOwner'], expect: 'C3 與 MDS API 是同一份資料。', imgs: [['ch11/c11-1-matrix-cluster.png', 'C3:Cluster 範圍的群組對應'], ['ch11/c11-2-matrix-topic.png', 'C3:Topic 範圍的群組對應']] },
      { t: '11.3 日常:ming(orders-read)可讀;yujie 想建 topic → 被拒', manual: [consume('plain-ming', 'orders.events', 'demo-ming'), 'kc kafka-topics --bootstrap-server $BOOT --command-config /clients/plain-yujie.properties --create --topic infra.ops-demo --partitions 1 --replication-factor 2'], ev: 'ming-daily', evb: 'yujie-before', re: /Processed a total of [1-9]\d* messages[\s\S]*(TopicAuthorizationException|Authorization failed)/i, expect: 'ming 讀到資料;yujie 建立 topic 被拒(Authorization failed):他是開發者,不是 topic 管理。' },
      { t: '11.4 臨時提權 1:經核准,把 yujie 加進 ops(AD 操作)', re: /modifying entry/, ui: ['phpLDAPadmin:cn=ops 的 member 加入 CN=YUJIE,OU=orders,OU=dev,OU=users,dc=corp,dc=demo → Update Object'], uiEq: [ldapMod('add', 'yujie', 'ops'), 'sleep 10'], expect: 'Kafka 端零變更;約 10 秒內生效。', imgs: [['ch11/ldap-grant-yujie-ops-after.png', 'ops 加入 yujie 之後']] },
      { t: '11.5 ops(Operator)能看,但什麼都改不了', why: '實測:Operator 建不了 topic、讀不到資料、改不了授權,連 kafka-topics --describe 都被拒(只能列出 topic 清單)。所以只屬於 ops 的人,OP menu 裡依賴 describe 的項目也跑不了。',
        manual: ['kc kafka-topics --bootstrap-server $BOOT --command-config /clients/plain-yujie.properties --create --topic infra.ops-demo --partitions 1 --replication-factor 2', bindRes('Group:orders-write', 'DeveloperRead', 'Topic', 'infra.', 'PREFIXED', 'yujie:yujie-pw') + '   # yujie 想改授權'], ev: 'ops-limits', evb: 'ops-noacl', re: /(TopicAuthorizationException|Authorization failed)[\s\S]*HTTP 403/i, expect: '建 topic 被拒;改授權回 [HTTP 403]。' },
      { t: '11.6 收回 1:把 yujie 移出 ops(AD 操作)', re: /modifying entry/, uiEq: [ldapMod('delete', 'yujie', 'ops'), 'sleep 10'], expect: '群組成員清空(僅剩占位成員 NOBODY)。' },
      { t: '11.7 臨時提權 2:把 yujie 加進 topic-admin;這是強角色', ui: ['phpLDAPadmin:cn=topic-admin 的 member 加入 CN=YUJIE,…'], uiEq: [ldapMod('add', 'yujie', 'topic-admin'), 'sleep 10'],
        manual: ['kc kafka-topics --bootstrap-server $BOOT --command-config /clients/plain-yujie.properties --create --topic infra.ops-demo --partitions 1 --replication-factor 2', 'echo ops-secret-1 | kc kafka-console-producer --bootstrap-server $BOOT --command-config /clients/plain-gary.properties --topic infra.ops-demo   # 先由 gary 放一筆資料', consume('plain-yujie', 'infra.ops-demo', 'demo-yujie'), bindRes('Group:orders-write', 'DeveloperRead', 'Topic', 'infra.', 'PREFIXED', 'yujie:yujie-pw') + '   # 在他的 Topic* 範圍內改授權'],
        ev: 'topic-create', evb: 'topic-read', evc: 'topic-acl', re: /Created topic[\s\S]*ops-secret-1[\s\S]*HTTP 204/, expect: '建立 topic 成功;讀到 ops-secret-1;改授權回 [HTTP 204]。',
        warn: 'topic-admin(ResourceOwner Topic*、Group*)是強角色:能建、刪 topic,讀得到所有資料,而且在自己的 Topic* 範圍內還能改授權。所以只在需要時臨時加入,事後立刻收回。舊版教材說「維運能管 topic 但讀不到資料」,對新的角色設計不成立。' },
      { t: '11.8 收回 2:把 yujie 移出 topic-admin;並先收掉剛才示範用的授權', re: /modifying entry[\s\S]*HTTP 204/, manual: ["hc --cert /certs/client-bootstrap.pem --key /certs/client-bootstrap.key \"${JSON[@]}\" -X DELETE $MDS/security/1.0/principals/Group%3Aorders-write/roles/DeveloperRead/bindings -d '{\"scope\":{\"clusters\":{\"kafka-cluster\":\"" + CID + "\"}},\"resourcePatterns\":[{\"resourceType\":\"Topic\",\"name\":\"infra.\",\"patternType\":\"PREFIXED\"}]}'"], uiEq: [ldapMod('delete', 'yujie', 'topic-admin'), 'sleep 10'], expect: '[HTTP 204];群組成員清空。' },
      { t: '11.9 臨時提權 3:把 ming 加進 rbac-admin;他只能改授權', ui: ['phpLDAPadmin:cn=rbac-admin 的 member 加入 CN=MING,…'], uiEq: [ldapMod('add', 'ming', 'rbac-admin'), 'sleep 10'],
        manual: [bindRes('Group:orders-write', 'DeveloperRead', 'Topic', 'infra.', 'PREFIXED', 'ming:ming-pw') + '   # ming 改授權', 'kc kafka-topics --bootstrap-server $BOOT --command-config /clients/plain-ming.properties --create --topic infra.ming-test --partitions 1 --replication-factor 2'],
        ev: 'rbac-bind', evb: 'rbac-nodata', re: /HTTP 204[\s\S]*(TopicAuthorizationException|Authorization failed)/i, expect: '改授權回 [HTTP 204];ming 建 topic 被拒。', tip: 'UserAdmin 只管授權,不能建 topic、不能讀資料,所以拆成獨立的 rbac-admin 群組。' },
      { t: '11.10 授權生效:yujie(開發者)現在讀得到 infra.ops-demo', why: '注意這裡換了一個新的 consumer group 名稱(demo-yujie-effect)。同一個 group 讀過的 topic 會提交 offset,再用 --from-beginning 也不會從頭讀(實測踩過:讀到 0 筆、逾時)。',
        manual: ['sleep 6', consume('plain-yujie', 'infra.ops-demo', 'demo-yujie-effect')], ev: 'dev-effect', re: /ops-secret-1/, expect: '讀到 ops-secret-1。之後出現 TimeoutException 是正常的:topic 只有 1 筆資料,consumer 等不到第 3 筆,15 秒後逾時結束。' },
      { t: '11.11 收回 3,以及收回後再操作皆被拒', uiEq: [ldapMod('delete', 'ming', 'rbac-admin'), 'sleep 10'], manual: ['kc kafka-topics --bootstrap-server $BOOT --command-config /clients/plain-yujie.properties --create --topic infra.ops-demo2 --partitions 1 --replication-factor 2', bindRes('Group:orders-write', 'DeveloperRead', 'Topic', 'infra.', 'PREFIXED', 'ming:ming-pw')], ev: 'topic-revoked', evb: 'rbac-revoked', re: /(TopicAuthorizationException|Authorization failed)[\s\S]*HTTP 403/i, expect: 'yujie 建 topic 被拒;ming 改授權回 [HTTP 403]。回到日常唯讀與開發者狀態。' },
      { t: '11.12 稽核:誰在什麼時候做了授權變更、誰被拒', manual: [AUDIT(R`--method '^(mds\.Authorize|kafka\.CreateTopics)$' --topic '^infra\.' --last 10`)], ev: 'audit', re: /YUJIE/, expect: '時間序事件:User:YUJIE CreateTopics DENIED → ALLOWED → 收回後 DENIED;User:MING mds.Authorize ALLOWED(UserAdmin)→ DENIED。',
        warn: 'UserAdmin 的授權變更(mds.Authorize)有 audit 紀錄,可以事後追查是誰、什麼時候改了什麼。' },
      { t: '11.13 清理(讓本 Lab 可重複練習)', why: '收回授權後,把示範用的 infra.* 讀取權限與 topic 一併清掉;否則下次練習時 yujie 會因為殘留的 role binding 直接讀得到資料。',
        manual: [
          "hc --cert /certs/client-bootstrap.pem --key /certs/client-bootstrap.key \"${JSON[@]}\" -X DELETE $MDS/security/1.0/principals/Group%3Aorders-write/roles/DeveloperRead/bindings -d '{\"scope\":{\"clusters\":{\"kafka-cluster\":\"" + CID + "\"}},\"resourcePatterns\":[{\"resourceType\":\"Topic\",\"name\":\"infra.\",\"patternType\":\"PREFIXED\"}]}'",
          'kc kafka-topics --bootstrap-server $BOOT --command-config /clients/token-bootstrap.properties --delete --topic infra.ops-demo',
        ], re: /HTTP 204/, expect: '[HTTP 204](binding 已移除);topic 刪除無錯誤。這裡用 bootstrap 憑證操作,因為此時 ming 已不是 rbac-admin。' },
    ],
  },
  // ───────────────────────── Lab 12 ─────────────────────────
  {
    id: 'ch12', n: 12, title: '(進階)legacy app 經 REST Proxy:機器用憑證、人用 Basic 並存', time: '15 分',
    goal: 'legacy app 無法用 Kafka client(沒辦法 SCRAM),只能 HTTP 丟資料。讓它經 REST Proxy 進來,同時人(AD 帳密)照常使用同一個 REST Proxy,且身分一路傳到 broker、權限最小化。',
    pre: ['Lab 5 完成(REST Proxy 與 MDS 的 impersonation 已設定)。', '起點狀態:清掉 legacy app 與開發者群組在 orders.* 的寫入 binding(見下方指令)。', '前提認知:服務帳號(SCRAM)進 REST Proxy 會是 401——REST Proxy 把 Basic 交給 MDS 查 AD,AD 沒有服務帳號;所以機器改用 client 憑證。'],
    pre_cmd: [
      unbindBoot('User:legacy-orders', 'DeveloperWrite', 'Topic', 'orders.'),
      unbindBoot('Group:orders-write', 'DeveloperWrite', 'Topic', 'orders.'),
      'sleep 6',
    ],
    autoAll: ['./demo.sh 12', './scenarios/ch12-legacy-app.sh'],
    steps: [
      { t: '12.1 REST Proxy 設定:讓「人」與「機器」並存', why: '只要三個設定。重點是 ssl.client.authentication:官方列有 NONE / REQUESTED / REQUIRED 三值,官方 AuthenticationHandler 範例是 REQUIRED(純 mTLS);人沒有憑證,所以人機並存必須用 REQUESTED。「人機並存」這個組合是本專案實測,官方文件未明述。處理器改用官方的多協定 AuthenticationHandler;憑證 DN 要對應成主體。',
        cfg: ['rest.servlet.initializor.classes=io.confluent.common.security.jetty.initializer.AuthenticationHandler   # 原本是 InstallBearerOrBasicSecurityHandler(只認 Basic/Bearer,憑證會被忽略 → 401)', 'ssl.client.authentication=REQUESTED                                  # 有帶憑證才驗;人不用憑證', 'auth.ssl.principal.mapping.rules=RULE:^.*CN=([^,]*).*$/$1/,DEFAULT      # 屬性名稱依官方 AuthenticationHandler 頁(實測:改成 confluent.rest. 前綴會失效);DN 在 Java 內是反序 O=Demo,CN=xxx(實測觀察),所以不能寫 ^CN=…'],
        expect: '本環境的 docker-compose 已包含這些設定;改完需重啟 REST Proxy(它沒有資料,可安全重啟)。', warn: '憑證身分只能用 User: 綁 role,不支援群組(官方:mTLS RBAC 不支援群組授權)。每個 legacy app 一張憑證,到期前要換;RBAC 綁的是 CN,CN 不變就不用重綁。' },
      { t: '12.2 發一張 client 憑證給 legacy app(CN = app 名稱)', why: '由客戶的 CA 簽發;CN 就是之後 RBAC 的主體(User:legacy-orders)。只有「無法用 Kafka client 的 legacy app」才需要憑證,其他服務仍走 SCRAM。',
        manual: [R`docker run --rm -v "$D/certs:/certs" --entrypoint sh alpine/openssl -c '
cd /certs
openssl genrsa -out client-legacy-orders.key 2048
openssl req -new -key client-legacy-orders.key -subj "/CN=legacy-orders/O=Demo" -out client-legacy-orders.csr
openssl x509 -req -in client-legacy-orders.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out client-legacy-orders.pem -days 825 -sha256
chmod 644 client-legacy-orders.*
openssl x509 -in client-legacy-orders.pem -noout -subject -issuer -dates'`],
        auto: ['bash scripts/make-client-cert.sh legacy-orders'], ev: 'issue-cert', re: /CN *= *legacy-orders/, expect: 'subject=CN=legacy-orders, O=Demo;issuer 是你的 CA。' },
      { t: '12.3 授權前:憑證通過認證,但沒有 role → 403', manual: [legacyPost('legacy-orders', 'orders.events')], auto: ['./scripts/rp-cert.sh legacy-orders POST /topics/orders.events \'{"records":[{"value":{"order":"L-1"}}]}\''], ev: 'no-role', re: /HTTP 403/, expect: '[HTTP 403],內文 error_code 40301。認證(你是誰)通過、授權(你能做什麼)還沒有——和人完全一樣的規則。' },
      { t: '12.4 C3 操作:把 orders.* 寫入權限指派給 User:legacy-orders', re: /HTTP 204/, why: '憑證身分只能綁 User:(不是群組)。C3 的 Principal name 輸入 legacy-orders,選 Create "legacy-orders"。',
        ui: ['gary 登入 C3 → Manage role assignments → Topic → Add role assignment', 'Principal type = User;Principal name 輸入 legacy-orders,選 Create "legacy-orders"', 'Role = DeveloperWrite;Pattern type = Prefixed;Resource ID = orders. → Save'],
        uiEq: [bindRes('User:legacy-orders', 'DeveloperWrite', 'Topic', 'orders.'), 'sleep 6'], expect: '列表出現 legacy-orders / DeveloperWrite / orders.*,與 AD 群組、服務帳號並列。', imgs: [['ch12/c12-1-legacy-form.png', 'C3:User / legacy-orders / DeveloperWrite / orders.'], ['ch12/c12-1-legacy-saved.png', 'C3:儲存後的 Topic 範圍列表']] },
      { t: '12.5 授權後:legacy app 寫入成功;寫 payments 被拒(最小權限)', ui: ['(Postman 版,選做)Settings → Certificates → Add Certificate:Host = localhost:8086,CRT file = demo/certs/client-legacy-orders.pem,KEY file = demo/certs/client-legacy-orders.key;Authorization 選 No Auth', 'POST https://localhost:8086/topics/orders.events,Headers:Content-Type = application/vnd.kafka.json.v2+json、Accept = application/vnd.kafka.v2+json,Body:{"records":[{"value":{"order":"L-1"}}]}'], manual: [legacyPost('legacy-orders', 'orders.events'), legacyPost('legacy-orders', 'payments.events')], ev: 'ok', re: /HTTP 200[\s\S]*HTTP 403/, evb: 'least-priv', expect: '第一個 [HTTP 200](回傳 partition 與 offset);第二個 [HTTP 403]。' },
      { t: '12.6 沒憑證也沒帳密 → 401;有效憑證但沒授權 → 403;偽造憑證 → TLS 就被拒', why: '三種「進不來」各有不同的層次:沒身分(401)、有身分沒權限(403)、不是客戶 CA 簽發(連 TLS 握手都過不了,HTTP 000)。',
        manual: [R`hc -H "Accept: application/vnd.kafka.v2+json" -H "Content-Type: application/vnd.kafka.json.v2+json" -X POST $RP/topics/orders.events -d '{"records":[{"value":{"x":1}}]}'`,
          R`docker run --rm -v "$D/certs:/certs" --entrypoint sh alpine/openssl -c 'cd /certs; openssl genrsa -out client-legacy-other.key 2048 2>/dev/null; openssl req -new -key client-legacy-other.key -subj "/CN=legacy-other/O=Demo" -out client-legacy-other.csr; openssl x509 -req -in client-legacy-other.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out client-legacy-other.pem -days 825 -sha256 2>/dev/null; chmod 644 client-legacy-other.*'`,
          legacyPost('legacy-other', 'orders.events'),
          R`docker run --rm -v "$D/certs:/certs" --entrypoint sh alpine/openssl -c 'cd /certs; openssl req -x509 -newkey rsa:2048 -nodes -keyout client-rogue.key -out client-rogue.pem -subj "/CN=legacy-orders/O=Demo" -days 2 2>/dev/null; chmod 644 client-rogue.*'`,
          legacyPost('rogue', 'orders.events')],
        ev: 'no-cert', evb: 'other-cert', evc: 'rogue-cert', re: /HTTP 401[\s\S]*HTTP 403[\s\S]*HTTP 000/, expect: '依序:[HTTP 401]、[HTTP 403]、[HTTP 000](TLS 握手失敗,curl 沒有拿到 HTTP 回應)。自簽憑證連 CN 寫成 legacy-orders 也沒用——信任來自 CA,不是名字。' },
      { t: '12.7 並存:同一個 REST Proxy,人照常用 Basic(AD 帳密)', why: '先讓開發者群組有 orders.* 寫入權(Lab 3 做過的授權),再用 yujie 的 Basic 帳密寫入。機器用憑證、人用帳密,兩種方式同時可用。',
        manual: [bindRes('Group:orders-write', 'DeveloperWrite', 'Topic', 'orders.'), 'sleep 6', R`hc -u yujie:yujie-pw -H "Accept: application/vnd.kafka.v2+json" -H "Content-Type: application/vnd.kafka.json.v2+json" -X POST $RP/topics/orders.events -d '{"records":[{"value":{"order":"H-1","by":"yujie"}}]}'`], ev: 'human', re: /HTTP 204[\s\S]*HTTP 200/, expect: '先 [HTTP 204](binding),再 [HTTP 200](yujie 寫入成功)。' },
      { t: '12.8 稽核:broker 端看到的主體', manual: [AUDIT(R`--topic '^(orders|payments)\.' --last 40 | grep -E "legacy|yujie" | tail -8`)], ev: 'audit', re: /User:legacy-orders.*ALLOWED/, expect: '機器是 User:legacy-orders(不是 restproxy),人是 User:YUJIE;沒授權的事件是 DENIED。', tip: '這證明 REST Proxy 不是把所有請求都變成自己的身分,而是把「進來的人或 app」的身分一路傳到 broker(經 MDS 代理)。' },
      { t: '12.9 看 MDS 日誌:人與機器對 MDS 的呼叫不同', why: '同樣是進 REST Proxy,MDS 看到的呼叫不一樣:人是 /authenticate(主體 yujie);機器是 /impersonate(主體 restproxy,代 legacy-orders 申請)。下面各發一個請求,再看 broker(MDS 內建於 broker)的請求日誌。',
        manual: [R`hc -u yujie:yujie-pw -H "Accept: application/vnd.kafka.v2+json" $RP/topics >/dev/null
hc --cert /certs/client-legacy-orders.pem --key /certs/client-legacy-orders.key -H "Accept: application/vnd.kafka.v2+json" $RP/topics >/dev/null
sleep 3
for b in broker1 broker2; do docker logs $b --since 25s 2>&1 | grep -E "> (GET|POST) https://[^ ]+/security/1.0/(authenticate|impersonate)"; done | sed -E 's#.*> (GET|POST) https://[^/]+(/[^ ]+) .*User Principal: (.*)#\1 \2   MDS 看到的主體: \3#' | sort -u`],
        auto: ['bash scripts/mds-calls.sh'], ev: 'mds-log', re: /impersonate .*restproxy/, expect: '看到 GET /security/1.0/authenticate 主體 yujie(人),以及 POST /security/1.0/impersonate 主體 restproxy、之後 GET /authenticate 主體 legacy-orders(機器)。',
        imgs: [['../labguide/img/flow.png', '圖:人與機器的身分傳遞(實測)']], tip: '人:REST Proxy 把使用者的 Basic 帳密轉給 MDS,MDS 向 AD 驗證後直接回 token。機器:REST Proxy 以自己的憑證(CN=restproxy)請 MDS「代 legacy-orders 簽發 token」,不經過 AD。之後的 /authenticate 呼叫用途為推論(未直接證實)。' },
      { t: '12.10 看「代為申請」的 token 內容', why: 'REST Proxy 向 MDS 申請的 token 是 MDS 用私鑰簽的 JWT。broker 用 MDS 的公鑰驗證簽章與到期時間,主體取自 sub。下面手動重現這個呼叫並解開 claims(不印 token 本身)。',
        manual: [R`TOK=$(hc --cert /certs/client-restproxy.pem --key /certs/client-restproxy.key "${'$'}{JSON[@]}" -X POST $MDS/security/1.0/impersonate -d '{"targetPrincipalName":"legacy-orders","targetPrincipalType":"USER"}' | grep -o '"auth_token":"[^"]*"' | cut -d'"' -f4)
echo "$TOK" | cut -d. -f2 | tr '_-' '/+' | awk '{ while (length($0) % 4) $0 = $0 "="; print }' | base64 -d 2>/dev/null; echo`],
        auto: ['bash scripts/mds-impersonate.sh restproxy legacy-orders claims'], ev: 'token', re: /cp_proxy/, expect: 'JSON 內有 "sub":"legacy-orders"(broker 看到的主體)、"cp_proxy":"O=Demo,CN=restproxy"(誰代為申請)、iss=Confluent,exp 比 iat 晚 3600 秒(1 小時)。' },
      { t: '12.11 風險:REST Proxy 的憑證能代誰?', why: 'impersonate 端點只認「impersonation 超級使用者」(本環境 User:restproxy)的憑證;但被代的對象只要不在「受保護清單」就可以。若特權身分(例如 SystemAdmin)不在清單內,拿到 REST Proxy 私鑰的人就能代他,等於升為管理員。實測修正前 GARY、c3 都能被代(200),所以要把所有特權身分列入受保護清單。**清單區分大小寫,要寫 AD 記錄的大小寫**:使用者名稱是 CN(大寫)時,寫成 User:gary 擋不住 GARY(實測:gary 回 403,GARY 與 Gary 都回 200)。',
        cfg: ['confluent.metadata.server.impersonation.super.users=User:restproxy', 'confluent.metadata.server.impersonation.protected.users=User:bootstrap;User:kafka-broker;User:kafka-controller;User:c3;User:restproxy;User:GARY   # 只能填 User:(官方範例格式);管理員個人帳號需逐一列入'],
        manual: [R`for t in yujie legacy-orders GARY c3 bootstrap; do printf "restproxy 憑證代 %-14s → " $t; hc --cert /certs/client-restproxy.pem --key /certs/client-restproxy.key "${'$'}{JSON[@]}" -X POST $MDS/security/1.0/impersonate -d "{\"targetPrincipalName\":\"$t\",\"targetPrincipalType\":\"USER\"}" | tail -1; done
printf "c3 憑證代 %-19s → " yujie; hc --cert /certs/client-c3.pem --key /certs/client-c3.key "${'$'}{JSON[@]}" -X POST $MDS/security/1.0/impersonate -d '{"targetPrincipalName":"yujie","targetPrincipalType":"USER"}' | tail -1`],
        auto: ['for t in yujie legacy-orders GARY c3 bootstrap; do printf "restproxy 憑證代 %-14s → " $t; bash scripts/mds-impersonate.sh restproxy $t; done'], ev: 'impersonate-scope', re: /GARY[^\n]*403[\s\S]*c3 +→[^\n]*403[\s\S]*bootstrap[^\n]*403/, expect: 'yujie、legacy-orders 為 [HTTP 200](一般使用者可代,正常);GARY、c3、bootstrap 為 [HTTP 403](受保護);用 c3 的憑證代別人也是 403(它不是 impersonation 超級使用者)。',
        imgs: [['../labguide/img/protected.png', '圖:受保護清單修正前後(實測)']],
        warn: '導入時務必:1) 特權身分(所有 SystemAdmin、管理員個人帳號)都列入 protected.users;2) 嚴格保護 client-restproxy 的私鑰檔權限(owner、600);3) 監看 MDS 日誌中 restproxy 對 /impersonate 的呼叫。限制:audit log 的 actingPrincipal 為空,看不出請求經過 REST Proxy。受保護清單只認 User:——實測在清單中混入 Group:kafka-admins,整份清單失效(連清單內的 User:c3 都能被代,HTTP 200),不要這樣做;AD 新增管理員時,要同步更新清單(broker 靜態設定)。' },
      { t: '12.12 清理', manual: [unbindBoot('User:legacy-orders', 'DeveloperWrite', 'Topic', 'orders.', false), unbindBoot('Group:orders-write', 'DeveloperWrite', 'Topic', 'orders.', false)], re: /HTTP 204[\s\S]*HTTP 204/, expect: '兩個 [HTTP 204]。', warn: '注意:這一步會移除 Group:orders-write 對 orders. 的 DeveloperWrite(Lab 3 建立,Lab 5、6 需要)。照 12 → 13 → 14 往下做沒問題;若要回頭重做 Lab 5 或 6,請先執行 ./scripts/reset.sh 與 Lab 3 的授權。' },
    ],
  },
  // ───────────────────────── Lab 13 ─────────────────────────
  {
    id: 'ch13', n: 13, title: '(進階)Control Center 身分盤點:人與機器各走哪條路', time: '20 分',
    goal: '像 REST Proxy 一樣盤點 C3:誰連到誰、人與機器各用什麼身分、哪些連線沒有認證、哪些身分擁有過大權力。每一項都用日誌、audit 與實際呼叫驗證,並與官方文件對照。',
    pre: ['Lab 5 完成(C3、MDS 已設定)。', 'C3 與 REST Proxy 容器執行中;已有人用 C3 操作過(audit 內有事件)。', '官方文件重點(C3 RBAC 頁):REST 層要用 BEARER;C3 不支援 OAUTHBEARER 以外的 SASL 機制;C3 主體必須是 SystemAdmin;MDS 認證的範例是帳密。官方 mTLS RBAC 頁(7.8+)另有憑證做法(Streams 用 TokenCertificateLoginCallbackHandler)。本環境 C3→MDS 以 confluent.metadata.ssl.* 另設憑證(屬性與官方範例不同),實測可行。'],
    table: { rows: [
      ['連線', '人 / 機器', '怎麼認證', '本 Lab 的證據'],
      ['瀏覽器 → C3 → MDS', '人', '登入時一次 Basic(C3 代轉給 MDS 換 token),之後全是 Bearer', '13.1 瀏覽器請求紀錄'],
      ['C3 → MDS(看使用者能看什麼)', '人', '使用者本人的 token', '13.2 MDS 日誌主體=ming'],
      ['C3 → broker(使用者操作)', '人', '帶使用者本人的身分(OAUTHBEARER)', '13.3 audit 主體=User:MING / gary'],
      ['C3 自己 → MDS / broker', '機器', 'client 憑證(CN=c3)換 token;User:c3(SystemAdmin)', '13.4、13.5'],
      ['自動化 → C3 API', '機器', '憑證換 MDS token → Bearer', '13.6'],
      ['→ Prometheus / Alertmanager', '機器', 'HTTPS + Basic 帳密(C3、broker 各帶 c3 帳密);不帶帳密 401', '13.7、13.8;細節見 Lab 17'],
    ], colW: [2300, 1000, 3300, 2426] },
    autoAll: ['./demo.sh 13', './scenarios/ch13-c3-inventory.sh'],
    steps: [
      { t: '13.1 人:瀏覽器登入 C3,看它怎麼認證', why: '瀏覽器只在登入時用一次 Basic(AD 帳密),C3 把它轉給 MDS 換 token;之後所有對 C3 的呼叫都帶 Bearer token;同時伺服器還設了一個 HttpOnly 的 auth_token cookie——C3 優先看 Bearer,沒有 Bearer 才用 cookie(實測)。token 約 1 小時到期並會續期。',
        ui: ['以 gary 登入 C3(https://localhost:9022)', '按 F12 開發者工具 → Network → 重新整理 Topics 頁面', '看請求標頭:第一個 .../security/1.0/authenticate 的 Authorization 是 Basic;其餘 /2.0/... 與 /api/... 都是 Bearer'],
        auto: ['cd e2e && node probe-c3-api.mjs gary'], ev: 'browser', re: /authenticate +\[Basic\]/, imgs: [['../labguide/img/c3map.png', '圖:C3 的連線與身分(人 vs 機器)']], expect: '第一個 authenticate 呼叫是 [Basic];其餘全是 [Bearer]。這與官方說明一致:前端取得 token 並持續更新。' },
      { t: '13.2 人:MDS 日誌裡的呼叫主體是使用者本人', why: 'C3 查「這個使用者能看什麼」時,是用使用者自己的 token 呼叫 MDS,所以 MDS 看到的主體是 ming,不是 c3。',
        ui: ['以 ming 登入 C3,打開 Topics 頁面'], uiEq: ['(cd e2e && node probe-c3-api.mjs ming >/dev/null); sleep 2'],
        manual: [R`for b in broker1 broker2; do docker logs $b --since 60s 2>&1 | grep -E "> (GET|POST|PUT|DELETE) https://[^ ]+ -- [0-9]+ > User Principal: MING$"; done | sed -E 's#.*> (GET|POST|PUT|DELETE) https://[^/]+(/[^ ?]+).*User Principal: (.*)#\3 \1 \2#' | sort | uniq -c | sort -rn`],
        auto: ['bash scripts/mds-calls-by.sh MING 60'], ev: 'mds-as-user', re: /MING +(GET|POST|PUT) +\/security\/1\.0\/(lookup|authorize|authenticate)/, expect: '主體都是 ming:authenticate(登入)、lookup/.../visibility 與 PUT /authorize(依使用者權限過濾畫面)。沒有 c3。' },
      { t: '13.3 人:broker 端看到的也是使用者本人', why: '看 audit log 中「來源 IP 是 C3」的事件:主體是登入的使用者。官方 C3 RBAC 頁沒有明說 C3 以誰的身分查詢 Kafka(只說 C3 主體必須是 SystemAdmin),這裡是本環境的實測觀察,不是官方文字。',
        manual: [R`C3IP=$(docker inspect control-center --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
RPIP=$(docker inspect restproxy --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
kc kafka-console-consumer --bootstrap-server $BOOT --command-config /clients/token-bootstrap.properties --topic confluent-audit-log-events --from-beginning --timeout-ms 12000 2>/dev/null | node scripts/audit-by-source.mjs $C3IP $RPIP`],
        ev: 'audit-source', re: /C3 +\| User:(MING|GARY)/, expect: '來源 C3 的事件主體是 User:GARY、User:MING(ListOffsets、FetchConsumer、CreateTopics、DescribeConfigs);來源 REST Proxy 的則是 yujie、legacy-orders 等(對照 Lab 12)。', tip: '本 demo 的 audit router 只排除 kafka-broker、kafka-controller;c3 不排除,所以用 c3 憑證改授權會被記錄(實測)。為避免 C3 輪詢 offset 洗版(不處理時幾分鐘數千筆 ListOffsets / OffsetFetch),topic 前綴的 consume 路由不記錄「被允許」的事件,被拒的仍記;代價是看不到誰成功讀了資料。' },
      { t: '13.4 機器:C3 自己的服務身分', why: 'C3 的背景串流與內部 topic 用自己的身分:以 client 憑證(CN=c3)向 MDS 換 token,再用 OAUTHBEARER 連 broker。這與 REST Proxy 的「代為申請」不同:這裡是 C3 直接用自己的憑證換自己的 token。',
        manual: [R`TOK=$(hc --cert /certs/client-c3.pem --key /certs/client-c3.key -H "Accept: application/json" $MDS/security/1.0/authenticate | grep -o '"auth_token":"[^"]*"' | cut -d'"' -f4)
echo "$TOK" | cut -d. -f2 | tr '_-' '/+' | awk '{ while (length($0) % 4) $0 = $0 "="; print }' | base64 -d 2>/dev/null; echo`],
        auto: ['bash scripts/mds-token.sh c3 claims'], ev: 'c3-token', re: /"sub":"c3"/, expect: 'claims 內 "sub":"c3"、有效 1 小時。MDS 日誌中偶爾可見 c3 的 GET /authenticate(啟動與每小時續期)。' },
      { t: '13.5 風險:c3 的憑證 = 管理員', why: '官方要求 C3 主體必須是 SystemAdmin(要看全部 consumer group 與 lag)。所以任何拿到 client-c3 私鑰的人,等於拿到管理員:實測可以建立並刪除 role binding。',
        manual: [R`T=$(hc --cert /certs/client-c3.pem --key /certs/client-c3.key -H "Accept: application/json" $MDS/security/1.0/authenticate | grep -o '"auth_token":"[^"]*"' | cut -d'"' -f4)
B='{"scope":{"clusters":{"kafka-cluster":"XyZBQ3-GTvKH2qNfP7X33A"}},"resourcePatterns":[{"resourceType":"Topic","name":"probe-","patternType":"PREFIXED"}]}'
U=$MDS/security/1.0/principals/User%3Aprobe-user/roles/DeveloperRead/bindings
hc -X POST   -H "Authorization: Bearer $T" "${'$'}{JSON[@]}" $U -d "$B"
hc -X DELETE -H "Authorization: Bearer $T" "${'$'}{JSON[@]}" $U -d "$B"`],
        auto: ['bash scripts/c3-admin-proof.sh'], ev: 'c3-admin', re: /HTTP 204[\s\S]*HTTP 204/, expect: '兩個 [HTTP 204](建立、刪除都成功)。', warn: '保護 client-c3.keystore.p12:檔案權限(owner、600)、不放進版本庫、限制能登入 C3 主機的人;並已把 User:c3 列入 MDS 的 impersonation 受保護清單(Lab 12),避免 REST Proxy 憑證代為申請 c3 的 token。注意:拿掉 c3 的 SystemAdmin 並不能降低風險——實測 C3 的 Streams 與 license 立即 TopicAuthorizationException(_confluent-command、_confluent-alerts),約 1 分鐘後 C3 容器退出。' },
      { t: '13.6 機器:自動化(CI)呼叫 C3 API', why: '機器若要呼叫 C3 的 API,同樣先向 MDS 換 token(用 client 憑證),再帶 Bearer。沒有 token 就是 401。這裡用 Lab 12 的 legacy-orders 憑證示範(它只有 orders.* 寫入權)。',
        manual: [R`T=$(hc --cert /certs/client-legacy-orders.pem --key /certs/client-legacy-orders.key -H "Accept: application/json" $MDS/security/1.0/authenticate | grep -o '"auth_token":"[^"]*"' | cut -d'"' -f4)
hc -H "Authorization: Bearer $T" https://control-center:9022/2.0/clusters/kafka
hc https://control-center:9022/2.0/clusters/kafka`],
        auto: ['bash scripts/c3-api-check.sh legacy-orders'], ev: 'automation', re: /HTTP 200[\s\S]*HTTP 401/, expect: '第一個回 [] 與 [HTTP 200]:token 有效,但 legacy-orders 在 C3 沒有可見的叢集,所以是空清單(RBAC 仍生效);第二個(沒有 token)是一頁 HTML 的 401(Token is not present)。換成有叢集權限的主體(例如 gary 的 token)就會看到叢集資料。' },
      { t: '13.7 機器:Prometheus(HTTPS + Basic)', why: 'C3 與 broker 都要帶帳密才讀得到、寫得進 Prometheus;不帶帳密就是 401。(啟用方式與其他加密補強見 Lab 17。)',
        manual: [R`echo "--- 不帶帳密"; hc "https://prometheus:9090/api/v1/query?query=count(up)"
echo "--- 帶 Basic 帳密(c3)"; hc -u c3:prom-pw "https://prometheus:9090/api/v1/query?query=count(up)"`], auto: ['bash scripts/dcurl.sh "https://prometheus:9090/api/v1/query?query=count(up)"   # 不帶帳密', 'bash scripts/dcurl.sh -u c3:prom-pw "https://prometheus:9090/api/v1/query?query=count(up)"'], ev: 'prometheus', re: /HTTP 401[\s\S]*HTTP 200/, expect: '不帶帳密:Unauthorized 與 [HTTP 401];帶帳密:{"status":"success",...} 與 [HTTP 200]。', warn: '官方支援 C3 與 Prometheus / Alertmanager 之間的 TLS + HTTP Basic(CP 7.5 以後),另有 mTLS 設定頁。客戶不想管憑證時,以共用 server 憑證做 TLS 加上 Basic 帳密較貼合。Basic 沒有細部授權:有帳密就是完整讀寫,所以 C3 與其他用途的帳密要分開,而且 C3 的 INFO 日誌會印出 Authorization 標頭(Base64),日誌檔要保護。' },
      { t: '13.8 機器:Alertmanager(HTTPS + Basic)連「寫入」都要帳密', why: '下面先不帶帳密建立一筆靜音(被擋),再帶 c3 帳密建立(成功,3 分鐘)並立刻刪除。沒有保護的 Alertmanager,攻擊者可以用同樣方式靜音告警。',
        manual: [R`S=$(date -u -d "+1 minute" +%Y-%m-%dT%H:%M:%SZ); E=$(date -u -d "+3 minutes" +%Y-%m-%dT%H:%M:%SZ)
BODY="{\"matchers\":[{\"name\":\"alertname\",\"value\":\"probe\",\"isRegex\":false}],\"startsAt\":\"$S\",\"endsAt\":\"$E\",\"createdBy\":\"probe\",\"comment\":\"probe\"}"
echo "--- 不帶帳密"; hc -X POST https://alertmanager:9093/api/v2/silences -H "Content-Type: application/json" -d "$BODY"
echo "--- 帶 Basic 帳密(c3)"; R=$(hc -u c3:am-pw -X POST https://alertmanager:9093/api/v2/silences -H "Content-Type: application/json" -d "$BODY")
echo "$R"; ID=$(echo "$R" | grep -o '"silenceID":"[^"]*"' | cut -d'"' -f4)
hc -u c3:am-pw -X DELETE https://alertmanager:9093/api/v2/silence/$ID`],
        auto: ['bash scripts/alertmanager-probe.sh'], ev: 'alertmanager', re: /HTTP 401[\s\S]*HTTP 200[\s\S]*HTTP 200/, expect: '不帶帳密:Unauthorized 與 [HTTP 401];帶帳密:回傳 silenceID 與 [HTTP 200];刪除也是 [HTTP 200]。', imgs: [['../labguide/img/c3risk.png', '圖:C3 的三個風險與對策']] },
    ],
  },
  // ───────────────────────── Lab 14 ─────────────────────────
  {
    id: 'ch14', n: 14, title: '(進階)broker 內建 Admin REST 的保護:匿名擋下、依使用者授權', time: '10 分',
    goal: 'Confluent Server 的 broker 內建一組 Admin REST(/kafka/v3),與 MDS 共用 8091 埠。未設定安全擴充時它完全沒有認證。本 Lab 驗證:依官方設定後,匿名被擋、已登入者依自己的 role 授權。',
    pre: ['Lab 0 完成(compose 已含本 Lab 的設定,x-broker-env 內的 kafka.rest.* 區塊)。', '本 Lab 不需要 C3。', '官方依據:Configure Security for the Admin REST APIs for Confluent Server(kafka.rest. 前綴的屬性)。'],
    pre_cmd: [
      ldapMod('delete', 'ming', 'orders-read') + ' 2>/dev/null',
      ldapMod('delete', 'ming', 'orders-write') + ' 2>/dev/null',
      'sleep 10   # 等群組快取:本 Lab 要用「沒有任何 role 的 ming」',
    ],
    autoAll: ['./demo.sh 14', './scenarios/ch14-admin-rest.sh'],
    steps: [
      { t: '14.0 設定(已在 docker-compose 的 x-broker-env,僅供對照)', why: '未設定時,broker 日誌會印 REST security extensions are not configured;匿名 GET /kafka/v3/clusters 會成功進入 AdminClient,實測曾使 broker 記憶體耗盡而崩潰(2 次,首次原因未確認)。8091 同時是 MDS 埠,必須對使用者與元件開放,不能用防火牆整個擋掉。',
        cfg: ['kafka.rest.rest.servlet.initializor.classes=io.confluent.common.security.jetty.initializer.InstallBearerOrBasicSecurityHandler', 'kafka.rest.kafka.rest.resource.extension.class=io.confluent.kafkarest.security.KafkaRestSecurityResourceExtension', 'kafka.rest.public.key.path=/etc/kafka/secrets/public.pem            # MDS token 公鑰', 'kafka.rest.confluent.metadata.bootstrap.server.urls=https://broker1:8091,https://broker2:8092', 'kafka.rest.confluent.metadata.ssl.truststore.location=…', 'kafka.rest.bootstrap.servers=SASL_SSL://broker1:9094,SASL_SSL://broker2:9094   # 本專案實測:必須指向支援 OAUTHBEARER 的 CLIENT 埠', 'kafka.rest.client.security.protocol=SASL_SSL'],
        manual: [], expect: '(無指令)。重點:設定要成組出現;只加 kafka.rest.client.* 固定 SCRAM 身分而沒有安全擴充,實測會讓所有請求變成超級使用者,比未設定更糟。',
        warn: '若漏了 kafka.rest.bootstrap.servers,已認證的請求會回 Client SASL mechanism OAUTHBEARER not enabled in the server, enabled mechanisms are [SCRAM-SHA-512](它預設連到只開 SCRAM 的內部埠)。' },
      { t: '14.1 匿名呼叫 → 401', manual: [R`hc https://broker1:8091/kafka/v3/clusters | tail -1`], auto: ['bash scenarios/ch14-admin-rest.sh'], ev: 'anon', re: /HTTP 401/, expect: '[HTTP 401]。未設定時這個呼叫會直接成功。', imgs: [['ch14/01-anon.png', '匿名 → 401']] },
      { t: '14.2 錯誤密碼 → 401', manual: [R`hc -u gary:bad https://broker1:8091/kafka/v3/clusters | tail -1`], ev: 'badpw', re: /HTTP 401/, expect: '[HTTP 401]。' },
      { t: '14.3 管理員 gary:列出 topic', why: '以 AD 帳密(Basic)進入,Admin REST 把它交給 MDS 驗證,再以使用者身分向 Kafka 查詢。', manual: [R`hc -u gary:gary-pw https://broker1:8091/kafka/v3/clusters/XyZBQ3-GTvKH2qNfP7X33A/topics | grep -o '"kind":"KafkaTopicList"\|\[HTTP [0-9]*\]'`], ev: 'gary-topics', re: /KafkaTopicList[\s\S]*HTTP 200/, expect: '"kind":"KafkaTopicList" 與 [HTTP 200];清單內含全部 topic。' },
      { t: '14.4 無 role 的 ming:同一個呼叫,清單是空的', manual: [R`hc -u ming:ming-pw https://broker1:8091/kafka/v3/clusters/XyZBQ3-GTvKH2qNfP7X33A/topics | grep -o '"data":\[\]\|\[HTTP [0-9]*\]'`], ev: 'ming-topics', re: /"data":\[\][\s\S]*HTTP 200/, expect: '"data":[] 與 [HTTP 200]:只回他有權看的資源。' },
      { t: '14.5 ming 寫入 → 內容回 40301,但 HTTP 仍是 200', manual: [R`hc -u ming:ming-pw -X POST "${'$'}{JSON[@]}" https://broker1:8091/kafka/v3/clusters/XyZBQ3-GTvKH2qNfP7X33A/topics/orders.events/records -d '{"value":{"type":"JSON","data":{"x":1}}}'`], ev: 'ming-produce', re: /"error_code":40301/, expect: '內容含 "error_code":40301 與 Not authorized to access topics;HTTP 狀態碼仍是 200。', imgs: [['ch14/05-ming-produce.png', 'ming 寫入:內容 40301']], warn: '被拒時 HTTP 狀態碼仍是 200,錯誤在內容裡:監控與腳本必須檢查內容的 error_code,不能只看 HTTP 狀態碼。' },
      { t: '14.6 gary 寫入 → 成功', manual: [R`hc -u gary:gary-pw -X POST "${'$'}{JSON[@]}" https://broker1:8091/kafka/v3/clusters/XyZBQ3-GTvKH2qNfP7X33A/topics/orders.events/records -d '{"value":{"type":"JSON","data":{"x":1}}}'`], ev: 'gary-produce', re: /"offset":[0-9]+/, expect: '回傳 partition_id 與 offset。' },
    ],
  },
];
