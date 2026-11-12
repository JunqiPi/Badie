// 每一档、每种语言的分享预览图：/og/levels/<语言>/<档>.png（英文是 en），构建时生成 18 × 10 张
import type { APIRoute } from 'astro';
import { tier } from '../../../../app/assessment';
import { pathPrefixes, type Locale } from '../../../../app/i18n';
import { levels } from '../../../../app/levels';
import { levelImage } from '../../../../lib/og';
import { pathIn, translator } from '../../../../lib/static-i18n';
import { tierPages } from '../../../../lib/tiers';

const meanings = ['Just reached this level; some strokes aren’t consistent yet', 'Consistently does everything at this level', 'Solid at this level, with some next-level skills'];

export const getStaticPaths = () =>
  (Object.keys(pathPrefixes) as Locale[]).flatMap((locale) =>
    tierPages.filter((p) => p.selfAssessed).map((page) => ({ params: { lang: pathPrefixes[locale].slice(1) || 'en', tier: page.slug }, props: { locale, page } })),
  );

export const GET: APIRoute = async ({ props }) => {
  const { locale, page } = props as { locale: Locale; page: (typeof tierPages)[number] };
  const t = translator(pathIn(locale, '/levels/'));
  const png = await levelImage(locale, {
    label: page.label,
    name: t(levels[page.level - 1].name),
    meaning: t(meanings[Math.round(page.rating * 3) - page.level * 3 + 1]),
    summary: t(tier(page.rating).summary),
    kicker: t('Badie levels 1–9'),
    cta: t('Find your level · 2 min, no sign-up'),
  });
  return new Response(new Uint8Array(png), { headers: { 'Content-Type': 'image/png' } });
};
