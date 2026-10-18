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
await page.getByRole('heading', { name: 'Find a game' }).waitFor();
await page.getByRole('link', { name: 'Courts' }).first().click();

await page.getByRole('button', { name: 'Use my location' }).click();
const courts = page.getByRole('list', { name: 'Courts' }).getByRole('button');
await courts.first().waitFor();
const names = (await courts.allInnerTexts()).map((text) => text.split('\n')[0]);
assert.equal(names[0], 'Los Angeles Badminton Club', 'nearest court first');
assert.ok(names.includes('San Gabriel Valley Badminton Club'));

await courts.nth(1).click();
const star = page.getByRole('button', { name: 'Add to my courts' });
await star.click();
await page.waitForFunction(() => document.querySelector('[aria-label="Add to my courts"]')?.getAttribute('aria-pressed') === 'true');

await page.reload();
await page.getByRole('heading', { name: /Courts near/ }).waitFor();

// 换成中文：界面跟着变，刷新后仍记住；再换回英文
await page.getByRole('link', { name: 'Me', exact: true }).first().click();
await page.getByLabel('Language').selectOption('zh-Hans');
await page.getByRole('link', { name: '球馆' }).first().waitFor();
await page.reload();
await page.getByLabel('语言').selectOption('en');
await page.getByRole('link', { name: 'Courts' }).first().waitFor();

// 注销：要点两次；之后回到登录页，刷新也不会再登录
await page.getByRole('button', { name: 'Delete account' }).click();
await page.getByRole('button', { name: 'Yes, delete my account' }).click();
await page.getByRole('heading', { name: 'Sign in' }).waitFor();
await page.reload();
await page.getByRole('heading', { name: 'Sign in' }).waitFor();

console.log(`ok: ${email} signed in, saw ${names.length} courts, favourited one, session kept, account deleted`);
await browser.close();
