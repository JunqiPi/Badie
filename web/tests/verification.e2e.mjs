// 高水平认证端到端：Alex 凭赛事成绩申请 7 级 → 管理员 Blake 审核通过 → Alex 的资料显示认证
// 需要本地 Supabase 和已启动的网站；管理员只能直接写库添加（DB_URL）
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
  await page.getByRole('heading', { name: 'Find a game' }).waitFor();
}

// Alex 申请：赛事成绩 7 级
await alex.goto(`${base}/app/me/`);
await alex.getByRole('button', { name: 'Verify a higher level' }).click();
await alex.getByRole('combobox', { name: 'Level' }).selectOption({ label: '7' });
await alex.getByLabel('Link or certificate number').fill('example.com/results');
await alex.getByLabel('Name on the results or certificate').fill(`Alex Chen ${stamp}`);
await alex.getByRole('button', { name: 'Send for review' }).click();
await alex.getByText('Check the link. It needs to be the right kind of page for this evidence.').waitFor();
await alex.getByLabel('Link or certificate number').fill('usab.tournamentsoftware.com/sport/draw.aspx?id=1');
await alex.getByRole('button', { name: 'Send for review' }).click();
await alex.getByText(/Under review: level 7, Tournament results/).waitFor();

// 普通用户进不了审核页；Blake 成为管理员后审核通过
await blake.goto(`${base}/app/admin/`);
await blake.getByText('Admins only').waitFor();
const blakeId = sql(`select id from auth.users where email = 'blake${stamp}@test.local'`);
sql(`insert into admin_users (user_id) values ('${blakeId}')`);
await blake.goto(`${base}/app/me/`);
await blake.getByRole('link', { name: 'Review queue' }).click();
const card = blake.getByRole('article').filter({ hasText: `Alex Chen ${stamp}` });
await card.waitFor();
await card.getByRole('button', { name: 'Approve', exact: true }).click();
await blake.getByText('Approved', { exact: true }).waitFor();

await alex.reload();
await alex.getByText('Verified 7').waitFor();
sql(`delete from admin_users where user_id = '${blakeId}'`);

console.log('ok: applied with tournament results, rejected a wrong link, approved by an admin');
await browser.close();
