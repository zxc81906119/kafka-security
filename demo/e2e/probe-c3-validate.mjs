// 驗證 C3 如何驗 token:(1) 竄改 claims (2) 偽造簽章 (3) 有效 token 重複呼叫時 C3 有沒有回頭問 MDS
// 用法: node probe-c3-validate.mjs     (不印 token)
import crypto from 'node:crypto';
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';   // demo 自簽 CA,只在本探測內放寬
const MDS = 'https://localhost:8091', C3 = 'http://127.0.0.1:9021', URL = `${C3}/2.0/clusters/kafka`;
const login = async (u, p) => (await (await fetch(`${MDS}/security/1.0/authenticate`, { headers: { Authorization: 'Basic ' + Buffer.from(`${u}:${p}`).toString('base64'), Accept: 'application/json' } })).json()).auth_token;
const call = async (label, tok) => { const r = await fetch(URL, { headers: tok ? { Authorization: `Bearer ${tok}` } : {} }); console.log(`  ${label.padEnd(46)} → HTTP ${r.status}`); return r.status; };
const b64u = o => Buffer.from(typeof o === 'string' ? o : JSON.stringify(o)).toString('base64url');
const tm = await login('ming', 'ming-pw');
const [h, p, s] = tm.split('.');
const claims = JSON.parse(Buffer.from(p, 'base64url').toString());
console.log('取得 ming 的 MDS token:sub=' + claims.sub + ',簽發者=' + claims.iss);
console.log('\n(1) 有效 token 與各種被動過的 token 打 C3 API:');
await call('原封不動的 ming token', tm);
await call('竄改 sub=gary(保留原簽章)', `${h}.${b64u({ ...claims, sub: 'gary' })}.${s}`);
await call('竄改過期時間 exp+1 年(保留原簽章)', `${h}.${b64u({ ...claims, exp: claims.exp + 31536000 })}.${s}`);
const { privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const fp = b64u({ ...claims, sub: 'gary' }); const fh = b64u({ alg: 'RS256', kid: null });
await call('用別把私鑰重新簽發(sub=gary)', `${fh}.${fp}.${crypto.createSign('RSA-SHA256').update(`${fh}.${fp}`).sign(privateKey).toString('base64url')}`);
await call('alg=none(無簽章)', `${b64u({ alg: 'none' })}.${fp}.`);
console.log('\n(2) 有效 token 連續呼叫 6 次,稍後從 MDS 日誌看 C3 有沒有為了驗證而回頭呼叫 MDS:');
const t0 = new Date().toISOString().slice(11, 19);
for (let i = 0; i < 6; i++) await fetch(URL, { headers: { Authorization: `Bearer ${tm}` } });
console.log('  (起點時間 ' + t0 + ' UTC)');
