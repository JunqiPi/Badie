// 当晚端到端：组织者建群 → 一场开始了 30 分钟（直接写库）→ 球群页点“排场” → 全到了 → 开始 → 打完了（撤销条）
// → 用今晚的名单开一场比赛、输比分 → 收款填金额、标已付 → 球员在球群页“付给 … · $12”点“我付了” → 不登录的人看看板
// 需要本地 Supabase 和已启动的网站；场次和报名直接写进库（DB_URL）
import { execFileSync } from 'node:child_process';
import { chromium } from 'playwright';
import { base, signUp } from './helpers.mjs';

const db = process.env.DB_URL ?? 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const sql = (query) => execFileSync('psql', [db, '-qtAc', query]).toString().trim();
const stamp = Date.now();
const browser = await chromium.launch();
const open = async (viewport) =>
  (await browser.newContext({ viewport, timezoneId: 'America/Los_Angeles', geolocation: { latitude: 34.0765, longitude: -118.0462 }, permissions: ['geolocation'] })).newPage();
const olivia = await open({ width: 390, height: 844 });
const max = await open({ width: 390, height: 844 });

for (const [page, name] of [[olivia, 'Olivia'], [max, 'Max']]) {
  await signUp(page, `${name.toLowerCase()}${stamp}@test.local`, name);
  await page.getByRole('button', { name: 'Skip for now' }).click();
  await page.getByRole('heading', { name: 'Discover', level: 1 }).waitFor();
}

// Olivia 建群
const tomorrow = new Intl.DateTimeFormat('en-US', { weekday: 'long', timeZone: 'America/Los_Angeles' }).format(Date.now() + 86400000);
await olivia.goto(`${base}/groups/new/`);
await olivia.getByLabel('Name', { exact: true }).fill('Wed doubles');
await olivia.getByRole('combobox', { name: 'Choose venue' }).fill('Los Angeles Badminton');
await olivia.getByRole('option', { name: /Los Angeles Badminton Club/ }).click();
await olivia.getByLabel('Day of the week').selectOption(tomorrow);
await olivia.getByLabel('Spots').fill('8');
await olivia.getByRole('button', { name: 'Create group' }).click();
await olivia.getByRole('heading', { name: 'Wed doubles' }).waitFor();
const groupId = new URL(olivia.url()).pathname.split('/')[2];
const code = (await olivia.locator('p.font-mono').innerText()).trim();

// Max 凭群号加入
await max.goto(`${base}/join/`);
await max.getByLabel('Code').fill(code);
await max.getByRole('button', { name: 'Join' }).click();
await max.getByRole('button', { name: 'Join group' }).click();
await max.getByText('Welcome to Wed doubles.').waitFor();

// 一场 30 分钟前开始的球：Olivia、Max 和两个访客报了名
const ids = Object.fromEntries(['olivia', 'max'].map((n) => [n, sql(`select id from auth.users where email = '${n}${stamp}@test.local'`)]));
const session = sql(`insert into group_sessions (group_id, starts_at, ends_at, capacity)
                     values ('${groupId}', now() - interval '30 minutes', now() + interval '2 hours', 8) returning id`);
sql(`insert into session_signups (session_id, user_id) values ('${session}', '${ids.olivia}'), ('${session}', '${ids.max}')`);
sql(`insert into session_signups (session_id, guest_name, guest_token_hash)
     values ('${session}', 'Tina', md5(random()::text)), ('${session}', 'Raj', md5(random()::text))`);

// 球群页：今天这一场有“排场”
await olivia.reload();
await olivia.getByRole('link', { name: 'Run courts' }).click();
await olivia.getByRole('heading', { name: 'Club night' }).waitFor();
await olivia.getByRole('button', { name: 'Everyone’s here' }).click();
await olivia.getByText('4 here', { exact: false }).waitFor();
await olivia.getByRole('button', { name: 'Start', exact: true }).click();

// 场地 1 排上了四个人；打完了 → 撤销条 → 同四个人再排上
const court = olivia.getByRole('article', { name: 'Court 1' });
await court.getByRole('button', { name: 'Finish' }).click();
await olivia.getByRole('button', { name: 'Undo' }).waitFor();
await court.getByRole('button', { name: 'Finish' }).waitFor();

// 看板（不登录）：能看到场地 1 和名字
const boardCode = sql(`select board_code from club_nights where session_id = '${session}'`);
const visitor = await (await browser.newContext({ viewport: { width: 390, height: 844 }, timezoneId: 'America/Los_Angeles' })).newPage();
await visitor.goto(`${base}/live/${boardCode}/`);
await visitor.getByRole('heading', { name: 'Wed doubles', level: 1 }).waitFor();
await visitor.getByText('Court 1').waitFor();
await visitor.getByText(/Tina/).first().waitFor();

// 比赛：用今晚的名单开一场单打循环，输一个比分
await olivia.getByRole('button', { name: 'Match', exact: true }).click();
await olivia.getByRole('button', { name: 'Start a match with tonight’s list' }).click();
await olivia.getByText('4 players').waitFor();
await olivia.getByRole('button', { name: 'Singles round robin' }).click();
await olivia.getByRole('button', { name: 'Start', exact: true }).click();
await olivia.getByRole('heading', { name: 'Playing now' }).waitFor();
await olivia.getByRole('button', { name: 'Enter score' }).first().click();
const sheet = olivia.getByRole('dialog');
await sheet.getByRole('button', { name: /Tap to type/ }).first().click();
await sheet.getByRole('spinbutton').fill('21');
await sheet.getByRole('button', { name: /Tap to type/ }).last().click();
await sheet.getByRole('spinbutton').fill('15');
await sheet.getByRole('button', { name: 'Save', exact: true }).click();
await olivia.getByRole('cell', { name: '1–0' }).waitFor();

// 收款：每人 $12，Tina 当面付了
await olivia.getByRole('button', { name: 'Payments', exact: true }).click();
await olivia.getByLabel('Each person pays').fill('12');
await olivia.getByRole('button', { name: 'Save', exact: true }).click();
await olivia.getByText('$12 each').waitFor();
await olivia.getByRole('button', { name: 'Mark Tina as paid' }).click();
await olivia.getByText('Paid 1', { exact: true }).waitFor();

// Max 在球群页付钱，点“我付了”
await max.goto(`${base}/groups/${groupId}/`);
await max.getByRole('button', { name: 'Pay Olivia · $12' }).click();
await max.getByRole('heading', { name: 'Pay Olivia' }).waitFor();
await max.getByRole('button', { name: 'I paid' }).click();
await max.getByText('Paid', { exact: true }).first().waitFor();

// 组织者那边：自己标的
await olivia.reload();
await olivia.getByText('Paid 2', { exact: true }).waitFor();
await olivia.getByText('Paid 2', { exact: true }).click();
await olivia.getByText('Marked by them').waitFor();

console.log('ok: ran the courts, finished a game, played a match, set the fee and collected payments');
await browser.close();
