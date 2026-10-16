// 网页应用端到端测试：邮箱验证码登录 → 建资料 → 附近球馆 → 收藏 → 重新打开仍保持登录
// 需要本地 Supabase（supabase start）和已启动的网站（BASE_URL）
import { chromium } from 'playwright';
import assert from 'node:assert/strict';

const base = process.env.BASE_URL ?? 'http://127.0.0.1:4321';
const mailpit = process.env.MAILPIT_URL ?? 'http://127.0.0.1:54324';
const email = `player${Date.now()}@test.local`;

async function emailedCode() {
  for (let attempt = 0; attempt < 30; attempt++) {
    const { messages = [] } = await (await fetch(`${mailpit}/api/v1/messages`)).json();
    const message = messages.find((m) => m.To?.some((to) => to.Address === email));
    if (message) {
      const full = await (await fetch(`${mailpit}/api/v1/message/${message.ID}`)).json();
      const code = (full.Text || full.HTML).match(/\b\d{6,10}\b/)?.[0];
      if (code) return code;
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`no sign-in email for ${email}`);
}

const browser = await chromium.launch();
const context = await browser.newContext({
  viewport: { width: 1280, height: 900 },
  geolocation: { latitude: 34.0765, longitude: -118.0462 },
  permissions: ['geolocation'],
});
const page = await context.newPage();
page.on('pageerror', (error) => {
  throw error;
});

await page.goto(`${base}/app/`);
await page.getByLabel('Email').fill(email);
await page.getByRole('button', { name: 'Email me a code' }).click();
await page.getByLabel('Sign-in code').fill(await emailedCode());
await page.getByRole('button', { name: 'Sign in' }).click();

await page.getByLabel('Nickname').fill('Alex');
await page.getByRole('button', { name: 'Continue' }).click();

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

await page.goto(`${base}/app/`);
await page.getByRole('heading', { name: /Courts near/ }).waitFor();
assert.match(page.url(), /\/app\/courts\/$/);

console.log(`ok: ${email} signed in, saw ${names.length} courts, favourited one, session kept`);
await browser.close();
