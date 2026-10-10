// 檢查 Grafana 儀表板「真的有資料」:把每個面板的 PromQL 查詢,透過 Grafana 的資料來源代理(Grafana → Prometheus)各執行一次,
// 數有幾個查詢回傳資料。這樣能分辨『儀表板匯入了』和『儀表板用得起來』:標籤對不上的話,面板會是空的。
// 用法:node dash-coverage.mjs <Grafana 網址> <admin 帳號:密碼> <CA 憑證檔> <儀表板 json…>
//   例:node dash-coverage.mjs https://localhost:3000 admin:xxxx certs/ca.pem config/grafana/dashboards/kafka-cluster-kraft.json
// 輸出:每個儀表板一行「檔名  查詢 N 個,有資料 M 個,沒資料 K 個」,最後列出沒資料的查詢前幾個(供判斷是環境沒有該功能,還是標籤對不上)。
import fs from 'node:fs';
import https from 'node:https';

const [base, auth, caFile, ...files] = process.argv.slice(2);
const agent = new https.Agent({ ca: fs.readFileSync(caFile) });
const header = 'Basic ' + Buffer.from(auth).toString('base64');

function get(path) {
  return new Promise((resolve, reject) => {
    https.get(base + path, { agent, headers: { Authorization: header } }, res => {
      let s = ''; res.on('data', d => (s += d)); res.on('end', () => resolve({ code: res.statusCode, body: s }));
    }).on('error', reject);
  });
}

// 儀表板變數的代入值:env = demo;其餘多選變數用「全部」(.*);時間間隔用固定值
function substitute(expr, vars) {
  let e = expr;
  for (const [k, v] of Object.entries(vars)) e = e.split('${' + k + '}').join(v).split('$' + k).join(v);
  return e.split('$__rate_interval').join('5m').split('$__interval').join('1m').split('$__range').join('1h');
}

const exprs = dash => {
  const out = new Set();
  const walk = o => {
    if (Array.isArray(o)) o.forEach(walk);
    else if (o && typeof o === 'object') { if (typeof o.expr === 'string' && o.expr.trim()) out.add(o.expr); Object.values(o).forEach(walk); }
  };
  walk(dash.panels || []); walk(dash.rows || []);
  return [...out];
};

let totalEmpty = [];
for (const f of files) {
  const dash = JSON.parse(fs.readFileSync(f, 'utf8'));
  const vars = { env: 'demo', Prometheus: 'Prometheus' };
  for (const v of dash.templating?.list || []) if (!(v.name in vars)) vars[v.name] = v.name === 'percentile' ? '0.99' : '.*';
  let withData = 0, empty = 0, error = 0; const emptyList = [];
  for (const raw of exprs(dash)) {
    const q = substitute(raw, vars);
    const r = await get('/api/datasources/proxy/uid/Prometheus/api/v1/query?query=' + encodeURIComponent(q));
    let ok = false;
    try { const j = JSON.parse(r.body); if (j.status === 'success') { ok = j.data.result.length > 0; } else error++; } catch { error++; }
    if (ok) withData++; else { empty++; emptyList.push(raw.slice(0, 110)); }
  }
  const name = f.split(/[\/]/).pop();
  console.log(`${name.padEnd(28)} 查詢 ${withData + empty} 個,有資料 ${withData} 個,沒資料 ${empty} 個(其中查詢出錯 ${error} 個)`);
  totalEmpty.push([name, emptyList]);
}
if (process.env.SHOW_EMPTY) for (const [n, l] of totalEmpty) { console.log('--- ' + n + ' 沒資料的查詢(前 ' + Math.min(l.length, +process.env.SHOW_EMPTY) + ' 個):'); l.slice(0, +process.env.SHOW_EMPTY).forEach(x => console.log('  ' + x)); }
