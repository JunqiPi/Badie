import type { ReactNode } from 'react';
import { t } from './i18n';
import { Avatar, LevelBadge } from './kit';
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

/** 卡片上半部分：有背景照片就铺满；没有就是纯色 + 中间的大头像 */
export function CardCover({ person, avatarSize = 140, className = '', children }: { person: CardPerson; avatarSize?: number; className?: string; children?: ReactNode }) {
  const color = cardColorOf(person.id, person.card_color);
  return (
    <div className={`relative grid place-items-center overflow-hidden ${person.card_photo ? 'bg-surface-muted' : background[color]} ${className}`}>
      {person.card_photo ? (
        <img src={avatarUrl(person.card_photo)} alt="" draggable={false} className="absolute inset-0 size-full object-cover" />
      ) : (
        <Avatar id={person.id} name={person.nickname} photo={person.avatar} size={avatarSize} className="relative shadow-card" />
      )}
      {children}
    </div>
  );
}

/** 发现页的大卡片（iOS 的 CoverCard）：左上角一个白色小标签（多远 · 常去哪家，或时间 · 项目），
 *  下面写名字、编号、等级，一行“双打 · 靠谱”，再下面是 footer（空闲时间）。
 *  有照片：照片铺满整张，字压在底部的深色渐变上；没照片：上面约六成是纯色 + 大头像，下面一块白色信息区 */
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
  const photo = !!person.card_photo;
  const misses = person.recent_no_shows ?? 0;
  const line = [...details, reliable && t('Reliable'), misses > 0 && t('{n} missed game in 180 days|{n} missed games in 180 days', { n: misses })]
    .filter(Boolean).join(' · ');
  // 昵称太长时只截昵称，编号一直看得到
  const name = (
    <>
      <span className="truncate">{person.nickname}</span>
      {person.tag != null && <span className={`shrink-0 ${photo ? 'text-white/70' : 'text-ink-secondary'}`}>{tagText(person.tag)}</span>}
    </>
  );
  return (
    <article aria-label={person.nickname} className="sticker relative flex h-full flex-col overflow-hidden">
      {/* 没照片：颜色占六成，信息区至少四成，字多时颜色让出来 */}
      <CardCover person={person} className={`min-h-0 ${photo ? 'flex-1' : 'flex-[62_1_0%] border-b-[3px] border-stroke'}`} />
      {label && (
        <span className="absolute top-3 left-3 max-w-[calc(100%-1.5rem)] truncate rounded-full border-2 border-stroke bg-surface px-2.5 py-0.5 text-caption font-black text-ink">
          {label}
        </span>
      )}
      <div className={`grid content-start gap-2 px-4 pb-4 sm:px-5 ${photo
        ? 'absolute inset-x-0 bottom-0 bg-linear-to-t from-black/85 via-black/60 to-transparent pt-14 text-white'
        : 'flex-[38_1_0%] bg-surface pt-4 text-ink'}`}>
        <div className="flex min-w-0 items-center gap-2">
          {profile ? <Link to={`/players/${person.id}/`} className="flex min-w-0 text-title3 hover:underline">{name}</Link> : <p className="flex min-w-0 text-title3">{name}</p>}
          <LevelBadge rating={person.rating} named={false} />
        </div>
        {line && <p className={`truncate text-subhead font-bold ${photo ? 'text-white/90' : 'text-ink-secondary'}`}>{line}</p>}
        {footer}
      </div>
      {children}
    </article>
  );
}
