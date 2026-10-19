// 球局端到端：发起公开单打 → 附近的人看到并加入 → 人齐开局；私密局凭房间码加入 → 房主取消
import { chromium } from 'playwright';
import { base, signUp } from './helpers.mjs';

const stamp = Date.now();
const browser = await chromium.launch();
// 两个人都在洛杉矶羽毛球俱乐部附近
const open = async (viewport) =>
  (await browser.newContext({ viewport, timezoneId: 'America/Los_Angeles', geolocation: { latitude: 34.07, longitude: -118.05 }, permissions: ['geolocation'] })).newPage();
const alex = await open({ width: 1280, height: 900 });
const blake = await open({ width: 390, height: 844 });

for (const [page, name] of [[alex, 'Alex'], [blake, 'Blake']]) {
  await signUp(page, `${name.toLowerCase()}${stamp}@rooms.local`, name);
  await page.getByRole('button', { name: 'Skip for now' }).click();
  await page.getByRole('heading', { name: 'Up for a game tonight?' }).waitFor();
  await page.goto(`${base}/rooms/`);
  await page.getByRole('heading', { name: 'Nearby games', level: 1 }).waitFor();
}

async function post(page, { mode, isPublic, daysAhead }) {
  await page.getByRole('link', { name: 'Start a game' }).first().click();
  await page.getByRole('button', { name: mode }).click();
  await page.getByRole('combobox', { name: 'Choose venue' }).fill('Los Angeles Badminton');
  await page.getByRole('option', { name: /Los Angeles Badminton Club/ }).click();
  await page.getByRole('radiogroup', { name: 'Date (next 14 days)' }).getByRole('radio').nth(daysAhead).click();
  if (!isPublic) await page.getByRole('button', { name: 'Only people with the code' }).click();
  await page.getByRole('button', { name: 'Casual' }).click();
  await page.getByLabel('Note (optional)').fill('Court 3, bring a shuttle');
  await page.getByRole('button', { name: 'Post game' }).click();
  await page.getByText('Court 3, bring a shuttle').waitFor();
  return page.locator('p.grid-cols-6').getAttribute('aria-label');
}

// Alex 发起明天的公开单打；Blake 在附近看到并加入
await post(alex, { mode: 'Singles', isPublic: true, daysAhead: 1 });
await alex.getByText('Start when all 2 spots are filled.').waitFor();

await blake.getByRole('button', { name: 'Use my location' }).click();
await blake.getByRole('link', { name: /Hosted by Alex/ }).first().click();
await blake.getByText('Join to see who’s playing.').waitFor();
await blake.getByRole('button', { name: 'Join game' }).click();
await blake.getByText('You’re in! The host starts the game when every spot is filled.').waitFor();

// 人齐了，Alex 开局，两边都能进球局页
await alex.reload();
await alex.getByRole('link', { name: 'Blake' }).waitFor();
await alex.getByRole('button', { name: 'Start game' }).click();
await alex.getByText('Game on! Everyone’s in.').waitFor();
await alex.getByRole('link', { name: 'View game' }).click();
await alex.getByRole('link', { name: 'Blake' }).waitFor();

await blake.reload();
await blake.getByText('Game on! Everyone’s in.').waitFor();

// Blake 发起后天的私密双打，Alex 凭房间码加入
await blake.goto(`${base}/app/rooms/`);
const code = await post(blake, { mode: 'Doubles', isPublic: false, daysAhead: 2 });
await alex.goto(`${base}/join/`);
await alex.getByLabel('Code').fill(code);
await alex.getByRole('button', { name: 'Join', exact: true }).click();
await alex.getByText('You’re in. The host starts the game when every spot is filled.').waitFor();
await alex.getByText('2 of 4').waitFor();

// Blake 取消，Alex 收到通知
await blake.reload();
await blake.getByRole('button', { name: 'Cancel game' }).click();
await blake.getByRole('button', { name: 'Yes, cancel for everyone' }).click();
await blake.getByText('The host cancelled this game.').waitFor();
await alex.goto(`${base}/notifications/`);
await alex.getByText('Game cancelled').first().waitFor();

console.log(`ok: posted, found nearby, joined, started; joined private room ${code} by code and saw it cancelled`);
await browser.close();
