// 讀 stdin 的 Tempo 搜尋結果(/api/search 的 JSON),每個 trace 印一行:「trace-id  跨了哪些服務(逗號分隔)  根 span 名稱」。
// 沒有任何 trace 不印東西;JSON 壞掉印「?」。用法:  curl ... /api/search | node scripts/lib/tempo-traces.mjs
let s = '';
process.stdin.on('data', d => (s += d)).on('end', () => {
  try {
    const json = JSON.parse(s.slice(s.indexOf('{'), s.lastIndexOf('}') + 1));
    for (const t of json.traces || []) console.log(`${t.traceID} ${Object.keys(t.serviceStats || {}).sort().join(',')} ${t.rootTraceName || ''}`);
  } catch {
    console.log('?');
  }
});
