// 等级卡片端到端测试：从分享链接（/levels/4/?ref=card）进来 → 不登录测级 → 结果页的打法和卡片 → 保存图片、复制链接，全程没有登录框
// → 注册并建好资料后等级已经存上，不用再答一遍
// 需要本地 Supabase（supabase start）和已启动的网站（BASE_URL）
import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { base, emailedCode, password, pwnedPasswords } from './helpers.mjs';

const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 390, height: 844 }, locale: 'en-US', permissions: ['clipboard-read', 'clipboard-write'] });
const page = await context.newPage();
page.on('pageerror', (error) => {
  throw error;
});
const visited = [];
page.on('framenavigated', (frame) => frame === page.mainFrame() && visited.push(new URL(frame.url()).pathname));

// 分享卡片带来的访问：标题换成“你的朋友是 4。你呢？”
await page.goto(`${base}/levels/4/?ref=card`);
await page.getByRole('heading', { name: 'Your friend is 4. What about you?' }).waitFor();
assert.equal(await page.evaluate(() => localStorage.getItem('badie-ref')), 'card');
await page.getByRole('link', { name: 'Find your level · 2 min, no sign-up' }).click();
await page.waitForURL('**/level-quiz/');

// 和 iOS 测试里的 demo 一样的答案：4 级，六边形战士，离 5 级还差反手后场
const picks = [4, 4, 4, 2, 3, 3, 4, 2, 2, 3, 2, 0, 0, 0];
for (const [i, pick] of picks.entries()) {
  await page.getByText(`Question ${i + 1} of ${picks.length}`).waitFor();
  await page.locator('section ul > li > button').nth(pick).click();
}
await page.waitForURL('**/level-quiz/result/');
await page.getByRole('heading', { name: 'All-rounder' }).waitFor();
await page.getByText('Self-rated').waitFor();
await page.getByRole('img', { name: 'Front of the level card' }).waitFor();

// 保存图片、复制链接
const [download] = await Promise.all([page.waitForEvent('download'), page.getByRole('link', { name: 'Save image' }).click()]);
assert.equal(download.suggestedFilename(), 'badie-level-4.png');
await page.getByRole('button', { name: 'Copy link' }).click();
assert.equal(await page.evaluate(() => navigator.clipboard.readText()), `${new URL(base).origin}/levels/4/?ref=card`);
// 翻到背面：保存的是背面
await page.getByRole('button', { name: 'Flip' }).click();
await page.getByRole('img', { name: 'Back of the level card' }).waitFor();
const [back] = await Promise.all([page.waitForEvent('download'), page.getByRole('link', { name: 'Save image' }).click()]);
assert.equal(back.suggestedFilename(), 'badie-level-4-back.png');
assert.ok(!visited.some((path) => path.startsWith('/signin/')), `no sign-in on the way: ${visited.join(' ')}`);

// 去注册：建好资料后等级已经存上，不用再答一遍；来源记在资料里
const email = `card${Date.now()}@test.local`;
await pwnedPasswords(page);
await page.goto(`${base}/signin/?new&next=${encodeURIComponent('/level-quiz/result/')}`);
await page.getByLabel('Email', { exact: true }).fill(email);
await page.getByLabel('Password', { exact: true }).fill(password);
await page.getByRole('button', { name: 'Create account' }).click();
await page.getByLabel('6-digit code').fill(await emailedCode(email));
await page.getByRole('button', { name: 'Create account' }).click();
await page.getByLabel('Nickname').fill('Cardy');
await page.getByRole('radio', { name: 'Male', exact: true }).click();
await page.getByLabel('Where did you hear about Badie? (optional)').selectOption('level_card');
await page.getByRole('button', { name: 'Continue' }).click();
await page.waitForURL('**/level-quiz/result/');
await page.getByText('Level saved.').waitFor();
assert.equal(await page.evaluate(() => sessionStorage.getItem('badie-quiz-answers')), null, 'answers leave the browser once saved');

// 重新打开：结果从资料里的答案算出来，“我的”里能再分享卡片
await page.reload();
await page.getByText('Level saved.').waitFor();
await page.goto(`${base}/me/`);
await page.getByText('Lv.4').first().waitFor();
await page.getByRole('link', { name: 'Share level card' }).waitFor();

await browser.close();
console.log('level card e2e passed');
