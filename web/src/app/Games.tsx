import { useState } from 'react';
import { count, gapText } from './assessment';
import { money } from './Courts';
import { Players } from './Play';
import { Reviews } from './Review';
import { Link } from './router';
import { GamesTabs } from './Rankings';
import { problem, supabase, useLive, type Game, type MyChallenges, type Outcome, type PlayRecord } from './supabase';
import { day, hours, relative } from './time';
import { Button, EmptyState, PageHeader, Skeleton, toast } from './ui';

const live = (g: Game) => g.status === 'scheduled' && new Date(g.ends_at).getTime() > Date.now();
/** 结束后 48 小时内还有没评价的球友 */
const toReview = (g: Game) =>
  g.status === 'scheduled' && Date.now() > new Date(g.ends_at).getTime() && Date.now() < new Date(g.review_until).getTime() &&
  g.players.some((p) => !p.me && !p.reviewed);

export function Games() {
  const { data: games, failed } = useLive<Game[]>('my_games');
  const { data: record } = useLive<PlayRecord>('my_record', { every: 300_000 });
  const upcoming = games?.filter(live).reverse() ?? [];
  const past = games?.filter((g) => !live(g)) ?? [];

  return (
    <div>
      <PageHeader eyebrow="My games" title="My games" />
      <GamesTabs current="games" />
      <Challenges />
      {record && <RecordCard record={record} />}

      <section aria-labelledby="upcoming" className="mt-8 grid gap-3">
        <h2 id="upcoming" className="text-xl font-black">Upcoming</h2>
        {games === undefined && !failed && [0, 1].map((i) => <Skeleton key={i} className="h-24" />)}
        {failed && games === undefined && <EmptyState title="Couldn’t load your games">Check your connection and try again.</EmptyState>}
        {games && upcoming.length === 0 && (
          <EmptyState title="No games coming up" action={<Link to="/app/play/" className="button">Find a game</Link>}>
            Create a request and we’ll match you with players at your level.
          </EmptyState>
        )}
        {upcoming.map((g) => <GameRow key={g.id} game={g} />)}
      </section>

      {past.length > 0 && (
        <section aria-labelledby="past" className="mt-10 grid gap-3">
          <h2 id="past" className="text-xl font-black">Past</h2>
          {past.map((g) => <GameRow key={g.id} game={g} />)}
        </section>
      )}
    </div>
  );
}

function RecordCard({ record }: { record: PlayRecord }) {
  const stats = [
    ['Win rate', record.games ? `${Math.round((record.wins / record.games) * 100)}%` : '–'],
    ['Wins – losses', `${record.wins}–${record.losses}`],
    ['Games played', String(record.games_played)],
  ];
  return (
    <section aria-label="This month" className="tile grid gap-4 bg-surface p-5 sm:p-6">
      <p className="eyebrow">This month</p>
      <dl className="grid grid-cols-3 gap-3">
        {stats.map(([label, value]) => (
          <div key={label}>
            <dt className="text-sm font-bold text-ink-tertiary">{label}</dt>
            <dd className="display mt-1 text-4xl tabular-nums">{value}</dd>
          </div>
        ))}
      </dl>
      <p className="text-sm text-ink-tertiary">
        {record.games > 0 && `${count(record.games, 'confirmed game')} against ${count(record.opponents, 'opponent')}, ${gapText(record.gap)}. `}
        {record.public ? 'Shown on your profile.' : `Shown on your profile from 5 confirmed games (${record.games} so far).`}
        {' '}Up to 3 games a month count against the same opponents.
        {record.late_cancels > 0 && ` Late cancellations: ${record.late_cancels}.`}
      </p>
    </section>
  );
}

const resultText: Record<Game['result']['status'], string> = {
  awaiting: 'Result to report',
  disputed: 'Results don’t match',
  verified: 'Result confirmed',
  unsure: 'Not counted',
  expired: 'No result',
};

function GameRow({ game: g }: { game: Game }) {
  const started = new Date(g.starts_at).getTime() < Date.now();
  const rate = toReview(g);
  const label = g.status === 'cancelled' ? 'Cancelled' : rate ? 'Rate players' : started ? resultText[g.result.status] : relative(g.starts_at);
  return (
    <Link to={`/app/games/${g.id}/`} className="sticker lift flex flex-wrap items-center justify-between gap-3 p-4 sm:p-5">
      <span className="min-w-0">
        <span className="block font-black">{day(g.starts_at, g.venue.tz)} · {hours(g.starts_at, g.ends_at, g.venue.tz)}</span>
        <span className="block truncate text-sm text-ink-secondary">{g.mode === 'doubles' ? 'Doubles' : 'Singles'} at {g.venue.name}</span>
      </span>
      <span className={`chip ${g.status === 'cancelled' ? 'bg-surface-muted text-ink' : rate || (g.result.status === 'awaiting' && started) ? 'bg-butter' : 'bg-mint'}`}>{label}</span>
    </Link>
  );
}

export function GameDetail({ id }: { id: string }) {
  const { data: games, refresh } = useLive<Game[]>('my_games');
  const game = games?.find((g) => g.id === id);
  if (!games) return <Skeleton className="h-96" />;
  if (!game) return <EmptyState title="Game not found" action={<Link to="/app/games/" className="button">My games</Link>}>It may be older than 60 days.</EmptyState>;
  return <GameView game={game} onChange={refresh} />;
}

function GameView({ game: g, onChange }: { game: Game; onChange: () => void }) {
  const [busy, setBusy] = useState<string>();
  const [confirmCancel, setConfirmCancel] = useState(false);
  const now = Date.now();
  const start = new Date(g.starts_at).getTime();
  const end = new Date(g.ends_at).getTime();
  const scheduled = g.status === 'scheduled';
  const canCheckIn = scheduled && !g.checked_in && now >= start - 30 * 60000 && now <= end;
  const canCancel = scheduled && now < start;
  const late = start - now < 2 * 3600000;
  const canReport = scheduled && now >= start && now <= end + 7 * 86400000 && g.result.status !== 'verified';
  const tz = g.venue.tz;

  async function act(name: string, fn: string, args: Record<string, unknown>, done: string) {
    setBusy(name);
    const { error } = await supabase!.rpc(fn, args);
    setBusy(undefined);
    if (error) toast(problem(error), 'error');
    else toast(done);
    onChange();
  }

  const players = g.mode === 'doubles' ? 4 : 2;
  const hoursLong = (end - start) / 3600000;
  const cost = g.venue.pricing?.perPerson ?? (g.venue.pricing?.perCourtHour ? (g.venue.pricing.perCourtHour * hoursLong) / players : undefined);

  return (
    <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_22rem] lg:items-start">
      <div className="grid gap-6">
        <div>
          <Link to="/app/games/" className="link text-sm">My games</Link>
          <p className="eyebrow mt-6">{g.mode === 'doubles' ? 'Doubles' : 'Singles'}{g.status === 'cancelled' ? ' · Cancelled' : ''}</p>
          <h1 className="display mt-2 text-[clamp(2.5rem,6vw,3.75rem)]">{day(g.starts_at, tz)}</h1>
          <p className="mt-2 text-xl font-black">{hours(g.starts_at, g.ends_at, tz)}</p>
        </div>

        <section aria-label="Players" className="sticker p-5 sm:p-6">
          <Players players={g.players} mode={g.mode} />
        </section>

        {scheduled && now >= start && <Result game={g} canReport={canReport} busy={busy} act={act} />}
        {toReview(g) && <Reviews game={g} onDone={onChange} />}
      </div>

      <aside className="grid gap-4">
        {scheduled && now <= end + 48 * 3600000 && (
          <Link to={`/app/messages/game/${g.id}/`} className="button justify-self-start">Message players</Link>
        )}
        <section aria-label="Court" className="tile grid gap-3 bg-surface p-5">
          <p className="eyebrow">Court</p>
          <p className="text-lg font-black">{g.venue.name}</p>
          <p className="text-ink-secondary">{[g.venue.street, g.venue.city].filter(Boolean).join(', ')}</p>
          {cost !== undefined && (
            <p className="font-bold">About {money(Math.ceil(cost), g.venue.country)} each <span className="font-semibold text-ink-tertiary">(split at the court)</span></p>
          )}
          <a className="button button-quiet justify-self-start" href={`https://maps.apple.com/?q=${encodeURIComponent(g.venue.name)}&ll=${g.venue.lat},${g.venue.lon}`}>Directions</a>
        </section>

        {scheduled && (canCheckIn || g.checked_in || now < start) && (
          <section aria-label="Check in" className="tile grid gap-3 bg-surface p-5">
            {g.checked_in ? (
              <p className="font-black">You’re checked in.</p>
            ) : canCheckIn ? (
              <Button busy={busy === 'checkin'} onClick={() => act('checkin', 'check_in', { p_game: g.id }, 'Checked in')}>I’m here</Button>
            ) : (
              <p className="text-ink-secondary">Check in when you arrive. It opens 30 minutes before the start.</p>
            )}
          </section>
        )}

        {canCancel && (
          <section aria-label="Can’t make it" className="tile grid gap-3 bg-surface p-5">
            {confirmCancel ? (
              <>
                <p className="font-bold" role="alert">
                  {late ? 'The game starts in under 2 hours, so this counts as a late cancellation.' : 'The other players will be put back in the queue first.'}
                </p>
                <div className="flex flex-wrap gap-2">
                  <Button variant="danger" busy={busy === 'cancel'} onClick={() => act('cancel', 'cancel_game', { p_game: g.id }, 'Game cancelled')}>Cancel game</Button>
                  <Button variant="quiet" onClick={() => setConfirmCancel(false)}>Keep it</Button>
                </div>
              </>
            ) : (
              <Button variant="quiet" onClick={() => setConfirmCancel(true)}>Can’t make it</Button>
            )}
          </section>
        )}
      </aside>
    </div>
  );
}

function Result({ game: g, canReport, busy, act }: {
  game: Game;
  canReport: boolean;
  busy?: string;
  act: (name: string, fn: string, args: Record<string, unknown>, done: string) => void;
}) {
  const mine: Outcome = g.my_team === 1 ? 'team1' : 'team2';
  const theirs: Outcome = g.my_team === 1 ? 'team2' : 'team1';
  const reported = g.my_report?.outcome;
  const { status, outcome } = g.result;
  const choices: [Outcome | null, string][] = [[mine, 'We won'], [theirs, 'We lost'], ['friendly', 'Just for fun'], [null, 'Can’t remember']];
  const summary =
    status === 'verified'
      ? outcome === 'friendly' ? 'Confirmed: a friendly game, no winner.' : `Confirmed: you ${outcome === mine ? 'won' : 'lost'}.`
      : status === 'disputed'
        ? 'Your reports don’t match. Either side can change theirs within 7 days of the game.'
        : status === 'unsure'
          ? 'One side doesn’t remember the result, so this game won’t count.'
          : status === 'expired'
            ? 'No result was agreed within 7 days.'
            : g.my_report
              ? 'Waiting for the other side to report.'
              : 'How did it go? The result counts once both sides agree.';

  return (
    <section aria-labelledby="result" className="tile grid gap-4 bg-surface p-5 sm:p-6">
      <h2 id="result" className="text-xl font-black">Result</h2>
      <p role="status" className="text-ink-secondary">{summary}</p>
      {canReport && (
        <div className="flex flex-wrap gap-2" role="group" aria-label="Report the result">
          {choices.map(([value, label]) => (
            <button
              key={label}
              onClick={() => act('report', 'report_result', { p_game: g.id, p_outcome: value }, 'Result saved')}
              disabled={Boolean(busy)}
              aria-pressed={g.my_report !== null && reported === value}
              className="toggle"
            >
              {label}
            </button>
          ))}
        </div>
      )}
    </section>
  );
}

/** 约战：收到的（接受 / 拒绝）和发出的（等回应 / 未成行 / 已约成） */
function Challenges() {
  const { data, refresh } = useLive<MyChallenges>('my_challenges', { every: 60_000 });
  const [busy, setBusy] = useState<string>();
  if (!data || (data.incoming.length === 0 && data.outgoing.length === 0)) return null;

  async function act(name: string, fn: string, args: Record<string, unknown>, done: string) {
    setBusy(name);
    const { error } = await supabase!.rpc(fn, args);
    setBusy(undefined);
    if (error) toast(problem(error), 'error');
    else toast(done);
    refresh();
  }

  return (
    <section aria-labelledby="challenges" className="mb-8 grid gap-3">
      <h2 id="challenges" className="text-xl font-black">Challenges</h2>
      {data.incoming.map((c) => (
        <article key={c.id} className="sticker grid gap-3 bg-butter p-5 text-on-accent">
          <p className="font-black">
            <Link to={`/app/players/${c.player.id}/`} className="underline">{c.player.nickname}</Link> challenged you to singles
          </p>
          <p className="font-bold">{day(c.starts_at, c.venue.tz)} · {hours(c.starts_at, c.ends_at, c.venue.tz)} at {c.venue.name}</p>
          {c.message && <p className="font-medium">“{c.message}”</p>}
          <p className="text-sm font-semibold">Answer by {day(c.expires_at, c.venue.tz)}. Declining is fine, they’ll only see it didn’t happen.</p>
          <div className="flex flex-wrap gap-2">
            <Button busy={busy === `yes-${c.id}`} disabled={Boolean(busy)} onClick={() => act(`yes-${c.id}`, 'respond_challenge', { p_challenge: c.id, p_accept: true }, 'Game on!')}>Accept</Button>
            <Button variant="quiet" disabled={Boolean(busy)} onClick={() => act(`no-${c.id}`, 'respond_challenge', { p_challenge: c.id, p_accept: false }, 'Declined')}>Decline</Button>
          </div>
        </article>
      ))}
      {data.outgoing.map((c) => (
        <article key={c.id} className="tile flex flex-wrap items-center justify-between gap-3 bg-surface p-4">
          <span className="min-w-0">
            <span className="block font-black">You challenged {c.player.nickname}</span>
            <span className="block text-sm text-ink-secondary">{day(c.starts_at, c.venue.tz)} · {hours(c.starts_at, c.ends_at, c.venue.tz)} at {c.venue.name}</span>
          </span>
          {c.status === 'pending' ? (
            <span className="flex items-center gap-3">
              <span className="chip bg-sky">Waiting</span>
              <button className="link text-sm" disabled={Boolean(busy)} onClick={() => act(`w-${c.id}`, 'withdraw_challenge', { p_challenge: c.id }, 'Challenge withdrawn')}>Withdraw</button>
            </span>
          ) : c.status === 'accepted' && c.game_id ? (
            <Link to={`/app/games/${c.game_id}/`} className="chip bg-mint">Game on</Link>
          ) : (
            <span className="chip bg-surface-muted text-ink">Didn’t happen</span>
          )}
        </article>
      ))}
    </section>
  );
}
