// 驗證「手動指令」:依 Lab 順序,用 labs.mjs 的同一份資料,實際執行每個步驟的 manual 指令
// (有介面操作的步驟,以 uiEq 等效指令代替),並用 re 檢查輸出。結果寫入 verify.log / verify.json。
// 用法: node verify.mjs [labId ...]   例: node verify.mjs ch03 ch04   (不帶參數 = Lab 1~11 依序)
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { LABS, SETUP } from './labs.mjs';

const demo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const only = process.argv.slice(2);
let header = SETUP.split('\n').slice(1).join('\n');
const baseHeader = header;   // 去掉第一行 cd
const results = []; let fail = 0;
const log = [];

function runBash(script) {
  const r = spawnSync('bash', ['-c', header + '\n' + script], { cwd: demo, encoding: 'utf8', timeout: 600000, maxBuffer: 64 * 1024 * 1024 });
  return ((r.stdout || '') + (r.stderr || '')).replace(/\r/g, '');
}

for (const lab of LABS) {
  if (lab.n === 0) continue;
  if (only.length && !only.includes(lab.id)) continue;
  console.log(`\n=== Lab ${lab.n} ${lab.title}`);
  header = baseHeader;
  for (const c of lab.pre_cmd || []) runBash(c);
  for (const s of lab.steps) {
    const cmds = [...(s.uiEq || []), ...(s.manual || [])];
    if (!cmds.length) { console.log(`  - ${s.t}: (僅介面操作,略過)`); continue; }
    const out = runBash(cmds.join('\n'));
    if (s.defs) header += '\n' + (s.manual || []).join('\n');
    const ok = (s.re ? s.re.test(out) : true) && (s.reNot ? !s.reNot.test(out) : true);
    if (!ok) fail++;
    results.push({ lab: lab.id, step: s.t, ok, hasRe: !!(s.re || s.reNot) });
    log.push(`\n##### ${lab.id} ${s.t} → ${ok ? 'PASS' : 'FAIL'}\n${out.split('\n').filter(l => !/^(WARNING|SLF4J)|^\s+at /.test(l)).slice(0, 40).join('\n')}`);
    console.log(`  ${ok ? '✔' : '✘'} ${s.t}${(s.re || s.reNot) ? '' : '  (無自動判定)'}`);
  }
}
fs.writeFileSync(path.join(demo, 'labguide', 'verify.log'), log.join('\n'));
fs.writeFileSync(path.join(demo, 'labguide', 'verify.json'), JSON.stringify(results, null, 1));
console.log(`\n失敗 ${fail} 項(詳見 labguide/verify.log)`);
process.exit(fail ? 1 : 0);
