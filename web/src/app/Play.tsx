import { useEffect, useState, type ReactNode, type SubmitEvent } from 'react';
import { t } from './i18n';
import { Icon, type IconName } from './icons';
import { Avatar, Empty, IconTile, LevelBadge, Notice, Starburst, StatTile, Tag, type Tint } from './kit';
import { CourtSearch, type Court } from './pickers';
import { enablePush, pushState, type PushState } from './push';
import { Link } from './router';
import { problem, supabase, useLive, type Mode, type Player, type Profile, type Ticket } from './supabase';
import { clock, dateChip, dayName, moment, nextDays, relative, timeOf, zoned } from './time';
import { Button, PageHeader, Skeleton, toast } from './ui';

/** 快速匹配（iOS 的 MatchSetupView + 请求状态）：桌面左边设置、右边我的请求 */
export function Play({ profile }: { profile: Profile }) {
  const { data: tickets, failed, refresh } = useLive<Ticket[]>('my_matchmaking');
  const open = tickets?.filter((ticket) => ['searching', 'offered', 'paused'].includes(ticket.status)) ?? [];
  const recent = tickets?.filter((ticket) => !open.includes(ticket)).slice(0, 5) ?? [];

  return (
    <div>
      <PageHeader back="/" title={t('Quick Match')}>
        {t('Tell us when you’re free and where you can play. We’ll match you with players at your level and email you when there’s a match.')}
      </PageHeader>

      {!profile.assessed_at && (
        <div className="mb-6">
          <Notice icon="sparkle" tint="lavender" action={{ label: t('Take the quiz'), to: '/level-quiz/' }}>
            {t('You’re starting at level 3. Take the 2-minute level quiz so you’re matched with the right players.')}
          </Notice>
        </div>
      )}

      <div className="grid gap-8 lg:grid-cols-[minmax(0,1fr)_26rem] lg:items-start">
        <section aria-labelledby="requests" className="grid gap-3 lg:order-2 lg:sticky lg:top-24">
          <h2 id="requests" className="text-title3">{t('Your requests')}</h2>
          {tickets === undefined && !failed && [0, 1].map((i) => <Skeleton key={i} className="h-36" />)}
          {failed && tickets === undefined && <Empty icon="warning" tint="peach" title={t('Couldn’t load your requests')}>{t('Check your connection and try again.')}</Empty>}
          {tickets && open.length === 0 && (
            <Empty icon="bolt" tint="lime" title={t('No open requests')}>{t('Create one and we’ll look for players while you get on with your day.')}</Empty>
          )}
          {open.length > 0 && <PushPrompt />}
          {open.map((ticket) => <TicketCard key={ticket.id} ticket={ticket} onChange={refresh} />)}
          {recent.length > 0 && (
            <>
              <h3 className="mt-3 text-footnote font-bold text-ink-secondary">{t('Recent')}</h3>
              {recent.map((ticket) => <TicketCard key={ticket.id} ticket={ticket} onChange={refresh} />)}
            </>
          )}
        </section>

        <NewRequest onCreated={refresh} />
      </div>
    </div>
  );
}

const toleranceText = (tolerance: Ticket['skill_tolerance']) =>
  tolerance === 8 ? t('Any level') : t('Level ±{n}', { n: tolerance });


/** 有约球请求在找人时，提示打开这台设备的推送（配上了第一时间知道）；开着或不支持时不显示 */
function PushPrompt() {
  const [state, setState] = useState<PushState>();
  useEffect(() => void pushState().then(setState), []);
  if (state !== 'off') return null;
  return (
    <Notice icon="bell" tint="sky" action={{ label: t('Turn on'), onClick: () => enablePush().then(setState, () => toast(t('Couldn’t change notifications. Try again.'), 'error')) }}>
      {t('Get a notification the moment we find you a match.')}
    </Notice>
  );
}
/** 只有人数：同一天附近在找同类球局的人，和其中条件都合适的人 */
function Pool({ ticket }: { ticket: Ticket }) {
  const { data } = useLive<{ available: number; compatible: number }>('ticket_pool', { args: { p_ticket: ticket.id }, every: 60_000 });
  if (!data) return null;
  return (
    <div className="grid grid-cols-2 gap-2">
      <StatTile value={data.available} label={ticket.last_minute ? t('Looking right now') : t('Free that day nearby')} />
      <StatTile value={data.compatible} label={t('Good fit')} />
    </div>
  );
}

const status: Record<Ticket['status'], { icon: IconName; tint: Tint; label: string }> = {
  searching: { icon: 'search', tint: 'sky', label: 'Matching in background' },
  offered: { icon: 'bolt', tint: 'lime', label: 'Match found' },
  paused: { icon: 'warning', tint: 'peach', label: 'Paused' },
  matched: { icon: 'checkCircle', tint: 'mint', label: 'Game on' },
  expired: { icon: 'hourglass', tint: 'muted', label: 'No match this time' },
  cancelled: { icon: 'xCircle', tint: 'muted', label: 'Cancelled' },
};

function TicketCard({ ticket, onChange }: { ticket: Ticket; onChange: () => void }) {
  const [busy, setBusy] = useState<string>();

  async function act(name: string, fn: string, args: Record<string, unknown>, done?: string) {
    setBusy(name);
    const { error } = await supabase!.rpc(fn, args);
    setBusy(undefined);
    if (error) toast(problem(error), 'error');
    else if (done) toast(done);
    onChange();
  }

  if (ticket.offer) {
    const o = ticket.offer;
    const tz = o.venue.tz;
    const waiting = o.my_response === 'accepted';
    return (
      <article className="sticker animate-enter grid gap-4 bg-butter p-5 text-on-accent">
        <div className="text-center">
          <p className="text-footnote font-bold">{ticket.mode === 'doubles' ? t('Doubles') : t('Singles')} · {dayName(o.starts_at, tz)} {timeOf(o.starts_at, tz)}–{timeOf(o.ends_at, tz)}</p>
          <h3 className="display mt-1 text-[1.75rem]">{waiting ? t('Waiting for everyone to confirm') : t('Found your buddies!')}</h3>
          <p className="text-footnote font-bold">{o.venue.name} · {o.venue.city}</p>
        </div>
        <Versus players={o.players} />
        <div className="grid gap-1.5">
          <p className="flex justify-between text-footnote font-bold">
            <span>{t('Confirmations')}</span>
            <span className="tabular-nums">{t('{n}/{total} confirmed', { n: o.accepted, total: o.players.length })}</span>
          </p>
          <span className="block h-3 overflow-hidden rounded-full border-2 border-[#17140f] bg-white">
            <span className="block h-full bg-lime" style={{ width: `${(o.accepted / o.players.length) * 100}%` }} />
          </span>
        </div>
        {waiting ? (
          <p className="text-footnote font-bold" role="status">{t('You’re in. We’ll email you when everyone has confirmed.')}</p>
        ) : (
          <>
            <p className="flex items-center gap-2 text-footnote font-bold">
              <Icon name="clock" className="size-4" />
              {t('Confirm by {time} ({relative}). Declining is fine and doesn’t count against you.', { time: moment(o.respond_by, tz), relative: relative(o.respond_by) })}
            </p>
            <div className="grid grid-cols-[auto_1fr] gap-3">
              <Button className="button-lg button-quiet" busy={busy === 'decline'} disabled={Boolean(busy)} onClick={() => act('decline', 'respond_offer', { p_offer: o.id, p_accept: false }, t('Declined. We’ll keep looking.'))}>
                {t('Not this time')}
              </Button>
              <Button className="button-lg" busy={busy === 'accept'} disabled={Boolean(busy)} onClick={() => act('accept', 'respond_offer', { p_offer: o.id, p_accept: true }, t('Confirmed'))}>
                {t('Confirm game')}
              </Button>
            </div>
          </>
        )}
      </article>
    );
  }

  const s = status[ticket.status];
  const tz = ticket.venues[0]?.tz;
  // 普通请求到点没约成、离开赛还有 30 分钟以上：可以用同样的条件转成临时局
  const canGoLastMinute = ticket.status === 'expired' && !ticket.last_minute && new Date(ticket.starts_at).getTime() - Date.now() >= 30 * 60000;
  return (
    <article className="sticker animate-enter grid gap-3 p-4">
      <div className="flex items-center gap-2">
        <Tag icon={s.icon} tint={s.tint}>{t(s.label)}</Tag>
        {ticket.last_minute && <Tag tint="peach">{t('Last-minute')}</Tag>}
      </div>
      <ul className="grid gap-2">
        <Summary icon={ticket.mode === 'doubles' ? 'users' : 'user'} tint="lavender"
                 title={`${ticket.mode === 'doubles' ? t('Doubles') : t('Singles')} · ${dayName(ticket.starts_at, tz)} ${timeOf(ticket.starts_at, tz)}–${timeOf(ticket.ends_at, tz)}`}
                 subtitle={toleranceText(ticket.skill_tolerance)} />
        <Summary icon="pin" tint="sky" title={ticket.venues.map((v) => v.name).join(' · ')} subtitle={t('Only match with players who picked the same venue')} />
      </ul>
      {ticket.status === 'searching' && <Pool ticket={ticket} />}
      {ticket.status === 'paused' && <p className="text-footnote font-bold">{t('You missed a confirmation, so we stopped sending you matches for this time.')}</p>}
      {ticket.status === 'expired' && (
        <p className="text-footnote text-ink-secondary">
          {canGoLastMinute ? t('No one matched in time. Try a last-minute game: we’ll look for players who are free right now.') : t('No one matched this time. Try a wider window or more courts.')}
        </p>
      )}
      <div className="flex flex-wrap gap-2">
        {canGoLastMinute && (
          <Button className="button-sm" busy={busy === 'retry'} disabled={Boolean(busy)}
                  onClick={() => act('retry', 'submit_ticket', {
                    p_mode: ticket.mode, p_starts_at: ticket.starts_at, p_ends_at: ticket.ends_at, p_venue_ids: ticket.venues.map((v) => v.id),
                    p_skill_tolerance: ticket.skill_tolerance, p_auto_accept: true,
                  }, t('Looking for players who are free right now.'))}>
            {t('Try last-minute')}
          </Button>
        )}
        {ticket.status === 'paused' && (
          <Button className="button-sm" busy={busy === 'resume'} disabled={Boolean(busy)} onClick={() => act('resume', 'resume_ticket', { p_ticket: ticket.id }, t('Looking again'))}>
            {t('Keep looking')}
          </Button>
        )}
        {ticket.status === 'matched' && ticket.game_id && <Link to={`/games/${ticket.game_id}/`} className="button button-sm">{t('View game')}</Link>}
        {(ticket.status === 'searching' || ticket.status === 'paused') && (
          <Button className="button-sm" variant="quiet" busy={busy === 'cancel'} disabled={Boolean(busy)} onClick={() => act('cancel', 'cancel_ticket', { p_ticket: ticket.id }, t('Request cancelled'))}>
            {t('Cancel request')}
          </Button>
        )}
      </div>
    </article>
  );
}

const Summary = ({ icon, tint, title, subtitle }: { icon: IconName; tint: Tint; title: ReactNode; subtitle?: ReactNode }) => (
  <li className="flex items-center gap-3">
    <IconTile icon={icon} tint={tint} size="sm" />
    <span className="min-w-0">
      <span className="block font-bold">{title}</span>
      {subtitle && <span className="block text-footnote text-ink-secondary">{subtitle}</span>}
    </span>
  </li>
);

/** 找到的搭子：两边的球友卡，中间 VS（iOS 的 MatchFoundView） */
function Versus({ players }: { players: Player[] }) {
  const teams = [1, 2].map((team) => players.filter((p) => p.team === team));
  return (
    <div className="grid grid-cols-[1fr_auto_1fr] items-center gap-2">
      {teams.map((team, i) => (
        <ul key={i} className={`grid gap-2 ${i === 1 ? 'order-3' : ''}`}>
          {team.map((p) => (
            <li key={p.id} className={`flex items-center gap-2 rounded-[14px] border-2 border-[#17140f] p-1.5 ${p.me ? 'bg-lime' : 'bg-lavender'}`}>
              <Avatar id={p.id} name={p.nickname} size={32} />
              <span className="grid min-w-0 justify-items-start">
                {p.me ? <span className="truncate text-footnote font-bold">{t('You')}</span>
                  : <Link to={`/players/${p.id}/`} className="max-w-full truncate text-footnote font-bold hover:underline">{p.nickname}</Link>}
                <LevelBadge rating={p.rating} named={false} compact />
              </span>
            </li>
          ))}
        </ul>
      ))}
      <span className="order-2"><Starburst size={52}>VS</Starburst></span>
    </div>
  );
}

const presets: [string, number, number][] = [
  ['Morning 7–9 AM', 7 * 60, 9 * 60],
  ['Midday 12–2 PM', 12 * 60, 14 * 60],
  ['Afternoon 2–5 PM', 14 * 60, 17 * 60],
  ['Evening 7–9 PM', 19 * 60, 21 * 60],
  ['Late night 9–11 PM', 21 * 60, 23 * 60],
];

/** 新的约球请求：模式、日期、时间段、球馆、对手水平 */
function NewRequest({ onCreated }: { onCreated: () => void }) {
  const [mode, setMode] = useState<Mode>('doubles');
  const [courts, setCourts] = useState<Court[]>([]);
  const [favorites, setFavorites] = useState<Court[]>([]);
  const tz = courts[0]?.time_zone_id ?? Intl.DateTimeFormat().resolvedOptions().timeZone;
  const days = nextDays(14);
  // 默认今晚 7–9 点；已经来不及就默认明天
  const [date, setDate] = useState(() => {
    const asked = new URLSearchParams(location.search).get('date');
    if (asked && days.includes(asked)) return asked;
    return zoned(days[0], 19 * 60, tz).getTime() - Date.now() < 30 * 60000 ? days[1] : days[0];
  });
  const [from, setFrom] = useState(19 * 60);
  const [to, setTo] = useState(21 * 60);
  const [tolerance, setTolerance] = useState<1 | 2 | 8>(1);
  const [autoAccept, setAutoAccept] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  useEffect(() => {
    supabase!
      .from('favorite_venues')
      .select('venues(id, name, city, time_zone_id)')
      .then(({ data }) => {
        const list = (data ?? []).flatMap((f) => (f.venues ? [f.venues as unknown as Court] : []));
        setFavorites(list);
        setCourts((picked) => (picked.length ? picked : list.slice(0, 3)));
      });
  }, []);

  const toggleCourt = (court: Court) =>
    setCourts((list) => (list.some((c) => c.id === court.id) ? list.filter((c) => c.id !== court.id) : list.length < 3 ? [...list, court] : list));

  // 和数据库一样的检查，先在这里提示
  const startsAt = zoned(date, from, tz);
  const endsAt = zoned(date, to, tz);
  const hoursLong = (endsAt.getTime() - startsAt.getTime()) / 3600000;
  const lead = startsAt.getTime() - Date.now();
  const lastMinute = lead >= 30 * 60000 && lead < 2.5 * 3600000;
  const issue = !courts.length
    ? t('Pick at least one court.')
    : hoursLong < 1 || hoursLong > 8
      ? t('Pick a window between 1 and 8 hours.')
      : lead < 30 * 60000
        ? t('Pick a start at least 30 minutes from now.')
        : undefined;

  async function submit(event: SubmitEvent) {
    event.preventDefault();
    if (issue) return setError(issue);
    setBusy(true);
    setError(undefined);
    const { error } = await supabase!.rpc('submit_ticket', {
      p_mode: mode,
      p_starts_at: startsAt.toISOString(),
      p_ends_at: endsAt.toISOString(),
      p_venue_ids: courts.map((c) => c.id),
      p_skill_tolerance: tolerance,
      p_auto_accept: autoAccept,
    });
    setBusy(false);
    if (error) return setError(problem(error));
    toast(t('Request sent. We’re looking for players.'));
    onCreated();
  }

  const suggestions = favorites.filter((f) => !courts.some((c) => c.id === f.id));

  return (
    <form onSubmit={submit} noValidate aria-labelledby="new-request" className="grid min-w-0 gap-6 lg:order-1">
      <h2 id="new-request" className="sr-only">{t('New request')}</h2>

      <FormatPicker value={mode} onChange={setMode} />

      <DayPicker days={days} value={date} onChange={setDate} />

      <TimeRange from={from} to={to} onChange={(start, end) => { setFrom(start); setTo(end); }} />
      {lastMinute && (
        <Notice icon="bolt" tint="peach">
          {t('Last-minute game: we only match players who are looking right now, and everyone has 5–10 minutes to confirm. Turn on automatic accept below so you don’t miss it.')}
        </Notice>
      )}

      <fieldset className="grid gap-2">
        <legend className="mb-1 flex w-full justify-between text-headline">
          {t('Venues (up to {n})', { n: 3 })}
          <span className="text-footnote font-bold text-ink-secondary tabular-nums">{courts.length}/3</span>
        </legend>
        <p className="text-footnote text-ink-secondary">{t('Only match with players who picked the same venue')}</p>
        <div className="sticker grid gap-2 p-3">
          {courts.map((c) => (
            <div key={c.id} className="flex items-center gap-3">
              <IconTile icon="pin" tint="sky" size="sm" />
              <span className="min-w-0 flex-1">
                <span className="block truncate font-bold">{c.name}</span>
                <span className="block truncate text-footnote text-ink-secondary">{c.city}</span>
              </span>
              <button type="button" onClick={() => toggleCourt(c)} aria-label={t('Remove {name}', { name: c.name })}
                      className="press grid size-11 place-items-center rounded-full text-ink-tertiary hover:bg-surface-muted hover:text-ink">
                <Icon name="xCircle" className="size-5" />
              </button>
            </div>
          ))}
          {courts.length < 3 && <CourtSearch onPick={toggleCourt} label={courts.length ? t('Add or change venue') : t('Choose venue')} />}
          {courts.length < 3 && suggestions.length > 0 && (
            <ul className="flex flex-wrap gap-2" aria-label={t('My courts')}>
              {suggestions.map((c) => (
                <li key={c.id}>
                  <button type="button" onClick={() => toggleCourt(c)} className="toggle"><Icon name="plus" className="size-3.5" />{c.name}</button>
                </li>
              ))}
            </ul>
          )}
        </div>
      </fieldset>

      <fieldset className="grid gap-2">
        <legend className="mb-2 text-headline">{t('Opponents’ level')}</legend>
        <div className="flex flex-wrap gap-2">
          {([[1, 'Within 1 level'], [2, 'Within 2'], [8, 'Any']] as const).map(([value, label]) => (
            <button type="button" key={value} onClick={() => setTolerance(value)} aria-pressed={tolerance === value} className="toggle">{t(label)}</button>
          ))}
        </div>
      </fieldset>

      <label className="sticker flex cursor-pointer items-start gap-3 p-4">
        <span className="min-w-0 flex-1">
          <span className="block font-bold">{t('Accept matches automatically')}</span>
          <span className="block text-footnote text-ink-secondary">{t('Skip the confirmation step when a match fits this request.')}</span>
        </span>
        <input type="checkbox" role="switch" checked={autoAccept} onChange={(e) => setAutoAccept(e.target.checked)}
               className="relative mt-0.5 h-7 w-12 shrink-0 cursor-pointer appearance-none rounded-full border-2 border-stroke bg-surface-muted transition-colors before:absolute before:top-0.5 before:left-0.5 before:size-5 before:rounded-full before:border-2 before:border-stroke before:bg-white before:transition-transform checked:bg-lime checked:before:translate-x-5" />
      </label>

      {error && <p role="alert" className="font-bold text-danger">{error}</p>}
      <Button busy={busy} className="button-lg w-full"><Icon name="bolt" className="size-5" />{t('Start matching')}</Button>
    </form>
  );
}

/** 时间加减（iOS 的 TimeStepper）：每次 30 分钟 */
function Stepper({ label, value, onChange }: { label: string; value: number; onChange: (delta: number) => void }) {
  return (
    <div className="sticker grid justify-items-center gap-1 px-2 py-2.5" role="group" aria-label={label}>
      <span className="text-caption text-ink-secondary">{label}</span>
      <span className="flex items-center gap-1">
        <button type="button" onClick={() => onChange(-30)} aria-label={t('Earlier')} className="press grid size-9 place-items-center rounded-full hover:bg-surface-muted">
          <Icon name="minus" className="size-4" />
        </button>
        <output className="min-w-[5.5rem] text-center text-title2 tabular-nums">{clock(value)}</output>
        <button type="button" onClick={() => onChange(30)} aria-label={t('Later')} className="press grid size-9 place-items-center rounded-full hover:bg-surface-muted">
          <Icon name="plus" className="size-4" />
        </button>
      </span>
    </div>
  );
}

/** 单打 / 双打：两张大卡片，选中的是柠檬绿 */
export function FormatPicker({ value, onChange }: { value: Mode; onChange: (mode: Mode) => void }) {
  return (
    <fieldset className="grid gap-2">
      <legend className="mb-2 text-headline">{t('Format')}</legend>
      <div className="grid grid-cols-2 gap-3">
        {(['singles', 'doubles'] as const).map((m) => (
          <button
            type="button"
            key={m}
            onClick={() => onChange(m)}
            aria-pressed={value === m}
            className="press grid justify-items-start gap-1 rounded-[20px] border-2 border-stroke bg-surface p-4 text-left aria-pressed:bg-lime aria-pressed:text-on-accent aria-pressed:shadow-card"
          >
            <Icon name={m === 'doubles' ? 'users' : 'user'} className="size-6" />
            <span className="text-title3">{m === 'doubles' ? t('Doubles') : t('Singles')}</span>
            <span className="text-footnote font-bold opacity-70">{m === 'doubles' ? t('2 vs 2') : t('1 vs 1')}</span>
          </button>
        ))}
      </div>
    </fieldset>
  );
}

/** 日期条：接下来两周，选中的是柠檬绿 */
export function DayPicker({ days, value, onChange }: { days: string[]; value: string; onChange: (date: string) => void }) {
  return (
    <fieldset className="grid gap-2">
      <legend className="mb-2 text-headline">{t('Date (next 14 days)')}</legend>
      <div className="rail" role="radiogroup" aria-label={t('Date (next 14 days)')}>
        {days.map((d, i) => {
          const chip = dateChip(d, i);
          return (
            <button key={d} type="button" role="radio" aria-checked={value === d} aria-label={chip.full} onClick={() => onChange(d)}
                    className="press grid w-[3.5rem] justify-items-center gap-0.5 rounded-[16px] border-2 border-stroke bg-surface py-2 aria-checked:bg-lime aria-checked:text-on-accent aria-checked:shadow-low">
              <span className="text-caption">{chip.label}</span>
              <span className="text-[1.25rem] leading-tight font-black tabular-nums">{chip.day}</span>
            </button>
          );
        })}
      </div>
    </fieldset>
  );
}

/** 开始 / 结束时间：加减 30 分钟，加上几个常用时段 */
export function TimeRange({ from, to, onChange, maxHours = 8 }: { from: number; to: number; onChange: (from: number, to: number) => void; maxHours?: number }) {
  const step = (value: number, delta: number, min: number, max: number) => Math.min(max, Math.max(min, value + delta));
  const hoursLong = (to - from) / 60;
  return (
    <fieldset className="grid gap-3">
      <legend className="mb-2 text-headline">{maxHours === 8 ? t('Time slot (1–8 hours)') : t('Time')}</legend>
      <div className="grid grid-cols-[1fr_auto_1fr] items-center gap-3">
        <Stepper label={t('Start')} value={from} onChange={(delta) => onChange(step(from, delta, 6 * 60, 23 * 60), to)} />
        <Icon name="arrowRight" className="size-4 text-ink-tertiary" />
        <Stepper label={t('End')} value={to} onChange={(delta) => onChange(from, step(to, delta, 7 * 60, 24 * 60))} />
      </div>
      <p className="text-footnote text-ink-secondary">
        {hoursLong >= 1 && hoursLong <= maxHours
          ? t('{duration} total. Matches need at least 30 minutes of overlap', { duration: t('{n} hours', { n: hoursLong }) })
          : t('Pick a window between 1 and {n} hours.', { n: maxHours })}
      </p>
      <div className="rail">
        {presets.map(([label, start, end]) => (
          <button key={label} type="button" aria-pressed={from === start && to === end} onClick={() => onChange(start, end)}
                  className="toggle aria-pressed:bg-peach!">
            {t(label)}
          </button>
        ))}
      </div>
    </fieldset>
  );
}
