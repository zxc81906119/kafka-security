import fs from 'node:fs';
const f = 'scripts/app-lab.sh';
let s = fs.readFileSync(f, 'utf8');
function rep(a, b) { if (s.split(a).length !== 2) throw new Error('anchor ' + a.slice(0, 50)); s = s.replace(a, () => b); }
rep("dup_of() { echo \"$1\" | grep -o '重複=[0-9]*' | head -1 | cut -d= -f2; }", "dup_of() { echo \"$1\" | grep -o ' 重複=[0-9]*' | head -1 | cut -d= -f2; }   # 前面的空白不能省:否則會先匹配到「不重複=」");
rep("revoked_eager=$(grep -m1 \"REVOKED\" /tmp/app-c1-eager.out | grep -o '\[.*\]' | tr -cd '0-9' | wc -c)", "revoked_eager=$(grep -m1 \"REVOKED\" /tmp/app-c1-eager.out | sed 's/.*REVOKED *//' | tr -cd '0-9' | wc -c)");
rep("revoked_coop=$(grep -m1 \"REVOKED\" /tmp/app-c1-cooperative.out | grep -o '\[.*\]' | tr -cd '0-9' | wc -c)", "revoked_coop=$(grep -m1 \"REVOKED\" /tmp/app-c1-cooperative.out | sed 's/.*REVOKED *//' | tr -cd '0-9' | wc -c)");
fs.writeFileSync(f, s);
