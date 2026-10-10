// 讀 stdin 的 Prometheus 規則清單(/api/v1/rules 的 JSON),針對指定的規則群組輸出:
//   count 模式:印「規則數 health=ok 的規則數」,例如 "7 7"(找不到群組印 "0 0";JSON 壞掉印 "? ?")
//   list  模式:每條規則印一行「名稱  health  state」
// 用法:  curl ... | node scripts/lib/prom-rules.mjs <群組名稱> count|list
const [group, mode = 'count'] = process.argv.slice(2);
let s = '';
process.stdin.on('data', d => (s += d)).on('end', () => {
  try {
    const json = JSON.parse(s.slice(s.indexOf('{'), s.lastIndexOf('}') + 1));
    const g = json.data.groups.find(x => x.name === group);
    if (!g) { if (mode === 'count') console.log('0 0'); return; }
    if (mode === 'list') {
      for (const r of g.rules) console.log('  ' + r.name.padEnd(36) + r.health.padEnd(6) + (r.state || ''));
    } else {
      console.log(g.rules.length + ' ' + g.rules.filter(r => r.health === 'ok').length);
    }
  } catch {
    if (mode === 'count') console.log('? ?');
  }
});
