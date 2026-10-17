// 社交端到端：打完一场 → 评价 → 球局群聊 → 双方都想再约成为球友 → 私信 → 拉黑
// 需要本地 Supabase 和已启动的网站；球局直接写进库（DB_URL）
import { execFileSync } from 'node:child_process';
import { chromium } from 'playwright';
import { base, signUp } from './helpers.mjs';

const db = process.env.DB_URL ?? 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const stamp = Date.now();
const sql = (query) => execFileSync('psql', [db, '-qtAc', query]).toString().trim();

const browser = await chromium.launch();
const open = async (viewport) => (await browser.newContext({ viewport, timezoneId: 'America/Los_Angeles' })).newPage();
const alex = await open({ width: 1280, height: 900 });
const blake = await open({ width: 390, height: 844 });

for (const [page, name] of [[alex, 'Alex'], [blake, 'Blake']]) {
  await signUp(page, `${name.toLowerCase()}${stamp}@test.local`, name);
  await page.getByRole('button', { name: 'Skip for now' }).click();
  await page.getByRole('heading', { name: 'Find a game' }).waitFor();
}

// 两人一小时前打完一场单打
const game = sql(`with g as (
    insert into games (mode, starts_at, ends_at, venue_id) values ('singles', now() - interval '3 hours', now() - interval '1 hour', 'v-us-ca-21-badminton-club-21bc') returning id)
  insert into game_players (game_id, user_id, team, rating)
    select g.id, u.id, case when u.email like 'alex%' then 1 else 2 end, 3 from g, auth.users u
    where u.email in ('alex${stamp}@test.local', 'blake${stamp}@test.local')
  returning game_id`).split('\n')[0];
sql('select public.prompt_reviews()');

// Alex：通知 → 评价 → 群聊
await alex.reload();
await alex.getByRole('link', { name: /Messages, \d+ unread/ }).click();
await alex.getByRole('tab', { name: 'Updates' }).click();
await alex.getByText('How was your game?').click();
await alex.getByRole('heading', { name: 'Rate your partners' }).waitFor();
const form = alex.getByRole('form', { name: 'Review Blake' });
await form.getByRole('radio', { name: 'On time' }).click();
await form.getByRole('radio', { name: 'About right' }).click();
await form.getByRole('button', { name: 'Friendly' }).click();
await form.getByLabel('I’d play with Blake again').check();
await form.getByRole('button', { name: 'Send review' }).click();
await alex.getByText('Thanks! Review for Blake sent.').waitFor();
await alex.getByRole('link', { name: 'Message players' }).click();
await alex.getByRole('textbox', { name: 'Message' }).fill('Good game! Venmo me $10 for the court?');
await alex.keyboard.press('Enter');
await alex.getByRole('log').getByText('Good game!').waitFor();

// Blake：看到群聊（含防骗提示）→ 评价 Alex 也选再约 → 成为球友 → 私信
await blake.goto(`${base}/app/messages/`);
await blake.getByRole('link', { name: /21 Badminton Club/ }).click();
await blake.getByText('You never need to pay').waitFor();
await blake.getByRole('link', { name: 'Alex' }).click();
await blake.getByText('1 game together').waitFor();
await blake.goto(`${base}/app/games/${game}/`);
const back = blake.getByRole('form', { name: 'Review Alex' });
await back.getByRole('radio', { name: 'On time' }).click();
await back.getByRole('radio', { name: 'Higher' }).click();
await back.getByLabel('I’d play with Alex again').check();
await back.getByRole('button', { name: 'Send review' }).click();
await blake.getByText('Thanks! Review for Alex sent.').waitFor();

await blake.goto(`${base}/app/messages/?tab=friends`);
await blake.getByRole('link', { name: 'Message', exact: true }).click();
await blake.getByRole('textbox', { name: 'Message' }).fill('Same time next week?');
await blake.getByRole('button', { name: 'Send' }).click();
await blake.getByRole('log').getByText('Same time next week?').waitFor();

// Alex：收到私信；拉黑后私信关闭
await alex.goto(`${base}/app/messages/`);
await alex.getByRole('link', { name: /^Blake/ }).click();
await alex.getByRole('log').getByText('Same time next week?').waitFor();
await alex.getByRole('heading', { name: 'Blake' }).getByRole('link').click();
await alex.getByText('Friend', { exact: true }).waitFor();
await alex.getByRole('button', { name: 'Block' }).click();
await alex.getByRole('button', { name: 'Block' }).click();
await alex.getByRole('button', { name: 'Unblock' }).waitFor();
await alex.goto(`${base}/app/messages/dm/${sql(`select id from auth.users where email = 'blake${stamp}@test.local'`)}/`);
await alex.getByText('You can only message friends.').waitFor();

console.log('ok: reviewed, chatted, became friends, messaged and blocked');
await browser.close();
