// 第 12 章 UI:gary 在 C3 把 orders.* 寫入權限指派給 legacy app(User:legacy-orders;憑證身分只能綁 User:,不支援群組)
import { launch, c3Login, c3AddTopicRole } from './lib.mjs';
const action = process.argv[2];
const { browser, page } = await launch();
try {
  if (action === 'assign-legacy') {
    await c3Login(page, 'gary');
    await c3AddTopicRole(page, { principalType: 'User', principalName: 'legacy-orders', role: 'DeveloperWrite', pattern: 'Prefixed', resource: 'orders.', chapter: 'ch12', name: 'c12-1-legacy' });
  }
} finally { await browser.close(); }
