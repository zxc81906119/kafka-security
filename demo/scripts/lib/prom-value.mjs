// 讀 stdin 的 Prometheus 查詢結果(/api/v1/query 的 JSON,前面可能夾著 curl 的雜訊),印出第一筆的值。
// 沒有結果印「無」;JSON 壞掉印「?」。用法:  curl ... | node scripts/lib/prom-value.mjs
let s = '';
process.stdin.on('data', d => (s += d)).on('end', () => {
  try {
    const json = JSON.parse(s.slice(s.indexOf('{'), s.lastIndexOf('}') + 1));
    const result = json.data.result;
    console.log(result.length ? result[0].value[1] : '無');
  } catch {
    console.log('?');
  }
});
