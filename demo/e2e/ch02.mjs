// 第 2 章:人用 AD 帳號登入 C3 —— gary / yujie / ming 看到的內容不同
import { launch, c3Login, shot, banner, C3, CLUSTER } from './lib.mjs';
const ch = 'ch02';
for (const user of ['gary', 'yujie', 'ming']) {
  const { browser, page } = await launch(user);
  console.log('user', user);
  await page.goto(`${C3}/login`); await page.locator('input[type=password]').waitFor({ timeout: 30000 }); await page.waitForTimeout(800);
  await banner(page, `以 AD 帳號 ${user} 登入 Control Center`);
  await shot(page, ch, `${user}-1-login`, `${user}:C3 登入畫面(帳號/密碼就是 AD 的)`);
  await c3Login(page, user);
  await banner(page, `${user} 已登入:首頁`);
  await shot(page, ch, `${user}-2-home`, `${user}:登入後首頁`);
  await page.goto(`${C3}/clusters/${CLUSTER}/management/topics`); await page.waitForTimeout(4500);
  await banner(page, `${user} 看到的 Topics`);
  await shot(page, ch, `${user}-3-topics`, `${user}:Topics 清單(可見範圍由 RBAC 決定)`);
  await page.getByLabel('Administration menu').click(); await page.waitForTimeout(700);
  await shot(page, ch, `${user}-4-admin-menu`, `${user}:Administration 選單(是否有 Manage role assignments)`);
  await page.getByText('View my role assignments').click().catch(() => {}); await page.waitForTimeout(3000);
  await banner(page, `${user} 的 role assignments`);
  await shot(page, ch, `${user}-5-my-roles`, `${user}:View my role assignments`);
  await browser.close();
}
