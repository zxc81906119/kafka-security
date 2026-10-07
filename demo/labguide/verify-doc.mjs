// 內容自檢:手冊裡每一條指令都實際執行,並檢查結果。三層:
//  M = 手動指令(manual;有介面操作的步驟以 uiEq 等效指令代替)實跑,輸出符合判定式(re / reNot)
//  A = 專案包好的指令(auto)實跑,輸出符合判定式
//  E = 證據檔(evidence/,整章腳本的輸出)符合判定式
// 另外把每個步驟「手動指令」的實跑輸出存到 manual-out/<lab>/<NN>.log,build-story.mjs 直接拿它當手冊的「實際執行輸出」,
// 所以手冊顯示的輸出就是手冊顯示的指令實跑的結果。
// 用法: node verify-doc.mjs [labId ...]   例: node verify-doc.mjs ch03 ch04   (不帶參數 = Lab 1~17 依序)
//       EVIDENCE_ONLY=1 node verify-doc.mjs   只比對證據檔,不實跑(幾秒完成)
// 結果:verify-doc.log(不符合的輸出)、verify-doc.json(每步的 M/A/E)
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { LABS as LABS0, SETUP } from './labs.mjs';
import { LABS_EXTRA } from './labs-extra.mjs';
const LABS = [...LABS0, ...LABS_EXTRA];
const here = path.dirname(fileURLToPath(import.meta.url));
const demo = path.resolve(here, '..');
const only = process.argv.slice(2);
const EVIDENCE_ONLY = process.env.EVIDENCE_ONLY === '1';
const baseHeader = SETUP.split('\n').slice(1).join('\n');   // 去掉第一行 cd
let header = baseHeader;
const rows = []; const log = [];

const clean = s => s.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, '').replace(/\r/g, '');
// 與 scripts/lib-ev.sh 的 _ev_filter 相同:去掉 JVM / Kafka 工具的雜訊,只留有意義的行(存檔用;判定式仍看原始輸出)
const NOISE = /^(WARNING|SLF4J)|^\s+at |Option .* is deprecated|--(producer|consumer)\.config is deprecated|KIP-848|^Warning: --|AppInfoParser|^\s*$|Caused by: .*TimeoutException|Error in kafka producer I\/O thread|ErrorLoggingCallback|UnknownTopicOrPartition|Transactional method invoked/;
const NOISE2 = /AdminMetadataManager|^ ?\(org\.apache\.kafka\.tools|^ ?\(org\.apache\.kafka\.clients/;
const filterOut = s => s.split('\n').filter(l => !NOISE.test(l)).map(l => l.replace(/^\[20[0-9-]+ [0-9:,]+\] /, '')).filter(l => !NOISE2.test(l)).map(l => l.replace(/ \(org\.apache\.kafka\.[a-zA-Z.]+\)$/, '')).join('\n');

function run(script, cwd = demo) {
  const r = spawnSync('bash', ['-c', header + '\n' + script], { cwd, encoding: 'utf8', timeout: 900000, maxBuffer: 64 * 1024 * 1024 });
  return clean((r.stdout || '') + (r.stderr || ''));
}
function evidenceText(ch, slug) {
  const dir = path.join(demo, 'evidence', ch);
  if (!fs.existsSync(dir)) return null;
  const f = fs.readdirSync(dir).find(n => n.endsWith('-' + slug + '.log') && /^\d\d-/.test(n));
  return f ? clean(fs.readFileSync(path.join(dir, f), 'utf8')).split('\n').slice(2).join('\n') : null;
}
const judge = (s, out) => (s.re ? s.re.test(out) : true) && (s.reNot ? !s.reNot.test(out) : true);
const hasJudge = s => !!(s.re || s.reNot);
const runnableAuto = a => typeof a === 'string' && !a.startsWith('(') && !/^\.\/demo\.sh/.test(a) && !/^\.\/scenarios\//.test(a) && !/^\.\/preflight/.test(a);

for (const lab of LABS) {
  if (lab.n === 0) continue;
  if (only.length && !only.includes(lab.id)) continue;
  console.log(`\n=== Lab ${lab.n} ${lab.title}`);
  header = baseHeader;
  const pre = lab.id === 'ch16' ? 'cd opmenu; ' : '';   // Lab 16 的指令要在 demo/opmenu 目錄執行
  const outDir = path.join(here, 'manual-out', lab.id);
  if (!EVIDENCE_ONLY) { fs.rmSync(outDir, { recursive: true, force: true }); fs.mkdirSync(outDir, { recursive: true }); }
  if (!EVIDENCE_ONLY) for (const c of lab.pre_cmd || []) run(pre + c);
  lab.steps.forEach((s, i) => {
    const row = { lab: lab.id, step: s.t, M: '-', A: '-', E: '-' };
    const cmds = [...(s.uiEq || []), ...(s.manual || [])];
    if (cmds.length && !EVIDENCE_ONLY) {
      const out = run(pre + cmds.join('\n'));
      if (s.defs) header += '\n' + (s.manual || []).join('\n').split('\n').filter(l => !/^\s*echo /.test(l)).join('\n');   // 後面步驟要用到的變數與函式(例如 token);echo 不帶過去,免得每步都重印
      fs.writeFileSync(path.join(outDir, String(i + 1).padStart(2, '0') + '.log'), filterOut(out).trim() + '\n');
      if (hasJudge(s)) { row.M = judge(s, out) ? 'ok' : 'FAIL'; if (row.M === 'FAIL') log.push(`\n##### ${lab.id} ${s.t} [M]\n${out.slice(0, 1500)}`); } else row.M = '無判定';
    }
    if (EVIDENCE_ONLY && cmds.length) {   // 不實跑時:用上次存下的手動指令輸出(manual-out)判定
      const mo = path.join(outDir, String(i + 1).padStart(2, '0') + '.log');
      if (!fs.existsSync(mo)) row.M = '缺輸出';
      else if (hasJudge(s)) { const out = fs.readFileSync(mo, 'utf8'); row.M = judge(s, out) ? 'ok(存檔)' : 'FAIL'; if (row.M === 'FAIL') log.push(`\n##### ${lab.id} ${s.t} [M 存檔] re=${s.re || ''} reNot=${s.reNot || ''}\n${out.slice(0, 1200)}`); }
      else row.M = '無判定';
    }
    // uiEq(等效指令)與 auto(專案腳本)做的是同一件狀態變更,擇一執行:有 uiEq 時不再跑 auto
    const autos = (EVIDENCE_ONLY || s.uiEq) ? [] : (s.auto || []).filter(runnableAuto);
    for (const a of autos.length ? [autos.join('\n')] : []) {   // 多條 auto 指令合在一起跑,跟手動指令一樣用同一個判定式看整段輸出
      const out = run(pre + a);
      if (hasJudge(s)) { const ok = judge(s, out); if (row.A !== 'FAIL') row.A = ok ? 'ok' : 'FAIL'; if (!ok) log.push(`\n##### ${lab.id} ${s.t} [A] ${a}\n${out.slice(0, 1500)}`); } else row.A = '無判定';
    }
    if (s.ev) {
      const parts = ['ev', 'evb', 'evc'].filter(k => s[k]).map(k => evidenceText(lab.id, s[k]));
      if (parts.some(p => p === null)) { row.E = '缺證據'; log.push(`\n##### ${lab.id} ${s.t} [E] 找不到證據 ${['ev', 'evb', 'evc'].filter(k => s[k]).map(k => s[k]).join(',')}`); }
      else if (hasJudge(s)) { const ev = parts.join('\n'); row.E = judge(s, ev) ? 'ok' : 'FAIL'; if (row.E === 'FAIL') log.push(`\n##### ${lab.id} ${s.t} [E] re=${s.re || ''} reNot=${s.reNot || ''}\n${ev.slice(0, 1200)}`); }
      else row.E = '無判定';
    }
    rows.push(row);
    console.log(`  M:${row.M} A:${row.A} E:${row.E}  ${s.t}`);
  });
}
fs.writeFileSync(path.join(here, 'verify-doc.log'), log.join('\n'));
fs.writeFileSync(path.join(here, 'verify-doc.json'), JSON.stringify(rows, null, 1));
const bad = rows.filter(r => [r.M, r.A, r.E].some(x => x === 'FAIL' || x === '缺證據'));
const nojudge = rows.filter(r => [r.M, r.A, r.E].includes('無判定'));
console.log(`\n不符合 ${bad.length} 項、沒有判定式 ${nojudge.length} 項 / 共 ${rows.length} 步(詳見 verify-doc.log)`);
process.exit(bad.length ? 1 : 0);
