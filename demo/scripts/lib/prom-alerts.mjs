// 讀 stdin 的 Prometheus 告警清單(/api/v1/alerts 的 JSON),印出「正在觸發(firing)」的告警名稱,逗號分隔、已排序。
// 沒有印「-」;JSON 壞掉印「?」。
// 用法:  curl ... | node scripts/lib/prom-alerts.mjs [名稱要符合的正規表示式] [要排除的正規表示式]
//   例:  ... | node scripts/lib/prom-alerts.mjs '^Kafka(Tls|Mtls)'
//   告警帶有 instance 標籤時,輸出「名稱@instance」。
const include = new RegExp(process.argv[2] || '.');
const exclude = process.argv[3] ? new RegExp(process.argv[3]) : null;
let s = '';
process.stdin.on('data', d => (s += d)).on('end', () => {
  try {
    const json = JSON.parse(s.slice(s.indexOf('{'), s.lastIndexOf('}') + 1));
    const names = json.data.alerts
      .filter(a => a.state === 'firing' && include.test(a.labels.alertname) && !(exclude && exclude.test(a.labels.alertname)))
      .map(a => a.labels.alertname + (a.labels.instance ? '@' + a.labels.instance : ''))
      .sort();
    console.log(names.join(',') || '-');
  } catch {
    console.log('?');
  }
});
