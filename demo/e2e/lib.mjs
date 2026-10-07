// 共用:C3 / phpLDAPadmin 的 Playwright 操作與截圖
import { launchChromium } from './browser.mjs';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const C3 = process.env.C3_URL || 'https://localhost:9022';   // C3 走 HTTPS(共用 server 憑證;瀏覽器要信任 demo CA,自動化這裡略過驗證)
export const CLUSTER = 'XyZBQ3-GTvKH2qNfP7X33A';
export const PW = { gary: 'gary-pw', yujie: 'yujie-pw', ming: 'ming-pw' };
// 客戶 AD 的使用者名稱是 CN(大寫),分散在多層 OU;這裡是 demo LDAP 裡各人的完整 DN
export const USER_DN = {
  gary: "cn=GARY,ou=platform,ou=it,ou=users,dc=corp,dc=demo",
  yujie: "cn=YUJIE,ou=orders,ou=dev,ou=users,dc=corp,dc=demo",
  ming: "cn=MING,ou=platform,ou=it,ou=users,dc=corp,dc=demo",
};

export async function launch(user) {
  const browser = await launchChromium();
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, ignoreHTTPSErrors: true });
  const page = await ctx.newPage();
  return { browser, ctx, page };
}

export async function c3Login(page, user) {
  await page.goto(`${C3}/login`);
  await page.fill('input[type=text]', user);
  await page.fill('input[type=password]', PW[user]);
  await page.keyboard.press('Enter');
  await page.waitForURL(/home|clusters/, { timeout: 40000 });
  await page.waitForTimeout(2500);
}

export async function shot(page, chapter, name, title) {
  const dir = path.join(root, 'evidence', chapter);
  fs.mkdirSync(dir, { recursive: true });
  // 在頁面右上角覆蓋一個「目前登入者」標籤,方便講解與截圖辨識身分
  const f = path.join(dir, `${name}.png`);
  await page.screenshot({ path: f });
  fs.writeFileSync(path.join(dir, `${name}.png.txt`), title + '\n');
  console.log('  📸', chapter + '/' + name + '.png —', title);
}

export async function banner(page, text) {
  await page.evaluate(t => {
    let b = document.getElementById('__demo_banner');
    if (!b) { b = document.createElement('div'); b.id = '__demo_banner';
      b.style.cssText = 'position:fixed;left:50%;transform:translateX(-50%);bottom:14px;z-index:99999;background:#111827ee;color:#fff;padding:8px 18px;border-radius:999px;font:600 15px "Segoe UI","Microsoft JhengHei",sans-serif;box-shadow:0 4px 14px #0006';
      document.body.appendChild(b); }
    b.textContent = t;
  }, text);
}

// ---------- phpLDAPadmin(AD 管理介面模擬) ----------
export const LDAPADMIN = 'http://localhost:8081';
export async function ldapLogin(page) {
  await page.goto(`${LDAPADMIN}/cmd.php?cmd=login_form&server_id=1`); await page.waitForTimeout(1200);
  await page.fill('input[name=login]', 'cn=admin,dc=corp,dc=demo');
  await page.fill('input[name=login_pass]', 'adminpw');
  await page.uncheck('input[name=anonymous_bind]').catch(() => {});
  await page.click('input[name=submit]'); await page.waitForTimeout(2500);
}
export async function openGroup(page, group) {
  await page.goto(`${LDAPADMIN}/cmd.php?cmd=template_engine&server_id=1&dn=${encodeURIComponent(`cn=${group},ou=groups,dc=corp,dc=demo`)}`);
  await page.waitForTimeout(2500);
}
// 在群組頁面新增/移除一個成員(uid):實際走 phpLDAPadmin 的網頁流程
export async function ldapGroupMember(page, group, uid, action /* 'add'|'remove' */, chapter, namePrefix) {
  const dn = USER_DN[uid];   // 使用者分散在多層 OU,DN 要用完整路徑
  if (!dn) throw new Error(`未知的使用者 ${uid}`);
  const verb = action === 'add' ? '加入' : '移除';
  await openGroup(page, group);
  await banner(page, `AD 管理介面:群組 ${group}(${verb} ${uid} 之前)`);
  if (chapter) await shot(page, chapter, `${namePrefix}-before`, `LDAP(模擬 AD)群組 ${group}:${verb} ${uid} 之前`);
  if (action === 'add') {
    await page.goto(`${LDAPADMIN}/cmd.php?cmd=add_value_form&server_id=1&dn=${encodeURIComponent(`cn=${group},ou=groups,dc=corp,dc=demo`)}&attr=member`);
    await page.locator('input[name^="new_values[member]"]:not([type="hidden"])').first().fill(dn);   // 新欄位的編號取決於原本有幾位成員(含 NOBODY 佔位),所以改找「可見的」輸入欄位
    if (chapter) { await banner(page, `在 member 欄位輸入 ${uid} 的 DN`); await shot(page, chapter, `${namePrefix}-form`, `LDAP 管理介面:新增 member 值(${uid})`); }
    await page.click('input[name=submit]'); await page.waitForTimeout(1500);
  } else {
    // 移除:進入群組頁,把該成員欄位清空後 Update Object
    await openGroup(page, group);
    for (const el of await page.$$('input[name^="new_values[member]"]')) { if ((await el.inputValue()).toLowerCase() === dn.toLowerCase()) await el.fill(''); }
    await page.getByRole('button', { name: 'Update Object' }).click(); await page.waitForTimeout(1500);
  }
  // 確認頁(update_confirm):按 Update Object
  const confirm = page.getByRole('button', { name: 'Update Object' });
  if (await confirm.count()) { await confirm.first().click(); await page.waitForTimeout(2000); }
  await openGroup(page, group);
  await banner(page, `AD 管理介面:群組 ${group} 已${verb} ${uid}`);
  if (chapter) await shot(page, chapter, `${namePrefix}-after`, `LDAP(模擬 AD)群組 ${group}:${verb} ${uid} 之後`);
}

// ---------- C3「Add role assignment」(react-select 下拉) ----------
const reEscape = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
async function choose(page, idx, text, { type = false } = {}) {
  const input = page.locator('input[role=combobox]').nth(idx);
  await input.click(); await page.waitForTimeout(500);
  if (type) { await input.fill(text); await page.waitForTimeout(800); }
  const options = page.locator('[id*="-option-"]');
  let opt = options.filter({ hasText: new RegExp('^\\s*' + reEscape(text) + '\\s*$') }).first();
  // 不在 AD 的服務帳號:C3 允許直接輸入名稱(選項會顯示為 Create "名稱")
  if (!(await opt.count())) opt = options.filter({ hasText: 'Create' }).first();
  await opt.waitFor({ timeout: 8000 });
  await opt.click(); await page.waitForTimeout(500);
}

async function addRole(page, scopeTab, { principalType, principalName, role, pattern, resource, chapter, name, label }) {
  await page.goto(`${C3}/access-control/manage/assignments/kafka/${CLUSTER}`); await page.waitForTimeout(2500);
  await page.getByText(scopeTab, { exact: true }).first().click(); await page.waitForTimeout(1800);
  await page.getByRole('button', { name: 'Add role assignment' }).click(); await page.waitForTimeout(1500);
  await choose(page, 0, principalType);
  await choose(page, 1, principalName, { type: true });
  await choose(page, 2, role);
  await choose(page, 3, pattern);
  await page.getByLabel('Resource ID*').fill(resource);
  if (chapter) {
    await banner(page, `gary 在 C3 指派:${principalType} ${principalName} → ${role} on ${resource}(${pattern})`);
    await shot(page, chapter, name + '-form', `C3:Add role assignment — ${principalType} ${principalName} / ${role} / ${resource}`);
  }
  await page.getByRole('button', { name: 'Save' }).click(); await page.waitForTimeout(2500);
  if (chapter) { await banner(page, '指派完成:列表出現新的 role assignment'); await shot(page, chapter, name + '-saved', `C3:指派完成後的 ${label} 範圍列表`); }
}
export const c3AddTopicRole = (page, o) => addRole(page, 'Topic', { ...o, label: 'Topic' });
export const c3AddGroupRole = (page, o) => addRole(page, 'Group', { ...o, label: 'Consumer Group' });
