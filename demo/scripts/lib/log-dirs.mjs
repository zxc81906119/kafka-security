// 讀 stdin 的 kafka-log-dirs --describe 輸出(JSON),每台 broker 印一行:「broker <id>  <資料量> MB  分區: <編號…>」。
// 用法:  kafka-log-dirs ... --describe --topic-list <topic> | grep '^{' | node scripts/lib/log-dirs.mjs
let s = '';
process.stdin.on('data', d => (s += d)).on('end', () => {
  try {
    const json = JSON.parse(s);
    for (const b of json.brokers.sort((x, y) => x.broker - y.broker)) {
      let bytes = 0; const parts = [];
      for (const dir of b.logDirs) for (const p of dir.partitions) { bytes += p.size; parts.push(p.partition.split('-').pop()); }
      parts.sort((x, y) => x - y);
      console.log(`  broker ${b.broker}  ${String(Math.round(bytes / 1048576)).padStart(4)} MB  分區: ${parts.join(',') || '(無)'}`);
    }
  } catch { console.log('  (讀不到 log-dirs 輸出)'); }
});
