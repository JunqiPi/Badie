// Google / Apple 登录按钮：不等服务器就显示（第一次默认都开，之后用记下的结果）；后台没开就收起；
// 开了的话跳到 Supabase 的授权地址（PKCE），对方取消回来时给提示
// 本地没有真的 Google / Apple 账号，所以拦下设置接口和跳转，只检查我们这边做对了
import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import { base } from './helpers.mjs';

const browser = await chromium.launch();
const page = await browser.newPage();
page.on('pageerror', (error) => {
  throw error;
});

// 第一次打开：服务器还没回话，按钮就已经在了；本地后台没开第三方登录，回话后收起
let answered = false;
await page.route('**/auth/v1/settings', async (route) => {
  await new Promise((resolve) => setTimeout(resolve, 2000));
  answered = true;
  await route.continue();
});
await page.goto(`${base}/signin/`);
await page.getByRole('button', { name: 'Continue with Apple' }).waitFor();
assert.equal(answered, false, '按钮要在服务器回话之前就出现');
await page.getByRole('button', { name: 'Continue with Apple' }).waitFor({ state: 'detached' });
await page.unroute('**/auth/v1/settings');

// 记住了：再打开直接只有邮箱
await page.reload();
await page.getByLabel('Email').waitFor();
assert.equal(await page.getByRole('button', { name: /Continue with/ }).count(), 0);

// 开了 Google 和 Apple
await page.route('**/auth/v1/settings', (route) => route.fulfill({ json: { external: { email: true, google: true, apple: true } } }));
let authorize;
await page.route('**/auth/v1/authorize**', (route) => {
  authorize = new URL(route.request().url());
  return route.fulfill({ contentType: 'text/html', body: '<p>provider</p>' });
});
await page.goto(`${base}/signin/?next=%2Fplay%2F`);
await page.getByRole('button', { name: 'Continue with Apple' }).waitFor();
await page.getByRole('button', { name: 'Continue with Google' }).click();
await page.getByText('provider').waitFor();
assert.equal(authorize.searchParams.get('provider'), 'google');
assert.equal(authorize.searchParams.get('redirect_to'), `${base}/signin/?next=%2Fplay%2F`);
assert.equal(authorize.searchParams.get('code_challenge_method')?.toLowerCase(), 's256');
assert.ok(authorize.searchParams.get('code_challenge'));

// 在对方页面点了取消，跳回来带着 error
await page.goto(`${base}/signin/?error=access_denied&error_description=cancelled`);
await page.getByText('Sign-in didn’t finish. Try again, or use your email.').waitFor();

console.log('ok: provider buttons show without waiting, hide when disabled, PKCE redirect back to the page you came from, cancel handled');
await browser.close();
