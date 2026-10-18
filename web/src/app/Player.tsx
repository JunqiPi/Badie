import { useState, type SubmitEvent } from 'react';
import { gapText, tier } from './assessment';
import { t } from './i18n';
import { CourtSearch, type Court } from './pickers';
import { Link } from './router';
import { avatarUrl, problem, supabase, useLive, type Friend, type Mode, type PlayerCard } from './supabase';
import { day, halfHours, today, zoned } from './time';
import { Button, EmptyState, Field, Skeleton, toast } from './ui';
import { kindLabel } from './Verification';

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
      <EmptyState title={t('Player not found')} action={<Link to="/games/" className="button">{t('My games')}</Link>}>
        {t('You can see players you’ve been matched or played with, and your friends.')}
      </EmptyState>
    );
  }
  const level = tier(card.rating);
  const rate = card.win_rate;

  return (
    <div className="grid max-w-2xl gap-6">
      <button onClick={() => history.back()} className="link justify-self-start text-sm">{t('Back')}</button>

      <section aria-labelledby="player" className="sticker grid gap-4 p-6 sm:p-8">
        <div className="flex items-start gap-5">
          {card.avatar && (
            <img src={avatarUrl(card.avatar)} alt="" width={88} height={88} className="size-22 shrink-0 rounded-full border-2 border-stroke object-cover" />
          )}
          <div className="min-w-0">
            <p className="eyebrow">{card.relationship === 'friend' ? t('Friend') : t('Player')}</p>
            <h1 id="player" className="display mt-2 text-[clamp(2.5rem,7vw,4rem)] break-words">{card.nickname}</h1>
            <p className="mt-2 text-lg font-black">
              {t('Level {level}', { level: level.label })} · {level.name}
              {!card.assessed && <span className="font-semibold text-ink-tertiary"> {t('(not assessed yet)')}</span>}
            </p>
          </div>
        </div>
        {card.avatar && <RemovePhoto userId={card.id} onDone={refresh} />}
        <ul className="flex flex-wrap gap-2" aria-label={t('Highlights')}>
          {card.verified && <li className="chip bg-mint" title={kindLabel(card.verified)}>{t('Verified level')}</li>}
          {card.new_player ? <li className="chip bg-sky">{t('New player')}</li> : card.reliable && <li className="chip bg-mint">{t('Reliable')}</li>}
          <li className="chip bg-surface-muted text-ink">{t(card.games_band)}</li>
          {card.tags.map((tag) => <li key={tag} className="chip bg-lavender">{t(tagLabels[tag] ?? tag)}</li>)}
        </ul>
        {card.relationship !== 'self' && <Actions card={card} onChange={refresh} />}
        {card.relationship !== 'self' && card.relationship !== 'friend' && <MessageOption card={card} />}
      </section>

      {rate && (
        <section aria-labelledby="winrate" className="tile grid gap-2 bg-surface p-6">
          <h2 id="winrate" className="eyebrow">{t('This month')}</h2>
          <p className="text-lg font-black">
            {rate.games ? t('{n}% wins', { n: Math.round((rate.wins / rate.games) * 100) }) : t('No confirmed games yet')}
            <span className="font-semibold text-ink-secondary"> · {rate.wins}–{rate.games - rate.wins}</span>
          </p>
          {rate.games > 0 && (
            <p className="text-ink-secondary">
              {t('{n} game|{n} games', { n: rate.games })} · {t('{n} opponent|{n} opponents', { n: rate.opponents })} · {gapText(rate.gap)}
            </p>
          )}
          {card.relationship === 'self' && !rate.public && <p className="text-sm text-ink-tertiary">{t('Others see this from 5 confirmed games.')}</p>}
        </section>
      )}

      {card.challenge !== 'hidden' && <Challenge card={card} onChange={refresh} />}

      {card.relationship !== 'self' && (
        <section aria-labelledby="together" className="tile grid gap-2 bg-surface p-6">
          <h2 id="together" className="eyebrow">{t('You and {name}', { name: card.nickname })}</h2>
          <p className="font-bold">
            {card.games_together === 0 ? t('No games together yet') : t('{n} game together|{n} games together', { n: card.games_together })}
            {card.last_game && (
              <span className="font-semibold text-ink-secondary">
                {' · '}{t('last on {date} at {venue}', { date: day(card.last_game.starts_at, card.last_game.tz), venue: card.last_game.venue })}
              </span>
            )}
          </p>
          {card.mutual_friends > 0 && <p className="text-ink-secondary">{t('{n} friend in common|{n} friends in common', { n: card.mutual_friends })}</p>}
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

/** 管理员：撤下不合适的照片 */
function RemovePhoto({ userId, onDone }: { userId: string; onDone: () => void }) {
  const { data: admin } = useLive<boolean>('is_admin', { every: 3_600_000 });
  const [busy, setBusy] = useState(false);
  if (!admin) return null;
  async function remove() {
    setBusy(true);
    const { error } = await supabase!.rpc('admin_clear_avatar', { p_user: userId });
    setBusy(false);
    if (error) return toast(problem(error), 'error');
    toast(t('Photo removed'));
    onDone();
  }
  return <Button variant="quiet" busy={busy} onClick={remove} className="justify-self-start">{t('Remove photo (admin)')}</Button>;
}

/** 不是球友时的私信入口：同球群可以发一条消息请求 */
function MessageOption({ card }: { card: PlayerCard }) {
  const { status, group } = card.message;
  if (status === 'open') return <Link to={`/messages/dm/${card.id}/`} className="button button-quiet justify-self-start">{t('Message')}</Link>;
  if (status === 'requested') return <p className="text-sm font-bold text-ink-secondary">{t('Message request sent')}</p>;
  if (status === 'new_account') return <p className="text-sm text-ink-tertiary">{t('After 3 games you can send message requests to people in your groups.')}</p>;
  if (status !== 'request') return null;
  return (
    <div className="grid justify-items-start gap-1">
      <Link to={`/messages/dm/${card.id}/`} className="button button-quiet">{t('Send a message request')}</Link>
      <p className="text-sm text-ink-tertiary">{t('You’re both in {group}.', { group: group ?? '' })}</p>
    </div>
  );
}

function Actions({ card, onChange }: { card: PlayerCard; onChange: () => void }) {
  const { busy, run } = useAction(onChange);
  const [confirmRemove, setConfirmRemove] = useState(false);
  const user = { p_user: card.id };

  switch (card.relationship) {
    case 'friend':
      return (
        <div className="flex flex-wrap gap-3">
          <Link to={`/messages/dm/${card.id}/`} className="button">{t('Message')}</Link>
          {confirmRemove ? (
            <Button variant="quiet" busy={busy === 'remove'} onClick={() => run('remove', 'remove_friend', user, t('Removed from friends'))}>
              {t('Yes, remove friend')}
            </Button>
          ) : (
            <Button variant="quiet" onClick={() => setConfirmRemove(true)}>{t('Remove friend')}</Button>
          )}
        </div>
      );
    case 'incoming':
      return (
        <div className="flex flex-wrap items-center gap-3">
          <p className="w-full font-bold">{t('{name} wants to be friends.', { name: card.nickname })}</p>
          <Button busy={busy === 'accept'} onClick={() => run('accept', 'respond_friend_request', { ...user, p_accept: true }, t('You’re now friends'))}>{t('Accept')}</Button>
          <Button variant="quiet" busy={busy === 'ignore'} onClick={() => run('ignore', 'respond_friend_request', { ...user, p_accept: false })}>{t('Ignore')}</Button>
        </div>
      );
    case 'requested':
      return <p className="font-bold text-ink-secondary">{t('Friend request sent')}</p>;
    case 'blocked':
      return <Button variant="quiet" busy={busy === 'unblock'} onClick={() => run('unblock', 'unblock_user', user, t('Unblocked'))}>{t('Unblock')}</Button>;
    default:
      return (
        <div>
          <Button busy={busy === 'add'} onClick={() => run('add', 'send_friend_request', user, t('Friend request sent'))}>{t('Add friend')}</Button>
          <p className="mt-2 text-sm text-ink-tertiary">{t('Friends can message each other. Players who both pick “play again” after a game become friends automatically.')}</p>
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
      <h2 id="safety" className="eyebrow">{t('Safety')}</h2>
      {step === 'block' ? (
        <>
          <p className="font-bold" role="alert">
            {t('You won’t be matched with {name} again, and you’ll stop being friends. They won’t be told.', { name: card.nickname })}
          </p>
          <div className="flex flex-wrap gap-2">
            <Button variant="danger" busy={busy === 'block'} onClick={() => run('block', 'block_user', { p_user: card.id }, t('Blocked')).then(() => setStep(undefined))}>{t('Block')}</Button>
            <Button variant="quiet" onClick={() => setStep(undefined)}>{t('Cancel')}</Button>
          </div>
        </>
      ) : step === 'report' ? (
        <form
          className="grid gap-3"
          onSubmit={(e) => {
            e.preventDefault();
            run('report', 'report_user', { p_user: card.id, p_reason: reason, p_details: details }, t('Thanks. Our team will look into it.')).then((ok) => ok && setStep(undefined));
          }}
        >
          <fieldset className="grid gap-2">
            <legend className="mb-1 font-extrabold">{t('What happened?')}</legend>
            {reasons.map(([value, label]) => (
              <label key={value} className="flex items-center gap-3 font-semibold">
                <input type="radio" name="reason" value={value} checked={reason === value} onChange={() => setReason(value)} className="size-5 accent-[var(--color-lime)]" />
                {t(label)}
              </label>
            ))}
          </fieldset>
          <label className="grid gap-1.5">
            <span className="font-extrabold">{t('Details')} <span className="font-semibold text-ink-tertiary">{t('(optional)')}</span></span>
            <textarea value={details} onChange={(e) => setDetails(e.target.value)} maxLength={1000} rows={3} className="field" />
          </label>
          <div className="flex flex-wrap gap-2">
            <Button busy={busy === 'report'}>{t('Send report')}</Button>
            <Button type="button" variant="quiet" onClick={() => setStep(undefined)}>{t('Cancel')}</Button>
          </div>
        </form>
      ) : (
        <div className="flex flex-wrap gap-2">
          {card.relationship !== 'blocked' && <Button variant="quiet" onClick={() => setStep('block')}>{t('Block')}</Button>}
          <Button variant="quiet" onClick={() => setStep('report')}>{t('Report')}</Button>
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

/** 双打的搭档：自己的球友，不能是对面的人 */
export function PartnerSelect({ exclude, value, onChange }: { exclude: string[]; value: string; onChange: (id: string) => void }) {
  const { data } = useLive<{ friends: Friend[] }>('my_friends', { every: 300_000 });
  const friends = data?.friends.filter((f) => !exclude.includes(f.id));
  if (friends?.length === 0) return <p className="font-semibold">{t('Add a friend first to play doubles.')}</p>;
  return (
    <Field label={t('Your partner')} hint={t('A friend who’s free then.')}>
      {(props) => (
        <select {...props} value={value} onChange={(e) => onChange(e.target.value)} className="field">
          <option value="">{t('Pick a friend')}</option>
          {friends?.map((f) => <option key={f.id} value={f.id}>{f.nickname}</option>)}
        </select>
      )}
    </Field>
  );
}

/** 约战：单打或带一位球友打双打；选球馆和时间，对方 48 小时内回应 */
function Challenge({ card, onChange }: { card: PlayerCard; onChange: () => void }) {
  const [open, setOpen] = useState(false);
  const [mode, setMode] = useState<Mode>('singles');
  const [partner, setPartner] = useState('');
  const [court, setCourt] = useState<Court>();
  const tz = court?.time_zone_id ?? Intl.DateTimeFormat().resolvedOptions().timeZone;
  const [date, setDate] = useState(() => today(tz, 1));
  const [from, setFrom] = useState(19 * 60);
  const [to, setTo] = useState(21 * 60);
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  if (card.challenge !== 'available') {
    return <p className="tile bg-surface p-5 text-ink-secondary">{t(challengeReasons[card.challenge] ?? 'You can’t challenge this player right now.')}</p>;
  }
  if (!open) {
    return (
      <div>
        <Button variant="quiet" onClick={() => setOpen(true)}>{t('Challenge')}</Button>
      </div>
    );
  }

  async function send(event: SubmitEvent) {
    event.preventDefault();
    const starts = zoned(date, from, tz);
    const ends = zoned(date, to, tz);
    const length = (ends.getTime() - starts.getTime()) / 3600000;
    if (!court) return setError(t('Pick a court.'));
    if (mode === 'doubles' && !partner) return setError(t('Pick your partner.'));
    if (length < 1 || length > 3) return setError(t('Pick 1 to 3 hours.'));
    if (starts.getTime() < Date.now() + 2 * 3600000) return setError(t('Pick a start at least 2 hours from now.'));
    setBusy(true);
    const { error } = await supabase!.rpc('send_challenge', {
      p_target: card.id, p_venue: court.id, p_starts_at: starts.toISOString(), p_ends_at: ends.toISOString(), p_message: message,
      p_partner: mode === 'doubles' ? partner : null,
    });
    setBusy(false);
    if (error) return setError(problem(error));
    toast(t('Challenge sent to {name}', { name: card.nickname }));
    setOpen(false);
    onChange();
  }

  const times = halfHours();
  return (
    <form onSubmit={send} noValidate aria-labelledby="challenge" className="sticker grid gap-4 p-6">
      <h2 id="challenge" className="text-lg font-black">
        {mode === 'doubles' ? t('Challenge {name} to doubles', { name: card.nickname }) : t('Challenge {name} to singles', { name: card.nickname })}
      </h2>
      <div role="group" aria-label={t('Game type')} className="flex gap-2">
        {(['singles', 'doubles'] as const).map((value) => (
          <button key={value} type="button" onClick={() => setMode(value)} aria-pressed={mode === value} className="toggle">
            {value === 'doubles' ? t('Doubles') : t('Singles')}
          </button>
        ))}
      </div>
      {mode === 'doubles' && (
        <>
          <PartnerSelect exclude={[card.id]} value={partner} onChange={setPartner} />
          <p className="text-sm text-ink-tertiary">{t('{name} picks a partner when they accept.', { name: card.nickname })}</p>
        </>
      )}
      <div className="grid gap-2">
        <p className="font-extrabold">{t('Court')}</p>
        {court ? (
          <button type="button" onClick={() => setCourt(undefined)} aria-pressed="true" aria-label={t('Change court: {name}', { name: court.name })} className="toggle justify-self-start">
            {court.name} <span aria-hidden="true">×</span>
          </button>
        ) : (
          <CourtSearch onPick={setCourt} label={t('Court')} />
        )}
      </div>
      <div className="grid gap-3 sm:grid-cols-3">
        <Field label={t('Day')}>
          {(props) => <input {...props} type="date" value={date} min={today(tz)} max={today(tz, 13)} onChange={(e) => setDate(e.target.value)} className="field" />}
        </Field>
        <Field label={t('From')}>
          {(props) => (
            <select {...props} value={from} onChange={(e) => setFrom(Number(e.target.value))} className="field">
              {times.map((h) => <option key={h.minutes} value={h.minutes}>{h.label}</option>)}
            </select>
          )}
        </Field>
        <Field label={t('Until')}>
          {(props) => (
            <select {...props} value={to} onChange={(e) => setTo(Number(e.target.value))} className="field">
              {times.map((h) => <option key={h.minutes} value={h.minutes}>{h.label}</option>)}
            </select>
          )}
        </Field>
      </div>
      <Field label={t('Message (optional)')} hint={t('Up to 60 characters. No phone numbers or links.')}>
        {(props) => <input {...props} value={message} maxLength={60} onChange={(e) => setMessage(e.target.value)} className="field" />}
      </Field>
      <p className="text-sm text-ink-tertiary">{t('They have 48 hours to answer. If they say no or don’t answer, you’ll just see it didn’t happen.')}</p>
      {error && <p role="alert" className="font-bold text-danger">{error}</p>}
      <div className="flex flex-wrap gap-2">
        <Button busy={busy}>{t('Send challenge')}</Button>
        <Button type="button" variant="quiet" onClick={() => setOpen(false)}>{t('Cancel')}</Button>
      </div>
    </form>
  );
}
