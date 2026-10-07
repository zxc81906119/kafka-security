// 第 3 章 UI 部分:用參數選擇動作,供 scenarios/ch03 串接(終端機與 UI 交錯執行)
// 用法: node ch03-ui.mjs assign-developers | add-ming | ming-view
import { launch, c3Login, c3AddTopicRole, ldapLogin, ldapGroupMember, shot, banner, C3, CLUSTER } from './lib.mjs';
const action = process.argv[2];
const { browser, page } = await launch();
try {
  if (action === 'assign-developers') {
    await c3Login(page, 'gary');
    await c3AddTopicRole(page, { principalType: 'Group', principalName: 'orders-write', role: 'DeveloperWrite', pattern: 'Prefixed', resource: 'orders.', chapter: 'ch03', name: 'c3-1-write' });
    await c3AddTopicRole(page, { principalType: 'Group', principalName: 'orders-write', role: 'DeveloperRead', pattern: 'Prefixed', resource: 'orders.', chapter: 'ch03', name: 'c3-2-read' });
  } else if (action === 'add-ming') {
    await ldapLogin(page);
    await ldapGroupMember(page, 'orders-write', 'ming', 'add', 'ch03', 'ldap-add-ming');
  } else if (action === 'ming-view') {
    await c3Login(page, 'ming');
    await page.goto(`${C3}/clusters/${CLUSTER}/management/topics`); await page.waitForTimeout(5000);
    await banner(page, 'ming(已加入 orders-write)重新整理 C3:現在看得到 orders.* topics');
    await shot(page, 'ch03', 'c3-3-ming-topics', 'ming 加入 AD 群組後,C3 Topics 清單出現 orders.*(Kafka 端零變更)');
  }
} finally { await browser.close(); }
