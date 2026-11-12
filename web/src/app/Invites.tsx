import { useEffect, useState } from 'react';
import { t } from './i18n';
import { Icon } from './icons';
import { CountPill, IconButton, IconTile, Notice, ScreenHeader } from './kit';
import { MiniCard, Sheet, sortUsual } from './Nearby';
import { CourtSearch, type Court } from './pickers';
import { navigate } from './router';
import { problem, supabase, useLive, type InviteSuggestion, type InviteUser, type NearbyPlayer, type RoomInvite, type RoomSummary } from './supabase';
import { clock, dateChip, day, dayName, timeOf, today } from './time';
import { Button, Skeleton, toast } from './ui';
import {
  choiceCaption, choiceLabel, choiceOf, datesOf, fits, nextOccurrence, slotLabel, unset, windowDetail, windowOf, windowTitle,
  type DayChoice, type TimeChoice, type UsualTime,
} from './usual';

// 附近的人的邀请：右滑 = 约 TA 一个只有两个人的球局，时间可以先定个大概。对方可以好、换个时间或不了

const localZone = () => Intl.DateTimeFormat().resolvedOptions().timeZone;

/** 邀请出错时给人看的话 */
export function inviteProblem(error: { message: string }) {
  switch (error.message) {
    case 'not_available': return t('They can’t be added right now.');
    case 'overlapping': return t('You already have a game at that time.');
    case 'too_late': return t('Too late now. Try another time.');
    case 'invalid_slot': return t('That start time is too soon now. Pick another.');
    case 'invalid_venues': return t('That court can’t be used right now. Pick another.');
    default: return problem(error);
  }
}

type Sent = { remaining: number | null; label: string };

/** 约 TA 的半屏：哪天、什么时候、球馆。room 有值时是“换个时间” */
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

function Compose({ other, venues, slot, date, room, onClose, onSent, onError }: ComposeProps) {
  const [court, setCourt] = useState<Court>();
  const [mine, setMine] = useState<Court[]>([]);
  const [choice, setChoice] = useState<{ day: DayChoice; time: TimeChoice }>();
  const [picking, setPicking] = useState(false);
  const [moreDates, setMoreDates] = useState(false);
  const [busy, setBusy] = useState(false);
  const tz = court?.time_zone_id ?? localZone();
  const usual = sortUsual(other.usual_times);

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
        if (unset(room)) return setChoice(choiceOf(room, zone));
        if (room.starts_at && room.ends_at) return setChoice(choiceOf({ window_start: room.starts_at, window_end: room.ends_at }, zone));
        return setChoice({ day: { kind: 'weekend' }, time: { kind: 'any' } });
      }
      const { data } = await supabase!.rpc('suggest_invite_window', { p_user: other.id });
      const suggestion = data as InviteSuggestion | null;
      const theirs = venues ?? [];
      const shared = theirs.find((v) => list.some((m) => m.id === v.id));
      const id = suggestion?.venue_id ?? shared?.id ?? list[0]?.id ?? theirs[0]?.id;
      const c = list.find((m) => m.id === id) ?? (id ? await venue(id) : undefined);
      setCourt(c);
      const zone = c?.time_zone_id ?? localZone();
      const next = slot && nextOccurrence(slot, zone);
      if (next) {
        const index = usual.findIndex((u) => u.weekday === slot!.weekday && u.start === slot!.start && u.end === slot!.end);
        return setChoice({ day: { kind: 'date', date: next.date }, time: { kind: 'custom', from: next.from, to: next.to, usual: index } });
      }
      if (suggestion) return setChoice(choiceOf(suggestion, zone));
      if (date) return setChoice({ day: { kind: 'date', date }, time: { kind: 'any' } });
      setChoice({ day: { kind: 'weekend' }, time: { kind: 'any' } });
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
  if (!choice) return <>{header}<Skeleton className="h-72" /></>;

  const { day: dayChoice, time } = choice;
  const days = Array.from({ length: 7 }, (_, i) => today(tz, i));
  const multi = datesOf(dayChoice, tz).length > 1;
  const pickDay = (next: DayChoice) =>
    setChoice({ day: next, time: time.kind === 'custom' ? (next.kind === 'date' ? { kind: 'custom', from: time.from, to: time.to } : { kind: 'any' }) : time });
  const pickTime = (next: TimeChoice) =>
    setChoice({ day: next.kind === 'custom' && multi ? { kind: 'date', date: datesOf(dayChoice, tz)[0] } : dayChoice, time: next });
  const pickUsual = (u: UsualTime, index: number) => {
    const next = nextOccurrence(u, tz);
    if (next) setChoice({ day: { kind: 'date', date: next.date }, time: { kind: 'custom', from: next.from, to: next.to, usual: index } });
  };
  const ok = fits(dayChoice, time, tz);
  const shared = court && venues?.some((v) => v.id === court.id) && mine.some((m) => m.id === court.id);
  const isDate = (d: string) => dayChoice.kind === 'date' && dayChoice.date === d;
  const options = [...mine, ...(venues ?? []).filter((v) => !mine.some((m) => m.id === v.id)).map((v) => ({ id: v.id, name: v.name, city: '', time_zone_id: null }))]
    .filter((c) => c.id !== court?.id);
  const halfHours = (from: number, to: number) => Array.from({ length: (to - from) / 30 + 1 }, (_, i) => from + i * 30);

  async function send() {
    if (!court || !ok) return;
    setBusy(true);
    const w = windowOf(dayChoice, time, tz);
    const args = {
      p_venue: court.id,
      p_window_start: w.start.toISOString(),
      p_window_end: w.end.toISOString(),
      p_daypart: w.daypart ?? (time.kind === 'any' ? 'any' : null),
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
    onSent({ remaining: (data as { remaining?: number } | null)?.remaining ?? null, label: choiceLabel(dayChoice, time) });
  }

  return (
    <>
      {header}
      <div className="grid gap-2" role="group" aria-labelledby="compose-day">
        <span id="compose-day" className="text-footnote font-bold text-ink-secondary">{t('Which day')}</span>
        <div className="flex flex-wrap gap-2">
          <button type="button" className="toggle" aria-pressed={dayChoice.kind === 'weekend'} onClick={() => pickDay({ kind: 'weekend' })}>{t('This weekend')}</button>
          <button type="button" className="toggle" aria-pressed={dayChoice.kind === 'weekdays'} onClick={() => pickDay({ kind: 'weekdays' })}>{t('Weekdays next week')}</button>
          {days.map((d, i) => (
            <button key={d} type="button" className="toggle" aria-pressed={isDate(d)} aria-label={dateChip(d, i).full} onClick={() => pickDay({ kind: 'date', date: d })}>
              {dateChip(d, i).label}
            </button>
          ))}
          {dayChoice.kind === 'date' && !days.includes(dayChoice.date) && (
            <button type="button" className="toggle" aria-pressed="true">{day(`${dayChoice.date}T12:00:00Z`, 'UTC')}</button>
          )}
          <button type="button" className="toggle" aria-expanded={moreDates} aria-label={t('More dates')} onClick={() => setMoreDates(!moreDates)}>
            <Icon name="dots" className="size-4" />
          </button>
        </div>
        {moreDates && (
          <input type="date" className="field" aria-label={t('More dates')} min={today(tz, 0)} max={today(tz, 30)}
                 value={dayChoice.kind === 'date' ? dayChoice.date : ''}
                 onChange={(e) => e.target.value && pickDay({ kind: 'date', date: e.target.value })} />
        )}
      </div>

      <div className="grid gap-2" role="group" aria-labelledby="compose-time">
        <span id="compose-time" className="text-footnote font-bold text-ink-secondary">{t('What time')}</span>
        <div className="flex flex-wrap gap-2">
          {usual.map((u, i) => (
            <button key={`${u.weekday}-${u.start}`} type="button" className="toggle" aria-pressed={time.kind === 'custom' && time.usual === i} onClick={() => pickUsual(u, i)}>
              {slotLabel(u)}
            </button>
          ))}
          {(['morning', 'afternoon', 'evening'] as const).map((part) => (
            <button key={part} type="button" className="toggle" aria-pressed={time.kind === 'part' && time.part === part} onClick={() => pickTime({ kind: 'part', part })}>
              {{ morning: t('Morning'), afternoon: t('Afternoon'), evening: t('Evening') }[part]}
            </button>
          ))}
          <button type="button" className="toggle" aria-pressed={time.kind === 'any'} onClick={() => pickTime({ kind: 'any' })}>{t('Whenever')}</button>
          <button type="button" className="toggle" aria-pressed={time.kind === 'custom' && time.usual === undefined}
                  onClick={() => pickTime(time.kind === 'custom' ? { kind: 'custom', from: time.from, to: time.to } : { kind: 'custom', from: 19 * 60, to: 21 * 60 })}>
            {t('Set my own')}
          </button>
        </div>
        {time.kind === 'custom' && time.usual === undefined && (
          <div className="flex flex-wrap items-center gap-2 text-subhead font-bold">
            <label className="flex items-center gap-2">{t('From')}
              <select className="field w-auto" value={time.from}
                      onChange={(e) => { const from = Number(e.target.value); pickTime({ kind: 'custom', from, to: Math.max(time.to, from + 120) }); }}>
                {halfHours(360, 1320).map((m) => <option key={m} value={m}>{clock(m)}</option>)}
              </select>
            </label>
            <label className="flex items-center gap-2">{t('To')}
              <select className="field w-auto" value={time.to} onChange={(e) => pickTime({ kind: 'custom', from: time.from, to: Number(e.target.value) })}>
                {halfHours(time.from + 120, 1440).map((m) => <option key={m} value={m}>{clock(m)}</option>)}
              </select>
            </label>
          </div>
        )}
        <p className={`text-footnote font-bold ${ok ? 'text-ink-secondary' : 'text-danger'}`} aria-live="polite">
          {ok ? choiceCaption(dayChoice, time, tz) : t('Too late for that. Pick a later time.')}
        </p>
      </div>

      <div className="grid gap-2">
        <span className="text-footnote font-bold text-ink-secondary">{t('Court')}</span>
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

/** 小卡片下面的时间：“周六 11/15 · 下午”和“14:00–18:00 之间 · 2 小时 · 球馆” */
export function InviteSlot({ room }: { room: RoomSummary }) {
  const tz = room.venue?.tz;
  const open = unset(room);
  const title = open ? windowTitle(room, tz)
    : room.starts_at && room.ends_at ? `${dayName(room.starts_at, tz)} · ${timeOf(room.starts_at, tz)}–${timeOf(room.ends_at, tz)}` : t('Time not set yet');
  const detail = [open ? windowDetail(room, tz) : null, open ? t('2 hours') : null, room.venue?.name].filter(Boolean).join(' · ');
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
    : room.my_status !== 'owner' && inv.rounds === 0 ? t('{name} invited you to play', { name: other.nickname })
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

/** 发现页的待办里：有人约我时一个小标签“邀请 N”，点开回复 */
export function InvitePill() {
  const { waiting, refresh } = useInvites();
  const [open, setOpen] = useState(false);
  const [counter, setCounter] = useState<Invite>();
  const count = waiting.length;
  return (
    <>
      {count > 0 && <CountPill icon="mail" title={t('Invites')} count={count} onClick={() => setOpen(true)} />}
      <Sheet open={open && count > 0} onClose={() => setOpen(false)} labelledBy="invites-title">
        <div className="flex items-center gap-3">
          <p id="invites-title" className="kicker flex-1 text-ink-secondary">{t('Invites')}</p>
          <IconButton icon="x" label={t('Close')} onClick={() => setOpen(false)} />
        </div>
        {waiting.map((r) => (
          <InviteAnswer key={r.id} room={r} onDone={() => void refresh()} onCounter={(room) => { setOpen(false); setCounter(room); }} />
        ))}
      </Sheet>
      <CounterSheet room={counter} onClose={() => setCounter(undefined)} onSent={() => void refresh()} />
    </>
  );
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
