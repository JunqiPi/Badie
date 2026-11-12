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

/** 卡片上半部分：有背景照片就铺满；没有就是颜色 + Badie 底纹 + 中间的大头像 */
export function CardCover({ person, avatarSize = 140, className = '', children }: { person: CardPerson; avatarSize?: number; className?: string; children?: ReactNode }) {
  const color = cardColorOf(person.id, person.card_color);
  return (
    <div className={`relative grid place-items-center overflow-hidden ${person.card_photo ? 'bg-surface-muted' : background[color]} ${className}`}>
      {person.card_photo ? (
        <img src={avatarUrl(person.card_photo)} alt="" draggable={false} className="absolute inset-0 size-full object-cover" />
      ) : (
        <>
          <span aria-hidden="true" className={`pointer-events-none absolute inset-0 ${color === 'ink' ? 'opacity-[0.14] invert' : 'opacity-10'}`}
                style={{ backgroundImage: 'url(/logo.svg)', backgroundSize: '44px 50px', backgroundRepeat: 'space' }} />
          <Avatar id={person.id} name={person.nickname} photo={person.avatar} size={avatarSize} className="relative shadow-low" />
        </>
      )}
      {children}
    </div>
  );
}

/** 一张铺满的卡片（iOS 的 DayCardView）：背景照片或颜色铺满整张，左上角一个白色小标签（多远 · 常去哪家，或时间 · 项目），
 *  底部压一层深色渐变：名字、编号、等级，一行“双打 · 靠谱”，再下面是 footer（空闲时间） */
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
      {person.tag != null && <span className="shrink-0 text-white/70">{tagText(person.tag)}</span>}
    </>
  );
  return (
    <article aria-label={person.nickname} className="sticker relative flex h-full flex-col overflow-hidden">
      {/* 没有照片时大头像往上挪，不被底部的字挡住 */}
      <CardCover person={person} className="min-h-0 flex-1 pb-28" />
      {label && (
        <span className="absolute top-3 left-3 max-w-[calc(100%-1.5rem)] truncate rounded-full border-2 border-stroke bg-surface px-2.5 py-0.5 text-caption font-black text-ink">
          {label}
        </span>
      )}
      <div className="absolute inset-x-0 bottom-0 grid gap-2 bg-linear-to-t from-black/85 via-black/60 to-transparent px-4 pt-14 pb-4 text-white sm:px-5">
        <div className="flex min-w-0 items-center gap-2">
          {profile ? <Link to={`/players/${person.id}/`} className="flex min-w-0 text-title3 hover:underline">{name}</Link> : <p className="flex min-w-0 text-title3">{name}</p>}
          <LevelBadge rating={person.rating} named={false} />
        </div>
        {line && <p className="truncate text-subhead font-bold text-white/90">{line}</p>}
        {footer}
      </div>
      {children}
    </article>
  );
}
