// 网页应用端到端测试：邮箱验证码登录 → 建资料（跳过定级）→ 附近球馆 → 收藏 → 重新打开仍保持登录 → 换语言 → 注销账号
// 需要本地 Supabase（supabase start）和已启动的网站（BASE_URL）
import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { base, signUp } from './helpers.mjs';

const email = `player${Date.now()}@test.local`;

const browser = await chromium.launch();
const context = await browser.newContext({
  viewport: { width: 1280, height: 900 },
  geolocation: { latitude: 34.0765, longitude: -118.0462 },
  permissions: ['geolocation'],
});
// App 登录用的人机验证页：没配置 site key（本地、CI）时直接告诉 App 不需要验证
const probe = await context.newPage();
const messages = [];
await probe.exposeFunction('captchaMessage', (message) => messages.push(message));
await probe.addInitScript(() => {
  const app = /** @type {any} */ (window);
  app.webkit = { messageHandlers: { captcha: { postMessage: (message) => app.captchaMessage(message) } } };
});
await probe.goto(`${base}/captcha/`);
for (let i = 0; i < 50 && messages.length === 0; i++) await probe.waitForTimeout(100);
assert.deepEqual(messages, [{ token: '' }]);
await probe.close();

const page = await context.newPage();

await signUp(page, email, 'Alex');
await page.getByRole('button', { name: 'Skip for now' }).click();
await page.getByRole('heading', { name: 'Up for a game tonight?' }).waitFor();
// 顶栏的 tab 都是真正的页面：球馆是静态页面，整页打开
await page.getByRole('link', { name: 'Courts' }).first().click();
await page.waitForURL('**/courts/');

await page.getByRole('button', { name: 'Use my location' }).click();
const courts = page.getByRole('list', { name: 'Courts' }).getByRole('button');
await courts.first().waitFor();
const names = (await courts.allInnerTexts()).map((text) => text.split('\n')[0]);
assert.equal(names[0], 'Los Angeles Badminton Club', 'nearest court first');
assert.ok(names.includes('San Gabriel Valley Badminton Club'));

await courts.nth(1).click();
await page.getByRole('button', { name: 'Add to my courts' }).click();
await page.getByRole('button', { name: 'In my courts' }).waitFor();

// 位置记在这个浏览器里：刷新后直接显示附近的球馆
await page.reload();
await page.getByRole('heading', { name: /Courts near/ }).waitFor();
await courts.first().waitFor();

// 语言切换在顶栏：换成中文，静态页面和顶栏都跟着变，刷新后仍记住；再换回英文
await page.getByRole('button', { name: /^Language/ }).click();
await page.getByRole('option', { name: '简体中文' }).click();
await page.getByRole('link', { name: '球馆' }).first().waitFor();
await page.getByRole('heading', { name: '按国家浏览' }).waitFor();
await page.reload();
// 键盘也能换：打开后焦点在当前语言上，上移一格回到英文，回车选中
await page.getByRole('button', { name: /^语言/ }).focus();
await page.keyboard.press('ArrowDown');
await page.getByRole('option', { name: '简体中文', selected: true }).waitFor();
await page.keyboard.press('ArrowUp');
await page.keyboard.press('Enter');
await page.getByRole('link', { name: 'Courts' }).first().waitFor();

// 注销：要点两次；之后变回没登录，刷新也不会再登录
await page.goto(`${base}/settings/`);
await page.getByRole('button', { name: 'Delete account' }).click();
await page.getByRole('button', { name: 'Yes, delete my account' }).click();
await page.getByText('Sign in to continue').waitFor();
await page.reload();
await page.getByText('Sign in to continue').waitFor();

console.log(`ok: ${email} signed in, saw ${names.length} courts, favourited one, session kept, account deleted`);
await browser.close();
