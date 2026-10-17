// 球群端到端：建群 → 凭群号加入 → 报名 → 群聊
import { chromium } from 'playwright';
import { base, signUp } from './helpers.mjs';

const stamp = Date.now();
const browser = await chromium.launch();
const open = async (viewport) => (await browser.newContext({ viewport, timezoneId: 'America/Los_Angeles' })).newPage();
const alex = await open({ width: 1280, height: 900 });
const blake = await open({ width: 390, height: 844 });

for (const [page, name] of [[alex, 'Alex'], [blake, 'Blake']]) {
  await signUp(page, `${name.toLowerCase()}${stamp}@test.local`, name);
  await page.getByRole('button', { name: 'Skip for now' }).click();
  await page.getByRole('link', { name: 'Groups' }).click();
  await page.getByRole('heading', { name: 'Groups', level: 1 }).waitFor();
}

// Alex 建群：明天（洛杉矶）那个星期几
const tomorrow = new Intl.DateTimeFormat('en-US', { weekday: 'long', timeZone: 'America/Los_Angeles' }).format(Date.now() + 86400000);
await alex.getByRole('link', { name: 'Start a group' }).click();
await alex.getByLabel('Name', { exact: true }).fill('Thu doubles');
await alex.getByRole('combobox', { name: 'Court' }).fill('Los Angeles Badminton');
await alex.getByRole('option', { name: /Los Angeles Badminton Club/ }).click();
await alex.getByLabel('Day').selectOption(`${tomorrow}s`);
await alex.getByLabel('Spots').fill('8');
await alex.getByRole('button', { name: 'Create group' }).click();
await alex.getByRole('heading', { name: 'Thu doubles' }).waitFor();
const code = (await alex.locator('p.font-mono').innerText()).trim();

// Blake 凭群号加入、报名
await blake.getByLabel('Have a group number?').fill(code);
await blake.getByRole('button', { name: 'Find group' }).click();
await blake.getByRole('button', { name: 'Join group' }).click();
await blake.getByText(`Welcome to Thu doubles!`).waitFor();
await blake.getByRole('button', { name: 'Sign up' }).first().click();
await blake.getByText('Going', { exact: true }).first().waitFor();
await blake.getByText('1 of 8 going').first().waitFor();

// 群聊
await blake.getByRole('link', { name: 'Group chat' }).click();
await blake.getByRole('textbox', { name: 'Message' }).fill('Bringing new shuttles');
await blake.getByRole('button', { name: 'Send' }).click();
await blake.getByRole('log').getByText('Bringing new shuttles').waitFor();

await alex.reload();
await alex.getByRole('link', { name: /^Blake/ }).waitFor();
await alex.goto(`${base}/app/messages/`);
await alex.getByRole('link', { name: /Thu doubles/ }).click();
await alex.getByRole('log').getByText('Bringing new shuttles').waitFor();

console.log(`ok: created group ${code}, joined by number, signed up and chatted`);
await browser.close();
