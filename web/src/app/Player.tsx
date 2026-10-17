import { useState, type SubmitEvent } from 'react';
import { count, gapText, tier } from './assessment';
import { CourtSearch, type Court } from './pickers';
import { Link } from './router';
import { problem, supabase, useLive, type PlayerCard } from './supabase';
import { day, halfHours, today, zoned } from './time';
import { Button, EmptyState, Field, Skeleton, toast } from './ui';

export const tagLabels: Record<string, string> = {
  friendly: 'Friendly',
  punctual: 'On time',
  skilled: 'Solid skills',
  patient: 'Great with beginners',
  fair_play: 'Fair play',
  great_partner: 'Great partner',
};

/** 球友资料：只有正面信息和客观记录（DESIGN.md §11–12） */
export function PlayerPage({ id }: { id: string }) {
  const { data: card, refresh } = useLive<PlayerCard | null>('player_card', { args: { p_user: id }, every: 120_000 });
  if (card === undefined) return <Skeleton className="h-96 max-w-2xl" />;
  if (card === null) {
    return (
      <EmptyState title="Player not found" action={<Link to="/app/games/" className="button">My games</Link>}>
        You can see players you’ve been matched or played with, and your friends.
      </EmptyState>
    );
  }
  const level = tier(card.rating);

  return (
    <div className="grid max-w-2xl gap-6">
      <button onClick={() => history.back()} className="link justify-self-start text-sm">Back</button>

      <section aria-labelledby="player" className="sticker grid gap-4 p-6 sm:p-8">
        <div>
          <p className="eyebrow">{card.relationship === 'friend' ? 'Friend' : 'Player'}</p>
          <h1 id="player" className="display mt-2 text-[clamp(2.5rem,7vw,4rem)] break-words">{card.nickname}</h1>
          <p className="mt-2 text-lg font-black">
            Level {level.label} · {level.name}
            {!card.assessed && <span className="font-semibold text-ink-tertiary"> (not assessed yet)</span>}
          </p>
        </div>
        <ul className="flex flex-wrap gap-2" aria-label="Highlights">
          {card.new_player ? <li className="chip bg-sky">New player</li> : card.reliable && <li className="chip bg-mint">Reliable</li>}
          <li className="chip bg-surface-muted text-ink">{card.games_band}</li>
          {card.tags.map((t) => <li key={t} className="chip bg-lavender">{tagLabels[t] ?? t}</li>)}
        </ul>
        {card.relationship !== 'self' && <Actions card={card} onChange={refresh} />}
      </section>

      {card.win_rate && (
        <section aria-labelledby="winrate" className="tile grid gap-2 bg-surface p-6">
          <h2 id="winrate" className="eyebrow">This month</h2>
          <p className="text-lg font-black">
            {card.win_rate.games ? `${Math.round((card.win_rate.wins / card.win_rate.games) * 100)}% wins` : 'No confirmed games yet'}
            <span className="font-semibold text-ink-secondary"> · {card.win_rate.wins}–{card.win_rate.games - card.win_rate.wins}</span>
          </p>
          {card.win_rate.games > 0 && (
            <p className="text-ink-secondary">{count(card.win_rate.games, 'game')} against {count(card.win_rate.opponents, 'opponent')}, {gapText(card.win_rate.gap)}.</p>
          )}
          {card.relationship === 'self' && !card.win_rate.public && <p className="text-sm text-ink-tertiary">Others see this from 5 confirmed games.</p>}
        </section>
      )}

      {card.challenge !== 'hidden' && <Challenge card={card} onChange={refresh} />}

      {card.relationship !== 'self' && (
        <section aria-labelledby="together" className="tile grid gap-2 bg-surface p-6">
          <h2 id="together" className="eyebrow">You and {card.nickname}</h2>
          <p className="font-bold">
            {card.games_together === 0 ? 'No games together yet' : `${card.games_together} game${card.games_together > 1 ? 's' : ''} together`}
            {card.last_game && <span className="font-semibold text-ink-secondary"> · last on {day(card.last_game.starts_at, card.last_game.tz)} at {card.last_game.venue}</span>}
          </p>
          {card.mutual_friends > 0 && <p className="text-ink-secondary">{card.mutual_friends} friend{card.mutual_friends > 1 ? 's' : ''} in common</p>}
        </section>
      )}

      {card.relationship !== 'self' && <Safety card={card} onChange={refresh} />}
    </div>
  );
}

function useAction(onChange: () => void) {
  const [busy, setBusy] = useState<string>();
  async function run(name: string, fn: string, args: Record<string, unknown>, done?: string) {
    setBusy(name);
    const { error } = await supabase!.rpc(fn, args);
    setBusy(undefined);
    if (error) toast(problem(error), 'error');
    else if (done) toast(done);
    onChange();
    return !error;
  }
  return { busy, run };
}

function Actions({ card, onChange }: { card: PlayerCard; onChange: () => void }) {
  const { busy, run } = useAction(onChange);
  const [confirmRemove, setConfirmRemove] = useState(false);
  const user = { p_user: card.id };

  switch (card.relationship) {
    case 'friend':
      return (
        <div className="flex flex-wrap gap-3">
          <Link to={`/app/messages/dm/${card.id}/`} className="button">Message</Link>
          {confirmRemove ? (
            <Button variant="quiet" busy={busy === 'remove'} onClick={() => run('remove', 'remove_friend', user, 'Removed from friends')}>
              Yes, remove friend
            </Button>
          ) : (
            <Button variant="quiet" onClick={() => setConfirmRemove(true)}>Remove friend</Button>
          )}
        </div>
      );
    case 'incoming':
      return (
        <div className="flex flex-wrap items-center gap-3">
          <p className="w-full font-bold">{card.nickname} wants to be friends.</p>
          <Button busy={busy === 'accept'} onClick={() => run('accept', 'respond_friend_request', { ...user, p_accept: true }, 'You’re now friends')}>Accept</Button>
          <Button variant="quiet" busy={busy === 'ignore'} onClick={() => run('ignore', 'respond_friend_request', { ...user, p_accept: false })}>Ignore</Button>
        </div>
      );
    case 'requested':
      return <p className="font-bold text-ink-secondary">Friend request sent</p>;
    case 'blocked':
      return <Button variant="quiet" busy={busy === 'unblock'} onClick={() => run('unblock', 'unblock_user', user, 'Unblocked')}>Unblock</Button>;
    default:
      return (
        <div>
          <Button busy={busy === 'add'} onClick={() => run('add', 'send_friend_request', user, 'Friend request sent')}>Add friend</Button>
          <p className="mt-2 text-sm text-ink-tertiary">Friends can message each other. Players who both pick “play again” after a game become friends automatically.</p>
        </div>
      );
  }
}

const reasons = [
  ['harassment', 'Harassment or unwanted messages'],
  ['scam', 'Asked for money or personal details'],
  ['unsafe', 'Unsafe or aggressive play'],
  ['fake', 'Fake profile or level'],
  ['other', 'Something else'],
] as const;

function Safety({ card, onChange }: { card: PlayerCard; onChange: () => void }) {
  const { busy, run } = useAction(onChange);
  const [step, setStep] = useState<'block' | 'report'>();
  const [reason, setReason] = useState<string>('harassment');
  const [details, setDetails] = useState('');

  return (
    <section aria-labelledby="safety" className="tile grid gap-3 bg-surface p-6">
      <h2 id="safety" className="eyebrow">Safety</h2>
      {step === 'block' ? (
        <>
          <p className="font-bold" role="alert">
            You won’t be matched with {card.nickname} again, and you’ll stop being friends. They won’t be told.
          </p>
          <div className="flex flex-wrap gap-2">
            <Button variant="danger" busy={busy === 'block'} onClick={() => run('block', 'block_user', { p_user: card.id }, 'Blocked').then(() => setStep(undefined))}>Block</Button>
            <Button variant="quiet" onClick={() => setStep(undefined)}>Keep</Button>
          </div>
        </>
      ) : step === 'report' ? (
        <form
          className="grid gap-3"
          onSubmit={(e) => {
            e.preventDefault();
            run('report', 'report_user', { p_user: card.id, p_reason: reason, p_details: details }, 'Thanks. Our team will look into it.').then((ok) => ok && setStep(undefined));
          }}
        >
          <fieldset className="grid gap-2">
            <legend className="mb-1 font-extrabold">What happened?</legend>
            {reasons.map(([value, label]) => (
              <label key={value} className="flex items-center gap-3 font-semibold">
                <input type="radio" name="reason" value={value} checked={reason === value} onChange={() => setReason(value)} className="size-5 accent-[var(--color-lime)]" />
                {label}
              </label>
            ))}
          </fieldset>
          <label className="grid gap-1.5">
            <span className="font-extrabold">Details <span className="font-semibold text-ink-tertiary">(optional)</span></span>
            <textarea value={details} onChange={(e) => setDetails(e.target.value)} maxLength={1000} rows={3} className="field" />
          </label>
          <div className="flex flex-wrap gap-2">
            <Button busy={busy === 'report'}>Send report</Button>
            <Button type="button" variant="quiet" onClick={() => setStep(undefined)}>Cancel</Button>
          </div>
        </form>
      ) : (
        <div className="flex flex-wrap gap-2">
          {card.relationship !== 'blocked' && <Button variant="quiet" onClick={() => setStep('block')}>Block</Button>}
          <Button variant="quiet" onClick={() => setStep('report')}>Report</Button>
        </div>
      )}
    </section>
  );
}

const challengeReasons: Record<string, string> = {
  friends_only: 'They only accept challenges from friends.',
  level_out_of_range: 'They only accept challenges from players within 1 level.',
  already_pending: 'Challenge sent. Waiting for their answer.',
  cooldown: 'You can challenge them again a week after your last challenge.',
  too_many_outgoing: 'You have 3 open challenges. Wait for answers first.',
  daily_limit: 'You’ve used today’s challenges.',
  target_busy: 'They have too many open challenges right now.',
};

/** 单打约战：选球馆和时间，对方 48 小时内回应 */
function Challenge({ card, onChange }: { card: PlayerCard; onChange: () => void }) {
  const [open, setOpen] = useState(false);
  const [court, setCourt] = useState<Court>();
  const tz = court?.time_zone_id ?? Intl.DateTimeFormat().resolvedOptions().timeZone;
  const [date, setDate] = useState(() => today(tz, 1));
  const [from, setFrom] = useState(19 * 60);
  const [to, setTo] = useState(21 * 60);
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  if (card.challenge !== 'available') {
    return <p className="tile bg-surface p-5 text-ink-secondary">{challengeReasons[card.challenge] ?? 'You can’t challenge this player right now.'}</p>;
  }
  if (!open) {
    return (
      <div>
        <Button variant="quiet" onClick={() => setOpen(true)}>Challenge to singles</Button>
      </div>
    );
  }

  async function send(event: SubmitEvent) {
    event.preventDefault();
    const starts = zoned(date, from, tz);
    const ends = zoned(date, to, tz);
    const length = (ends.getTime() - starts.getTime()) / 3600000;
    if (!court) return setError('Pick a court.');
    if (length < 1 || length > 3) return setError('Pick 1 to 3 hours.');
    if (starts.getTime() < Date.now() + 2 * 3600000) return setError('Pick a start at least 2 hours from now.');
    setBusy(true);
    const { error } = await supabase!.rpc('send_challenge', {
      p_target: card.id, p_venue: court.id, p_starts_at: starts.toISOString(), p_ends_at: ends.toISOString(), p_message: message,
    });
    setBusy(false);
    if (error) return setError(problem(error));
    toast(`Challenge sent to ${card.nickname}`);
    setOpen(false);
    onChange();
  }

  return (
    <form onSubmit={send} noValidate aria-labelledby="challenge" className="sticker grid gap-4 p-6">
      <h2 id="challenge" className="text-lg font-black">Challenge {card.nickname} to singles</h2>
      <div className="grid gap-2">
        <p className="font-extrabold">Court</p>
        {court ? (
          <button type="button" onClick={() => setCourt(undefined)} aria-pressed="true" aria-label={`Change court: ${court.name}`} className="toggle justify-self-start">
            {court.name} <span aria-hidden="true">×</span>
          </button>
        ) : (
          <CourtSearch onPick={setCourt} label="Court" />
        )}
      </div>
      <div className="grid gap-3 sm:grid-cols-3">
        <Field label="Day">
          {(props) => <input {...props} type="date" value={date} min={today(tz)} max={today(tz, 13)} onChange={(e) => setDate(e.target.value)} className="field" />}
        </Field>
        <Field label="From">
          {(props) => (
            <select {...props} value={from} onChange={(e) => setFrom(Number(e.target.value))} className="field">
              {halfHours.map((h) => <option key={h.minutes} value={h.minutes}>{h.label}</option>)}
            </select>
          )}
        </Field>
        <Field label="Until">
          {(props) => (
            <select {...props} value={to} onChange={(e) => setTo(Number(e.target.value))} className="field">
              {halfHours.map((h) => <option key={h.minutes} value={h.minutes}>{h.label}</option>)}
            </select>
          )}
        </Field>
      </div>
      <Field label="Message (optional)" hint="Up to 60 characters. No phone numbers or links.">
        {(props) => <input {...props} value={message} maxLength={60} onChange={(e) => setMessage(e.target.value)} className="field" />}
      </Field>
      <p className="text-sm text-ink-tertiary">They have 48 hours to answer. If they say no or don’t answer, you’ll just see it didn’t happen.</p>
      {error && <p role="alert" className="font-bold text-danger">{error}</p>}
      <div className="flex flex-wrap gap-2">
        <Button busy={busy}>Send challenge</Button>
        <Button type="button" variant="quiet" onClick={() => setOpen(false)}>Cancel</Button>
      </div>
    </form>
  );
}
