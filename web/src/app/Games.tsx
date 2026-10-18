import { useState } from 'react';
import { GameTicket, RequestCard, RoomCard } from './cards';
import { money } from './Courts';
import { toReview } from './Home';
import { currentLocale, t } from './i18n';
import { Icon, type IconName } from './icons';
import { ArrowLabel, Avatar, AvatarStack, Empty, IconButton, IconTile, LargeTitle, LevelBadge, Notice, ScreenHeader, SectionTitle, Segmented, Starburst, StatTile, Tag, fill, type Tint } from './kit';
import { PartnerSelect } from './Player';
import { Reviews } from './Review';
import { Link } from './router';
import { problem, supabase, useLive, type Game, type MyChallenges, type MyGroups, type Outcome, type PlayRecord, type RoomSummary, type Ticket } from './supabase';
import { day, dayName, hours, timeOf } from './time';
import { Button, Field, Skeleton, toast } from './ui';

const live = (g: Game) => g.status === 'scheduled' && new Date(g.ends_at).getTime() > Date.now();

type Segment = 'upcoming' | 'ended';

/** 球局 tab（iOS 的 GamesView）：三个入口、待评价、我的固定局和房间、即将开始 / 已结束 */
export function Games() {
  const { data: games, failed } = useLive<Game[]>('my_games');
  const { data: requests } = useLive<Ticket[]>('my_matchmaking');
  const { data: challenges } = useLive<MyChallenges>('my_challenges', { every: 60_000 });
  const { data: groups } = useLive<MyGroups>('my_groups', { every: 120_000 });
  const { data: rooms } = useLive<RoomSummary[]>('my_rooms', { every: 60_000 });
  const [segment, setSegment] = useState<Segment>(new URLSearchParams(location.search).get('tab') === 'ended' ? 'ended' : 'upcoming');
  const upcoming = games?.filter(live).reverse() ?? [];
  const past = games?.filter((g) => !live(g)) ?? [];
  const reviews = games?.filter(toReview) ?? [];
  const open = requests?.filter((r) => ['searching', 'offered', 'paused'].includes(r.status)) ?? [];
  const incoming = challenges?.incoming.length ?? 0;
  const list = segment === 'upcoming' ? upcoming : past;

  return (
    <div className="grid gap-6">
      <LargeTitle title={t('Games')} subtitle={t('My games and rooms')}>
        <IconButton icon="challenge" label={t('Challenges')} badge={incoming} to="/challenges/" />
        <IconButton icon="trophy" label={t('Leaderboard')} to="/rankings/" />
      </LargeTitle>

      {incoming > 0 && (
        <Notice icon="challenge" tint="peach" action={{ label: t('Take a look'), to: '/challenges/' }}>
          {t('{n} challenge awaiting reply|{n} challenges awaiting reply', { n: incoming })}
        </Notice>
      )}

      <ul className="grid grid-cols-3 gap-3">
        {shortcuts.map((s) => (
          <li key={s.to}>
            <Link to={s.to} className={`sticker lift grid h-full content-start gap-2 p-4 ${fill[s.tint]}`}>
              <Icon name={s.icon} className="size-6" />
              <span className="text-headline">{t(s.title)}</span>
              <span className="text-caption opacity-80">{t(s.subtitle)}</span>
            </Link>
          </li>
        ))}
      </ul>

      {reviews.length > 0 && (
        <Link to={`/games/${reviews[0].id}/`} className="sticker lift flex items-center gap-3 bg-pink p-4 text-on-accent">
          <Icon name="star" className="size-5" />
          <span className="flex-1 text-footnote font-bold">{t('{n} player is waiting for your review (within 48 hours)|{n} players are waiting for your review (within 48 hours)', { n: reviews.reduce((sum, g) => sum + g.players.filter((p) => !p.me && !p.reviewed).length, 0) })}</span>
          <Icon name="chevronRight" className="size-4" />
        </Link>
      )}

      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_24rem] lg:items-start lg:gap-8">
        <section aria-labelledby="mine" className="grid min-w-0 gap-3">
          <h2 id="mine" className="sr-only">{t('My games')}</h2>
          <Segmented
            label={t('My games')}
            value={segment}
            onChange={(next) => {
              setSegment(next);
              history.replaceState(null, '', next === 'ended' ? '/games/?tab=ended' : '/games/');
            }}
            options={[
              { value: 'upcoming', label: t('Upcoming'), badge: upcoming.length },
              { value: 'ended', label: t('Ended') },
            ]}
          />
          {games === undefined && !failed && [0, 1].map((i) => <Skeleton key={i} className="h-24" />)}
          {failed && games === undefined && <Empty icon="warning" tint="peach" title={t('Couldn’t load your games')}>{t('Check your connection and try again.')}</Empty>}
          {games && list.length === 0 && (
            segment === 'upcoming' ? (
              <Empty icon="calendar" tint="sky" title={t('No games coming up')} action={{ label: t('Quick Match'), to: '/play/' }}>
                {t('Find a buddy with Quick Match, or start a game for nearby players to join.')}
              </Empty>
            ) : (
              <Empty icon="clock" tint="sky" title={t('No past games yet')}>{t('Finished games and their results show up here.')}</Empty>
            )
          )}
          <div key={segment} className="animate-enter grid gap-3">
            {list.map((g) => <GameRow key={g.id} game={g} />)}
          </div>
        </section>

        <aside className="grid min-w-0 gap-6" aria-label={t('More')}>
          {open.length > 0 && (
            <section aria-labelledby="waiting" className="grid gap-2">
              <SectionTitle id="waiting" title={t('Waiting for a match')} detail={t('Shows below once everyone confirms')} />
              {open.map((r) => <RequestCard key={r.id} request={r} />)}
            </section>
          )}
          {groups && groups.sessions.length > 0 && (
            <section aria-labelledby="sessions" className="grid gap-2">
              <SectionTitle id="sessions" title={t('My weekly sessions')} action={{ label: t('Groups'), to: '/groups/' }} />
              {groups.sessions.map((s) => (
                <Link key={s.id} to={`/groups/${s.group_id}/`} className="sticker lift grid gap-1 bg-lime/45 p-4">
                  <span className="flex items-center gap-1.5 text-footnote font-bold text-ink-secondary"><Icon name="group" className="size-4" />{s.group}</span>
                  <span className="text-headline">{dayName(s.starts_at, s.tz)} · {hours(s.starts_at, s.ends_at, s.tz)}</span>
                  <span className="text-footnote font-bold">{s.waitlisted ? t('On the waitlist') : t('Signed up ✓')}</span>
                </Link>
              ))}
            </section>
          )}
          {rooms && rooms.length > 0 && (
            <section aria-labelledby="rooms" className="grid gap-2">
              <SectionTitle id="rooms" title={t('My rooms')} detail={t('{n} active', { n: rooms.length })} />
              {rooms.map((r) => <RoomCard key={r.id} room={r} wide />)}
            </section>
          )}
          <WeeklyMini />
        </aside>
      </div>
    </div>
  );
}

const shortcuts: { to: string; icon: IconName; tint: Tint; title: string; subtitle: string }[] = [
  { to: '/rooms/new/', icon: 'court', tint: 'peach', title: 'Start a game', subtitle: 'Have a court, need players' },
  { to: '/groups/', icon: 'group', tint: 'sky', title: 'Regular games', subtitle: 'Weekly groups' },
  { to: '/join/', icon: 'hash', tint: 'lavender', title: 'Room code', subtitle: 'Room code or group ID' },
];

/** 本月战绩小卡（在球局页右栏） */
function WeeklyMini() {
  const { data: record } = useLive<PlayRecord>('my_record', { every: 300_000 });
  if (!record) return null;
  return (
    <section aria-labelledby="month" className="grid gap-2">
      <SectionTitle id="month" title={t('This month')} action={{ label: t('Leaderboard'), to: '/rankings/' }} />
      <div className="grid grid-cols-3 gap-2">
        <StatTile tint="lime" value={record.games ? `${Math.round((record.wins / record.games) * 100)}%` : '–'} label={t('Win rate')} />
        <StatTile tint="butter" value={`${record.wins}–${record.losses}`} label={t('W–L')} />
        <StatTile tint="peach" value={record.games_played} label={t('Played')} />
      </div>
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

/** 一场球（iOS 的 GameRowCard）：左边日期块，右边模式时间、球馆、头像和状态 */
function GameRow({ game: g }: { game: Game }) {
  const started = new Date(g.starts_at).getTime() < Date.now();
  const rate = toReview(g);
  const tz = g.venue.tz;
  const date = new Date(g.starts_at);
  const weekday = new Intl.DateTimeFormat(currentLocale(), { weekday: 'short', timeZone: tz ?? undefined }).format(date);
  const dayNumber = new Intl.DateTimeFormat('en', { day: 'numeric', timeZone: tz ?? undefined }).format(date);
  const tint = g.status === 'cancelled' ? 'bg-surface-muted text-ink' : started ? 'bg-mint text-on-accent' : 'bg-peach text-on-accent';
  const others = g.players.filter((p) => !p.me);
  return (
    <Link to={`/games/${g.id}/`} className="sticker lift flex items-center gap-3 p-3">
      <span className={`grid h-[62px] w-14 shrink-0 place-content-center justify-items-center rounded-[14px] border-2 border-stroke ${tint}`}>
        <span className="text-caption">{weekday}</span>
        <span className="text-[1.5rem] leading-none font-black tabular-nums">{dayNumber}</span>
      </span>
      <span className="grid min-w-0 flex-1 gap-1">
        <span className="flex items-center gap-1.5">
          <span className="truncate text-headline tabular-nums">{g.mode === 'doubles' ? t('Doubles') : t('Singles')} · {timeOf(g.starts_at, tz)}–{timeOf(g.ends_at, tz)}</span>
          {g.status === 'cancelled' && <Tag tint="muted">{t('Cancelled')}</Tag>}
        </span>
        <span className="truncate text-footnote text-ink-secondary">{g.venue.name}</span>
        <span className="flex items-center gap-1.5">
          <AvatarStack people={others} size={24} />
          {rate ? <Tag icon="star" tint="pink">{t('Rate players')}</Tag>
            : started && g.status === 'scheduled' ? (
              <Tag tint={g.result.status === 'verified' ? 'mint' : g.result.status === 'disputed' ? 'pink' : 'butter'}>
                {g.result.status === 'verified' && g.result.outcome !== 'friendly'
                  ? g.result.outcome === (g.my_team === 1 ? 'team1' : 'team2') ? t('Won') : t('Lost')
                  : t(resultText[g.result.status])}
                {g.score ? ` · ${g.score}` : ''}
              </Tag>
            ) : null}
        </span>
      </span>
      <Icon name="chevronRight" className="size-4 text-ink-tertiary" />
    </Link>
  );
}

export function GameDetail({ id }: { id: string }) {
  const { data: games, refresh } = useLive<Game[]>('my_games');
  const game = games?.find((g) => g.id === id);
  if (!games) return <Skeleton className="h-96" />;
  if (!game) {
    return <Empty icon="question" tint="butter" title={t('Game not found')} action={{ label: t('Games'), to: '/games/' }}>{t('It may be older than 60 days.')}</Empty>;
  }
  return <GameView game={game} onChange={refresh} />;
}

/** 双方阵容：头像 + 名字 + 等级，中间一个 VS 星形 */
export function Lineup({ players, mode }: { players: Game['players']; mode: Game['mode'] }) {
  const teams = [1, 2].map((team) => players.filter((p) => p.team === team));
  return (
    <div className="grid grid-cols-[1fr_auto_1fr] items-center gap-3">
      {teams.map((team, i) => (
        <ul key={i} className={`grid gap-3 ${i === 1 ? 'order-3' : ''}`} aria-label={mode === 'doubles' ? t('Team {n}', { n: i + 1 }) : undefined}>
          {team.map((p) => (
            <li key={p.id} className={`flex min-w-0 items-center gap-2.5 ${i === 1 ? 'flex-row-reverse text-right' : ''}`}>
              <Link to={p.me ? '/me/' : `/players/${p.id}/`} className="press shrink-0 rounded-full">
                <Avatar id={p.id} name={p.nickname} size={48} />
              </Link>
              <span className={`grid min-w-0 gap-0.5 ${i === 1 ? 'justify-items-end' : 'justify-items-start'}`}>
                <span className="max-w-full truncate font-bold">{p.me ? t('You') : p.nickname}</span>
                <LevelBadge rating={p.rating} named={false} compact />
                {p.checked_in && <span className="text-caption font-bold text-ink-secondary">✓ {t('checked in')}</span>}
              </span>
            </li>
          ))}
        </ul>
      ))}
      <span className="order-2"><Starburst size={54}>VS</Starburst></span>
    </div>
  );
}

function GameView({ game: g, onChange }: { game: Game; onChange: () => Promise<void> }) {
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

  async function act(name: string, fn: string, args: Record<string, unknown>, done: string) {
    setBusy(name);
    const { error } = await supabase!.rpc(fn, args);
    setBusy(undefined);
    if (error) toast(problem(error), 'error');
    else toast(done);
    await onChange();
  }

  const players = g.mode === 'doubles' ? 4 : 2;
  const hoursLong = (end - start) / 3600000;
  const cost = g.venue.pricing?.perPerson ?? (g.venue.pricing?.perCourtHour ? (g.venue.pricing.perCourtHour * hoursLong) / players : undefined);

  return (
    <div className="grid gap-6">
      <ScreenHeader title={g.mode === 'doubles' ? t('Doubles game') : t('Singles game')} back="/games/" />
      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_24rem] lg:items-start lg:gap-8">
        <div className="grid min-w-0 gap-6">
          <GameTicket game={g} />

          <section aria-labelledby="players" className="sticker grid gap-4 p-5">
            <h2 id="players" className="text-headline">{t('Players')}</h2>
            <Lineup players={g.players} mode={g.mode} />
          </section>

          {scheduled && now >= start && <Result game={g} canReport={canReport} busy={busy} act={act} />}
          {toReview(g) && <Reviews game={g} onDone={onChange} />}
        </div>

        <aside className="grid min-w-0 gap-4" aria-label={t('More')}>
          {scheduled && (canCheckIn || g.checked_in || now < start) && (
            <section aria-label={t('Check in')} className={`sticker grid gap-3 p-5 ${g.checked_in ? 'bg-mint text-on-accent' : canCheckIn ? 'bg-lime text-on-accent' : ''}`}>
              {g.checked_in ? (
                <p className="flex items-center gap-2 text-headline"><Icon name="checkCircle" className="size-6" />{t('You’re checked in.')}</p>
              ) : canCheckIn ? (
                <Button className="button-lg button-inverse" busy={busy === 'checkin'} onClick={() => act('checkin', 'check_in', { p_game: g.id }, t('Checked in'))}>
                  <ArrowLabel>{t('I’m here')}</ArrowLabel>
                </Button>
              ) : (
                <p className="flex items-start gap-2 text-footnote font-bold text-ink-secondary"><Icon name="clock" className="size-5 shrink-0" />{t('Check in when you arrive. It opens 30 minutes before the start.')}</p>
              )}
            </section>
          )}

          {scheduled && now <= end + 48 * 3600000 && (
            <Link to={`/messages/game/${g.id}/`} className="button button-lg w-full"><Icon name="chats" className="size-5" />{t('Message players')}</Link>
          )}

          <section aria-labelledby="court" className="sticker grid gap-3 p-5">
            <div className="flex items-start gap-3">
              <IconTile icon="pin" tint="sky" />
              <div className="min-w-0">
                <h2 id="court" className="text-headline">{g.venue.name}</h2>
                <p className="text-footnote text-ink-secondary">{[g.venue.street, g.venue.city].filter(Boolean).join(', ')}</p>
              </div>
            </div>
            {cost !== undefined && (
              <p className="flex items-center gap-2 text-footnote font-bold">
                <Icon name="coins" className="size-4" />
                {t('About {price} each', { price: money(Math.ceil(cost), g.venue.country) })}
                <span className="font-semibold text-ink-tertiary">{t('(split at the court)')}</span>
              </p>
            )}
            <a className="button button-quiet" href={`https://maps.apple.com/?q=${encodeURIComponent(g.venue.name)}&ll=${g.venue.lat},${g.venue.lon}`}>
              <Icon name="locate" className="size-4" />{t('Directions')}
            </a>
          </section>

          {scheduled && <Fees game={g} busy={busy} act={act} />}

          {canCancel && (
            <section aria-label={t('Can’t make it')} className="grid gap-3">
              {confirmCancel ? (
                <div className="sticker grid gap-3 bg-pink p-4 text-on-accent">
                  <p className="font-bold" role="alert">
                    {late ? t('The game starts in under 2 hours, so this counts as a late cancellation.') : t('The other players will be put back in the queue first.')}
                  </p>
                  <div className="flex flex-wrap gap-2">
                    <Button variant="danger" busy={busy === 'cancel'} onClick={() => act('cancel', 'cancel_game', { p_game: g.id }, t('Game cancelled'))}>{t('Cancel game')}</Button>
                    <Button variant="quiet" onClick={() => setConfirmCancel(false)}>{t('Keep it')}</Button>
                  </div>
                </div>
              ) : (
                <Button variant="quiet" onClick={() => setConfirmCancel(true)}>{t('Can’t make it')}</Button>
              )}
            </section>
          )}
        </aside>
      </div>
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
  const [score, setScore] = useState(g.my_report?.score ?? '');
  const { status, outcome } = g.result;
  const choices: [Outcome | null, string][] = [[mine, 'We won'], [theirs, 'We lost'], ['friendly', 'Just for fun'], [null, 'Can’t remember']];
  const summary =
    status === 'verified'
      ? outcome === 'friendly' ? t('Confirmed: a friendly game, no winner.') : outcome === mine ? t('Confirmed: you won.') : t('Confirmed: you lost.')
      : status === 'disputed'
        ? t('Your reports don’t match. Either side can change theirs within 7 days of the game.')
        : status === 'unsure'
          ? t('One side doesn’t remember the result, so this game won’t count.')
          : status === 'expired'
            ? t('No result was agreed within 7 days.')
            : g.my_report
              ? t('Waiting for the other side to report.')
              : t('How did it go? The result counts once both sides agree.');

  return (
    <section aria-labelledby="result" className={`sticker grid gap-4 p-5 ${status === 'verified' ? 'bg-mint text-on-accent' : status === 'disputed' ? 'bg-pink text-on-accent' : ''}`}>
      <div className="flex items-center gap-3">
        <IconTile icon="trophy" tint={status === 'verified' ? 'surface' : 'butter'} />
        <h2 id="result" className="text-headline">{t('Result')}</h2>
        {g.score && <span className="ml-auto text-title3 tabular-nums">{g.score}</span>}
      </div>
      <p role="status" className="text-subhead font-bold">{summary}</p>
      {canReport && (
        <Field label={t('Score (optional)')} hint={t('Pick the result below to save it.')}>
          {(props) => <input {...props} value={score} maxLength={40} inputMode="numeric" placeholder="21:18 19:21 21:15"
                             onChange={(e) => setScore(e.target.value)} className="field max-w-xs tabular-nums" />}
        </Field>
      )}
      {canReport && (
        <div className="flex flex-wrap gap-2" role="group" aria-label={t('Report the result')}>
          {choices.map(([value, label]) => (
            <button
              key={label}
              onClick={() => act('report', 'report_result', { p_game: g.id, p_outcome: value, p_score: score }, t('Result saved'))}
              disabled={Boolean(busy)}
              aria-pressed={g.my_report !== null && reported === value}
              className="toggle"
            >
              {t(label)}
            </button>
          ))}
        </div>
      )}
    </section>
  );
}

/** 场地费 AA：只是记账。自己标自己，房间开的局房主可以替所有人标 */
function Fees({ game: g, busy, act }: {
  game: Game;
  busy?: string;
  act: (name: string, fn: string, args: Record<string, unknown>, done: string) => Promise<void>;
}) {
  // 勾上马上显示，等服务器的最新数据回来再以它为准（失败会恢复原样）
  const [pending, setPending] = useState<Record<string, boolean>>({});
  const me = g.players.find((p) => p.me);
  const host = g.host_id !== null && g.host_id === me?.id;
  const isPaid = (p: Game['players'][number]) => pending[p.id] ?? Boolean(p.paid);
  const paid = g.players.filter(isPaid).length;

  async function mark(id: string, value: boolean) {
    setPending((all) => ({ ...all, [id]: value }));
    await act(`paid-${id}`, 'mark_paid', { p_game: g.id, p_user: id, p_paid: value }, t('Saved'));
    setPending(({ [id]: _, ...rest }) => rest);
  }
  return (
    <section aria-labelledby="fees" className="sticker grid gap-2 p-5">
      <h2 id="fees" className="flex items-center gap-3">
        <IconTile icon="coins" tint="butter" size="sm" />
        <span className="text-headline">{t('Court fee')}</span>
        <span className="ml-auto text-footnote font-bold text-ink-secondary tabular-nums">{t('{n} of {total} paid', { n: paid, total: g.players.length })}</span>
      </h2>
      <ul className="grid gap-1">
        {g.players.map((p) => (
          <li key={p.id}>
            <label className="flex min-h-11 items-center gap-3">
              <input type="checkbox" checked={isPaid(p)} disabled={Boolean(busy) || !(p.me || host)}
                     onChange={(e) => mark(p.id, e.target.checked)}
                     className="size-5 accent-[var(--color-lime)]" />
              <span className="min-w-0 flex-1 truncate font-bold">{p.me ? t('You') : p.nickname}</span>
              <Tag tint={isPaid(p) ? 'mint' : 'muted'}>{isPaid(p) ? t('Paid') : t('Not yet')}</Tag>
            </label>
          </li>
        ))}
      </ul>
      <p className="text-caption text-ink-tertiary">{host ? t('As the host, you can mark anyone.') : t('Mark yourself once you’ve paid your share.')}</p>
    </section>
  );
}

/** 约战（iOS 的 ChallengesView）：收到的（接受 / 拒绝）和发出的（等回应 / 未成行 / 已约成） */
export function Challenges() {
  const { data, refresh } = useLive<MyChallenges>('my_challenges', { every: 60_000 });
  const [busy, setBusy] = useState<string>();
  // 双打挑战：接受前选的搭档
  const [partners, setPartners] = useState<Record<string, string>>({});
  if (!data) return <Skeleton className="h-64" />;

  async function act(name: string, fn: string, args: Record<string, unknown>, done: string) {
    setBusy(name);
    const { error } = await supabase!.rpc(fn, args);
    setBusy(undefined);
    if (error) toast(problem(error), 'error');
    else toast(done);
    refresh();
  }

  return (
    <div className="mx-auto grid max-w-2xl gap-5">
      <ScreenHeader title={t('Challenges')} back="/games/" />
      {data.incoming.length === 0 && data.outgoing.length === 0 && (
        <Empty icon="challenge" tint="peach" title={t('No challenges')}>
          {t('Open a player’s profile and tap Challenge to propose a game. They have 48 hours to answer.')}
        </Empty>
      )}
      {data.incoming.length > 0 && <h2 className="text-title3">{t('Waiting for your answer')}</h2>}
      {data.incoming.map((c) => (
        <article key={c.id} className="sticker grid gap-3 bg-peach p-5 text-on-accent">
          <div className="flex items-center gap-3">
            <Avatar id={c.player.id} name={c.player.nickname} size={44} />
            <p className="min-w-0 flex-1 font-bold">
            <Link to={`/players/${c.player.id}/`} className="underline">{c.player.nickname}</Link>{' '}
            {c.partner ? t('and {partner} challenged you to doubles', { partner: c.partner.nickname }) : t('challenged you to singles')}
            </p>
            <Starburst size={48}>VS</Starburst>
          </div>
          <p className="text-headline">
            {day(c.starts_at, c.venue.tz)} · {hours(c.starts_at, c.ends_at, c.venue.tz)} · {c.venue.name}
          </p>
          {c.message && <p className="font-medium">“{c.message}”</p>}
          <p className="text-sm font-semibold">{t('Answer by {date}. Declining is fine, they’ll only see it didn’t happen.', { date: day(c.expires_at, c.venue.tz) })}</p>
          {c.partner && (
            <PartnerSelect exclude={[c.player.id, c.partner.id]} value={partners[c.id] ?? ''} onChange={(id) => setPartners({ ...partners, [c.id]: id })} />
          )}
          <div className="flex flex-wrap gap-2">
            <Button busy={busy === `yes-${c.id}`} disabled={Boolean(busy) || Boolean(c.partner && !partners[c.id])}
                    onClick={() => act(`yes-${c.id}`, 'respond_challenge', { p_challenge: c.id, p_accept: true, p_partner: partners[c.id] ?? null }, t('Game on!'))}>
              {t('Accept')}
            </Button>
            <Button variant="quiet" disabled={Boolean(busy)} onClick={() => act(`no-${c.id}`, 'respond_challenge', { p_challenge: c.id, p_accept: false }, t('Declined'))}>{t('Decline')}</Button>
          </div>
        </article>
      ))}
      {data.outgoing.length > 0 && <h2 className="text-title3">{t('Sent')}</h2>}
      {data.outgoing.map((c) => (
        <article key={c.id} className="sticker flex flex-wrap items-center justify-between gap-3 p-4">
          <span className="min-w-0">
            <span className="block font-bold">
              {c.partner ? t('You and {partner} challenged {name}', { partner: c.partner.nickname, name: c.player.nickname }) : t('You challenged {name}', { name: c.player.nickname })}
            </span>
            <span className="block text-footnote text-ink-secondary">{day(c.starts_at, c.venue.tz)} · {hours(c.starts_at, c.ends_at, c.venue.tz)} · {c.venue.name}</span>
          </span>
          {c.status === 'pending' ? (
            <span className="flex items-center gap-3">
              <span className="chip bg-sky">{t('Waiting')}</span>
              <button className="link text-sm" disabled={Boolean(busy)} onClick={() => act(`w-${c.id}`, 'withdraw_challenge', { p_challenge: c.id }, t('Challenge withdrawn'))}>{t('Withdraw')}</button>
            </span>
          ) : c.status === 'accepted' && c.game_id ? (
            <Link to={`/games/${c.game_id}/`} className="chip bg-mint">{t('Game on')}</Link>
          ) : (
            <span className="chip bg-surface-muted text-ink">{t('Didn’t happen')}</span>
          )}
        </article>
      ))}
    </div>
  );
}
