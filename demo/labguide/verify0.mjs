// 驗證 Lab 0(建置環境)的「手動指令」:
//  - 0.2 憑證:在暫存資料夾執行(不動目前環境的 certs/),檢查產出檔案與 SAN
//  - 0.3~0.8:對「已啟動」的環境重跑(皆為冪等:compose up 不重建、binding 重送回 204、SCRAM 同密碼、topic --if-not-exists)
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { LABS, SETUP } from './labs.mjs';

const demo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const header = SETUP.split('\n').slice(1).join('\n');
const lab0 = LABS.find(l => l.n === 0);
const run = (script, cwd, pre = '') => {
  const r = spawnSync('bash', ['-c', header + '\n' + pre + '\n' + script], { cwd, encoding: 'utf8', timeout: 900000, maxBuffer: 64 * 1024 * 1024 });
  return ((r.stdout || '') + (r.stderr || '')).replace(/\r/g, '');
};
const log = []; let fail = 0;
const check = (name, ok, out) => { if (!ok) fail++; console.log(`  ${ok ? '✔' : '✘'} ${name}`); log.push(`\n##### ${name} → ${ok ? 'PASS' : 'FAIL'}\n${out.split('\n').filter(l => !/^(WARNING|SLF4J)/.test(l)).slice(-40).join('\n')}`); };

// 0.2 憑證(暫存資料夾)
{
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'cpcerts-'));
  const tmpW = spawnSync('bash', ['-c', `cd "${tmp.replace(/\\/g, '/')}" && (pwd -W 2>/dev/null || pwd)`], { encoding: 'utf8' }).stdout.trim();
  const s = lab0.steps.find(x => x.t.startsWith('0.2'));
  const out = run(s.manual.join('\n'), tmp, `cd "${tmp.replace(/\\/g, '/')}"; export D="${tmpW}"`);
  const files = fs.existsSync(path.join(tmp, 'certs')) ? fs.readdirSync(path.join(tmp, 'certs')) : [];
  const need = ['ca.pem', 'server.keystore.p12', 'client-c3.keystore.p12', 'client-restproxy.keystore.p12', 'client-bootstrap.keystore.p12', 'keypair.pem', 'public.pem', 'truststore.p12', 'keystore_creds', 'sslkey_creds', 'truststore_creds'];
  const miss = need.filter(f => !files.includes(f));
  check('0.2 憑證(暫存資料夾)產出齊全:缺 ' + (miss.join(',') || '無'), miss.length === 0, out + '\n' + files.join(' '));
  // SAN 檢查:共用憑證含 localhost 與各元件名稱
  const san = run(`docker run --rm -v "${tmpW}/certs:/certs:ro" --entrypoint sh alpine/openssl -c "openssl x509 -in /certs/server.pem -noout -subject -ext subjectAltName"`, demo);
  check('0.2 共用憑證 SAN 含 localhost / broker1 / restproxy', /localhost/.test(san) && /broker1/.test(san) && /restproxy/.test(san) && /kafka\.demo\.local/.test(san), san);
}
// 0.3 ~ 0.8(冪等)
const expect = { '0.3': /LDAP-ready/, '0.4': /modifying entry|already exists|Type or value exists/i, '0.5': /MDS-ready/, '0.6': /HTTP 204/, '0.7': /Completed updating config[\s\S]*Created topic|already exists|Completed updating config/, '0.8': /REST Proxy no-credentials: 401[\s\S]*C3 login page: 200/ };
for (const s of lab0.steps) {
  const k = s.t.slice(0, 3);
  if (!expect[k]) continue;
  const out = run(s.manual.join('\n'), demo);
  check(s.t, expect[k].test(out), out);
}
fs.writeFileSync(path.join(demo, 'labguide', 'verify0.log'), log.join('\n'));
console.log(`\nLab 0 失敗 ${fail} 項(詳見 labguide/verify0.log)`);
process.exit(fail ? 1 : 0);
