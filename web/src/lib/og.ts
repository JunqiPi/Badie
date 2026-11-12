// 每一档、每种语言的分享预览图（1200×630，og:image）：构建时用 satori 排版、resvg 转成 PNG，不经过浏览器。
// 字体用 npm 上的 @fontsource（Nunito + 各语言的 Noto Sans），只加载这张图用到的字所在的分片
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import satori from 'satori';
import { Resvg } from '@resvg/resvg-js';
import type { Locale } from '../app/i18n';

const require = createRequire(import.meta.url);

/** 各语言补 Nunito 没有的字：中日韩、泰文、天城文 */
const scriptFont: Partial<Record<Locale, string>> = {
  'zh-Hans': 'noto-sans-sc', 'zh-Hant': 'noto-sans-tc', ja: 'noto-sans-jp', ko: 'noto-sans-kr', th: 'noto-sans-thai', hi: 'noto-sans-devanagari',
};

type Slice = { file: string; ranges: [number, number][] };
const slices = new Map<string, Slice[]>();
const buffers = new Map<string, Buffer>();

/** 读 @fontsource 的 CSS：每个分片的 woff 文件和 unicode-range */
function slicesOf(pkg: string, weight: number) {
  const key = `${pkg}/${weight}`;
  if (!slices.has(key)) {
    const css = join(dirname(require.resolve(`@fontsource/${pkg}/package.json`)), `${weight}.css`);
    const list = [...readFileSync(css, 'utf8').matchAll(/@font-face\s*{([^}]*)}/g)].map(([, block]) => {
      const file = join(dirname(css), block.match(/url\(\.\/([^)]+\.woff)\)/)![1]);
      const ranges = (block.match(/unicode-range:\s*([^;]+);/)?.[1] ?? 'U+0-10FFFF').split(',').map((range) => {
        const [from, to = from] = range.trim().replace(/^U\+/i, '').split('-');
        return [parseInt(from, 16), parseInt(to, 16)] as [number, number];
      });
      return { file, ranges };
    });
    slices.set(key, list);
  }
  return slices.get(key)!;
}

/** 这张图要的字体分片。satori 同名同粗细的字体只认一个，所以每个分片用自己的名字，再按顺序全列进 fontFamily */
function fonts(text: string, locale: Locale) {
  const codes = [...new Set([...text].map((c) => c.codePointAt(0)!))];
  const wanted = (slice: Slice) => codes.some((code) => slice.ranges.some(([from, to]) => code >= from && code <= to));
  const packages = ['nunito', ...(scriptFont[locale] ? [scriptFont[locale]!] : [])];
  const files = packages.flatMap((pkg) => slicesOf(pkg, 900).filter(wanted).map((slice) => slice.file.replace(/-900-normal\.woff$/, '')));
  const list = files.flatMap((base, i) =>
    ([900, 700] as const).map((weight) => {
      const file = `${base}-${weight}-normal.woff`;
      if (!buffers.has(file)) buffers.set(file, readFileSync(file));
      return { name: `f${i}`, data: buffers.get(file)!, weight, style: 'normal' as const };
    }),
  );
  return { list, family: files.map((_, i) => `f${i}`).join(', ') };
}

type Node = { type: string; props: Record<string, unknown> };
const h = (type: string, style: Record<string, unknown>, ...children: (Node | string)[]): Node => ({
  type,
  props: { style: { display: 'flex', ...style }, children: children.length === 1 ? children[0] : children },
});

const ink = '#17140f';
const lime = '#d4f33f';

/** 一张预览图：大字等级、名称、这一档的意思和一句说明、“测测你几级” */
export async function levelImage(locale: Locale, text: { label: string; name: string; meaning: string; summary: string; kicker: string; cta: string }) {
  const font = fonts(`${Object.values(text).join('')}badie.rsvp`, locale);
  const element = h(
    'div',
    { width: 1200, height: 630, boxSizing: 'border-box', flexDirection: 'column', justifyContent: 'space-between', padding: 56, background: lime, color: ink, fontFamily: font.family },
    h('div', { justifyContent: 'space-between', alignItems: 'center' },
      h('div', { fontSize: 46, fontWeight: 900 }, 'badie.'),
      h('div', { fontSize: 26, fontWeight: 700 }, text.kicker)),
    h('div', { alignItems: 'center', gap: 56 },
      h('div', { width: 300, height: 300, flexShrink: 0, alignItems: 'center', justifyContent: 'center', borderRadius: 44, background: ink, color: lime,
        fontSize: [...text.label].length > 2 ? 150 : 180, fontWeight: 900, transform: 'rotate(-4deg)', boxShadow: '10px 12px 0 rgba(23,20,15,0.25)' }, text.label),
      h('div', { flexDirection: 'column', gap: 14, flex: 1, minWidth: 0 },
        h('div', { fontSize: 68, fontWeight: 900, lineHeight: 1.08 }, text.name),
        h('div', { fontSize: 30, fontWeight: 700, lineHeight: 1.3 }, text.meaning),
        h('div', { fontSize: 28, fontWeight: 700, lineHeight: 1.3, color: '#3d3a2c', wordBreak: 'break-word' }, text.summary))),
    h('div', { justifyContent: 'space-between', alignItems: 'center', gap: 24 },
      h('div', { background: ink, color: lime, fontSize: 30, fontWeight: 900, padding: '16px 30px', borderRadius: 999 }, text.cta),
      h('div', { fontSize: 28, fontWeight: 900 }, 'badie.rsvp')),
  );
  const svg = await satori(element as never, { width: 1200, height: 630, fonts: font.list });
  return new Resvg(svg).render().asPng();
}
