// 讀 stdin 的 Mailpit 郵件清單(GET /api/v1/messages 的 JSON),每封信印一行:「主旨 | 收件人 | 內文前 80 字」。
// 沒有信不印東西;JSON 壞掉印「?」。用法:  curl ... /api/v1/messages | node scripts/lib/mailpit-list.mjs
let s = '';
process.stdin.on('data', d => (s += d)).on('end', () => {
  try {
    const json = JSON.parse(s.slice(s.indexOf('{'), s.lastIndexOf('}') + 1));
    for (const m of json.messages || []) {
      const to = (m.To || []).map(t => t.Address).join(',');
      console.log(`${m.Subject} | ${to} | ${(m.Snippet || '').replace(/\s+/g, ' ').slice(0, 80)}`);
    }
  } catch {
    console.log('?');
  }
});
