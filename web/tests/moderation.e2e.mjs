// 举报处理端到端：网页上改昵称带脏话会被拒；Blake 被举报 → 管理员 Alex 在审核页看到并改掉 Blake 的昵称
// 需要本地 Supabase 和已启动的网站；管理员和举报直接写库（DB_URL）
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
  await signUp(page, `${name.toLowerCase()}${stamp}@mod.local`, name);
  await page.getByRole('button', { name: 'Skip for now' }).click();
  await page.getByRole('heading', { name: 'Up for a game tonight?' }).waitFor();
}
// 昵称带脏话存不了，并告诉你原因
await blake.goto(`${base}/settings/`);
await blake.getByLabel('Nickname', { exact: true }).fill('Shit Show');
await blake.getByRole('button', { name: 'Save', exact: true }).first().click();
await blake.getByText('Offensive words aren’t allowed. Try different words.').waitFor();

const id = (name) => sql(`select id from auth.users where email = '${name}${stamp}@mod.local'`);
const [alexId, blakeId] = [id('alex'), id('blake')];

// 举报直接写库（网页上举报要先打过交道，见 social.e2e）
sql(`insert into user_reports (reporter_id, reported_id, reason, details) values ('${alexId}', '${blakeId}', 'inappropriate', 'rude name')`);
sql(`insert into admin_users (user_id) values ('${alexId}')`);

// 管理员在审核页看到举报，改掉 Blake 的昵称
await alex.goto(`${base}/admin/`);
await alex.getByRole('heading', { name: 'Reports' }).waitFor();
await alex.getByText('Inappropriate name, photo or messages').waitFor();
await alex.getByText('rude name').waitFor();
await alex.getByRole('button', { name: 'Reset nickname' }).click();
await alex.getByText('No open reports').waitFor();
const renamed = sql(`select nickname from profiles where id = '${blakeId}'`);
if (!renamed.startsWith('Player ')) throw new Error(`nickname not reset: ${renamed}`);
sql(`delete from admin_users where user_id = '${alexId}'`);

console.log(`ok: offensive nickname refused; report shown on the admin page and handled (nickname is now ${renamed})`);
await browser.close();
