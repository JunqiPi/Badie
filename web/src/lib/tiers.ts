// 每一档自己的页面（/levels/4-plus/）：1−（0.67）到 6+（6.33）是 18 个自评档；7–9 级各一个说明页（要证据审核，不出卡片）
import { tier, tierSlug } from '../app/assessment';

export type TierPage = { slug: string; label: string; level: number; rating: number; selfAssessed: boolean };

const selfAssessed: TierPage[] = Array.from({ length: 18 }, (_, i) => {
  const rating = Math.round(((i + 2) / 3) * 100) / 100;
  return { slug: tierSlug(rating), label: tier(rating).label, level: tier(rating).level, rating, selfAssessed: true };
});
const verified: TierPage[] = [7, 8, 9].map((level) => ({ slug: String(level), label: String(level), level, rating: level, selfAssessed: false }));

export const tierPages = [...selfAssessed, ...verified];

/** 一级里的几档：1–6 级是 −、基础、+ 三档，7–9 级只有一页 */
export const tierSlugs = (level: number) => tierPages.filter((p) => p.level === level);
