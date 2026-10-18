// 约球端到端：两人各自发请求 → 配上 → 都确认 → 球局 → 签到 → 两边报赛果 → 战绩
// 需要本地 Supabase 和已启动的网站；把球局挪到“已开始”要直接改库（DB_URL）
import { execFileSync } from 'node:child_process';
import { chromium } from 'playwright';
import { base, signUp } from './helpers.mjs';

const db = process.env.DB_URL ?? 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const stamp = Date.now();
const sql = (query) => execFileSync('psql', [db, '-qc', query]);

// 之前跑测试剩下的请求会抢先配对，先撤掉（只动测试账号）
sql("update match_tickets set status = 'cancelled' where status in ('searching', 'offered', 'paused') and user_id in (select id from auth.users where email like '%@test.local')");

const browser = await chromium.launch();
const open = async (viewport) => (await browser.newContext({ viewport, timezoneId: 'America/Los_Angeles' })).newPage();
const alex = await open({ width: 1280, height: 900 });
const blake = await open({ width: 390, height: 844 });

// Alex 做完问卷（每题选第 2 项 → 3−），Blake 跳过（按 3 级）
await signUp(alex, `alex${stamp}@test.local`, 'Alex');
for (let i = 1; i <= 14; i++) {
  await alex.getByText(`${i} of 14`).waitFor();
  await alex.locator('section ul button').nth(1).click();
}
await alex.getByRole('heading', { name: '3−' }).waitFor();
await alex.getByRole('button', { name: 'Save my level' }).click();
await alex.getByRole('heading', { name: 'Find a game' }).waitFor();

await signUp(blake, `blake${stamp}@test.local`, 'Blake');
await blake.getByRole('button', { name: 'Skip for now' }).click();
await blake.getByText('You’re starting at level 3').waitFor();

async function request(page) {
  await page.getByRole('button', { name: 'Singles' }).click();
  await page.getByRole('combobox', { name: 'Search courts' }).fill('Los Angeles Badminton');
  await page.getByRole('option', { name: /Los Angeles Badminton Club/ }).click();
  await page.getByRole('button', { name: 'Find players' }).click();
}

await request(alex);
await alex.getByText('Looking for players', { exact: true }).waitFor();
await alex.getByText('Nearby that day: 0 looking, 0 a good fit.').waitFor();
await request(blake);
await blake.getByText('Singles match found').waitFor();
await blake.getByRole('button', { name: 'I’m in' }).click();
await blake.getByText('You’re in. Waiting for the others').waitFor();

await alex.reload();
await alex.getByRole('button', { name: 'I’m in' }).click();
await alex.getByText('Game on', { exact: true }).waitFor();
await alex.getByRole('link', { name: 'View game' }).click();
await alex.getByRole('link', { name: 'Blake' }).waitFor();

// 把这局挪到已经开始
sql(`update games set starts_at = date_trunc('hour', now()) - interval '1 hour', ends_at = date_trunc('hour', now()) + interval '1 hour'
     where id in (select game_id from game_players join auth.users u on u.id = user_id where u.email = 'alex${stamp}@test.local')`);
await alex.reload();
await alex.getByRole('button', { name: 'I’m here' }).click();
await alex.getByText('You’re checked in.').waitFor();
await alex.getByLabel('Score (optional)').fill('21:15 21:18');
await alex.getByRole('button', { name: 'We won' }).click();
await alex.getByText('Waiting for the other side to report.').waitFor();
await alex.getByText('Score: 21:15 21:18').waitFor();
// 场地费：标自己已付，不能替对方标（匹配的局没有发起人）
await alex.getByRole('checkbox', { name: /You/ }).check();
await alex.getByText('1 of 2 paid').waitFor();
if (await alex.getByRole('checkbox', { name: /Blake/ }).isEnabled()) throw new Error('should not mark someone else as paid');

await blake.goto(`${base}/app/games/`);
await blake.getByRole('link', { name: /Singles at Los Angeles Badminton Club/ }).click();
await blake.getByRole('button', { name: 'We lost' }).click();
await blake.getByText('Confirmed: you lost.').waitFor();
await blake.getByText('Score: 21:15 21:18').waitFor();

await alex.goto(`${base}/app/games/`);
await alex.getByText('100%').waitFor();

console.log('ok: two players matched, confirmed, checked in, agreed on the result and score, and marked the court fee');
await browser.close();
