import { useEffect, useState, type SubmitEvent } from 'react';
import { tier } from './assessment';
import { Combobox } from './Combobox';
import { Link } from './router';
import { problem, supabase, useLive, type Mode, type Player, type Profile, type Ticket } from './supabase';
import { day, halfHours, hours, moment, relative, today, zoned } from './time';
import { Button, EmptyState, Field, PageHeader, Skeleton, toast } from './ui';

type Court = { id: string; name: string; city: string; time_zone_id: string | null };

export function Play({ profile }: { profile: Profile }) {
  const { data: tickets, failed, refresh } = useLive<Ticket[]>('my_matchmaking');
  const open = tickets?.filter((t) => ['searching', 'offered', 'paused'].includes(t.status)) ?? [];
  const recent = tickets?.filter((t) => !open.includes(t)) ?? [];

  return (
    <div>
      <PageHeader eyebrow="Find partners" title="Find a game">
        Tell us when you’re free and where you can play. We’ll match you with players at your level and email you when there’s a match.
      </PageHeader>

      {!profile.assessed_at && (
        <div className="tile mb-8 flex flex-wrap items-center justify-between gap-4 bg-lavender p-5 text-on-accent">
          <div>
            <p className="font-black">You’re starting at level 3</p>
            <p className="font-medium">Take the 2-minute level quiz so you’re matched with the right players.</p>
          </div>
          <Link to="/app/level/" className="button button-quiet">Take the quiz</Link>
        </div>
      )}

      <div className="grid gap-8 lg:grid-cols-[minmax(0,1fr)_24rem] lg:items-start">
        <section aria-labelledby="requests" className="grid gap-4">
          <h2 id="requests" className="text-xl font-black">Your requests</h2>
          {tickets === undefined && !failed && [0, 1].map((i) => <Skeleton key={i} className="h-36" />)}
          {failed && tickets === undefined && <EmptyState title="Couldn’t load your requests">Check your connection and try again.</EmptyState>}
          {tickets && open.length === 0 && (
            <EmptyState title="No open requests">Create one and we’ll look for players while you get on with your day.</EmptyState>
          )}
          {open.map((t) => <TicketCard key={t.id} ticket={t} onChange={refresh} />)}
          {recent.length > 0 && (
            <>
              <h3 className="mt-4 eyebrow">Recent</h3>
              {recent.map((t) => <TicketCard key={t.id} ticket={t} onChange={refresh} />)}
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

function TicketCard({ ticket: t, onChange }: { ticket: Ticket; onChange: () => void }) {
  const [busy, setBusy] = useState<string>();
  const tz = t.offer?.venue.tz;

  async function act(name: string, fn: string, args: Record<string, unknown>, done?: string) {
    setBusy(name);
    const { error } = await supabase!.rpc(fn, args);
    setBusy(undefined);
    if (error) toast(problem(error), 'error');
    else if (done) toast(done);
    onChange();
  }

  if (t.offer) {
    const o = t.offer;
    const waiting = o.my_response === 'accepted';
    return (
      <article className="sticker animate-enter grid gap-4 bg-butter p-5 text-on-accent sm:p-6">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div>
            <p className="eyebrow text-on-accent!">{t.mode === 'doubles' ? 'Doubles match found' : 'Singles match found'}</p>
            <h3 className="mt-1 text-2xl font-black">{day(o.starts_at, tz)} · {hours(o.starts_at, o.ends_at, tz)}</h3>
            <p className="font-bold">{o.venue.name}, {o.venue.city}</p>
          </div>
        </div>
        <Players players={o.players} mode={t.mode} />
        {waiting ? (
          <p className="font-bold" role="status">
            You’re in. Waiting for the others ({o.accepted} of {o.players.length} confirmed). We’ll email you when it’s on.
          </p>
        ) : (
          <>
            <p className="font-bold">
              Confirm by {moment(o.respond_by, tz)} ({relative(o.respond_by)}). Declining is fine and doesn’t count against you.
            </p>
            <div className="flex flex-wrap gap-3">
              <Button busy={busy === 'accept'} disabled={Boolean(busy)} onClick={() => act('accept', 'respond_offer', { p_offer: o.id, p_accept: true }, 'Confirmed')}>
                I’m in
              </Button>
              <Button variant="quiet" busy={busy === 'decline'} disabled={Boolean(busy)} onClick={() => act('decline', 'respond_offer', { p_offer: o.id, p_accept: false }, 'Declined. We’ll keep looking.')}>
                Can’t make it
              </Button>
            </div>
          </>
        )}
      </article>
    );
  }

  const status = statusText[t.status];
  const venueTz = t.venues[0]?.tz;
  return (
    <article className="tile animate-enter grid gap-3 bg-surface p-5">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className={`chip ${status.tone}`}>
          {t.status === 'searching' && <span aria-hidden="true" className="size-2 animate-pulse rounded-full bg-current" />}
          {status.label}
        </span>
        <span className="text-sm font-bold text-ink-tertiary">
          {t.mode === 'doubles' ? 'Doubles' : 'Singles'} · {t.skill_tolerance === 8 ? 'any level' : `within ${t.skill_tolerance} level${t.skill_tolerance > 1 ? 's' : ''}`}
        </span>
      </div>
      <div>
        <h3 className="text-lg font-black">{day(t.starts_at, venueTz)} · {hours(t.starts_at, t.ends_at, venueTz)}</h3>
        <p className="text-ink-secondary">{t.venues.map((v) => v.name).join(' · ')}</p>
      </div>
      {t.status === 'paused' && <p className="font-semibold">You missed a confirmation, so we stopped sending you matches for this time.</p>}
      {t.status === 'expired' && <p className="text-ink-secondary">Nothing counts against you. Try a wider time window or more courts next time.</p>}
      {(t.status === 'searching' || t.status === 'paused' || t.status === 'matched') && (
        <div className="flex flex-wrap gap-3">
          {t.status === 'paused' && (
            <Button busy={busy === 'resume'} disabled={Boolean(busy)} onClick={() => act('resume', 'resume_ticket', { p_ticket: t.id }, 'Looking again')}>
              Keep looking
            </Button>
          )}
          {t.status === 'matched' && t.game_id && <Link to={`/app/games/${t.game_id}/`} className="button">View game</Link>}
          {t.status !== 'matched' && (
            <Button variant="quiet" busy={busy === 'cancel'} disabled={Boolean(busy)} onClick={() => act('cancel', 'cancel_ticket', { p_ticket: t.id }, 'Request cancelled')}>
              Cancel request
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
        <ul key={i} className={`grid gap-2 ${i === 1 ? 'order-3 text-right' : ''}`} aria-label={mode === 'doubles' ? `Team ${i + 1}` : undefined}>
          {team.map((p, n) => (
            <li key={n} className="min-w-0">
              <span className="block truncate font-black">{p.me ? 'You' : p.nickname}</span>
              <span className="text-sm font-bold opacity-75">Level {tier(p.rating).label}{p.checked_in ? ' · checked in' : ''}</span>
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
  const [hits, setHits] = useState<Court[]>([]);
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

  async function search(query: string) {
    const q = query.replace(/[%_*(),.]/g, ' ').trim();
    if (q.length < 2) return setHits([]);
    const { data } = await supabase!.from('venues').select('id, name, city, time_zone_id').is('merged_into', null).ilike('name', `%${q}%`).limit(8);
    setHits((data ?? []) as Court[]);
  }

  // 和数据库一样的检查，先在这里提示
  const startsAt = zoned(date, from, tz);
  const endsAt = zoned(date, to, tz);
  const hoursLong = (endsAt.getTime() - startsAt.getTime()) / 3600000;
  const issue = !courts.length
    ? 'Pick at least one court.'
    : hoursLong < 1 || hoursLong > 8
      ? 'Pick a window between 1 and 8 hours.'
      : startsAt.getTime() < Date.now() + 2.5 * 3600000
        ? 'Pick a start at least 2½ hours from now.'
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
    toast('Request sent. We’re looking for players.');
    onCreated();
  }

  const suggestions = favorites.filter((f) => !courts.some((c) => c.id === f.id));

  return (
    <form onSubmit={submit} noValidate aria-labelledby="new-request" className="sticker grid gap-5 p-5 sm:p-6 lg:sticky lg:top-6">
      <h2 id="new-request" className="text-xl font-black">New request</h2>

      <fieldset className="grid gap-2">
        <legend className="mb-2 font-extrabold">Game</legend>
        <div className="flex gap-2">
          {(['doubles', 'singles'] as const).map((m) => (
            <button type="button" key={m} onClick={() => setMode(m)} aria-pressed={mode === m} className="toggle flex-1">
              {m === 'doubles' ? 'Doubles' : 'Singles'}
            </button>
          ))}
        </div>
      </fieldset>

      <Field label="Day">
        {(props) => <input {...props} type="date" value={date} min={today(tz)} max={today(tz, 13)} onChange={(e) => setDate(e.target.value)} className="field" />}
      </Field>

      <div className="grid grid-cols-2 gap-3">
        <Field label="From">
          {(props) => (
            <select {...props} value={from} onChange={(e) => setFrom(Number(e.target.value))} className="field">
              {halfHours.slice(0, -2).map((h) => <option key={h.minutes} value={h.minutes}>{h.label}</option>)}
            </select>
          )}
        </Field>
        <Field label="Until">
          {(props) => (
            <select {...props} value={to} onChange={(e) => setTo(Number(e.target.value))} className="field">
              {halfHours.slice(2).map((h) => <option key={h.minutes} value={h.minutes}>{h.label}</option>)}
            </select>
          )}
        </Field>
      </div>
      <p className="-mt-3 text-sm text-ink-tertiary">A wider window makes a match more likely. Games last up to 2 hours.</p>

      <fieldset className="grid gap-2">
        <legend className="mb-2 font-extrabold">Courts you can get to <span className="font-semibold text-ink-tertiary">(up to 3)</span></legend>
        {courts.length > 0 && (
          <ul className="flex flex-wrap gap-2">
            {courts.map((c) => (
              <li key={c.id}>
                <button type="button" onClick={() => toggleCourt(c)} aria-pressed="true" aria-label={`Remove ${c.name}`} className="toggle">
                  {c.name} <span aria-hidden="true">×</span>
                </button>
              </li>
            ))}
          </ul>
        )}
        {courts.length < 3 && (
          <>
            <Combobox
              label="Search courts"
              placeholder="Search courts by name"
              options={hits}
              onQuery={search}
              onPick={toggleCourt}
              render={(c) => (
                <>
                  <span className="block font-extrabold">{c.name}</span>
                  <span className="block text-sm text-ink-secondary">{c.city}</span>
                </>
              )}
            />
            {suggestions.length > 0 && (
              <ul className="flex flex-wrap gap-2" aria-label="My courts">
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
        <legend className="mb-2 font-extrabold">Opponents’ level</legend>
        <div className="flex flex-wrap gap-2">
          {([[1, 'Within 1 level'], [2, 'Within 2'], [8, 'Any']] as const).map(([value, label]) => (
            <button type="button" key={value} onClick={() => setTolerance(value)} aria-pressed={tolerance === value} className="toggle">{label}</button>
          ))}
        </div>
      </fieldset>

      <label className="flex items-start gap-3">
        <input type="checkbox" checked={autoAccept} onChange={(e) => setAutoAccept(e.target.checked)} className="mt-1 size-5 accent-[var(--color-lime)]" />
        <span>
          <span className="block font-extrabold">Accept matches automatically</span>
          <span className="block text-sm text-ink-tertiary">Skip the confirmation step when a match fits this request.</span>
        </span>
      </label>

      {error && <p role="alert" className="font-bold text-danger">{error}</p>}
      <Button busy={busy}>Find players</Button>
    </form>
  );
}
