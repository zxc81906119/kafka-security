// 第 11 章 UI:AD 群組異動(臨時提權/收回)以 LDAP 網頁介面操作;gary 在 C3 檢視各群組的 role 對應
import { launch, c3Login, ldapLogin, ldapGroupMember, shot, banner, C3, CLUSTER } from './lib.mjs';
const [action, user, group] = process.argv.slice(2);
const { browser, page } = await launch();
try {
  if (action === 'grant' || action === 'revoke') {
    await ldapLogin(page);
    await ldapGroupMember(page, group, user, action === 'grant' ? 'add' : 'remove', 'ch11', `ldap-${action}-${user}-${group}`);
  } else if (action === 'c3-matrix') {
    await c3Login(page, 'gary');
    await page.goto(`${C3}/access-control/manage/assignments/kafka/${CLUSTER}`); await page.waitForTimeout(3000);
    for (const [tab, name] of [['Cluster', 'c11-1-matrix-cluster'], ['Topic', 'c11-2-matrix-topic']]) {
      const t = page.getByText(tab, { exact: true }).first();
      if (await t.count()) { await t.click(); await page.waitForTimeout(2000); }
      await banner(page, `gary 在 C3 檢視:各 AD 群組對應的角色(${tab} 範圍)`);
      await shot(page, 'ch11', name, `C3 角色指派:${tab} 範圍(群組 → 角色)`);
    }
  }
} finally { await browser.close(); }
