// 榜单与约战端到端：确认过的比赛 → 周榜和场馆榜 → 资料页胜率 → 发起挑战 → 对方接受 → 生成球局
// 需要本地 Supabase 和已启动的网站；比赛记录直接写进库（DB_URL）
import { execFileSync } from 'node:child_process';
import { chromium } from 'playwright';
import { base, signUp } from './helpers.mjs';

const db = process.env.DB_URL ?? 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const stamp = Date.now();
const sql = (query) => execFileSync('psql', [db, '-qtAc', query]).toString().trim();

const browser = await chromium.launch();
const open = async (viewport) =>
  (await browser.newContext({ viewport, timezoneId: 'America/Los_Angeles', geolocation: { latitude: 34.0765, longitude: -118.0462 }, permissions: ['geolocation'] })).newPage();
const alex = await open({ width: 1280, height: 900 });
const blake = await open({ width: 390, height: 844 });
const casey = `casey${stamp}@test.local`;

for (const [page, name] of [[alex, 'Alex'], [blake, 'Blake']]) {
  await signUp(page, `${name.toLowerCase()}${stamp}@test.local`, name);
  await page.getByRole('button', { name: 'Skip for now' }).click();
  await page.getByRole('heading', { name: 'Find a game' }).waitFor();
}

// 第三个人只在库里；三人注册满 7 天；Alex 本周赢了 Blake 两场、赢了 Casey 一场（都已双方确认）
const ids = Object.fromEntries(['alex', 'blake'].map((n) => [n, sql(`select id from auth.users where email = '${n}${stamp}@test.local'`)]));
ids.casey = sql(`insert into auth.users (id, email) values (gen_random_uuid(), '${casey}') returning id`).split('\n')[0];
sql(`insert into profiles (id, nickname, country_code) values ('${ids.casey}', 'Casey', 'US');
     update profiles set created_at = now() - interval '10 days', country_code = 'US' where id in ('${ids.alex}', '${ids.blake}', '${ids.casey}')`);
for (const [k, other] of [[1, 'blake'], [2, 'casey'], [3, 'blake']]) {
  sql(`with g as (insert into games (mode, starts_at, ends_at, venue_id)
         values ('singles', now() - interval '${k * 5 + 60} minutes', now() - interval '${k * 5} minutes', 'v-us-ca-labc') returning id),
       p as (insert into game_players (game_id, user_id, team, rating) select g.id, x.u::uuid, x.t, 3 from g, (values ('${ids.alex}', 1), ('${ids[other]}', 2)) x(u, t) returning game_id, user_id)
       insert into result_reports (game_id, reporter_id, outcome) select game_id, user_id, 'team1' from p`);
}

// 周榜：Alex 15 + 15 + 7.5 ≈ 38 分
await alex.getByRole('link', { name: 'My games' }).first().click();
await alex.getByRole('link', { name: 'Rankings' }).click();
await alex.getByText(/You’re #\d+ with 38 points/).waitFor();
await alex.getByRole('listitem').filter({ hasText: 'Alex (you)' }).getByText('38 pts').waitFor();

// 上周：这些比赛不算进去
await alex.getByRole('button', { name: 'Last week' }).click();
await alex.getByRole('heading', { name: 'Last week' }).waitFor();
await alex.getByRole('heading', { name: 'Court champions' }).waitFor();
await alex.waitForFunction(() => !document.querySelector('.skeleton'));
if (await alex.getByText('Alex (you)').count()) throw new Error('this week’s games showed up on last week’s board');
await alex.getByRole('button', { name: 'This week' }).click();
await alex.getByText('38 pts').waitFor();

// 资料页的胜率（自己看得到，3 场还不公开）
await alex.getByRole('link', { name: /Alex \(you\)/ }).click();
await alex.getByText('100% wins').waitFor();
await alex.getByText('Others see this from 5 confirmed games.').waitFor();

// Alex 向 Blake 发起挑战，Blake 接受
await alex.goto(`${base}/app/players/${ids.blake}/`);
await alex.getByRole('button', { name: 'Challenge to singles' }).click();
await alex.getByRole('combobox', { name: 'Court' }).fill('Los Angeles Badminton');
await alex.getByRole('option', { name: /Los Angeles Badminton Club/ }).click();
await alex.getByLabel('Message (optional)').fill('Best of three?');
await alex.getByRole('button', { name: 'Send challenge' }).click();
await alex.getByText('Challenge sent. Waiting for their answer.').waitFor();

await blake.goto(`${base}/app/games/`);
await blake.getByText('challenged you to singles').waitFor();
await blake.getByText('“Best of three?”').waitFor();
await blake.getByRole('button', { name: 'Accept' }).click();
await blake.getByText('Game on!').waitFor();

await alex.goto(`${base}/app/games/`);
await alex.getByRole('link', { name: 'Game on' }).waitFor();

console.log('ok: weekly board, win rate, challenge sent and accepted');
await browser.close();
