// 按昵称搜球友：搜到 → 加球友 → 对方通过；关掉“可以按昵称找到我”后搜不到
import { chromium } from 'playwright';
import { base, signUp } from './helpers.mjs';

const stamp = Date.now();
// 昵称里不能有一串数字（防留电话），用字母做唯一后缀
const nickname = `Dana${[...String(stamp).slice(-6)].map((d) => 'abcdefghij'[d]).join('')}`;
const browser = await chromium.launch();
const open = async (viewport) => (await browser.newContext({ viewport, timezoneId: 'America/Los_Angeles' })).newPage();
const casey = await open({ width: 1280, height: 900 });
const dana = await open({ width: 390, height: 844 });

for (const [page, name] of [[casey, 'Casey'], [dana, nickname]]) {
  await signUp(page, `${name.toLowerCase()}${stamp}@search.local`, name);
  await page.getByRole('button', { name: 'Skip for now' }).click();
  await page.getByRole('heading', { name: 'Find a game' }).waitFor();
}

await casey.goto(`${base}/app/messages/?tab=friends`);
await casey.getByRole('searchbox', { name: 'Nickname' }).fill(nickname.toLowerCase());
await casey.getByRole('link', { name: new RegExp(nickname) }).waitFor();
await casey.getByRole('button', { name: 'Add friend' }).click();
await casey.getByText('Requested', { exact: true }).waitFor();

await dana.goto(`${base}/app/messages/?tab=friends`);
await dana.getByRole('button', { name: 'Accept' }).click();
await dana.getByText('You’re now friends').waitFor();

// 关掉之后搜不到
await dana.goto(`${base}/app/me/`);
await dana.getByLabel('Let players find me by nickname').uncheck();
await dana.getByText('Saved').waitFor();
await casey.reload();
await casey.getByRole('searchbox', { name: 'Nickname' }).fill(nickname);
await casey.getByText('No one by that name. They may have turned off search.').waitFor();

console.log(`ok: found ${nickname} by nickname, became friends, then hidden from search`);
await browser.close();
