import type { ReactNode } from 'react';
import { t } from './i18n';
import { LevelBadge } from './kit';
import { Link } from './router';
import { avatarUrl, tagText } from './supabase';

/** 卡片颜色：没传背景照片时，卡片上半部分用这个颜色（和服务器、iOS 同一套名字） */
export const CARD_COLORS = ['lime', 'lavender', 'peach', 'sky', 'pink', 'mint', 'butter', 'ink'] as const;
export type CardColor = (typeof CARD_COLORS)[number];

export const cardColorName = (color: CardColor) =>
  ({
    lime: t('Lime'),
    lavender: t('Lavender'),
    peach: t('Peach'),
    sky: t('Sky blue'),
    pink: t('Pink'),
    mint: t('Mint'),
    butter: t('Butter'),
    ink: t('Ink'),
  })[color];

const background: Record<CardColor, string> = {
  lime: 'bg-lime',
  lavender: 'bg-lavender',
  peach: 'bg-peach',
  sky: 'bg-sky',
  pink: 'bg-pink',
  mint: 'bg-mint',
  butter: 'bg-butter',
  ink: 'bg-[#17140f]',
};

/** 没选过的人：按用户 ID 给一个浅色（不给墨黑）。和 iOS 一样：djb2 & 0x7fffffff，对 7 种浅色取余 */
export function cardColorOf(id: string, chosen?: string | null): CardColor {
  if (chosen && (CARD_COLORS as readonly string[]).includes(chosen)) return chosen as CardColor;
  let hash = 5381;
  for (const byte of new TextEncoder().encode(id)) hash = (Math.imul(hash, 33) + byte) >>> 0;
  return CARD_COLORS[(hash & 0x7fffffff) % 7];
}

/** 卡片上的人：昵称、编号、等级、头像、卡片颜色和背景照片 */
export interface CardPerson {
  id: string;
  nickname: string;
  tag: number | null;
  rating: number;
  avatar: string | null;
  card_color: string | null;
  card_photo: string | null;
  recent_no_shows?: number | null;
}

/** 没有照片时卡片上的球场线（白线，竖着的整片羽毛球场：13.4 × 6.1 米，单位 0.1 米） */
function CourtLines() {
  return (
    <svg viewBox="-2 -2 65 138" aria-hidden="true" className="absolute inset-5 size-[calc(100%-2.5rem)] text-white/85" fill="none" stroke="currentColor" strokeWidth="3">
      <rect x="0" y="0" width="61" height="134" vectorEffect="non-scaling-stroke" />
      <path d="M4.6 0V134M56.4 0V134M0 67H61M0 47.2H61M0 86.8H61M0 7.6H61M0 126.4H61M30.5 0V47.2M30.5 86.8V134" vectorEffect="non-scaling-stroke" />
    </svg>
  );
}

/** 卡片上半部分：有背景照片就铺满；没有就是卡片颜色 + 球场线 */
export function CardCover({ person, className = '', children }: { person: CardPerson; className?: string; children?: ReactNode }) {
  const color = cardColorOf(person.id, person.card_color);
  return (
    <div className={`relative overflow-hidden ${person.card_photo ? 'bg-surface-muted' : background[color]} ${className}`}>
      {person.card_photo
        ? <img src={avatarUrl(person.card_photo)} alt="" draggable={false} className="absolute inset-0 size-full object-cover" />
        : <CourtLines />}
      {children}
    </div>
  );
}

/** 发现页的大卡片（iOS 的 CoverCard）：上面约四分之三是照片（没照片是颜色 + 球场线），左上角一个白色小标签（多远 · 常去哪家，或时间 · 项目）；
 *  下面一小块信息：名字、编号、等级，一行“双打 · 靠谱”，再下面是 footer（空闲时间） */
export function DayCard({ person, label, details = [], reliable = false, profile = false, footer, children }: {
  person: CardPerson;
  /** 照片左上角的小标签 */
  label?: string;
  /** 名字下面那一行（没有的项传空），后面自动接“靠谱”或爽约次数 */
  details?: (string | false | null | undefined)[];
  reliable?: boolean;
  /** 名字链到 TA 的资料页 */
  profile?: boolean;
  footer?: ReactNode;
  /** 盖在照片上的东西（左滑右滑的提示） */
  children?: ReactNode;
}) {
  const misses = person.recent_no_shows ?? 0;
  const line = [...details, reliable && t('Reliable'), misses > 0 && t('{n} missed game in 180 days|{n} missed games in 180 days', { n: misses })]
    .filter(Boolean).join(' · ');
  // 昵称太长时只截昵称，编号一直看得到
  const name = (
    <>
      <span className="truncate">{person.nickname}</span>
      {person.tag != null && <span className="shrink-0 text-ink-secondary">{tagText(person.tag)}</span>}
    </>
  );
  return (
    <article aria-label={person.nickname} className="sticker relative flex h-full flex-col overflow-hidden">
      <CardCover person={person} className="min-h-0 flex-1 border-b-[3px] border-stroke" />
      {label && (
        <span className="absolute top-3 left-3 max-w-[calc(100%-1.5rem)] truncate rounded-full border-2 border-stroke bg-surface px-2.5 py-0.5 text-caption font-black text-ink">
          {label}
        </span>
      )}
      <div className="grid content-start gap-1.5 bg-surface px-4 pt-3 pb-4 text-ink sm:px-5">
        <div className="flex min-w-0 items-center gap-2">
          {profile ? <Link to={`/players/${person.id}/`} className="flex min-w-0 text-title3 hover:underline">{name}</Link> : <p className="flex min-w-0 text-title3">{name}</p>}
          <LevelBadge rating={person.rating} named={false} />
        </div>
        {line && <p className="truncate text-subhead font-bold text-ink-secondary">{line}</p>}
        {footer}
      </div>
      {children}
    </article>
  );
}
