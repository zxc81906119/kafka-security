#!/usr/bin/env node
// ============================================================================
// config-export.mjs — 把已驗證的 docker-compose 設定轉成正式環境(RHEL 手動安裝)用的 .properties
// ----------------------------------------------------------------------------
// 白話:demo 的設定寫在 docker-compose 的環境變數(KAFKA_SSL_KEYSTORE_LOCATION…),客戶在 RHEL 上要填的是
//   server.properties 這類檔案。這支工具用 Confluent 映像相同的轉換規則(去前綴、___→-、__→_、_→.、轉小寫)
//   把環境變數轉回設定名稱,並把 demo 專屬的值換成佔位符,手冊直接引用輸出,內容就不會和實測環境脫節。
// 用法:
//   node tools/config-export.mjs [輸出目錄]        預設輸出到 labguide/config-ref/
// 輸出:每個元件一份 <元件>.properties(controller、broker、restproxy、schema-registry、connect、control-center)
//   與 config-ref.json(給手冊產生器讀)。
// 前置條件:docker compose 可執行(只讀設定,不會啟動或改動容器)。
// ============================================================================
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DEMO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT = path.resolve(DEMO, process.argv[2] || 'labguide/config-ref');

// 代表性的服務(第二台以後設定相同,只差主機名稱)→ 正式環境的設定檔名與環境變數前綴
const COMPONENTS = [
  { svc: 'controller1', name: 'controller', file: 'controller.properties', prefix: 'KAFKA_', extra: { CONFLUENT_: 'confluent.' } },
  { svc: 'broker1', name: 'broker', file: 'server.properties', prefix: 'KAFKA_', extra: { CONFLUENT_: 'confluent.' } },
  { svc: 'restproxy1', name: 'restproxy', file: 'kafka-rest.properties', prefix: 'KAFKA_REST_' },
  { svc: 'schema-registry1', name: 'schema-registry', file: 'schema-registry.properties', prefix: 'SCHEMA_REGISTRY_' },
  { svc: 'connect1', name: 'connect', file: 'connect-distributed.properties', prefix: 'CONNECT_' },
  { svc: 'control-center', name: 'control-center', file: 'control-center.properties', prefix: 'CONTROL_CENTER_', to: 'confluent.controlcenter.' },
];

// 只有容器才需要的環境變數(JVM 參數、映像啟動腳本用、demo 實驗開關),不屬於設定檔
const DOCKER_ONLY = /^(KAFKA_OPTS|KAFKA_HEAP_OPTS|KAFKA_JMX_|KAFKA_LOG4J_|KAFKA_DATA_DIRS$|CLUSTER_ID$|CUB_|SCRAM_BOOTSTRAP_|QUORUM_|SBC_|.*_JMX_OPTS$|.*_HEAP_OPTS$|.*_LOG4J_|CONNECT_PLUGIN_PATH_EXTRA)/;

// Confluent 映像的轉換規則:___ → -、__ → _、_ → .,轉小寫
const toKey = (rest) => rest.replace(/___/g, '\u0001').replace(/__/g, '\u0002').replace(/_/g, '.')
  .replace(/\u0001/g, '-').replace(/\u0002/g, '_').toLowerCase();

// demo 的值 → 正式環境佔位符(主機、密碼、憑證目錄、叢集 ID)
function placeholder(key, v) {
  let s = String(v).replace(/\$\$/g, '$');          // compose 的 $$ 跳脫還原成 $
  if (/password|secret|credentials|user\.info|api\.key/i.test(key) || /^changeit$/.test(s)) return '<由 CyberArk 提供>';
  s = s.replace(/(password|secret)=("[^"]*"|[^\s;,]+)/gi, '$1="<由 CyberArk 提供>"');   // JAAS 等字串裡夾帶的密碼
  s = s.replace(/\/etc\/kafka\/secrets\//g, '<SSL_DIR>/')
    .replace(/\b(prometheus|alertmanager|minio|mailpit)\b(?=[:/])/g, (m) => `<${m.toUpperCase()}_HOST>`)
    .replace(/\bbroker([1-5])\b/g, '<BROKER$1_HOST>')
    .replace(/\bcontroller([1-4])\b/g, '<CONTROLLER$1_HOST>')
    .replace(/\bschema-registry([12])\b/g, '<SR$1_HOST>')
    .replace(/\bconnect([12])\b/g, '<CONNECT$1_HOST>')
    .replace(/\brestproxy([12])\b/g, '<RESTPROXY$1_HOST>')
    .replace(/\/mnt\/config\//g, '<C3_CONFIG_DIR>/')
    .replace(/\bopenldap\b/g, '<AD_HOST>')
    .replace(/dc=corp,dc=demo/gi, '<AD_BASE_DN>');
  return s;
}

const cfg = JSON.parse(execFileSync('docker', ['compose', '--profile', 'full', '--profile', 'connect', 'config', '--format', 'json'],
  { cwd: DEMO, encoding: 'utf8', maxBuffer: 64 << 20 }));

fs.mkdirSync(OUT, { recursive: true });
const all = {};
for (const c of COMPONENTS) {
  const env = cfg.services[c.svc]?.environment || {};
  const props = [];
  for (const [k, v] of Object.entries(env).sort()) {
    if (DOCKER_ONLY.test(k) || v === '' || v == null) continue;
    let key = null;
    const extra = Object.entries(c.extra || {}).find(([p]) => k.startsWith(p));
    if (k.startsWith(c.prefix)) key = (c.to || '') + toKey(k.slice(c.prefix.length));
    else if (extra) key = extra[1] + toKey(k.slice(extra[0].length));
    if (!key) continue;
    props.push({ key, value: placeholder(key, v), env: k });
  }
  all[c.name] = { file: c.file, source: c.svc, props };
  const body = [`# ${c.file} — 由 tools/config-export.mjs 從已驗證的 demo 設定(${c.svc})產生;<…> 為依環境填入的值`,
    ...props.map(p => `${p.key}=${p.value}`)].join('\n') + '\n';
  fs.writeFileSync(path.join(OUT, `${c.name}.properties`), body);
  console.log(`${c.name.padEnd(16)} ${String(props.length).padStart(3)} 項 → ${path.relative(DEMO, path.join(OUT, c.name + '.properties'))}`);
}
fs.writeFileSync(path.join(OUT, 'config-ref.json'), JSON.stringify(all, null, 2));
