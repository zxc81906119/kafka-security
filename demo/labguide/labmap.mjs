// 每個 Lab 的「Lab 地圖」:一句話講這堂要證明什麼、動到哪些元件(打亮)、走哪幾條路(✔ 允許 / ✘ 拒絕)。
// 產生 img-src/labmap-NN.html,再由 e2e/shot-img.mjs 轉成 img/labmap-NN.png(1280x480)。
// 用法: node labmap.mjs && (cd ../e2e && node shot-img.mjs labmap-00 … labmap-17)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const here = path.dirname(fileURLToPath(import.meta.url));

// 元件晶片(與「Demo 部署元件」圖對應)
const COMP = {
  browser: '瀏覽器', postman: 'Postman', cli: 'Kafka CLI / curl(kc、hc)', opmenu: 'OP menu', certs: '憑證',
  ad: '模擬 AD(openldap)', ldapadmin: 'phpLDAPadmin', controller: 'controller', broker: 'broker + MDS', rp: 'REST Proxy', c3: 'Control Center', prom: 'Prometheus', am: 'Alertmanager', legacy: 'legacy app', conjur: 'CyberArk(Conjur)',
};
// 每個 Lab:prove 一句話;use 用到的元件;flows [誰 / 做什麼, 經過哪裡, 結果]
export const MAPS = [
  { n: 0, prove: '把零件立起來:憑證 → 模擬 AD → controller → broker(含 MDS)→ 第一批授權 → REST Proxy、Control Center', use: ['cli', 'certs', 'ad', 'ldapadmin', 'controller', 'broker', 'rp', 'c3', 'prom', 'am'],
    flows: [['make-certs.sh', 'demo/certs', '✔ 一張共用 server 憑證 + client 憑證 + MDS token 金鑰'], ['up.sh(或逐步手動)', 'LDAP → controller → broker → bootstrap 授權 → 服務帳號、topic', '✔ preflight 18 / 18']] },
  { n: 1, prove: '預設全部拒絕:沒有身分、密碼錯、有身分但沒授權,三種都進不來', use: ['cli', 'rp', 'broker', 'ad'],
    flows: [['不帶帳密', 'REST Proxy', '✘ 401'], ['yujie 密碼錯', 'REST Proxy / broker(PLAIN)', '✘ 401 / 認證失敗'], ['ming 帳密正確、沒有 role', 'broker', '✘ 看不到任何業務 topic']] },
  { n: 2, prove: '人用 AD 帳號登入 Control Center;三個人看到的內容由 RBAC 決定', use: ['browser', 'c3', 'broker', 'ad'],
    flows: [['gary(登入時 Basic 一次,之後 Bearer)', 'C3 → MDS → AD', '✔ 全部 topic + 管理功能(cluster-admin 等群組有 role)'], ['yujie(在 orders-write,但群組還沒有 role)', 'C3', '✘ 登入成功,看不到任何業務 topic'], ['ming(不在任何群組)', 'C3', '✘ 登入成功,看不到資源、沒有管理選單']] },
  { n: 3, prove: '授權跟著 AD 群組走:role 綁 Group,人員異動只改 AD,Kafka 端零變更、數秒內生效', use: ['browser', 'c3', 'ldapadmin', 'ad', 'broker', 'cli'],
    flows: [['gary 在 C3 指派', 'Group:orders-write → DeveloperWrite / Read on orders.*', '✔ 204'], ['yujie 寫入 orders.events', 'broker', '✘ 授權前被拒 → ✔ 授權後成功'], ['ming 加進 AD 群組', 'phpLDAPadmin(Kafka 不動)', '✔ 約 5 秒後同一指令成功']] },
  { n: 4, prove: '正式環境「人只能唯讀」:orders-read 只有 DeveloperRead,寫入與建 topic 都被拒', use: ['browser', 'c3', 'ldapadmin', 'ad', 'broker', 'cli'],
    flows: [['gary 在 C3 指派', 'Group:orders-read → DeveloperRead on orders.*', '✔ 204'], ['ming 從 orders-write 移到 orders-read', '讀 orders.events', '✔ 讀到資料'], ['ming 寫入 / 建 topic', 'broker', '✘ 被拒;yujie 不受影響']] },
  { n: 5, prove: 'Postman 與腳本用同一份 AD 身分:REST Proxy 與 MDS 都認 Basic 帳密', use: ['postman', 'rp', 'broker', 'ad'],
    flows: [['無帳密 / 密碼錯', 'REST Proxy', '✘ 401'], ['gary / yujie / ming(Basic)', 'REST Proxy /topics', '✔ 認證都成功;各自只看到自己有權限的 topic'], ['gary', 'MDS lookup', '✔ 與 C3 同一份資料'], ['整份 collection(newman)', 'REST Proxy + MDS', '✔ 10 requests、14 assertions 全過']] },
  { n: 6, prove: '維運腳本共用、身分各人各自:同一支腳本讀各自的 client.properties,結果由 RBAC 決定', use: ['cli', 'broker', 'ad'],
    flows: [['yujie 跑 orders-heartbeat.sh', 'broker(yujie 的設定檔)', '✔ 送出'], ['ming 跑同一支腳本', 'broker(ming 的設定檔;唯讀)', '✘ 被拒'], ['反面教材:共用 shared-ops 帳號', 'broker', '✔ 都能寫 → audit 分不出是誰']] },
  { n: 7, prove: '機器不放 AD:Kafka 內建 SCRAM 服務帳號 + RBAC 最小權限', use: ['cli', 'broker', 'c3', 'browser'],
    flows: [['建立 svc-orders(SCRAM)', 'broker', '✔'], ['svc-orders 寫 orders.*', 'broker', '✘ 授權前 → ✔ 授權後(DeveloperWrite)'], ['svc-orders 寫 payments.*', 'broker', '✘ 最小權限'], ['用 AD 的方式驗 svc-orders', 'broker(PLAIN → LDAP)', '✘ 不在 AD']] },
  { n: 8, prove: '共用 server 憑證只能做加密、不能當身分:兩個元件出示同一張,MDS 看到同一個主體', use: ['cli', 'certs', 'broker', 'c3', 'rp'],
    flows: [['共用 server 憑證', 'MDS /authenticate', '主體 = kafka.demo.local(分不出是 C3 還是 REST Proxy)'], ['client-c3 / client-restproxy', 'MDS /authenticate', '主體 = c3 / restproxy(可各自授權)']] },
  { n: 9, prove: '密碼輪替不中斷;內部通道是 mTLS(共用憑證),沒憑證進不來、不是 super user 做不了事;AD 掛了服務不受影響', use: ['cli', 'broker', 'controller', 'ad'],
    flows: [['svc-orders-v2 新舊並行 → 停用舊帳號', 'broker', '✔ 不中斷;舊密碼立刻失效'], ['沒有身分連 CONTROLLER 9093', 'controller', '✘ 認證失敗'], ['停掉 AD', 'SCRAM 服務照常寫入;人登入失敗', '✔ / ✘']] },
  { n: 10, prove: '每個動作都查得到:從 audit topic 彙整誰被拒、誰被允許、誰改了授權', use: ['cli', 'broker'],
    flows: [['confluent-audit-log-events', '被拒事件彙總', 'DENIED:次數 / 主體 / 動作 / 資源'], ['', '被允許事件、授權變更', 'ALLOWED;mds.Authorize(含非管理員的嘗試)']] },
  { n: 11, prove: '維運分權:ops 看得到改不了;topic-admin 是強角色;rbac-admin 只管授權;臨時加入、事後收回', use: ['ldapadmin', 'ad', 'broker', 'cli', 'browser', 'c3'],
    flows: [['yujie 加進 ops', '建 topic / 改授權', '✘ ✘(只能看)'], ['yujie 加進 topic-admin', '建 topic / 讀資料 / 改授權', '✔ ✔ ✔(強角色,用完就收回)'], ['ming 加進 rbac-admin', '改授權 / 建 topic', '✔ / ✘'], ['全部收回', '再操作', '✘ 回到唯讀與開發者']] },
  { n: 12, prove: 'legacy app 只能 HTTP:機器用 client 憑證經 REST Proxy、人用 Basic 並存;身分一路傳到 broker', use: ['legacy', 'certs', 'rp', 'broker', 'browser', 'c3'],
    flows: [['legacy-orders 憑證', 'REST Proxy → MDS /impersonate → broker', '✘ 授權前 403 → ✔ 授權後 200;寫 payments ✘'], ['無憑證無帳密 / 偽造憑證', 'REST Proxy', '✘ 401 / TLS 握手被拒'], ['restproxy 憑證代 GARY、c3', 'MDS /impersonate', '✘ 403(受保護清單,區分大小寫)']] },
  { n: 13, prove: 'Control Center 盤點:人用本人身分;C3 自己用憑證身分(SystemAdmin);監控元件要認證', use: ['browser', 'c3', 'broker', 'prom', 'am', 'cli'],
    flows: [['gary / ming 用瀏覽器', 'C3 → MDS → broker', '主體 = 本人(MDS 日誌、audit 都看得到)'], ['C3 自己(CN=c3)', 'MDS 換 token', 'sub = c3,等於管理員 → 嚴控私鑰'], ['不帶帳密', 'Prometheus / Alertmanager', '✘ 401']] },
  { n: 14, prove: 'broker 內建的 Admin REST 也要保護:匿名擋下、已登入者依自己的 role', use: ['cli', 'broker', 'ad'],
    flows: [['匿名', 'broker 8091 /kafka/v3', '✘ 401(未設定時完全無認證)'], ['gary(AD 帳密)', '/kafka/v3 列 topic、寫入', '✔ 200'], ['ming', '/kafka/v3 寫入', 'HTTP 200 但內容 error_code 40301']] },
  { n: 15, prove: '人員異動只改 AD:已發出、還沒到期的 token 在收回群組的當下失去權限', use: ['ldapadmin', 'ad', 'broker', 'rp', 'cli'],
    flows: [['yujie 取 token → 寫入', 'REST Proxy', '✔ 200'], ['AD 移出 orders-write', 'phpLDAPadmin / ldapmodify', 'Kafka 與 token 都不動'], ['同一個 token 再寫入', 'REST Proxy', '✘ 403;帳號仍能登入但看不到業務 topic']] },
  { n: 16, prove: '日常維運走 OP menu:用自己的 AD 身分;能不能做由 Kafka RBAC 與 sudo 決定;每個動作留紀錄', use: ['opmenu', 'broker', 'am', 'cli'],
    flows: [['gary 登入選單', '健康檢查、生效設定、匯出權限、audit 查詢、滾動重啟', '✔'], ['維護模式', 'Alertmanager silence(HTTPS + Basic)', '✔ 開始 / 結束'], ['ming 用同一個選單匯出權限', 'MDS', '✘ 403(選單不判斷權限,Kafka 判斷)'], ['時窗外 / 別人持有鎖', '變更類項目', '✘ 被擋']] },
  { n: 17, prove: '線上傳輸都加密:AD 走 LDAPS、監控 HTTPS + Basic、Control Center HTTPS', use: ['broker', 'ad', 'prom', 'am', 'c3', 'browser', 'cli'],
    flows: [['broker → AD', 'LDAPS 636(信任 CA 才連得上)', '✔;389 上沒有 broker 的連線'], ['Prometheus / Alertmanager', '無帳密 / 錯密碼 / 明文 HTTP', '✘ 401 / 401 / 400;帶帳密 ✔ 200'], ['使用者 → C3 9022', '憑證驗證', '✔;不信任 CA → curl 錯誤 60']] },
  { n: 18, prove: '秘密不落地:應用、OP menu、broker 都以機器身分向 CyberArk(Conjur)取密碼;沒被授權的拿不到;輪替後應用自己跟上', use: ['conjur', 'cli', 'broker', 'opmenu', 'am', 'ad'],
    flows: [['svc-orders(API key → token)', 'Conjur 取 SCRAM 密碼 → 記憶體組設定 → 寫入 orders.events', '✔ 200;寫入成功'], ['rogue-app / 錯誤 API key', 'Conjur', '✘ 404 / 401'], ['輪替:改密碼,或新舊並行(建 v2 → 隔離舊帳號 → 看 audit → 才刪)', '應用重啟自動跟上 / 舊帳號', '✔ 零中斷 / ✘ 解除角色後被拒'], ['實驗:停用舊帳號時已連著的舊連線', '只停用 SCRAM 憑證 / 先解除角色', '✔ 只停用憑證擋不住 / ✘ 解除角色才切斷'], ['OP menu、broker2', '帳密與主金鑰執行時向 Conjur 取(自寫腳本或官方 summon)', '✔ 維護模式開關;設定檔只剩密文仍能查 AD']] },
  { n: 19, prove: '帳號被偷之後:停用的帳號舊連線會失效、認證失敗會告警、流量與連線數有上限;AD 鎖定是雙面刃', use: ['cli', 'broker', 'prom', 'am', 'ad'],
    flows: [['停用「連著的」帳號(只停用 SCRAM 憑證)', 'broker 每 60 秒重新認證', '✔ 約 60 秒內舊連線被切斷(第 18 章預設是切不斷)'], ['連續 5 次錯誤登入', 'broker → Prometheus 規則 → Alertmanager', '✔ KafkaAuthFailuresBurst firing,告警送達'], ['弱 TLS 套件 / 同來源 4 條連線 / 超額流量', 'broker(套件限定、連線上限、quota)', '✘ 弱套件被拒、超額連線被拒、吞吐量 1/16'], ['對 GARY 亂試 6 次', 'MDS / Kafka → AD(鎖定原則)', '✘ GARY 被鎖(連對密碼也進不去);✔ 緊急路徑與機器帳號不受影響;管理員解鎖後恢復'], ['刪除 SCRAM 帳號 → 重啟 broker(KAFKA-20774)', 'broker 重放 metadata', '✘ 所有 SCRAM 登入失敗 → ✔ 重建被刪帳號再重啟即恢復;所以停用一律覆寫密碼不刪除']] },
  { n: 20, prove: 'Schema Registry 納入同一套授權:subject 與 KEK 的權限跟 AD 群組走;欄位級加密(CSFLE)需要加購授權,這個環境無法驗證加密', use: ['cli', 'broker', 'ad', 'certs'],
    flows: [['無帳密 / 密碼錯', 'Schema Registry(交 MDS 驗證)', '✘ 401'], ['yujie 註冊 orders. / payments. 的 schema', 'SR → MDS 授權(subject role)', '✔ orders. 200 → ✘ payments. 403;列表只看到自己有權限的'], ['gary / yujie / ming 對 KEK', 'SR → MDS 授權(Kek:<名稱> role)', '✔ security 群組可建 → yujie 只能讀 → ✘ ming 無 role 403'], ['註冊帶 ENCRYPT 規則的 schema', 'Schema Registry 授權檢查', '✘ 402 需要企業版 + CSFLE 加購授權(加密與解密未驗證)'], ['讀 topic 原始位元組', 'kafka-console-consumer', '✘ 卡號是明文 → 上線前一定要這樣檢查']] },
  { n: 21, prove: 'HA 叢集(3 controller、3 broker、副本 3、min.isr 2):少 1 台不影響,少 2 台 broker 時 acks=all 被擋、acks=1 讀不到;controller 失去多數時控制面停擺;滾動重啟零遺失', use: ['cli', 'broker'],
    flows: [['停 1 台 broker', 'ISR 剩 2 ≥ min.isr 2', '✔ acks=all 寫入不中斷;URP>0 要告警'], ['停 2 台 broker', 'ISR 1 < min.isr 2', '✘ acks=all 被拒;acks=1 回報成功卻讀不到'], ['停 1 台 controller', '剩 2/3 仍有多數', '✔ 建 topic、寫入正常'], ['停 2 台 controller', '失去多數', '✘ 建 topic 與 describe 沒回應 → ✔ 既有 topic 讀寫仍可'], ['滾動重啟 3 broker + 3 controller', 'URP=0 才做下一台;active controller 最後', '✔ 背景寫入 2400 = 2400,零失敗']] },
];

const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');
const mark = r => (r.includes('✔') && r.includes('✘')) ? 'mix' : r.startsWith('✘') ? 'bad' : r.startsWith('✔') ? 'ok' : 'info';
function html(m, title) {
  const chips = Object.entries(COMP).map(([k, v]) => `<span class="chip ${m.use.includes(k) ? 'on' : ''}">${esc(v)}</span>`).join('');
  const flows = m.flows.map(([a, b, c]) => `<div class="f"><div class="a">${esc(a)}</div><div class="ar">➜</div><div class="b">${esc(b)}</div><div class="ar">➜</div><div class="c ${mark(c)}">${esc(c)}</div></div>`).join('');
  return `<!doctype html><html lang="zh-Hant"><head><meta charset="utf-8"><style>
  html,body{margin:0;background:#fff;font-family:"Microsoft JhengHei","Noto Sans TC","PingFang TC",sans-serif;color:#0f2a43}
  .s{width:1280px;box-sizing:border-box;padding:26px 44px 18px;overflow:hidden}
  h1{margin:0;font-size:26px}h1 span{color:#6b4fa0}
  .prove{margin:8px 0 12px;font-size:17px;font-weight:700;background:#f4f0fa;border-left:6px solid #6b4fa0;padding:8px 12px;border-radius:0 8px 8px 0}
  .lab{font-size:13px;color:#4a5a6a;margin:0 0 4px}
  .chips{display:flex;flex-wrap:wrap;gap:6px;margin-bottom:12px}
  .chip{font-size:12.5px;padding:3px 9px;border-radius:12px;background:#f1f4f7;color:#9aa6b2;border:1px solid #e1e7ed}
  .chip.on{background:#0f2a43;color:#fff;border-color:#0f2a43;font-weight:700}
  .f{display:flex;align-items:center;gap:8px;margin:7px 0}
  .a,.b,.c{border-radius:8px;padding:7px 10px;font-size:14px;line-height:1.3;box-sizing:border-box}
  .a{width:300px;flex:none;background:#e8f1fb;border:1px solid #17608f;font-weight:700}
  .b{flex:1;background:#fff;border:1px solid #c9d3dc}
  .c{width:380px;flex:none;font-weight:700}
  .c.ok{background:#e4f3e4;border:1px solid #2e9e49;color:#1f7a34}.c.bad{background:#fbe5e8;border:1px solid #c21a2c;color:#c21a2c}
  .c.mix{background:#fdf1de;border:1px solid #e8890c;color:#7a4a00}.c.info{background:#eef3f7;border:1px solid #6c7f93;color:#2f3f4f}
  .ar{color:#4a5a6a;font-size:18px}
  </style></head><body><div class="s">
  <h1>Lab ${m.n} 地圖 <span>${esc(title)}</span></h1>
  <div class="prove">這堂要證明:${esc(m.prove)}</div>
  <div class="lab">動到的元件(打亮者)</div><div class="chips">${chips}</div>
  ${flows}
  </div></body></html>`;
}

const { LABS } = await import('./labs.mjs');
const { LABS_EXTRA } = await import('./labs-extra.mjs');
const titles = Object.fromEntries([...LABS, ...LABS_EXTRA].map(l => [l.n, l.title]));
const out = path.join(here, 'img-src');
for (const m of MAPS) fs.writeFileSync(path.join(out, `labmap-${String(m.n).padStart(2, '0')}.html`), html(m, titles[m.n] || ''));
console.log('labmap html:', MAPS.length, '→', MAPS.map(m => 'labmap-' + String(m.n).padStart(2, '0')).join(' '));
