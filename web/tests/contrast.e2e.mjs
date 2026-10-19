// 文字对比度：公开页面和网页应用，浅色 / 深色各走一遍；先查静止状态，再把鼠标逐个移到能点的东西上查悬停状态。
// 正文至少 4.5:1，大字（24px 起，或 18.7px 起的粗体）至少 3:1（WCAG AA）。禁用的控件不算（规范豁免）
import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { base, signUp } from './helpers.mjs';

const interactive = 'a[href], button:not([disabled]), summary, [role="button"], [role="tab"], select, label:has(input)';

// 在页面里运行：root 里每段可见文字和它实际背景的对比度，不够的返回出来
function lowContrast(root) {
  const parse = (value) => {
    const m = value.match(/rgba?\(([^)]+)\)/);
    if (!m) return null;
    const [r, g, b, a = 1] = m[1].split(/[ ,/]+/).filter(Boolean).map(Number);
    return [r, g, b, a];
  };
  const over = (top, under) => {
    const a = top[3] + under[3] * (1 - top[3]);
    return a === 0 ? [0, 0, 0, 0] : [0, 1, 2].map((i) => (top[i] * top[3] + under[i] * under[3] * (1 - top[3])) / a).concat(a);
  };
  const luminance = ([r, g, b]) => {
    const f = (c) => ((c /= 255) <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
  };
  // 往上找背景，半透明的叠起来；遇到背景图（渐变、图片）就算不出来，跳过
  const background = (el) => {
    let color = [0, 0, 0, 0];
    for (let node = el; node; node = node.parentElement) {
      const style = getComputedStyle(node);
      if (style.backgroundImage !== 'none') return null;
      color = over(color, parse(style.backgroundColor) ?? [0, 0, 0, 0]);
      if (color[3] >= 0.999) return color;
    }
    return over(color, [255, 255, 255, 1]);
  };
  // 文字自己和外层的 opacity 都会让字变淡
  const fade = (el) => {
    let opacity = 1;
    for (let node = el; node; node = node.parentElement) opacity *= Number(getComputedStyle(node).opacity);
    return opacity;
  };
  const problems = [];
  const elements = [root, ...root.querySelectorAll('*')];
  for (const el of elements) {
    const text = [...el.childNodes].filter((n) => n.nodeType === 3).map((n) => n.textContent).join('').trim();
    if (!text) continue;
    const style = getComputedStyle(el);
    if (style.visibility !== 'visible' || el.getClientRects().length === 0) continue;
    if (el.closest('[aria-hidden="true"], .sr-only, :disabled, [aria-disabled="true"]')) continue;
    const bg = background(el);
    const fg = parse(style.color);
    if (!bg || !fg) continue;
    fg[3] *= fade(el);
    const [a, b] = [luminance(over(fg, bg)), luminance(bg)];
    const ratio = (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
    const size = parseFloat(style.fontSize);
    const large = size >= 24 || (size >= 18.66 && Number(style.fontWeight) >= 700);
    if (ratio < (large ? 3 : 4.5)) {
      problems.push({ text: text.slice(0, 40), ratio: Math.round(ratio * 100) / 100, color: style.color, background: `rgb(${bg.slice(0, 3).map(Math.round).join(', ')})` });
    }
  }
  return problems;
}

// 等进场动画播完（转圈这种无限循环的不等），否则淡入中的文字会被量成半透明
const settle = (page) => page.evaluate(() =>
  Promise.all(document.getAnimations().filter((a) => a.effect?.getTiming().iterations !== Infinity).map((a) => a.finished.catch(() => {}))));

const found = [];
async function audit(page, where) {
  await page.mouse.move(0, 0);
  await settle(page);
  for (const p of await page.locator('body').evaluate(lowContrast)) found.push({ where, state: 'static', ...p });

  // 同一种样式只悬停一次（长列表里的每一项都一样）
  const seen = new Set();
  for (const el of await page.locator(interactive).all()) {
    const key = await el.evaluate((node) => `${node.tagName}.${node.className}|${node.parentElement?.className}`).catch(() => null);
    if (!key || seen.has(key) || !(await el.isVisible().catch(() => false))) continue;
    seen.add(key);
    if (!(await el.hover({ timeout: 1500 }).then(() => true, () => false))) continue;
    await page.waitForTimeout(250);
    const label = ((await el.innerText().catch(() => '')) || (await el.getAttribute('aria-label')) || key).trim().slice(0, 30);
    for (const p of await el.evaluate(lowContrast)) found.push({ where, state: `hover "${label}"`, ...p });
  }
}

const browser = await chromium.launch();
// 浅色、深色各开一个窗口同时跑
async function check(colorScheme) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 }, colorScheme, timezoneId: 'America/Los_Angeles' });
  const page = await context.newPage();

  // 公开页面：首页 → 国家 → 城市 → 球馆
  await page.goto(`${base}/`);
  await page.locator('main h1').first().waitFor();
  await page.waitForLoadState('networkidle');
  await audit(page, `${colorScheme} /`);
  await page.goto(`${base}/courts/us/`);
  await audit(page, `${colorScheme} /courts/us/`);
  const firstLink = (pattern) => page.locator('main a[href]').evaluateAll(
    (links, source) => links.map((a) => a.getAttribute('href')).find((href) => new RegExp(source).test(href)), pattern);
  const city = await firstLink('^/courts/us/[^/]+/$');
  await page.goto(`${base}${city}`);
  await audit(page, `${colorScheme} ${city}`);
  const venue = await firstLink(`^${city}[^/]+/$`);
  await page.goto(`${base}${venue}`);
  await audit(page, `${colorScheme} venue`);
  await page.goto(`${base}/no-such-page/`);
  await audit(page, `${colorScheme} 404`);

  // 网页应用：登录页；注册后逐个页面看，再建一个球群看球群页和群聊
  await page.goto(`${base}/signin/`);
  await page.getByLabel('Email').waitFor();
  await audit(page, `${colorScheme} sign in`);
  await signUp(page, `contrast-${colorScheme}${Date.now()}@test.local`, 'Casey');
  await audit(page, `${colorScheme} level quiz`);
  await page.getByRole('button', { name: 'Skip for now' }).click();
  await page.getByRole('heading', { name: 'Up for a game tonight?' }).waitFor();
  await audit(page, `${colorScheme} home`);
  for (const path of ['/play/', '/games/', '/rankings/', '/challenges/', '/messages/', '/notifications/', '/courts/', '/me/', '/settings/', '/levels/', '/about/', '/join/', '/rooms/', '/rooms/new/', '/groups/', '/groups/new/']) {
    await page.goto(`${base}${path}`);
    await page.locator('main h1').first().waitFor();
    await page.waitForLoadState('networkidle');
    await audit(page, `${colorScheme} ${path}`);
  }
  const tomorrow = new Intl.DateTimeFormat('en-US', { weekday: 'long', timeZone: 'America/Los_Angeles' }).format(Date.now() + 86400000);
  await page.getByLabel('Name', { exact: true }).fill('Contrast club');
  await page.getByRole('combobox', { name: 'Choose venue' }).fill('Los Angeles Badminton');
  await page.getByRole('option', { name: /Los Angeles Badminton Club/ }).click();
  await page.getByLabel('Day of the week').selectOption(tomorrow);
  await page.getByRole('button', { name: 'Create group' }).click();
  await page.getByRole('heading', { name: 'Contrast club' }).waitFor();
  await audit(page, `${colorScheme} group`);
  await page.getByRole('link', { name: 'Group chat' }).click();
  await page.getByRole('textbox', { name: 'Message' }).fill('See you Thursday');
  await page.getByRole('button', { name: 'Send' }).click();
  await page.getByRole('log').getByText('See you Thursday').waitFor();
  await audit(page, `${colorScheme} group chat`);
  await page.goto(`${base}/rooms/new/`);
  await page.getByRole('combobox', { name: 'Choose venue' }).fill('Los Angeles Badminton');
  await page.getByRole('option', { name: /Los Angeles Badminton Club/ }).click();
  await page.getByRole('button', { name: 'Casual' }).click();
  await page.getByRole('button', { name: 'Post game' }).click();
  await page.getByText('Open spot').first().waitFor();
  await audit(page, `${colorScheme} room`);
  await page.goto(`${base}/settings/`);
  await page.getByRole('button', { name: 'Delete account' }).click();
  await audit(page, `${colorScheme} delete account`);

  // 手机宽度：底部导航和单栏布局（没有悬停，只看静止状态）
  await page.setViewportSize({ width: 390, height: 844 });
  for (const path of ['/', '/courts/us/', '/play/', '/games/', '/messages/', '/me/']) {
    await page.goto(`${base}${path}`);
    await page.locator('main h1').first().waitFor();
    await page.waitForLoadState('networkidle');
    await settle(page);
    for (const p of await page.locator('body').evaluate(lowContrast)) found.push({ where: `${colorScheme} phone ${path}`, state: 'static', ...p });
  }
  await context.close();
}
await Promise.all(['light', 'dark'].map(check));
await browser.close();

for (const p of found) console.log(`${p.where} · ${p.state} · "${p.text}" ${p.ratio}:1 (${p.color} on ${p.background})`);
assert.equal(found.length, 0, `${found.length} pieces of text are too faint`);
console.log('ok: every text has enough contrast, at rest and on hover, in light and dark');
