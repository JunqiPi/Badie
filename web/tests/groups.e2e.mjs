// 球群端到端：建群 → 凭群号加入 → 报名 → 群聊 → 同群的消息请求
// 需要本地 Supabase 和已启动的网站；打过的场次直接写进库（DB_URL）
import { execFileSync } from 'node:child_process';
import { chromium } from 'playwright';
import { base, signUp } from './helpers.mjs';

const db = process.env.DB_URL ?? 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const sql = (query) => execFileSync('psql', [db, '-qtAc', query]).toString().trim();
const stamp = Date.now();
const browser = await chromium.launch();
const open = async (viewport) => (await browser.newContext({ viewport, timezoneId: 'America/Los_Angeles' })).newPage();
const alex = await open({ width: 1280, height: 900 });
const blake = await open({ width: 390, height: 844 });

for (const [page, name] of [[alex, 'Alex'], [blake, 'Blake']]) {
  await signUp(page, `${name.toLowerCase()}${stamp}@test.local`, name);
  await page.getByRole('button', { name: 'Skip for now' }).click();
  await page.getByRole('heading', { name: 'Up for a game tonight?' }).waitFor();
  await page.goto(`${base}/groups/`);
  await page.getByRole('heading', { name: 'Regular games · Groups', level: 1 }).waitFor();
}

// Alex 建群：明天（洛杉矶）那个星期几
const tomorrow = new Intl.DateTimeFormat('en-US', { weekday: 'long', timeZone: 'America/Los_Angeles' }).format(Date.now() + 86400000);
await alex.getByRole('link', { name: 'Start a group' }).first().click();
await alex.getByLabel('Name', { exact: true }).fill('Thu doubles');
await alex.getByRole('combobox', { name: 'Choose venue' }).fill('Los Angeles Badminton');
await alex.getByRole('option', { name: /Los Angeles Badminton Club/ }).click();
await alex.getByLabel('Day of the week').selectOption(tomorrow);
await alex.getByLabel('Spots').fill('8');
await alex.getByRole('button', { name: 'Create group' }).click();
await alex.getByRole('heading', { name: 'Thu doubles' }).waitFor();
const code = (await alex.locator('p.font-mono').innerText()).trim();

// Blake 凭群号加入（“输入房间码 / 群号”页）、报名
await blake.goto(`${base}/join/`);
await blake.getByLabel('Code').fill(code);
await blake.getByRole('button', { name: 'Join' }).click();
await blake.getByRole('button', { name: 'Join group' }).click();
await blake.getByText(`Welcome to Thu doubles!`).waitFor();
await blake.getByRole('button', { name: 'Sign up' }).first().click();
await blake.getByText('Signed up', { exact: true }).first().waitFor();
await blake.getByText('1/8 signed up').first().waitFor();

// 群聊
await blake.getByRole('link', { name: 'Group chat' }).click();
await blake.getByRole('textbox', { name: 'Message' }).fill('Bringing new shuttles');
await blake.getByRole('button', { name: 'Send' }).click();
await blake.getByRole('log').getByText('Bringing new shuttles').waitFor();

await alex.reload();
await alex.getByRole('link', { name: /^Blake/ }).waitFor();
await alex.goto(`${base}/messages/`);
await alex.getByRole('link', { name: /Thu doubles/ }).click();
await alex.getByRole('log').getByText('Bringing new shuttles').waitFor();

// 消息请求：Blake 打满 3 场后可以给同群的 Alex 发一条，Alex 接受后继续聊
const ids = Object.fromEntries(['alex', 'blake'].map((n) => [n, sql(`select id from auth.users where email = '${n}${stamp}@test.local'`)]));
sql(`with g as (insert into games (mode, starts_at, ends_at, venue_id)
       select 'singles', now() - k * interval '1 day', now() - k * interval '1 day' + interval '1 hour', 'v-us-ca-labc' from generate_series(2, 4) k returning id)
     insert into game_players (game_id, user_id, team, rating) select id, '${ids.blake}', 1, 3 from g`);
await blake.goto(`${base}/players/${ids.alex}/`);
await blake.getByText('You’re both in Thu doubles.').waitFor();
await blake.getByRole('link', { name: 'Send a message request' }).click();
await blake.getByRole('textbox', { name: 'Message' }).fill('Want to rally before Thursday?');
await blake.getByRole('button', { name: 'Send' }).click();
await blake.getByText('Message request sent. You can keep chatting once they accept.').waitFor();

await alex.goto(`${base}/messages/`);
await alex.getByRole('link', { name: /Blake.*Message request/ }).click();
await alex.getByText('Blake wants to chat').waitFor();
await alex.getByRole('button', { name: 'Accept' }).click();
await alex.getByRole('textbox', { name: 'Message' }).fill('Sure, Wednesday?');
await alex.getByRole('button', { name: 'Send' }).click();
await alex.getByRole('log').getByText('Sure, Wednesday?').waitFor();
await blake.reload();
await blake.getByRole('log').getByText('Sure, Wednesday?').waitFor();
await blake.getByRole('textbox', { name: 'Message' }).waitFor();

console.log(`ok: created group ${code}, joined by number, signed up, chatted and sent a message request`);
await browser.close();
