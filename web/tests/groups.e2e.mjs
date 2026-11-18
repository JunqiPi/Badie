// 球群端到端：建群（两个球馆，场次在第二个）→ 发现页切到球群能看到 → 凭群号加入 → 报名 → 群聊 → 同群的消息请求
// 需要本地 Supabase 和已启动的网站；打过的场次直接写进库（DB_URL）
import { execFileSync } from 'node:child_process';
import { chromium } from 'playwright';
import { base, signUp } from './helpers.mjs';

const db = process.env.DB_URL ?? 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const sql = (query) => execFileSync('psql', [db, '-qtAc', query]).toString().trim();
const stamp = Date.now();
const browser = await chromium.launch();
const open = async (viewport) =>
  (await browser.newContext({ viewport, timezoneId: 'America/Los_Angeles', geolocation: { latitude: 34.0765, longitude: -118.0462 }, permissions: ['geolocation'] })).newPage();
const alex = await open({ width: 1280, height: 900 });
const blake = await open({ width: 390, height: 844 });

for (const [page, name] of [[alex, 'Alex'], [blake, 'Blake']]) {
  await signUp(page, `${name.toLowerCase()}${stamp}@test.local`, name);
  await page.getByRole('button', { name: 'Skip for now' }).click();
  await page.getByRole('heading', { name: 'Discover', level: 1 }).waitFor();
  await page.goto(`${base}/groups/`);
  await page.getByRole('heading', { name: 'Groups', level: 1, exact: true }).waitFor();
}

// Alex 建群：明天（洛杉矶）那个星期几
const tomorrow = new Intl.DateTimeFormat('en-US', { weekday: 'long', timeZone: 'America/Los_Angeles' }).format(Date.now() + 86400000);
await alex.getByRole('link', { name: 'Start a group' }).first().click();
await alex.getByLabel('Name', { exact: true }).fill('Thu doubles');
await alex.getByRole('combobox', { name: 'Choose venue' }).fill('Los Angeles Badminton');
await alex.getByRole('option', { name: /Los Angeles Badminton Club/ }).click();
// 第二个球馆，每周那一场放在第二个球馆
await alex.getByRole('combobox', { name: 'Add another court' }).fill('San Gabriel Valley');
await alex.getByRole('option', { name: /San Gabriel Valley Badminton Club/ }).click();
await alex.getByText('Main court', { exact: false }).first().waitFor();
await alex.getByLabel('Day of the week').selectOption(tomorrow);
await alex.getByRole('combobox', { name: /^Court/ }).selectOption({ label: 'San Gabriel Valley Badminton Club' });
await alex.getByLabel('Spots').fill('8');
await alex.getByRole('button', { name: 'Create group' }).click();
await alex.getByRole('heading', { name: 'Thu doubles' }).waitFor();
const code = (await alex.locator('p.font-mono').innerText()).trim();
// 球群页列出两个球馆，这一场写在第二个球馆
await alex.getByRole('heading', { name: 'Los Angeles Badminton Club' }).waitFor();
await alex.getByRole('article').first().getByText('San Gabriel Valley Badminton Club').waitFor();

// 发现页的筛选里选“球群”，附近能看到这个群（任何一个球馆在范围内都算）
await blake.goto(`${base}/`);
await blake.getByRole('button', { name: /^Filters/ }).click();
await blake.getByRole('button', { name: 'Groups', exact: true }).click();
// 注册时可能已经用定位选好了位置；没选就点“用我的位置”
const locate = blake.getByRole('button', { name: 'Use my location' });
if (await locate.waitFor({ timeout: 3000 }).then(() => true, () => false)) await locate.click();
await blake.getByRole('link', { name: /Thu doubles/ }).getByText('Also at San Gabriel Valley Badminton Club').waitFor();
// 记住选择：刷新后还是球群
await blake.reload();
await blake.getByRole('button', { name: 'Remove Groups' }).waitFor();

// Blake 凭群号加入（“输入房间码 / 群号”页）、报名
await blake.goto(`${base}/join/`);
await blake.getByLabel('Code').fill(code);
await blake.getByRole('button', { name: 'Join' }).click();
await blake.getByRole('button', { name: 'Join group' }).click();
await blake.getByText(`Welcome to Thu doubles.`).waitFor();
await blake.getByRole('button', { name: 'Sign up' }).first().click();
await blake.getByText('Signed up', { exact: true }).first().waitFor();
await blake.getByText('1/8 signed up').first().waitFor();

// 访客报名：Alex 在编辑页打开，没登录的人打开报名链接能看到场次和报名的人；Alex 能把访客移出这一场。
// 报名本身走 guest-signup 函数（人机验证），本机不跑函数，这里直接按函数那样写库
const groupId = new URL(alex.url()).pathname.split('/')[2];
await alex.goto(`${base}/groups/${groupId}/edit/`);
await alex.getByRole('button', { name: 'Let people sign up without an account' }).click();
await alex.getByRole('button', { name: 'Save' }).click();
await alex.getByRole('button', { name: 'Copy sign-up link' }).waitFor();
const guestCode = sql(`select guest_code from play_groups where id = '${groupId}'`);
sql(`select guest_sign_up('${guestCode}', (select id from group_sessions where group_id = '${groupId}' order by starts_at limit 1), 'Tina', null, 'en', '192.0.2.1')`);
const visitor = await (await browser.newContext({ viewport: { width: 390, height: 844 }, timezoneId: 'America/Los_Angeles' })).newPage();
await visitor.goto(`${base}/g/${guestCode}/`);
await visitor.getByRole('heading', { name: 'Thu doubles', level: 1 }).waitFor();
await visitor.getByText('2/8 signed up').first().waitFor();
await visitor.getByText('Tina').waitFor();
await visitor.getByLabel('Your name').waitFor();
// Tina 这台设备上存着凭证：看到自己报上了，换了手机要找组织者
const sessionId = sql(`select id from group_sessions where group_id = '${groupId}' order by starts_at limit 1`);
sql(`update session_signups set guest_token_hash = guest_token_hash('tina-token') where guest_name = 'Tina'`);
await visitor.evaluate((id) => localStorage.setItem('badie.guestSignups', JSON.stringify({ [id]: 'tina-token' })), sessionId);
await visitor.reload();
await visitor.getByText('You’re signed up', { exact: true }).waitFor();
await visitor.getByText('If you switch phones, ask Alex to take you off.').waitFor();
await alex.reload();
await alex.getByText('Who’s going').first().click();
await alex.getByRole('button', { name: 'Remove Tina from this session' }).click();
await alex.getByRole('button', { name: 'Remove from this session' }).click();
await alex.getByText('1/8 signed up').first().waitFor();

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
