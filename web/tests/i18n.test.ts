// 界面翻译：代码里每个 t('…')、定级题和静态页面的 data-t 在所有语言里都有译文，占位符一致；单复数按语言规则选
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { test } from 'node:test';
import { questions } from '../src/app/assessment.ts';
import { languages, t } from '../src/app/i18n.ts';

const app = new URL('../src/app/', import.meta.url);
const sources = (dir: URL, pattern: RegExp) =>
  readdirSync(dir, { recursive: true, encoding: 'utf8' }).filter((f) => pattern.test(f)).map((f) => readFileSync(new URL(f, dir), 'utf8'));
/** 源码里的 '\n' 是换行，译文文件里存的也是换行 */
const unescape = (text: string) => text.replace(/\\(.)/g, (_, c) => (c === 'n' ? '\n' : c));
const pages = ['pages', 'components', 'layouts'].flatMap((dir) => sources(new URL(`../src/${dir}/`, import.meta.url), /\.astro$/));
const keys = new Set([
  ...sources(app, /\.tsx?$/).flatMap((code) => [...code.matchAll(/\bt\(\s*'((?:[^'\\\n]|\\.)*)'/g)].map((m) => unescape(m[1]))),
  // 定级题的题目和选项写在数组里，翻译时才传给 t()，上面扫不到
  ...questions.flatMap((q) => [q.title, q.hint, ...q.options.map((o) => o.text)]),
  // 静态页面（球馆目录）在浏览器里按 data-t 翻译
  ...pages.flatMap((code) => [...code.matchAll(/\bdata-t(?:-placeholder|-label)?="([^"]+)"/g)].map((m) => m[1])),
]);
const placeholders = (text: string) => [...new Set(text.match(/\{\w+\}/g) ?? [])].sort();

for (const [code] of languages.filter(([code]) => code !== 'en')) {
  test(`${code}：每句都有译文，占位符和原文一致`, () => {
    const catalog: Record<string, string> = JSON.parse(readFileSync(new URL(`locales/${code}.json`, app), 'utf8'));
    for (const key of keys) {
      assert.ok(catalog[key]?.trim(), `缺少译文：${key}`);
      assert.deepEqual(placeholders(catalog[key]), placeholders(key), `占位符不一致：${key}`);
      if (!key.includes('|')) assert.ok(!catalog[key].includes('|'), `多了单复数分隔符：${key}`);
    }
  });
}

test('英文按数量选单复数，并填入参数', () => {
  assert.equal(t('{n} game|{n} games', { n: 1 }), '1 game');
  assert.equal(t('{n} game|{n} games', { n: 3 }), '3 games');
  assert.equal(t('Courts near {place}', { place: 'Irvine' }), 'Courts near Irvine');
  assert.equal(t('Not translated yet'), 'Not translated yet');
});
