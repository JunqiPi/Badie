import { useEffect, useState } from 'react';
import { t } from './i18n';
import { Icon } from './icons';
import { IconButton, IconTile, Notice, ScreenHeader, Segmented } from './kit';
import { MiniCard, Sheet, sortUsual } from './Nearby';
import { CourtSearch, type Court } from './pickers';
import { navigate } from './router';
import { problem, supabase, useLive, type InviteSuggestion, type InviteUser, type Mode, type NearbyPlayer, type RoomInvite, type RoomSummary } from './supabase';
import { clock, dateChip, dayName, timeOf, today, wallClock, zoned } from './time';
import { Button, Skeleton, toast } from './ui';
import { nextOccurrence, slotLabel, unset, weekdayOf, weekdayShort, windowDetail, windowTitle, type UsualTime } from './usual';

// 附近的人的邀请：右滑 = 约 TA 在某天几点到几点打单打或双打（旧版 App 发的可能只是个大概的时间）。对方可以好、换个时间或不了。
// 双打说好以后变成公开的双打局，附近的人可以加入

const localZone = () => Intl.DateTimeFormat().resolvedOptions().timeZone;

/** 邀请出错时给人看的话 */
export function inviteProblem(error: { message: string }) {
  switch (error.message) {
    case 'not_available': return t('They can’t be added right now.');
    case 'overlapping': return t('You already have a game at that time.');
    case 'too_late': return t('Too late now. Try another time.');
    case 'invalid_slot':
    case 'invalid_window': return t('That start time is too soon now. Pick another.');
    case 'invalid_venues': return t('That court can’t be used right now. Pick another.');
    default: return problem(error);
  }
}

type Sent = { remaining: number | null; label: string };

/** 约 TA 的半屏：项目、哪天、几点到几点、球馆。room 有值时是“换个时间” */
export function InviteSheet({ open, onClose, ...props }: ComposeProps & { open: boolean }) {
  return (
    <Sheet open={open} onClose={onClose} labelledBy="compose-title">
      <Compose onClose={onClose} {...props} />
    </Sheet>
  );
}

type ComposeProps = {
  other: InviteUser;
  /** TA 常去的、在我附近的球馆（默认约在两人都常去的那家） */
  venues?: NearbyPlayer['venues'];
  /** 点了卡片上 TA 的某段空闲时间 */
  slot?: UsualTime;
  /** 从某一天的卡片里约 */
  date?: string;
  /** 换个时间：这个邀请 */
  room?: RoomSummary;
  onClose: () => void;
  onSent: (sent: Sent) => void;
  onError?: (error: { message: string }) => void;
};

/** 约的是什么：项目、球馆当地的日期和开始、结束（从 0 点起的分钟，结束可以是 24:00） */
type Plan = { mode: Mode; date: string; from: number; to: number };

/** 最早能开始的时刻：现在 + 30 分钟，按半小时对齐（和服务器一样） */
const earliest = () => Math.ceil((Date.now() + 30 * 60000) / 1800000) * 1800000;

/** 从 from 开始打 2 小时；开始已经来不及的挪到最早能开始的半点 */
function twoHours(date: string, from: number, tz: string) {
  const soonest = wallClock(new Date(earliest()).toISOString(), tz);
  const start = soonest.date === date ? Math.max(from, soonest.minutes) : from;
  return { date, from: start, to: Math.min(1440, start + 120) };
}

function Compose({ other, venues, slot, date, room, onClose, onSent, onError }: ComposeProps) {
  const [court, setCourt] = useState<Court>();
  const [mine, setMine] = useState<Court[]>([]);
  const [plan, setPlan] = useState<Plan>();
  const [picking, setPicking] = useState(false);
  const [moreDates, setMoreDates] = useState(false);
  const [busy, setBusy] = useState(false);
  const tz = court?.time_zone_id ?? localZone();
  const usual = sortUsual(other.usual_times);

  // 默认：点的那段空闲时间，没点就是两人都有空的第一段，再没有就是 TA 的第一段空闲时间，都没有是晚上 7 点到 9 点
  useEffect(() => {
    void (async () => {
      const { data: favorites } = await supabase!.from('favorite_venues').select('venues(id, name, city, time_zone_id)');
      const list = (favorites ?? []).flatMap((f) => (f.venues ? [f.venues as unknown as Court] : []));
      setMine(list);
      if (room) {
        const v = room.venue;
        const c = v ? { id: v.id, name: v.name, city: v.city, time_zone_id: v.tz } : list[0];
        setCourt(c);
        const zone = c?.time_zone_id ?? localZone();
        const start = room.window_start ?? room.starts_at;
        const length = room.time_set && room.starts_at && room.ends_at ? (Date.parse(room.ends_at) - Date.parse(room.starts_at)) / 60000 : 120;
        const at = start ? wallClock(start, zone) : { date: today(zone, 1), minutes: 19 * 60 };
        return setPlan({ mode: room.mode, date: at.date, from: at.minutes, to: Math.min(1440, at.minutes + length) });
      }
      const { data } = await supabase!.rpc('suggest_invite_window', { p_user: other.id });
      const suggestion = data as InviteSuggestion | null;
      const theirs = venues ?? [];
      const shared = theirs.find((v) => list.some((m) => m.id === v.id));
      const id = suggestion?.venue_id ?? shared?.id ?? list[0]?.id ?? theirs[0]?.id;
      const c = list.find((m) => m.id === id) ?? (id ? await venue(id) : undefined);
      setCourt(c);
      const zone = c?.time_zone_id ?? localZone();
      const mode = other.preferred_mode ?? 'singles';
      const free = (slot && nextOccurrence(slot, zone))
        ?? (suggestion && (({ date, minutes }) => ({ date, from: minutes }))(wallClock(suggestion.window_start, zone)))
        ?? (usual[0] && nextOccurrence(usual[0], zone));
      if (free) return setPlan({ mode, ...twoHours(free.date, free.from, zone) });
      const evening = twoHours(date ?? today(zone, 0), 19 * 60, zone);
      setPlan({ mode, ...(evening.to - evening.from === 120 ? evening : twoHours(today(zone, 1), 19 * 60, zone)) });
    })();
  }, []);

  async function venue(id: string) {
    const { data } = await supabase!.from('venues').select('id, name, city, time_zone_id').eq('id', id).maybeSingle();
    return (data ?? undefined) as Court | undefined;
  }

  async function pickCourt(id: string, fallback?: Court) {
    setPicking(false);
    setCourt(mine.find((m) => m.id === id) ?? fallback ?? (await venue(id)));
  }

  const title = room ? t('Another time') : t('Invite {name}', { name: other.nickname });
  const header = (
    <div className="flex items-center gap-3">
      <h2 id="compose-title" className="flex-1 text-title2">{title}</h2>
      <IconButton icon="x" label={t('Close')} onClick={onClose} />
    </div>
  );
  if (!plan) return <>{header}<Skeleton className="h-72" /></>;

  const days = Array.from({ length: 14 }, (_, i) => today(tz, i));
  const set = (patch: Partial<Plan>) => setPlan({ ...plan, ...patch });
  // 改开始时间：打多久不变，最晚到 24:00
  const setFrom = (from: number) => set({ from, to: Math.min(1440, from + plan.to - plan.from) });
  const ok = zoned(plan.date, plan.from, tz).getTime() >= earliest() && plan.to - plan.from >= 60;
  const freeThen = usual.find((u) => u.weekday === weekdayOf(plan.date));
  const shared = court && venues?.some((v) => v.id === court.id) && mine.some((m) => m.id === court.id);
  const options = [...mine, ...(venues ?? []).filter((v) => !mine.some((m) => m.id === v.id)).map((v) => ({ id: v.id, name: v.name, city: '', time_zone_id: null }))]
    .filter((c) => c.id !== court?.id);
  const label = 'text-footnote font-bold text-ink-secondary';

  async function send() {
    if (!court || !ok || !plan || busy) return;
    setBusy(true);
    // 定好的时间：窗口就是开始到结束，打满整段
    const args = {
      p_venue: court.id,
      p_window_start: zoned(plan.date, plan.from, tz).toISOString(),
      p_window_end: zoned(plan.date, plan.to, tz).toISOString(),
      p_daypart: null,
      p_duration: plan.to - plan.from,
      p_mode: plan.mode,
    };
    const { data, error } = room
      ? await supabase!.rpc('counter_invite', { p_room: room.id, ...args })
      : await supabase!.rpc('invite_player', { p_user: other.id, ...args });
    setBusy(false);
    if (error) {
      if (onError) onError(error);
      else toast(inviteProblem(error), 'error');
      return;
    }
    onSent({
      remaining: (data as { remaining?: number } | null)?.remaining ?? null,
      label: `${weekdayShort(weekdayOf(plan.date))} ${clock(plan.from)}–${clock(plan.to)}`,
    });
  }

  return (
    <>
      {header}
      <div className="grid gap-2">
        <span className={label}>{t('Event')}</span>
        <Segmented label={t('Event')} value={plan.mode} onChange={(mode) => set({ mode })}
                   options={[{ value: 'singles', label: t('Singles') }, { value: 'doubles', label: t('Doubles') }]} />
      </div>

      <div className="grid gap-2" role="group" aria-labelledby="compose-day">
        <span id="compose-day" className={label}>{t('Date')}</span>
        <div className="-mx-5 flex gap-2 overflow-x-auto px-5 pb-1 [scrollbar-width:none]">
          {[...days, ...(days.includes(plan.date) ? [] : [plan.date])].map((d) => {
            const chip = dateChip(d, days.indexOf(d));
            return (
              <button key={d} type="button" aria-pressed={plan.date === d} aria-label={chip.full} onClick={() => set({ date: d })}
                      className="press grid min-w-12 shrink-0 justify-items-center rounded-[14px] border-2 border-stroke bg-surface px-2 py-1 aria-pressed:bg-lime aria-pressed:text-on-accent">
                <span className="text-caption font-bold whitespace-nowrap">{days.includes(d) ? chip.label : weekdayShort(weekdayOf(d))}</span>
                <span className="text-headline tabular-nums">{chip.day}</span>
              </button>
            );
          })}
          <button type="button" aria-expanded={moreDates} aria-label={t('More dates')} onClick={() => setMoreDates(!moreDates)}
                  className="press grid min-w-12 shrink-0 place-items-center rounded-[14px] border-2 border-stroke bg-surface px-2">
            <Icon name="dots" className="size-5" />
          </button>
        </div>
        {moreDates && (
          <input type="date" className="field" aria-label={t('More dates')} min={today(tz, 0)} max={today(tz, 30)} value={plan.date}
                 onChange={(e) => e.target.value && set({ date: e.target.value })} />
        )}
      </div>

      <div className="grid gap-2" role="group" aria-labelledby="compose-time">
        <p id="compose-time" className={label}>
          {t('Time')}
          {freeThen && <span className="font-normal"> · {t('{name} is free {time}', { name: other.nickname, time: slotLabel(freeThen) })}</span>}
        </p>
        <div className="grid grid-cols-2 gap-3">
          <Stepper label={t('Start')} value={plan.from} min={360} max={1380} onChange={setFrom} />
          <Stepper label={t('End')} value={plan.to} min={plan.from + 60} max={Math.min(1440, plan.from + 240)} onChange={(to) => set({ to })} />
        </div>
        {!ok && <p className="text-footnote font-bold text-danger" aria-live="polite">{t('Too late for that. Pick a later time.')}</p>}
      </div>

      <div className="grid gap-2">
        <span className={label}>{t('Court')}</span>
        {court && !picking ? (
          <button type="button" onClick={() => setPicking(true)} aria-label={t('Change court: {name}', { name: court.name })}
                  className="sticker press flex items-center gap-3 p-3 text-left">
            <IconTile icon="pin" tint="sky" size="sm" />
            <span className="min-w-0 flex-1">
              <span className="block truncate font-bold">{court.name}</span>
              {(shared || court.city) && <span className="block truncate text-footnote text-ink-secondary">{shared ? t('You both often play here') : court.city}</span>}
            </span>
            <Icon name="chevronRight" className="size-4 text-ink-tertiary" />
          </button>
        ) : (
          <div className="grid gap-2">
            {options.map((c) => (
              <button key={c.id} type="button" onClick={() => void pickCourt(c.id, c.time_zone_id ? c : undefined)}
                      className="press flex min-h-12 items-center gap-2 rounded-[14px] border-2 border-stroke bg-surface px-3 text-left text-subhead font-bold">
                <Icon name="pin" className="size-4 shrink-0" />
                <span className="min-w-0 flex-1 truncate">{c.name}</span>
              </button>
            ))}
            <CourtSearch onPick={(c) => void pickCourt(c.id, c)} label={t('Choose venue')} />
          </div>
        )}
      </div>

      <Button className="button-lg w-full" busy={busy} disabled={!court || !ok} onClick={send}>{room ? t('Send') : t('Send invite')}</Button>
    </>
  );
}

/** 开始、结束时间：减、加半小时 */
function Stepper({ label, value, min, max, onChange }: { label: string; value: number; min: number; max: number; onChange: (value: number) => void }) {
  const step = 'press grid size-11 shrink-0 place-items-center rounded-[12px] disabled:opacity-35';
  return (
    <div role="group" aria-label={label} className="sticker flex items-center gap-1 p-1">
      <button type="button" className={step} aria-label={`${label}: ${t('Earlier')}`} disabled={value - 30 < min} onClick={() => onChange(value - 30)}>
        <Icon name="minus" className="size-4" />
      </button>
      <span className="grid min-w-0 flex-1 justify-items-center">
        <span className="text-caption font-bold text-ink-secondary">{label}</span>
        <span className="text-headline tabular-nums" aria-live="polite">{clock(value)}</span>
      </span>
      <button type="button" className={step} aria-label={`${label}: ${t('Later')}`} disabled={value + 30 > max} onClick={() => onChange(value + 30)}>
        <Icon name="plus" className="size-4" />
      </button>
    </div>
  );
}

/** 小卡片下面的时间：“周六 · 19:00–21:00”和“单打 · 球馆”（旧版 App 发的大概时间：“周六 11/15 · 下午”和“14:00–18:00 之间 · 2 小时 · 单打 · 球馆”） */
export function InviteSlot({ room }: { room: RoomSummary }) {
  const tz = room.venue?.tz;
  const open = unset(room);
  const title = open ? windowTitle(room, tz)
    : room.starts_at && room.ends_at ? `${dayName(room.starts_at, tz)} · ${timeOf(room.starts_at, tz)}–${timeOf(room.ends_at, tz)}` : t('Time not set yet');
  const detail = [open ? windowDetail(room, tz) : null, open ? t('2 hours') : null, room.mode === 'doubles' ? t('Doubles') : t('Singles'), room.venue?.name]
    .filter(Boolean).join(' · ');
  return (
    <div className="sticker grid gap-0.5 p-4">
      <p className="text-headline">{title}</p>
      {detail && <p className="text-footnote font-bold text-ink-secondary">{detail}</p>}
    </div>
  );
}

type Invite = RoomSummary & { invite: RoomInvite };
export const isInvite = (r: RoomSummary): r is Invite => Boolean(r.invite);
const otherOf = (r: Invite) => (r.my_status === 'owner' ? r.invite.to : r.invite.from);

/** 一个邀请：标题、TA 的小卡片、时间，轮到我时 不了 / 换个时间 / 好 */
export function InviteAnswer({ room, onDone, onCounter, heading = 'h2' }: { room: Invite; onDone: () => void; onCounter: (room: Invite) => void; heading?: 'h1' | 'h2' }) {
  const [busy, setBusy] = useState<'yes' | 'no'>();
  const inv = room.invite;
  const other = otherOf(room);
  const Heading = heading;
  const title = !inv.awaiting_me ? t('Waiting for {name}', { name: other.nickname })
    : room.my_status !== 'owner' && inv.rounds === 0
      ? (room.mode === 'doubles' ? t('{name} invited you to play doubles', { name: other.nickname }) : t('{name} invited you to play', { name: other.nickname }))
    : t('{name} suggested another time', { name: other.nickname });

  async function respond(accept: boolean) {
    setBusy(accept ? 'yes' : 'no');
    const { data, error } = await supabase!.rpc('respond_invite', { p_room: room.id, p_accept: accept });
    setBusy(undefined);
    if (error) {
      toast(inviteProblem(error), 'error');
      return onDone();
    }
    onDone();
    const game = (data as { game_id?: string | null } | null)?.game_id;
    if (accept && game) {
      toast(t('Game confirmed'));
      navigate(`/games/${game}/`);
    } else if (accept) {
      // 双打：成了一个公开的双打局，等另外两个人
      toast(t('Doubles game open. 2 more players can join.'));
      navigate(`/rooms/${room.id}/`);
    }
  }

  return (
    <section aria-labelledby={`invite-${room.id}`} className="grid gap-3">
      <Heading id={`invite-${room.id}`} className="text-title3">{title}</Heading>
      <MiniCard user={other} />
      <InviteSlot room={room} />
      {inv.awaiting_me && (
        <div className="grid grid-cols-3 gap-3">
          <Button variant="quiet" busy={busy === 'no'} disabled={Boolean(busy)} onClick={() => respond(false)}>{t('No thanks')}</Button>
          <Button variant="quiet" disabled={Boolean(busy)} onClick={() => onCounter(room)}>{t('Another time')}</Button>
          <Button busy={busy === 'yes'} disabled={Boolean(busy)} onClick={() => respond(true)}>{t('Sure')}</Button>
        </div>
      )}
    </section>
  );
}

/** 换个时间的半屏 */
function CounterSheet({ room, onClose, onSent }: { room?: Invite; onClose: () => void; onSent: () => void }) {
  const other = room && otherOf(room);
  return (
    <InviteSheet open={Boolean(room)} onClose={onClose} other={other ?? ({} as InviteUser)} room={room}
                 onSent={() => { toast(t('Sent. Waiting for {name}.', { name: other?.nickname ?? '' })); onClose(); onSent(); }}
                 onError={(error) => { toast(inviteProblem(error), 'error'); onClose(); onSent(); }} />
  );
}

/** 等我回的邀请（nearby_invites 里 awaiting_me 的） */
function useInvites() {
  const { data, refresh } = useLive<RoomSummary[]>('nearby_invites', { every: 60_000 });
  return { waiting: (data ?? []).filter(isInvite).filter((r) => r.invite.awaiting_me), refresh };
}

/** 通知页最上面：还没回的邀请 */
export function InviteInbox() {
  const { waiting, refresh } = useInvites();
  const [counter, setCounter] = useState<Invite>();
  return (
    <>
      {waiting.length > 0 && (
        <div className="sticker grid gap-6 bg-butter/40 p-4">
          {waiting.map((r) => <InviteAnswer key={r.id} room={r} onDone={() => void refresh()} onCounter={setCounter} />)}
        </div>
      )}
      <CounterSheet room={counter} onClose={() => setCounter(undefined)} onSent={() => void refresh()} />
    </>
  );
}

/** 邀请局的房间页（通知里点进来）：回复、等对方回、撤回，或者看结果 */
export function InviteRoom({ room, onChange }: { room: Invite; onChange: () => void }) {
  const [counter, setCounter] = useState<Invite>();
  const [busy, setBusy] = useState(false);
  const other = otherOf(room);
  const owner = room.my_status === 'owner';

  async function leave() {
    setBusy(true);
    const { error } = await supabase!.rpc('leave_room', { p_room: room.id });
    setBusy(false);
    if (error) toast(inviteProblem(error), 'error');
    else if (owner) toast(t('Invite withdrawn'));
    onChange();
  }

  const closed = {
    declined: room.invite.declined_by && room.invite.declined_by !== other.id ? t('You can’t make it this time')
      : t('{name} can’t make it this time', { name: other.nickname }),
    expired: t('No answer in time, so the invite closed.'),
    owner_closed: t('Invite withdrawn'),
    start_time_passed: t('No answer in time, so the invite closed.'),
  };

  return (
    <div className="mx-auto grid max-w-lg gap-6">
      <ScreenHeader title={t('Invites')} back="/" />
      {room.status === 'started' && (
        <Notice icon="checkCircle" tint="mint" action={room.game_id ? { label: t('View game'), to: `/games/${room.game_id}/` } : undefined}>
          {t('Game confirmed. Everyone’s in.')}
        </Notice>
      )}
      {room.status === 'closed' && <Notice icon="xCircle" tint="muted">{closed[room.closed_reason ?? 'expired']}</Notice>}
      {room.status === 'open' ? (
        <>
          <InviteAnswer room={room} heading="h1" onDone={onChange} onCounter={setCounter} />
          {!room.invite.awaiting_me && (
            <Button variant="quiet" busy={busy} onClick={leave}>{owner ? t('Withdraw') : t('No thanks')}</Button>
          )}
        </>
      ) : (
        <>
          <MiniCard user={other} />
          <InviteSlot room={room} />
        </>
      )}
      <CounterSheet room={counter} onClose={() => setCounter(undefined)} onSent={onChange} />
    </div>
  );
}
