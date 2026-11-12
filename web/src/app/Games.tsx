import { useState } from 'react';
import { GameTicket, RequestCard, RoomCard } from './cards';
import { GroupCard } from './Groups';
import { money } from './Courts';
import { toReview } from './Home';
import { currentLocale, t } from './i18n';
import { Icon, type IconName } from './icons';
import { ArrowLabel, Avatar, AvatarStack, Empty, IconButton, IconTile, LargeTitle, LevelBadge, Notice, ScreenHeader, SectionTitle, Segmented, Starburst, StatTile, Tag, fill, type Tint } from './kit';
import { PartnerSelect } from './Player';
import { Reviews } from './Review';
import { Link } from './router';
import { gamesFromScore, problem, supabase, useLive, winPercent, type Game, type MyChallenges, type MyGroups, type PlayRecord, type RoomSummary, type Ticket } from './supabase';
import { day, dayName, hours, timeOf } from './time';
import { Button, Field, Skeleton, toast } from './ui';
import { Sheet } from './Nearby';
import { startOptions, unset, windowTitle } from './usual';

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
        <Notice icon="challenge" tint="peach" action={{ label: t('View challenges'), to: '/challenges/' }}>
          {t('{n} challenge awaiting reply|{n} challenges awaiting reply', { n: incoming })}
        </Notice>
      )}

      {/* 手机上三个并排时每格只剩 50–70px，长一点的词（Permainan、Regular）放不下：改成一行一个，图标在左 */}
      <ul className="grid gap-3 sm:grid-cols-3">
        {shortcuts.map((s) => (
          <li key={s.to}>
            <Link to={s.to} className={`sticker lift grid h-full content-start gap-2 p-4 max-sm:grid-cols-[auto_minmax(0,1fr)] max-sm:gap-x-3 max-sm:gap-y-0.5 max-sm:py-3 ${fill[s.tint]}`}>
              <Icon name={s.icon} className="size-6 max-sm:row-span-2 max-sm:self-center" />
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
          {groups && groups.groups.length > 0 && (
            <section aria-labelledby="my-groups" className="grid gap-2">
              <SectionTitle id="my-groups" title={t('My groups')} detail={String(groups.groups.length)} action={{ label: t('See all'), to: '/groups/' }} />
              {groups.groups.map((g) => <GroupCard key={g.id} group={g} />)}
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
  { to: '/groups/', icon: 'group', tint: 'sky', title: 'Groups', subtitle: 'Weekly games' },
  { to: '/join/', icon: 'hash', tint: 'lavender', title: 'Room code', subtitle: 'Room or group code' },
];

/** 本月战绩小卡（在球局页右栏） */
function WeeklyMini() {
  const { data: record } = useLive<PlayRecord>('my_record', { every: 300_000 });
  if (!record) return null;
  return (
    <section aria-labelledby="month" className="grid gap-2">
      <SectionTitle id="month" title={t('This month')} action={{ label: t('Leaderboard'), to: '/rankings/' }} />
      <div className="grid grid-cols-3 gap-2">
        <StatTile tint="lime" value={winPercent(record) === null ? '–' : `${winPercent(record)}%`} label={t('Win rate')} />
        <StatTile tint="butter" value={`${record.round_wins ?? record.wins}–${(record.rounds ?? record.games) - (record.round_wins ?? record.wins)}`} label={t('Games won–lost')} />
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
          <span className="truncate text-headline tabular-nums">{g.mode === 'doubles' ? t('Doubles') : t('Singles')} · {unset(g) ? windowTitle(g, tz) : `${timeOf(g.starts_at, tz)}–${timeOf(g.ends_at, tz)}`}</span>
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
    <div className="grid grid-cols-[minmax(0,1fr)_auto_minmax(0,1fr)] items-center gap-3">
      {teams.map((team, i) => (
        <ul key={i} className={`grid gap-3 ${i === 1 ? 'order-3' : ''}`} aria-label={mode === 'doubles' ? t('Team {n}', { n: i + 1 }) : undefined}>
          {team.map((p) => (
            // 最窄的手机上头像放到名字上面，名字和等级才放得下
            <li key={p.id} className={`flex min-w-0 items-center gap-2.5 max-[379px]:flex-col ${i === 1 ? 'flex-row-reverse text-right max-[379px]:items-end' : 'max-[379px]:items-start'}`}>
              <Link to={p.me ? '/me/' : `/players/${p.id}/`} aria-label={p.me ? t('You') : p.nickname} className="press shrink-0 rounded-full">
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
  // 还没定具体时间：签到按整个窗口；定时间的截止前都能取消，不算临时取消；不能填比分
  const loose = unset(g);
  const canCheckIn = scheduled && !g.checked_in && now >= start - 30 * 60000 && now <= end;
  const canCancel = scheduled && (loose ? !g.set_time_by || now < new Date(g.set_time_by).getTime() : now < start);
  const late = !loose && start - now < 2 * 3600000;
  const canReport = scheduled && !loose && now >= start && now <= end + 7 * 86400000 && g.result.status !== 'verified';

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

          {scheduled && loose && <SetTime game={g} onChange={onChange} />}
          {scheduled && !loose && now >= start && <Result game={g} canReport={canReport} busy={busy} act={act} />}
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
                    {late ? t('The game starts in under 2 hours, so this counts as a late cancellation.') : loose ? t('The other player will be told.') : t('The other players will be put back in the queue first.')}
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

/** 具体几点？还没定时间的球局（附近的人约成的），两个人在群聊里商量好，任何一方点“定时间”，从窗口里选开始时刻 */
function SetTime({ game: g, onChange }: { game: Game; onChange: () => Promise<void> }) {
  const [open, setOpen] = useState(false);
  const [picked, setPicked] = useState<string>();
  const [busy, setBusy] = useState(false);
  const tz = g.venue.tz ?? Intl.DateTimeFormat().resolvedOptions().timeZone;
  const days = open && unset(g) ? startOptions(g, tz) : [];
  const other = g.players.find((p) => !p.me);

  async function save() {
    if (!picked) return;
    setBusy(true);
    const { error } = await supabase!.rpc('set_game_time', { p_game: g.id, p_starts_at: picked });
    setBusy(false);
    if (error) return toast(problem(error), 'error');
    setOpen(false);
    toast(t('Time set. {name} has been told.', { name: other?.nickname ?? '' }));
    await onChange();
  }

  return (
    <section aria-labelledby="set-time" className="sticker grid gap-3 p-5">
      <div>
        <h2 id="set-time" className="text-headline">{t('What time exactly?')}</h2>
        <p className="text-footnote text-ink-secondary">{t('Agree in the chat, then tap Set time.')}</p>
        {g.set_time_by && (
          <p className="mt-1 text-footnote font-bold text-ink-secondary">{t('If no time is set by {time}, the game is cancelled.', { time: `${dayName(g.set_time_by, g.venue.tz)} ${timeOf(g.set_time_by, g.venue.tz)}` })}</p>
        )}
      </div>
      <Button onClick={() => { setPicked(undefined); setOpen(true); }}>{t('Set time')}</Button>
      <Sheet open={open} onClose={() => setOpen(false)} labelledBy="set-time-title">
        <div className="flex items-center gap-3">
          <h2 id="set-time-title" className="flex-1 text-title3">{t('Set time')}</h2>
          <IconButton icon="x" label={t('Close')} onClick={() => setOpen(false)} />
        </div>
        {days.length === 0 ? (
          <p className="font-bold">{t('Too late for that. Pick a later time.')}</p>
        ) : (
          days.map(({ date, starts }) => (
            <div key={date} className="grid gap-2" role="group" aria-label={dayName(starts[0].toISOString(), g.venue.tz)}>
              <span className="text-footnote font-bold text-ink-secondary">{dayName(starts[0].toISOString(), g.venue.tz)}</span>
              <div className="flex flex-wrap gap-2">
                {starts.map((s) => (
                  <button key={s.toISOString()} type="button" className="toggle tabular-nums" aria-pressed={picked === s.toISOString()} onClick={() => setPicked(s.toISOString())}>
                    {timeOf(s.toISOString(), g.venue.tz)}
                  </button>
                ))}
              </div>
            </div>
          ))
        )}
        <p className="text-footnote font-bold text-ink-secondary">{t('2 hours')}</p>
        <Button className="button-lg w-full" busy={busy} disabled={!picked} onClick={save}>{t('Save')}</Button>
      </Sheet>
    </section>
  );
}

/** 赛果：一场常常打好几局，先填两边各赢了几局（不问“谁赢了”）；也可以选“没计分，就是练球”或“记不清了”。
 *  双方填的一致才算数，胜率按局算 */
function Result({ game: g, canReport, busy, act }: {
  game: Game;
  canReport: boolean;
  busy?: string;
  act: (name: string, fn: string, args: Record<string, unknown>, done: string) => void;
}) {
  const team1 = g.my_team === 1;
  const reported = g.my_report;
  const reportedMine = team1 ? reported?.team1_games : reported?.team2_games;
  const reportedTheirs = team1 ? reported?.team2_games : reported?.team1_games;
  const [mine, setMine] = useState(reportedMine ?? 0);
  const [theirs, setTheirs] = useState(reportedTheirs ?? 0);
  const [score, setScore] = useState(g.my_report?.score ?? '');
  const [showScore, setShowScore] = useState(Boolean(g.my_report?.score));
  const { status, outcome } = g.result;
  const rounds = g.rounds ? (team1 ? [g.rounds.team1, g.rounds.team2] : [g.rounds.team2, g.rounds.team1]) : null;
  const singles = g.mode === 'singles';
  const summary =
    status === 'verified'
      ? rounds
        ? rounds[0] === rounds[1] ? t('Confirmed: a draw.') : rounds[0] > rounds[1] ? t('Confirmed: you won more games.') : t('Confirmed: they won more games.')
        : outcome === 'friendly' ? t('Confirmed: a practice session, no score.') : outcome === (team1 ? 'team1' : 'team2') ? t('Confirmed: you won.') : t('Confirmed: you lost.')
      : status === 'disputed'
        ? t('Your reports don’t match. Either side can change theirs within 7 days of the game.')
        : status === 'unsure'
          ? t('One side doesn’t remember the result, so this game won’t count.')
          : status === 'expired'
            ? t('No result was agreed within 7 days.')
            : g.my_report
              ? t('Waiting for the other side to report.')
              : t('How many games did each side win? It counts once both sides agree.');

  function typeScore(value: string) {
    setScore(value);
    const games = gamesFromScore(value);
    if (games) {
      setMine(games.mine);
      setTheirs(games.theirs);
    }
  }

  // 填了每局比分、又手动改了局数，两边对不上
  const parsed = gamesFromScore(score);
  const mismatch = parsed !== null && (parsed.mine !== mine || parsed.theirs !== theirs);

  function save() {
    const [a, b] = team1 ? [mine, theirs] : [theirs, mine];
    act('report', 'report_result', { p_game: g.id, p_outcome: 'friendly', p_score: score, p_team1_games: a, p_team2_games: b }, t('Result saved'));
  }

  const total = mine + theirs;
  return (
    <section aria-labelledby="result" className={`sticker grid gap-4 p-5 ${status === 'verified' ? 'bg-mint text-on-accent' : status === 'disputed' ? 'bg-pink text-on-accent' : ''}`}>
      <div className="flex items-center gap-3">
        <IconTile icon="trophy" tint={status === 'verified' ? 'surface' : 'butter'} />
        <h2 id="result" className="text-headline">{t('Result')}</h2>
        {rounds ? <span className="ml-auto text-title3 tabular-nums">{rounds[0]} : {rounds[1]}</span>
          : g.score && <span className="ml-auto text-title3 tabular-nums">{g.score}</span>}
      </div>
      <p role="status" className="text-subhead font-bold">{summary}</p>
      {canReport && (
        <>
          <div className="flex flex-wrap items-start justify-center gap-4">
            <GamesCounter label={singles ? t('You') : t('Your side')} value={mine} onChange={setMine} />
            <span aria-hidden="true" className="pt-9 text-title2 font-black">:</span>
            <GamesCounter label={t('Them')} value={theirs} onChange={setTheirs} />
          </div>
          {total > 0 && (
            <p className="justify-self-center rounded-[10px] border-2 border-stroke bg-lime px-3 py-1 text-footnote font-bold text-on-accent">
              {t('Games: {n}', { n: total })} · {mine === theirs ? t('a draw') : mine > theirs ? t('you won more') : t('they won more')}
            </p>
          )}
          {showScore ? (
            <Field label={t('Score of each game (optional)')} error={mismatch ? t('The scores don’t match the games above.') : undefined}>
              {(props) => <input {...props} value={score} maxLength={40} inputMode="text" autoComplete="off" placeholder="21:18 19:21 21:15"
                                 onChange={(e) => typeScore(e.target.value)} className="field max-w-xs tabular-nums" />}
            </Field>
          ) : (
            <button type="button" className="link justify-self-start text-footnote font-bold" onClick={() => setShowScore(true)}>
              {t('+ Add the score of each game (optional)')}
            </button>
          )}
          <Button type="button" className="justify-self-start" busy={busy === 'report'} disabled={Boolean(busy) || total === 0 || mismatch} onClick={save}>
            {t('Save result')}
          </Button>
          <div className="flex flex-wrap gap-2" role="group" aria-label={t('Or')}>
            <button type="button" className="toggle" disabled={Boolean(busy)} aria-pressed={reported?.outcome === 'friendly' && reportedMine == null}
                    onClick={() => act('report', 'report_result', { p_game: g.id, p_outcome: 'friendly', p_score: '' }, t('Result saved'))}>
              {t('No score, just practice')}
            </button>
            <button type="button" className="toggle" disabled={Boolean(busy)} aria-pressed={reported != null && reported.outcome === null}
                    onClick={() => act('report', 'report_result', { p_game: g.id, p_outcome: null, p_score: '' }, t('Result saved'))}>
              {t('Can’t remember')}
            </button>
          </div>
          <p className="text-caption text-ink-secondary">{t('It counts once both sides agree. Win rate is by game: games won ÷ games played.')}</p>
        </>
      )}
    </section>
  );
}

/** 一边赢了几局：− 数字 + */
function GamesCounter({ label, value, onChange }: { label: string; value: number; onChange: (n: number) => void }) {
  return (
    <div className="grid justify-items-center gap-1" role="group" aria-label={label}>
      <span className="font-bold">{label}</span>
      <div className="flex items-center gap-1 rounded-[14px] border-2 border-stroke bg-surface px-1">
        <button type="button" aria-label={t('One fewer game')} disabled={value === 0} onClick={() => onChange(Math.max(0, value - 1))}
                className="grid size-11 place-items-center text-title3 font-black disabled:opacity-40">−</button>
        <output aria-live="polite" className="min-w-8 text-center text-[2rem] font-black tabular-nums">{value}</output>
        <button type="button" aria-label={t('One more game')} disabled={value >= 15} onClick={() => onChange(Math.min(15, value + 1))}
                className="grid size-11 place-items-center text-title3 font-black disabled:opacity-40">+</button>
      </div>
      <span className="text-caption text-ink-secondary">{t('games won')}</span>
    </div>
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
      <h2 id="fees" className="flex flex-wrap items-center gap-3">
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
            <span className="max-[379px]:hidden"><Starburst size={48}>VS</Starburst></span>
          </div>
          <p className="text-headline">
            {day(c.starts_at, c.venue.tz)} · {hours(c.starts_at, c.ends_at, c.venue.tz)} · {c.venue.name}
          </p>
          {c.message && <p className="font-medium">“{c.message}”</p>}
          <p className="text-sm font-semibold">{t('Answer by {date}. If you decline, they’ll only see that it didn’t happen.', { date: day(c.expires_at, c.venue.tz) })}</p>
          {c.partner && (
            <PartnerSelect exclude={[c.player.id, c.partner.id]} value={partners[c.id] ?? ''} onChange={(id) => setPartners({ ...partners, [c.id]: id })} />
          )}
          <div className="flex flex-wrap gap-2">
            <Button busy={busy === `yes-${c.id}`} disabled={Boolean(busy) || Boolean(c.partner && !partners[c.id])}
                    onClick={() => act(`yes-${c.id}`, 'respond_challenge', { p_challenge: c.id, p_accept: true, p_partner: partners[c.id] ?? null }, t('Challenge accepted.'))}>
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
            <Link to={`/games/${c.game_id}/`} className="chip bg-mint">{t('Game confirmed')}</Link>
          ) : (
            <span className="chip bg-surface-muted text-ink">{t('Didn’t happen')}</span>
          )}
        </article>
      ))}
    </div>
  );
}
