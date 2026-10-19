// 浏览器推送的开关：设置里打开 → 服务器记下这台设备；关掉 → 删掉；发出约球请求后提示打开；退出登录 → 删掉。
// 测试用的浏览器连不上真正的推送服务，所以把浏览器的订阅换成假的，只检查我们这边的流程
import { execFileSync } from 'node:child_process';
import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import { base, signUp } from './helpers.mjs';

const db = process.env.DB_URL ?? 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const sql = (query) => execFileSync('psql', [db, '-qtAc', query]).toString().trim();
const email = `push${Date.now()}@test.local`;
const devices = () => Number(sql(`select count(*) from push_devices d join auth.users u on u.id = d.user_id where u.email = '${email}'`));

const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1280, height: 900 }, timezoneId: 'America/Los_Angeles' });
await context.grantPermissions(['notifications']);
await context.addInitScript(() => {
  // 无头 Chromium 授了权 Notification.permission 也还是 denied，这里按真浏览器的样子返回
  Object.defineProperty(Notification, 'permission', { get: () => 'granted' });
  Notification.requestPermission = async () => 'granted';
  // 假订阅：记在 localStorage，刷新后还在，和真的一样
  const fake = () => ({
    endpoint: localStorage.getItem('e2e-push'),
    toJSON() { return { endpoint: this.endpoint, keys: { p256dh: 'BTestKey', auth: 'TestAuth' } }; },
    unsubscribe: async () => (localStorage.removeItem('e2e-push'), true),
  });
  PushManager.prototype.subscribe = async () => {
    localStorage.setItem('e2e-push', `https://fcm.googleapis.com/fcm/send/e2e-${Math.random().toString(36).slice(2)}`);
    return fake();
  };
  PushManager.prototype.getSubscription = async () => (localStorage.getItem('e2e-push') ? fake() : null);
});
const page = await context.newPage();

await signUp(page, email, 'Pia');
await page.getByRole('button', { name: 'Skip for now' }).click();
await page.getByRole('heading', { name: 'Up for a game tonight?' }).waitFor();

// 设置里打开、关掉
await page.goto(`${base}/settings/`);
const toggle = page.getByRole('switch', { name: 'Notifications on this device' });
// 开关等服务器确认后才变，所以点完等它变成开 / 关
const switched = (on) => page.waitForFunction((on) => document.querySelector('[role="switch"]')?.checked === on, on);
await toggle.click();
await switched(true);
assert.equal(devices(), 1, 'device registered');
await toggle.click();
await switched(false);
assert.equal(devices(), 0, 'device removed');

// 发出约球请求后提示一次；点了就打开
await page.goto(`${base}/`);
await page.getByRole('link', { name: 'Start matching' }).click();
await page.getByRole('button', { name: 'Singles' }).click();
await page.getByRole('radiogroup', { name: 'Date (next 14 days)' }).getByRole('radio').nth(1).click();
await page.getByRole('combobox', { name: 'Choose venue' }).fill('Los Angeles Badminton');
await page.getByRole('option', { name: /Los Angeles Badminton Club/ }).click();
await page.getByRole('button', { name: 'Start matching' }).click();
const prompt = page.getByText('Get a notification the moment we find you a match.');
await prompt.waitFor();
await page.getByRole('button', { name: 'Turn on' }).click();
await prompt.waitFor({ state: 'detached' });
await page.waitForTimeout(500);
assert.equal(devices(), 1, 'turned on from the prompt');

// 退出登录：这台设备不再收这个账号的推送
await page.goto(`${base}/settings/`);
await page.getByRole('button', { name: 'Sign out' }).click();
await page.getByRole('link', { name: 'Sign in' }).first().waitFor();
assert.equal(devices(), 0, 'device removed on sign out');

console.log('ok: push turned on and off in settings, offered after a request, removed on sign out');
await browser.close();
