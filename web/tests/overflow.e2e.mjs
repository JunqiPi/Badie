// 排版检查：不登录能看的页面，在几种宽度和语言下不能左右滑动、不能有元素伸出屏幕、普通单词不能从中间断开。
// 不用连 Supabase：npm run build && npx astro preview，然后 node tests/overflow.e2e.mjs（BASE_URL 换地址）
import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import { base } from './helpers.mjs';

const pages = ['/', '/signin/', '/levels/', '/about/', '/contact/', '/games/', '/courts/', '/courts/my/', '/courts/gb/', '/privacy/', '/zh/', '/zh/about/'];
const widths = [320, 375, 768, 1024, 1440];
const locales = ['en', 'ms', 'vi', 'hi', 'th'];

function problems() {
  const width = document.documentElement.clientWidth;
  const found = [];
  if (document.documentElement.scrollWidth > width + 1) found.push(`page is ${document.documentElement.scrollWidth}px wide`);
  const scrolls = (el) => { for (let a = el.parentElement; a; a = a.parentElement) if (getComputedStyle(a).overflowX !== 'visible') return true; return false; };
  const wide = [...document.querySelectorAll('header *, main *')].find((el) => {
    const r = el.getBoundingClientRect();
    return r.width > 1 && (r.right > width + 1 || r.left < -1) && !scrolls(el) && !el.closest('[aria-hidden="true"]');
  });
  if (wide) found.push(`${wide.tagName.toLowerCase()}.${wide.className} sticks out: “${wide.textContent.trim().slice(0, 40)}”`);
  // 普通单词（不是网址、不是长串）被挤得从中间断开：说明那一栏太窄
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  for (let node = walker.nextNode(); node && found.length < 5; node = walker.nextNode()) {
    if (!node.parentElement?.closest('header, main') || /:\/\/|@/.test(node.data)) continue;
    for (const m of node.data.matchAll(/[^\s\-–—/]+/g)) {
      if (m[0].length < 2 || m[0].length > 18 || /[\p{Script=Han}\p{Script=Thai}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}_]/u.test(m[0])) continue;
      const range = document.createRange();
      range.setStart(node, m.index);
      range.setEnd(node, m.index + m[0].length);
      if (new Set([...range.getClientRects()].filter((r) => r.width > 0).map((r) => Math.round(r.top))).size > 1) found.push(`“${m[0]}” is broken across lines`);
    }
  }
  return found;
}

const browser = await chromium.launch();
const failures = [];
for (const locale of locales) {
  const context = await browser.newContext();
  await context.addInitScript((code) => localStorage.setItem('badie-language', code), locale);
  const page = await context.newPage();
  for (const path of pages) {
    if (path.startsWith('/zh/') && locale !== 'en') continue;
    await page.setViewportSize({ width: widths[0], height: 800 });
    await page.goto(`${base}${path}`);
    await page.getByRole('main').waitFor();
    await page.waitForTimeout(500);
    for (const width of widths) {
      await page.setViewportSize({ width, height: 800 });
      await page.waitForTimeout(150);
      for (const problem of await page.evaluate(problems)) failures.push(`${path} ${locale} ${width}px: ${problem}`);
    }
  }
  await context.close();
}
await browser.close();
assert.deepEqual(failures, []);
console.log('overflow: ok');
