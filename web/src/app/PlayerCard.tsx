import type { ReactNode } from 'react';
import { t } from './i18n';
import { Icon, type IconName } from './icons';
import { Avatar, LevelBadge } from './kit';
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

/** 一张铺满的卡片（iOS 的 DayCardView）：上面是背景照片或颜色，下面是等级、项目、时间、球馆 */
export function DayCard({ person, event, time, venues, footer, children }: {
  person: CardPerson;
  /** 项目（单打、混双……） */
  event: { icon: IconName; text: string };
  time: string;
  venues: string[];
  footer?: ReactNode;
  /** 盖在照片上的东西（左滑右滑的提示） */
  children?: ReactNode;
}) {
  const rows: [IconName, string][] = [[event.icon, event.text], ['clock', time], ...venues.map((v): [IconName, string] => ['pin', v])];
  const photo = Boolean(person.card_photo);
  return (
    <article aria-label={person.nickname} className="sticker flex h-full flex-col overflow-hidden">
      <CardCover person={person} className="min-h-0 flex-1">{children}</CardCover>
      <div className="relative grid gap-3 border-t-2 border-stroke p-4 sm:p-5">
        {/* 有背景照片：头像小一点，压在照片左下角 */}
        {photo && (
          <Avatar id={person.id} name={person.nickname} photo={person.avatar} size={64} className="absolute -top-10 left-4 shadow-low sm:left-5" />
        )}
        <div className={`flex min-w-0 items-center gap-2 ${photo ? 'pt-5' : ''}`}>
          {/* 昵称太长时只截昵称，编号一直看得到 */}
          <p className="flex min-w-0 flex-1 text-title3">
            <span className="truncate">{person.nickname}</span>
            {person.tag != null && <span className="shrink-0 text-ink-tertiary">{tagText(person.tag)}</span>}
          </p>
          <LevelBadge rating={person.rating} named={false} />
        </div>
        <ul className="grid gap-1 text-subhead font-bold">
          {rows.map(([icon, text], i) => (
            <li key={i} className="flex min-w-0 items-center gap-2">
              <Icon name={icon} className="size-4 shrink-0 text-ink-secondary" />
              <span className="truncate">{text}</span>
            </li>
          ))}
          {Boolean(person.recent_no_shows) && (
            <li className="flex min-w-0 items-center gap-2 text-danger">
              <Icon name="warning" className="size-4 shrink-0" />
              <span>{t('{n} missed game in 180 days|{n} missed games in 180 days', { n: person.recent_no_shows! })}</span>
            </li>
          )}
        </ul>
        {footer}
      </div>
    </article>
  );
}
