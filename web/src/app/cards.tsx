// 多个页面共用的卡片：球局票据、约球请求、公开球局（对应 iOS 的 GameTicketCard / TicketStatusCard / PublicRoomCard）
import { km } from './Courts';
import { eventLabel, eventOf } from './gender';
import { t } from './i18n';
import { Icon, type IconName } from './icons';
import { AvatarStack, Dashed, IconTile, Tag, type Tint } from './kit';
import { Link } from './router';
import type { Game, RoomSummary, Ticket } from './supabase';
import { dayName, relative, timeOf } from './time';

const modeName = (mode: Game['mode']) => (mode === 'doubles' ? t('Doubles') : t('Singles'));

/** “你和小明、琳琳等 3 人” */
export function playersText(players: { nickname: string; me: boolean }[]) {
  const others = players.filter((p) => !p.me).map((p) => p.nickname);
  if (others.length === 0) return t('Waiting for players to join');
  if (others.length === 1) return t('You and {name}', { name: others[0] });
  const names = others.slice(0, 2).join(t(', '));
  return others.length > 2 ? t('You, {names} and {n} more', { names, n: others.length - 2 }) : t('You and {names}', { names });
}

/** 球局票据：大号时间、日期、虚线、球馆、头像 */
export function GameTicket({ game: g, compact = false }: { game: Game; compact?: boolean }) {
  const now = Date.now();
  const start = new Date(g.starts_at).getTime();
  const end = new Date(g.ends_at).getTime();
  const tz = g.venue.tz;
  const cancelled = g.status === 'cancelled';
  // 票据底色固定是浅色，上面的小标签也用固定颜色（深色模式下不会变成深底深字）
  const [chip, chipClass] = cancelled
    ? [t('Cancelled'), 'border-[1.5px] border-[#17140f] bg-white']
    : now >= start && now < end ? [t('In progress'), 'border-[1.5px] border-[#17140f] bg-lime']
    : now >= end ? [g.result.status === 'verified' ? t('Done') : t('Result to report'), 'border-[1.5px] border-[#17140f] bg-[#ffe36e]']
    : [relative(g.starts_at), 'bg-[#17140f] text-lime'];
  return (
    <Ticket tint={cancelled ? 'muted' : now >= end ? 'mint' : 'peach'} notch={compact ? '52%' : '55%'}>
      <div className={`grid ${compact ? 'gap-2 p-4' : 'gap-3 p-5'}`}>
        <div className="flex items-center justify-between gap-2">
          <p className="kicker">{modeName(g.mode)} · {cancelled ? t('Cancelled') : t('Confirmed')}</p>
          <span className={`shrink-0 rounded-full px-2.5 py-1 text-caption font-black ${chipClass}`}>
            {chip}
          </span>
        </div>
        <p className="flex items-baseline gap-1 font-black tabular-nums">
          <span className={compact ? 'text-[2.125rem] leading-none' : 'text-[2.75rem] leading-none'}>{timeOf(g.starts_at, tz)}</span>
          <span className={compact ? 'text-headline' : 'text-title3'}>–{timeOf(g.ends_at, tz)}</span>
        </p>
        <p className="font-bold">{dayName(g.starts_at, tz)}</p>
        <div className="py-1"><Dashed /></div>
        <div className="min-w-0">
          <p className="truncate text-headline">{g.venue.name}</p>
          <p className="truncate text-footnote opacity-75">{[g.venue.street, g.venue.city].filter(Boolean).join(', ')}</p>
        </div>
        <div className="flex items-center gap-2">
          <AvatarStack people={g.players} size={compact ? 30 : 36} />
          <p className="min-w-0 truncate text-footnote font-bold">{playersText(g.players)}</p>
        </div>
      </div>
    </Ticket>
  );
}

/** 票据外形：左右各一个半圆缺口（样式在 global.css 的 ticket-cut / ticket-face） */
function Ticket({ tint, notch, children }: { tint: Tint; notch: string; children: React.ReactNode }) {
  const tints: Record<string, string> = { peach: 'bg-peach', mint: 'bg-mint', muted: 'bg-surface-muted', lime: 'bg-lime' };
  return (
    <div className="relative isolate text-on-accent" style={{ ['--notch' as string]: notch }}>
      <div aria-hidden="true" className="ticket-cut absolute inset-0 translate-x-[3px] translate-y-1 bg-shadow" />
      <div className={`ticket-cut ticket-face relative ${tints[tint]} ${tint === 'muted' ? 'text-ink' : ''}`}>{children}</div>
    </div>
  );
}

type RequestState = { icon: IconName; tint: Tint; title: string; action: boolean };

function requestState(r: Ticket): RequestState {
  if (r.offer && r.offer.my_response === 'pending') return { icon: 'bolt', tint: 'butter', title: t('Match found · confirm by {time}', { time: relative(r.offer.respond_by) }), action: true };
  if (r.offer) return { icon: 'hourglass', tint: 'mint', title: t('You’re in · waiting for {n} more', { n: r.offer.players.length - r.offer.accepted }), action: false };
  if (r.status === 'paused') return { icon: 'warning', tint: 'peach', title: t('Paused · you missed a confirmation'), action: true };
  if (r.status === 'matched') return { icon: 'checkCircle', tint: 'mint', title: t('Game confirmed'), action: false };
  if (r.status === 'searching') return { icon: 'search', tint: 'sky', title: r.last_minute ? t('Last-minute · looking now') : t('Looking for players'), action: false };
  return { icon: 'clock', tint: 'muted', title: r.status === 'expired' ? t('No match this time') : t('Cancelled'), action: false };
}

/** 约球请求：要你确认的是柠檬绿底 */
export function RequestCard({ request: r }: { request: Ticket }) {
  const state = requestState(r);
  const tz = r.venues[0]?.tz;
  return (
    <Link to="/play/" className={`sticker lift flex items-center gap-3 p-4 ${state.action ? 'bg-lime text-on-accent' : ''}`}>
      <IconTile icon={state.icon} tint={state.action ? 'surface' : state.tint} />
      <span className="min-w-0 flex-1">
        <span className={`kicker block ${state.action ? '' : 'text-ink-secondary'}`}>{t('Game request')} · {eventLabel(r.mode, eventOf(r.play_with, r.mixed)) ?? modeName(r.mode)}</span>
        <span className="block text-headline">{dayName(r.starts_at, tz)} · {timeOf(r.starts_at, tz)}–{timeOf(r.ends_at, tz)}</span>
        <span className={`block text-footnote font-bold ${state.action ? '' : 'text-ink-secondary'}`}>{state.title}</span>
      </span>
      <Icon name="chevronRight" className="size-4" />
    </Link>
  );
}

/** 公开球局：项目（男单、混双……；不限就写单打 / 双打）、水平、缺几个人、时间、球馆、空位 */
export function RoomCard({ room: r, distance, wide = false }: { room: RoomSummary; distance?: number; wide?: boolean }) {
  const open = Math.max(0, r.capacity - r.going);
  const tz = r.venue?.tz;
  return (
    <Link to={`/rooms/${r.id}/`} className={`sticker lift grid content-start gap-2 p-4 ${wide ? 'w-full' : 'w-[17rem]'}`}>
      <span className="flex items-center gap-1.5">
        <Tag icon={r.mode === 'doubles' ? 'users' : 'user'} tint="lavender">{eventLabel(r.mode, eventOf(r.gender, r.mixed)) ?? modeName(r.mode)}</Tag>
        <Tag>{t('Lv.{min}–{max}', { min: r.level_min, max: r.level_max })}</Tag>
        <span className="ml-auto">
          {r.my_status === 'owner' ? <Tag tint="butter">{t('Hosting')}</Tag>
            : r.my_status === 'member' ? <Tag icon="check" tint="lime">{t('Joined')}</Tag>
            : r.my_status === 'waitlisted' ? <Tag tint="butter">{t('Waitlist')}</Tag>
            : open === 0 ? <Tag tint="muted">{t('Full · waitlist')}</Tag>
            : <Tag tint="pink">{t('{n} spot left|{n} spots left', { n: open })}</Tag>}
        </span>
      </span>
      {r.starts_at && r.ends_at ? (
        <>
          <span className="text-footnote font-bold text-ink-secondary">{dayName(r.starts_at, tz)}</span>
          <span className="text-[1.5rem] leading-tight font-black tabular-nums">{timeOf(r.starts_at, tz)}–{timeOf(r.ends_at, tz)}</span>
        </>
      ) : (
        <span className="text-headline">{t('Time not set yet')}</span>
      )}
      <span className="truncate text-caption text-ink-secondary">{t('Hosted by {name}', { name: r.owner.nickname })}</span>
      <span className="flex min-w-0 items-center gap-1 text-footnote text-ink-secondary">
        <Icon name="pin" className="size-3.5" />
        <span className="truncate">{r.venue?.name ?? t('Court not set yet')}</span>
        {distance !== undefined && <span className="shrink-0">· {km(distance)}</span>}
      </span>
      <span className="flex items-center" aria-hidden="true">
        {Array.from({ length: r.capacity }, (_, i) => (
          <span key={i} className={`-mr-2 size-7 rounded-full border-[1.5px] border-stroke ${i < r.going ? 'bg-surface-muted' : 'border-dashed bg-surface'}`} />
        ))}
      </span>
    </Link>
  );
}
