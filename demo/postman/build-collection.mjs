// 產生 Postman collection + environment(requests 以章節編號命名,描述欄即講稿,Tests 自動判斷符合預期與否)
import fs from 'node:fs';
const BASE = '{{rest_proxy}}';
const MDS = '{{mds}}';
const KID = '{{kafka_cluster_id}}';
const basic = (u, p) => ({ type: 'basic', basic: [{ key: 'username', value: u }, { key: 'password', value: p }] });
const test = (name, expectStatus, extra = '') => ({ listen: 'test', script: { type: 'text/javascript', exec: [
  `pm.test(${JSON.stringify(name)}, function () { pm.response.to.have.status(${expectStatus}); });`, extra].filter(Boolean) } });
const req = (name, desc, method, url, auth, body, tests, headers = []) => ({
  name, event: [tests], request: { method, auth, description: desc,
    header: [...(headers.some(h => h.key === 'Accept') ? [] : [{ key: 'Accept', value: url.startsWith('{{mds}}') ? 'application/json' : 'application/vnd.kafka.v2+json' }]), ...(body ? [{ key: 'Content-Type', value: 'application/vnd.kafka.json.v2+json' }] : []), ...headers],
    url: { raw: url, host: [url.split('/')[0]], path: url.split('/').slice(1) }, ...(body ? { body: { mode: 'raw', raw: JSON.stringify(body, null, 2) } } : {}) } });
const msg = who => ({ records: [{ value: { order: 'A-3001', by: who } }] });
const U = n => basic('{{' + n + '_user}}', '{{' + n + '_pass}}');

const folder = (name, description, item) => ({ name, description, item });
const collection = {
  info: { name: 'Confluent 安全方案 Demo(AD 人員 + 服務)', schema: 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json',
    description: 'REST Proxy 與 MDS API。帳密不寫在 collection:請在 environment 的 secret 變數填入(人 = AD 帳號)。注意:服務帳號(SCRAM)不能用 Basic 進 REST Proxy(實測 401);機器請用 client 憑證(Postman:Settings → Certificates → Add client certificate,Host = localhost:8086,見 Lab 12)或原生 Kafka client。\n每個 request 的描述欄就是講稿;Tests 分頁會顯示綠/紅(符合預期與否)。' },
  event: [{ listen: 'prerequest', script: { type: 'text/javascript', exec: [
    '// MDS 驗證成功後會設定 auth_token cookie;若不清除,之後「換成另一個人的帳密」的請求仍會以前一個人的身分執行(Postman 與 newman 都是)。',
    'const resolved = pm.variables.replaceIn(pm.request.url.toString());',
    'pm.cookies.jar().clear(resolved, function () {});'] } }],
  item: [
    folder('1 沒有身分進不來', '建立「預設全拒絕」的基準', [
      req('1.1 未帶帳密 → 401', '**講稿**:沒有身分,REST Proxy 直接拒絕。', 'GET', `${BASE}/topics`, { type: 'noauth' }, null, test('未帶帳密應回 401', 401)),
      req('1.2 密碼錯誤 → 401', '**講稿**:帳號是 AD 的,密碼錯誤由 AD 驗證失敗。', 'GET', `${BASE}/topics`, basic('{{yujie_user}}', '{{bad_pass}}'), null, test('密碼錯誤應回 401', 401)),
    ]),
    folder('5 人:同一份 AD 身分用在工具上', '同一組 AD 帳密,Postman 與 C3 是同一個身分;授權由 AD 群組對應的 role 決定', [
      req('5.1 gary(組長)列出 topics → 200', '**講稿**:gary 屬 cluster-admin、topic-admin、rbac-admin、security(沒有 SystemAdmin),看得到全部 topic。', 'GET', `${BASE}/topics`, U('gary'), null, test('gary 應可列出 topics', 200, `pm.test('可看到 orders.events', function(){ pm.expect(pm.response.text()).to.include('orders.events'); });`)),
      req('5.2 yujie(developers)寫入 orders.events → 200', '**講稿**:yujie 的權限來自 AD 群組 orders-write。', 'POST', `${BASE}/topics/orders.events`, U('yujie'), msg('yujie'), test('yujie 應可寫入', 200)),
      req('5.3 yujie 寫入 payments.events → 403', '**講稿**:最小權限:developers 只被授權 orders.*,碰 payments.* 被拒。', 'POST', `${BASE}/topics/payments.events`, U('yujie'), msg('yujie'), test('yujie 寫 payments 應被拒', 403)),
      req('5.4 ming(readonly)寫入 orders.events → 403', '**講稿**:ming 已移到唯讀群組,寫入被拒(第 4 章)。', 'POST', `${BASE}/topics/orders.events`, U('ming'), msg('ming'), test('ming(唯讀)寫入應被拒', 403)),
      req('5.5 ming(readonly)列出 topics,仍看得到 orders.events → 200', '**講稿**:唯讀可以「看」:列出與讀取資料;但不能寫(5.4)。', 'GET', `${BASE}/topics`, U('ming'), null, test('ming 唯讀應可列出 topics', 200, `pm.test('看得到 orders.events', function(){ pm.expect(pm.response.text()).to.include('orders.events'); });`)),
    ]),
    folder('M MDS API(與 C3 同一份資料)', 'C3 畫面上點的 role assignment,就是這裡查到的資料', [
      req('M.1 gary 登入 MDS 取得 token → 200', '**講稿**:AD 帳密換取 MDS token(短效),之後可用 Bearer 呼叫。', 'GET', `${MDS}/security/1.0/authenticate`, U('gary'), null,
        test('應回 200 並含 auth_token', 200, `pm.test('含 auth_token', function(){ pm.expect(pm.response.json()).to.have.property('auth_token'); }); pm.collectionVariables.set('gary_token', pm.response.json().auth_token);`)),
      { name: 'M.2 列出 Group:orders-write 的 role binding', event: [test('應回 200', 200, `pm.test('含 DeveloperWrite', function(){ pm.expect(pm.response.text()).to.include('DeveloperWrite'); });`)],
        request: { method: 'POST', description: '**講稿**:這就是 C3「Manage role assignments」顯示的內容。', auth: { type: 'bearer', bearer: [{ key: 'token', value: '{{gary_token}}' }] },
          header: [{ key: 'Content-Type', value: 'application/json' }],
          url: { raw: `${MDS}/security/1.0/lookup/principal/Group:orders-write/resources`, host: ['{{mds}}'], path: ['security', '1.0', 'lookup', 'principal', 'Group:orders-write', 'resources'] },
          body: { mode: 'raw', raw: JSON.stringify({ clusters: { 'kafka-cluster': KID } }, null, 2) } } },
      { name: 'M.3 yujie 嘗試新增 role binding → 403', event: [test('非管理員不可新增 role binding', 403)],
        request: { method: 'POST', description: '**講稿**:不是授權管理員(rbac-admin)就不能改授權。', auth: basic('{{yujie_user}}', '{{yujie_pass}}'),
          header: [{ key: 'Content-Type', value: 'application/json' }],
          url: { raw: `${MDS}/security/1.0/principals/Group:orders-write/roles/DeveloperRead/bindings`, host: ['{{mds}}'], path: ['security', '1.0', 'principals', 'Group:orders-write', 'roles', 'DeveloperRead', 'bindings'] },
          body: { mode: 'raw', raw: JSON.stringify({ scope: { clusters: { 'kafka-cluster': KID } }, resourcePatterns: [{ resourceType: 'Topic', name: 'payments.', patternType: 'PREFIXED' }] }, null, 2) } } },
    ]),
  ],
};
const env = (name, values) => ({ name, values: values.map(([key, value, secret]) => ({ key, value, type: secret ? 'secret' : 'default', enabled: true })), _postman_variable_scope: 'environment' });
const common = [['rest_proxy', 'https://localhost:8086'], ['mds', 'https://localhost:8091'], ['kafka_cluster_id', 'XyZBQ3-GTvKH2qNfP7X33A']];
fs.writeFileSync('demo.postman_collection.json', JSON.stringify(collection, null, 2));
fs.writeFileSync('demo-humans.postman_environment.json', JSON.stringify(env('Demo - 人(AD 帳號)', [...common,
  ['gary_user', 'gary'], ['bad_pass', 'wrong-password', true], ['gary_pass', 'gary-pw', true], ['yujie_user', 'yujie'], ['yujie_pass', 'yujie-pw', true], ['ming_user', 'ming'], ['ming_pass', 'ming-pw', true]]), null, 2));
fs.writeFileSync('demo-service.postman_environment.json', JSON.stringify(env('Demo - 服務(範本;SCRAM 帳密僅供原生 Kafka client,不能用 Basic 進 REST Proxy)', [...common,
  ['svc_user', 'svc-orders'], ['svc_pass', '<從密碼庫注入>', true]]), null, 2));
console.log('ok');
