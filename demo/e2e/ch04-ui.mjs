// 第 4 章 UI:gary 在 C3 指派唯讀 role;LDAP 網頁介面把 ming 從 developers 移到 readonly
import { launch, c3Login, c3AddTopicRole, c3AddGroupRole, ldapLogin, ldapGroupMember, shot, banner, C3, CLUSTER } from './lib.mjs';
const action = process.argv[2];
const { browser, page } = await launch();
try {
  if (action === 'assign-readonly') {
    await c3Login(page, 'gary');
    await c3AddTopicRole(page, { principalType: 'Group', principalName: 'orders-read', role: 'DeveloperRead', pattern: 'Prefixed', resource: 'orders.', chapter: 'ch04', name: 'c3-1-readonly' });
    await c3AddGroupRole(page, { principalType: 'Group', principalName: 'orders-read', role: 'DeveloperRead', pattern: 'Prefixed', resource: 'demo-', chapter: null, name: 'x' });
  } else if (action === 'move-ming') {
    await ldapLogin(page);
    await ldapGroupMember(page, 'orders-read', 'ming', 'add', 'ch04', 'ldap-ming-to-readonly');
    await ldapGroupMember(page, 'orders-write', 'ming', 'remove', 'ch04', 'ldap-ming-from-developers');
  } else if (action === 'c3-readonly-view') {
    await c3Login(page, 'ming');
    await page.goto(`${C3}/clusters/${CLUSTER}/management/topics`); await page.waitForTimeout(5000);
    await banner(page, 'ming(readonly)在 C3:看得到 orders.* 但沒有「Add topic」等管理按鈕');
    await shot(page, 'ch04', 'c3-2-ming-readonly-topics', 'ming(orders-read)的 C3 Topics:可檢視');
  }
} finally { await browser.close(); }
