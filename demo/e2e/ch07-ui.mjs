// 第 7 章 UI:gary 在 C3 把 orders.* 寫入權限指派給服務帳號(User:svc-orders)
import { launch, c3Login, c3AddTopicRole, shot, banner, C3, CLUSTER } from './lib.mjs';
const action = process.argv[2];
const { browser, page } = await launch();
try {
  if (action === 'assign-svc') {
    await c3Login(page, 'gary');
    await c3AddTopicRole(page, { principalType: 'User', principalName: 'svc-orders', role: 'DeveloperWrite', pattern: 'Prefixed', resource: 'orders.', chapter: 'ch07', name: 'c7-1-svc' });
  }
} finally { await browser.close(); }
