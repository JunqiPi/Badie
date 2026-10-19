// 邮箱 + 密码：注册要输入邮件里的确认码；之后用密码登录不再发邮件；密码错了有提示；
// 设置里改密码（泄露过的密码不收）；忘记密码用邮件里的码重设；验证码登录仍然可用；同一邮箱不能再注册
import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import { base, emailCount, emailedCode, password, pwnedPasswords, signUp } from './helpers.mjs';

const email = `pass${Date.now()}@test.local`;
const browser = await chromium.launch();
const page = await (await browser.newContext({ viewport: { width: 1280, height: 900 } })).newPage();
await signUp(page, email, 'Pat');
await page.getByRole('button', { name: 'Skip for now' }).click();
// 后注册的拦截优先：这个密码当作泄露过
await pwnedPasswords(page, ['password123']);
assert.equal(await emailCount(email), 1, 'one email to confirm the address');

const signOut = async () => {
  await page.goto(`${base}/settings/`);
  await page.getByRole('button', { name: 'Sign out' }).click();
  await page.getByRole('link', { name: 'Sign in' }).first().waitFor();
};
const signIn = async (pass) => {
  await page.goto(`${base}/signin/`);
  await page.getByLabel('Email', { exact: true }).fill(email);
  await page.getByLabel('Password', { exact: true }).fill(pass);
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
};
const signedIn = () => page.getByRole('heading', { name: 'Up for a game tonight?' }).waitFor();

// 密码错了：提示，不说邮箱有没有注册
await signOut();
await signIn('not my password');
await page.getByText('Wrong email or password.', { exact: false }).waitFor();

// 密码对了：直接登录，不发邮件
await signIn(password);
await signedIn();
assert.equal(await emailCount(email), 1, 'signing in with a password sends no email');

// 设置里改密码：泄露过的不收
const newPassword = 'smash and dash 42';
await page.goto(`${base}/settings/`);
const field = page.getByLabel('New password', { exact: true });
await field.fill('password123');
await page.getByRole('button', { name: 'Save password' }).click();
await page.getByText('This password has appeared in a data breach.', { exact: false }).waitFor();
await field.fill(newPassword);
await page.getByRole('button', { name: 'Save password' }).click();
await page.getByText('Password saved').waitFor();

// 显示 / 隐藏密码
await page.getByRole('button', { name: 'Show password' }).click();
assert.equal(await field.getAttribute('type'), 'text');
await page.getByRole('button', { name: 'Hide password' }).click();

// 旧密码不能用了，新的可以
await signOut();
await signIn(password);
await page.getByText('Wrong email or password.', { exact: false }).waitFor();
await signIn(newPassword);
await signedIn();

// 忘记密码：填邮箱 → 邮件里的码 + 新密码 → 直接登录
await signOut();
await page.goto(`${base}/signin/`);
await page.getByLabel('Email', { exact: true }).fill(email);
let sent = await emailCount(email);
await page.getByRole('button', { name: 'Forgot password?' }).click();
await page.getByText('Check your email').waitFor();
const resetPassword = 'drop shot at dawn';
await page.getByLabel('6-digit code').fill(await emailedCode(email, sent));
await page.getByLabel('New password', { exact: true }).fill(resetPassword);
await page.getByRole('button', { name: 'Save password and sign in' }).click();
await signedIn();
await page.getByText('Password saved').waitFor();
await signOut();
await signIn(resetPassword);
await signedIn();

// 不想用密码：仍可以用邮件里的码登录
await signOut();
await page.goto(`${base}/signin/`);
await page.getByLabel('Email', { exact: true }).fill(email);
sent = await emailCount(email);
await page.getByRole('button', { name: 'Email me a code instead' }).click();
await page.getByLabel('6-digit code').fill(await emailedCode(email, sent));
await page.getByRole('button', { name: 'Sign in', exact: true }).click();
await signedIn();

// 同一邮箱再注册：提示去登录
await signOut();
await page.goto(`${base}/signin/?new`);
await page.getByLabel('Email', { exact: true }).fill(email);
await page.getByLabel('Password', { exact: true }).fill('another long password');
await page.getByRole('button', { name: 'Create account' }).click();
await page.getByText('This email already has an account.', { exact: false }).waitFor();
await page.getByRole('heading', { name: 'Sign in', exact: true }).waitFor();

console.log('ok: signed up with a confirmed email, signed in with a password (no email), changed and reset the password, code sign-in still works');
await browser.close();
