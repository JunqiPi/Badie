import { useEffect, useState, type SubmitEvent } from 'react';
import { tier } from './assessment';
import { PlayTabs } from './Groups';
import { t } from './i18n';
import { CourtSearch, type Court } from './pickers';
import { Link } from './router';
import { problem, supabase, useLive, type Mode, type Player, type Profile, type Ticket } from './supabase';
import { day, halfHours, hours, moment, relative, today, zoned } from './time';
import { Button, EmptyState, Field, PageHeader, Skeleton, toast } from './ui';

export function Play({ profile }: { profile: Profile }) {
  const { data: tickets, failed, refresh } = useLive<Ticket[]>('my_matchmaking');
  const open = tickets?.filter((ticket) => ['searching', 'offered', 'paused'].includes(ticket.status)) ?? [];
  const recent = tickets?.filter((ticket) => !open.includes(ticket)) ?? [];

  return (
    <div>
      <PageHeader eyebrow={t('Play')} title={t('Find a game')}>
        {t('Tell us when you’re free and where you can play. We’ll match you with players at your level and email you when there’s a match.')}
      </PageHeader>
      <PlayTabs current="play" />

      {!profile.assessed_at && (
        <div className="tile mb-8 flex flex-wrap items-center justify-between gap-4 bg-lavender p-5 text-on-accent">
          <div>
            <p className="font-black">{t('You’re starting at level 3')}</p>
            <p className="font-medium">{t('Take the 2-minute level quiz so you’re matched with the right players.')}</p>
          </div>
          <Link to="/app/level/" className="button button-quiet">{t('Take the quiz')}</Link>
        </div>
      )}

      <div className="grid gap-8 lg:grid-cols-[minmax(0,1fr)_24rem] lg:items-start">
        <section aria-labelledby="requests" className="grid gap-4">
          <h2 id="requests" className="text-xl font-black">{t('Your requests')}</h2>
          {tickets === undefined && !failed && [0, 1].map((i) => <Skeleton key={i} className="h-36" />)}
          {failed && tickets === undefined && <EmptyState title={t('Couldn’t load your requests')}>{t('Check your connection and try again.')}</EmptyState>}
          {tickets && open.length === 0 && (
            <EmptyState title={t('No open requests')}>{t('Create one and we’ll look for players while you get on with your day.')}</EmptyState>
          )}
          {open.map((ticket) => <TicketCard key={ticket.id} ticket={ticket} onChange={refresh} />)}
          {recent.length > 0 && (
            <>
              <h3 className="mt-4 eyebrow">{t('Recent')}</h3>
              {recent.map((ticket) => <TicketCard key={ticket.id} ticket={ticket} onChange={refresh} />)}
            </>
          )}
        </section>

        <NewRequest onCreated={refresh} />
      </div>
    </div>
  );
}

const statusText: Record<Ticket['status'], { label: string; tone: string }> = {
  searching: { label: 'Looking for players', tone: 'bg-sky' },
  offered: { label: 'Match found', tone: 'bg-butter' },
  paused: { label: 'Paused', tone: 'bg-peach' },
  matched: { label: 'Game on', tone: 'bg-mint' },
  expired: { label: 'No match this time', tone: 'bg-surface-muted text-ink' },
  cancelled: { label: 'Cancelled', tone: 'bg-surface-muted text-ink' },
};

const toleranceText = (tolerance: Ticket['skill_tolerance']) =>
  tolerance === 8 ? t('any level') : t('within {n} level|within {n} levels', { n: tolerance });

function TicketCard({ ticket, onChange }: { ticket: Ticket; onChange: () => void }) {
  const [busy, setBusy] = useState<string>();
  const tz = ticket.offer?.venue.tz;

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
    const waiting = o.my_response === 'accepted';
    return (
      <article className="sticker animate-enter grid gap-4 bg-butter p-5 text-on-accent sm:p-6">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div>
            <p className="eyebrow text-on-accent!">{ticket.mode === 'doubles' ? t('Doubles match found') : t('Singles match found')}</p>
            <h3 className="mt-1 text-2xl font-black">{day(o.starts_at, tz)} · {hours(o.starts_at, o.ends_at, tz)}</h3>
            <p className="font-bold">{o.venue.name}, {o.venue.city}</p>
          </div>
        </div>
        <Players players={o.players} mode={ticket.mode} />
        {waiting ? (
          <p className="font-bold" role="status">
            {t('You’re in. Waiting for the others ({accepted} of {total} confirmed). We’ll email you when it’s on.', { accepted: o.accepted, total: o.players.length })}
          </p>
        ) : (
          <>
            <p className="font-bold">
              {t('Confirm by {time} ({relative}). Declining is fine and doesn’t count against you.', { time: moment(o.respond_by, tz), relative: relative(o.respond_by) })}
            </p>
            <div className="flex flex-wrap gap-3">
              <Button busy={busy === 'accept'} disabled={Boolean(busy)} onClick={() => act('accept', 'respond_offer', { p_offer: o.id, p_accept: true }, t('Confirmed'))}>
                {t('I’m in')}
              </Button>
              <Button variant="quiet" busy={busy === 'decline'} disabled={Boolean(busy)} onClick={() => act('decline', 'respond_offer', { p_offer: o.id, p_accept: false }, t('Declined. We’ll keep looking.'))}>
                {t('Can’t make it')}
              </Button>
            </div>
          </>
        )}
      </article>
    );
  }

  const status = statusText[ticket.status];
  const venueTz = ticket.venues[0]?.tz;
  return (
    <article className="tile animate-enter grid gap-3 bg-surface p-5">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className={`chip ${status.tone}`}>
          {ticket.status === 'searching' && <span aria-hidden="true" className="size-2 animate-pulse rounded-full bg-current" />}
          {t(status.label)}
        </span>
        <span className="text-sm font-bold text-ink-tertiary">
          {ticket.mode === 'doubles' ? t('Doubles') : t('Singles')} · {toleranceText(ticket.skill_tolerance)}
        </span>
      </div>
      <div>
        <h3 className="text-lg font-black">{day(ticket.starts_at, venueTz)} · {hours(ticket.starts_at, ticket.ends_at, venueTz)}</h3>
        <p className="text-ink-secondary">{ticket.venues.map((v) => v.name).join(' · ')}</p>
      </div>
      {ticket.status === 'paused' && <p className="font-semibold">{t('You missed a confirmation, so we stopped sending you matches for this time.')}</p>}
      {ticket.status === 'expired' && <p className="text-ink-secondary">{t('Nothing counts against you. Try a wider time window or more courts next time.')}</p>}
      {(ticket.status === 'searching' || ticket.status === 'paused' || ticket.status === 'matched') && (
        <div className="flex flex-wrap gap-3">
          {ticket.status === 'paused' && (
            <Button busy={busy === 'resume'} disabled={Boolean(busy)} onClick={() => act('resume', 'resume_ticket', { p_ticket: ticket.id }, t('Looking again'))}>
              {t('Keep looking')}
            </Button>
          )}
          {ticket.status === 'matched' && ticket.game_id && <Link to={`/app/games/${ticket.game_id}/`} className="button">{t('View game')}</Link>}
          {ticket.status !== 'matched' && (
            <Button variant="quiet" busy={busy === 'cancel'} disabled={Boolean(busy)} onClick={() => act('cancel', 'cancel_ticket', { p_ticket: ticket.id }, t('Request cancelled'))}>
              {t('Cancel request')}
            </Button>
          )}
        </div>
      )}
    </article>
  );
}

export function Players({ players, mode }: { players: Player[]; mode: Mode }) {
  const teams = [1, 2].map((team) => players.filter((p) => p.team === team));
  return (
    <div className="grid grid-cols-[1fr_auto_1fr] items-center gap-3">
      {teams.map((team, i) => (
        <ul key={i} className={`grid gap-2 ${i === 1 ? 'order-3 text-right' : ''}`} aria-label={mode === 'doubles' ? t('Team {n}', { n: i + 1 }) : undefined}>
          {team.map((p, n) => (
            <li key={n} className="min-w-0">
              {p.me ? (
                <span className="block truncate font-black">{t('You')}</span>
              ) : (
                <Link to={`/app/players/${p.id}/`} className="block truncate font-black underline decoration-transparent decoration-2 underline-offset-4 transition-colors hover:decoration-current">
                  {p.nickname}
                </Link>
              )}
              <span className="text-sm font-bold opacity-75">
                {t('Level {level}', { level: tier(p.rating).label })}{p.checked_in ? ` · ${t('checked in')}` : ''}
              </span>
            </li>
          ))}
        </ul>
      ))}
      <span aria-hidden="true" className="order-2 display text-2xl opacity-60">vs</span>
    </div>
  );
}

function NewRequest({ onCreated }: { onCreated: () => void }) {
  const [mode, setMode] = useState<Mode>('doubles');
  const [courts, setCourts] = useState<Court[]>([]);
  const [favorites, setFavorites] = useState<Court[]>([]);
  const tz = courts[0]?.time_zone_id ?? Intl.DateTimeFormat().resolvedOptions().timeZone;
  const [date, setDate] = useState(() => today(tz, 1));
  const [from, setFrom] = useState(18 * 60);
  const [to, setTo] = useState(21 * 60);
  const [tolerance, setTolerance] = useState<1 | 2 | 8>(1);
  const [autoAccept, setAutoAccept] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  useEffect(() => {
    supabase!
      .from('favorite_venues')
      .select('venues(id, name, city, time_zone_id)')
      .then(({ data }) => setFavorites((data ?? []).flatMap((f) => (f.venues ? [f.venues as unknown as Court] : []))));
  }, []);

  const toggleCourt = (court: Court) =>
    setCourts((list) => (list.some((c) => c.id === court.id) ? list.filter((c) => c.id !== court.id) : list.length < 3 ? [...list, court] : list));

  // 和数据库一样的检查，先在这里提示
  const startsAt = zoned(date, from, tz);
  const endsAt = zoned(date, to, tz);
  const hoursLong = (endsAt.getTime() - startsAt.getTime()) / 3600000;
  const issue = !courts.length
    ? t('Pick at least one court.')
    : hoursLong < 1 || hoursLong > 8
      ? t('Pick a window between 1 and 8 hours.')
      : startsAt.getTime() < Date.now() + 2.5 * 3600000
        ? t('Pick a start at least 2½ hours from now.')
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
  const times = halfHours();

  return (
    <form onSubmit={submit} noValidate aria-labelledby="new-request" className="sticker grid gap-5 p-5 sm:p-6 lg:sticky lg:top-6">
      <h2 id="new-request" className="text-xl font-black">{t('New request')}</h2>

      <fieldset className="grid gap-2">
        <legend className="mb-2 font-extrabold">{t('Game')}</legend>
        <div className="flex gap-2">
          {(['doubles', 'singles'] as const).map((m) => (
            <button type="button" key={m} onClick={() => setMode(m)} aria-pressed={mode === m} className="toggle flex-1">
              {m === 'doubles' ? t('Doubles') : t('Singles')}
            </button>
          ))}
        </div>
      </fieldset>

      <Field label={t('Day')}>
        {(props) => <input {...props} type="date" value={date} min={today(tz)} max={today(tz, 13)} onChange={(e) => setDate(e.target.value)} className="field" />}
      </Field>

      <div className="grid grid-cols-2 gap-3">
        <Field label={t('From')}>
          {(props) => (
            <select {...props} value={from} onChange={(e) => setFrom(Number(e.target.value))} className="field">
              {times.slice(0, -2).map((h) => <option key={h.minutes} value={h.minutes}>{h.label}</option>)}
            </select>
          )}
        </Field>
        <Field label={t('Until')}>
          {(props) => (
            <select {...props} value={to} onChange={(e) => setTo(Number(e.target.value))} className="field">
              {times.slice(2).map((h) => <option key={h.minutes} value={h.minutes}>{h.label}</option>)}
            </select>
          )}
        </Field>
      </div>
      <p className="-mt-3 text-sm text-ink-tertiary">{t('A wider window makes a match more likely. Games last up to 2 hours.')}</p>

      <fieldset className="grid gap-2">
        <legend className="mb-2 font-extrabold">
          {t('Courts you can get to')} <span className="font-semibold text-ink-tertiary">{t('(up to 3)')}</span>
        </legend>
        {courts.length > 0 && (
          <ul className="flex flex-wrap gap-2">
            {courts.map((c) => (
              <li key={c.id}>
                <button type="button" onClick={() => toggleCourt(c)} aria-pressed="true" aria-label={t('Remove {name}', { name: c.name })} className="toggle">
                  {c.name} <span aria-hidden="true">×</span>
                </button>
              </li>
            ))}
          </ul>
        )}
        {courts.length < 3 && (
          <>
            <CourtSearch onPick={toggleCourt} />
            {suggestions.length > 0 && (
              <ul className="flex flex-wrap gap-2" aria-label={t('My courts')}>
                {suggestions.map((c) => (
                  <li key={c.id}>
                    <button type="button" onClick={() => toggleCourt(c)} aria-pressed="false" className="toggle">+ {c.name}</button>
                  </li>
                ))}
              </ul>
            )}
          </>
        )}
      </fieldset>

      <fieldset className="grid gap-2">
        <legend className="mb-2 font-extrabold">{t('Opponents’ level')}</legend>
        <div className="flex flex-wrap gap-2">
          {([[1, 'Within 1 level'], [2, 'Within 2'], [8, 'Any']] as const).map(([value, label]) => (
            <button type="button" key={value} onClick={() => setTolerance(value)} aria-pressed={tolerance === value} className="toggle">{t(label)}</button>
          ))}
        </div>
      </fieldset>

      <label className="flex items-start gap-3">
        <input type="checkbox" checked={autoAccept} onChange={(e) => setAutoAccept(e.target.checked)} className="mt-1 size-5 accent-[var(--color-lime)]" />
        <span>
          <span className="block font-extrabold">{t('Accept matches automatically')}</span>
          <span className="block text-sm text-ink-tertiary">{t('Skip the confirmation step when a match fits this request.')}</span>
        </span>
      </label>

      {error && <p role="alert" className="font-bold text-danger">{error}</p>}
      <Button busy={busy}>{t('Find players')}</Button>
    </form>
  );
}
