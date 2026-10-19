import { useEffect, useState, type ReactNode } from 'react';
import { tier } from './assessment';
import { setArea, useArea } from './area';
import { GameTicket, RequestCard, RoomCard } from './cards';
import { km } from './Courts';
import { t } from './i18n';
import { Icon, type IconName } from './icons';
import { ArrowLabel, Avatar, CardFan, Empty, IconTile, Notice, SectionTitle, StatTile, fill, type Tint } from './kit';
import { AboutFacts } from './Levels';
import type { Centre } from './pickers';
import { Link } from './router';
import { signInFirst } from './Shell';
import { supabase, useLive, type Game, type MyChallenges, type MyGroups, type NearbyVenue, type PlayRecord, type Profile, type RoomSummary, type Ticket, type WeeklyBoard } from './supabase';
import { dayName, timeOf } from './time';
import { toast } from './ui';

const live = (g: Game) => g.status === 'scheduled' && new Date(g.ends_at).getTime() > Date.now();
/** 结束后 48 小时内还有没评价的球友 */
export const toReview = (g: Game) =>
  g.status === 'scheduled' && Date.now() > new Date(g.ends_at).getTime() && Date.now() < new Date(g.review_until).getTime() &&
  g.players.some((p) => !p.me && !p.reviewed);

export function Home({ profile }: { profile: Profile | null }) {
  return profile ? <Dashboard me={profile} /> : <Welcome />;
}

function greeting() {
  const hour = new Date().getHours();
  return hour >= 5 && hour < 11 ? t('Good morning') : hour >= 11 && hour < 13 ? t('Good afternoon') : hour >= 13 && hour < 18 ? t('Good afternoon') : t('Good evening');
}

/** “Up for *a game* tonight?”：星号里的字用荧光笔标出来 */
function Headline({ children, size = 'text-[2.375rem] sm:text-[2.75rem] lg:text-[3.25rem]' }: { children?: ReactNode; size?: string }) {
  const parts = t('Up for *a game* tonight?').split('*');
  return (
    <div className="min-w-0">
      {children}
      <h1 className={`display mt-1 whitespace-pre-line ${size}`}>
        {parts.map((part, i) => (i % 2 ? <mark key={i} className="marker">{part}</mark> : part))}
      </h1>
    </div>
  );
}

// MARK: 登录后的首页

function Dashboard({ me }: { me: Profile }) {
  const { data: games } = useLive<Game[]>('my_games');
  const { data: requests } = useLive<Ticket[]>('my_matchmaking');
  const { data: challenges } = useLive<MyChallenges>('my_challenges', { every: 60_000 });
  const { data: record } = useLive<PlayRecord>('my_record', { every: 300_000 });
  const next = games?.filter(live).at(-1);
  const review = games?.find(toReview);
  const open = requests?.filter((r) => ['searching', 'offered', 'paused'].includes(r.status)) ?? [];
  const incoming = challenges?.incoming.length ?? 0;
  const level = tier(me.rating);

  return (
    <div className="grid gap-8 lg:gap-10">
      <header className="grid gap-5 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-end">
        <Headline>
          <p className="text-subhead font-bold text-ink-secondary">{t('{greeting}, {name}', { greeting: greeting(), name: me.nickname })}</p>
        </Headline>
        <div className="grid grid-cols-3 gap-2.5 lg:w-[30rem]">
          <Link to="/levels/" className="press rounded-[14px]"><StatTile stacked tint="lavender" icon="level" value={`Lv.${level.label}`} label={level.name} /></Link>
          <Link to="/games/" className="press rounded-[14px]"><StatTile stacked tint="peach" icon="games" value={record?.games_played ?? '–'} label={t('Games')} /></Link>
          <Link to="/rankings/" className="press rounded-[14px]">
            <StatTile stacked tint="lime" icon="trophy" value={record?.games ? `${Math.round((record.wins / record.games) * 100)}%` : '–'} label={t('Win rate')} />
          </Link>
        </div>
      </header>

      {!me.assessed_at && (
        <Notice icon="sparkle" tint="lavender" action={{ label: t('Take the quiz'), to: '/level-quiz/' }}>
          {t('You’re starting at level 3. Take the 2-minute level quiz so you’re matched with the right players.')}
        </Notice>
      )}

      <div className="grid gap-8 lg:grid-cols-[minmax(0,1fr)_22rem] lg:items-start lg:gap-10 xl:grid-cols-[minmax(0,1fr)_24rem]">
        <div className="grid min-w-0 gap-8">
          <div className={`grid gap-6 ${next ? 'xl:grid-cols-2' : ''}`}>
            {next && (
              <section aria-labelledby="next" className="grid content-start gap-2">
                <SectionTitle id="next" title={t('Next game')} action={{ label: t('Games'), to: '/games/' }} />
                <Link to={`/games/${next.id}/`} className="press block rounded-[22px]"><GameTicket game={next} compact /></Link>
              </section>
            )}
            <QuickMatch last={requests?.[0]} />
          </div>

          {incoming > 0 && (
            <Notice icon="challenge" tint="peach" action={{ label: t('Take a look'), to: '/challenges/' }}>
              {t('{n} challenge awaiting reply|{n} challenges awaiting reply', { n: incoming })}
            </Notice>
          )}
          {review && <ReviewBanner game={review} />}

          {open.length > 0 && (
            <section aria-labelledby="requests" className="grid gap-2">
              <SectionTitle id="requests" title={t('Game requests')} detail={t('{n} active', { n: open.length })} action={{ label: t('See all'), to: '/play/' }} />
              <div className="grid gap-3 xl:grid-cols-2">{open.map((r) => <RequestCard key={r.id} request={r} />)}</div>
            </section>
          )}

          <PublicGames />
        </div>

        <aside className="grid min-w-0 gap-8" aria-label={t('More')}>
          <WeeklyCard />
          <GroupsCard />
        </aside>
      </div>
    </div>
  );
}

/** 快速约球：按上次的设置（没有就是默认）一键开始，点了进设置页 */
function QuickMatch({ last, guest = false }: { last?: Ticket; guest?: boolean }) {
  const to = guest ? signInFirst('/play/') : '/play/';
  const tz = last?.venues[0]?.tz;
  const chips: [IconName, string][] = [
    [last?.mode === 'singles' ? 'user' : 'users', last?.mode === 'singles' ? t('Singles') : t('Doubles')],
    ['clock', last ? `${timeOf(last.starts_at, tz)}–${timeOf(last.ends_at, tz)}` : t('Tonight')],
    ['pin', last ? t('{n} venue|{n} venues', { n: last.venues.length }) : t('Courts near you')],
    ['level', !last || last.skill_tolerance === 1 ? t('Level ±1') : last.skill_tolerance === 8 ? t('Any level') : t('Level ±{n}', { n: last.skill_tolerance })],
  ];
  return (
    <section aria-labelledby="quick" className="sticker grid content-start gap-3 bg-lime p-5 text-on-accent">
      <div className="flex items-center justify-between">
        <h2 id="quick" className="kicker">{t('Quick play')}</h2>
        <Link to={to} className="-my-2 flex min-h-11 items-center text-footnote font-bold underline-offset-4 hover:underline">{t('Adjust')}</Link>
      </div>
      <p className="text-title2">{t('Finds buddies for you by level and time')}</p>
      <ul className="flex flex-wrap gap-1.5" aria-label={t('Settings')}>
        {chips.map(([icon, text]) => (
          <li key={icon} className="flex items-center gap-1 rounded-full border-[1.5px] border-[#17140f] bg-white px-2.5 py-1 text-footnote font-bold">
            <Icon name={icon} className="size-3" />
            {text}
          </li>
        ))}
      </ul>
      <Link to={to} className="button button-lg button-inverse mt-1 w-full">
        <ArrowLabel>{t('Start matching')}</ArrowLabel>
      </Link>
    </section>
  );
}

function ReviewBanner({ game }: { game: Game }) {
  const others = game.players.filter((p) => !p.me && !p.reviewed);
  return (
    <Link to={`/games/${game.id}/`} className="sticker lift flex items-center gap-3 bg-pink p-4 text-on-accent">
      <Avatar id={others[0].id} name={others[0].nickname} size={40} />
      <span className="min-w-0 flex-1">
        <span className="block text-headline">{t('Rate your game with {name}', { name: others.length > 1 ? t('{n} players', { n: others.length }) : others[0].nickname })}</span>
        <span className="block text-footnote">{t('Anonymous and combined, so the community stays reliable')}</span>
      </span>
      <Icon name="chevronRight" className="size-4" />
    </Link>
  );
}

/** 手机上横向滑动；桌面在主栏里排三张，更多的去“全部”看 */
const gamesRail = 'rail lg:mx-0 lg:grid lg:grid-cols-3 lg:overflow-visible lg:px-0';

/** 附近公开的球局（有场地缺人），横向滑动 */
function PublicGames() {
  const area = useArea();
  const [rooms, setRooms] = useState<RoomSummary[]>();
  useEffect(() => {
    if (!area) return;
    supabase!.rpc('rooms_near', { lat: area.lat, lng: area.lon, radius_km: 30 }).then(({ data }) => setRooms((data ?? []) as RoomSummary[]));
  }, [area?.lat, area?.lon]);

  return (
    <section aria-labelledby="public" className="grid gap-2">
      <SectionTitle id="public" title={t('Nearby games')} detail={t('Have a court, need players')} action={{ label: t('See all'), to: '/rooms/' }} />
      {!area ? (
        <AreaPrompt />
      ) : rooms === undefined ? (
        <div className={gamesRail}>{[0, 1, 2].map((i) => <div key={i} className="skeleton h-44 w-[17rem] lg:w-auto" />)}</div>
      ) : rooms.length === 0 ? (
        <Empty icon="court" tint="peach" title={t('No open games nearby right now')} action={{ label: t('Start a game'), to: '/rooms/new/' }}>
          {t('Booked a court but short on players? Start one and nearby players will see it.')}
        </Empty>
      ) : (
        <ul className={gamesRail}>{rooms.map((r) => <li key={r.id} className="w-[17rem] lg:w-auto lg:nth-[n+4]:hidden"><RoomCard room={r} wide /></li>)}</ul>
      )}
    </section>
  );
}

/** 本周排行：我的名次或还差多少能上榜 */
function WeeklyCard() {
  const { data: board } = useLive<WeeklyBoard>('weekly_board', { args: { p_scope: 'global', p_offset: 0 }, every: 300_000 });
  const text = !board ? '…'
    : board.me ? t('You’re #{rank} with {points} points.', { rank: board.me.rank, points: board.me.points })
    : board.progress ? t('{points} points so far. You’ll appear after 3 games against 2 different opponents (now {games} and {opponents}).', { ...board.progress })
    : t('Play 3 confirmed games against 2 different opponents this week to appear.');
  return (
    <Link to="/rankings/" className="sticker lift flex items-center gap-3 bg-butter p-4 text-on-accent">
      <IconTile icon="trophy" tint="surface" />
      <span className="min-w-0 flex-1">
        <span className="kicker block">{t('This week’s leaderboard')}</span>
        <span className="block text-headline">{text}</span>
      </span>
      <Icon name="chevronRight" className="size-4" />
    </Link>
  );
}

/** 固定局：我报了名的场次，没有就引导去找球群 */
function GroupsCard() {
  const { data } = useLive<MyGroups>('my_groups', { every: 120_000 });
  const sessions = data?.sessions.slice(0, 2) ?? [];
  return (
    <section aria-labelledby="groups" className="grid gap-2">
      <SectionTitle id="groups" title={t('Regular games')} detail={data?.groups.length ? t('{n} group|{n} groups', { n: data.groups.length }) : t('No more sign-up lists in chat')} action={{ label: t('See all'), to: '/groups/' }} />
      {sessions.length === 0 ? (
        <Link to="/groups/" className="sticker lift flex items-center gap-3 bg-sky p-4 text-on-accent">
          <IconTile icon="group" tint="surface" />
          <span className="min-w-0 flex-1">
            <span className="block text-headline">{t('Find a weekly session')}</span>
            <span className="block text-footnote">{t('Same time and venue every week. Sign up in one tap; join the waitlist automatically when full')}</span>
          </span>
          <Icon name="chevronRight" className="size-4" />
        </Link>
      ) : (
        sessions.map((s) => (
          <Link key={s.id} to={`/groups/${s.group_id}/`} className="sticker lift flex items-center gap-3 p-4">
            <IconTile icon="calendarCheck" tint={s.waitlisted ? 'butter' : 'lime'} />
            <span className="min-w-0 flex-1">
              <span className="kicker block truncate text-ink-secondary">{s.group}</span>
              <span className="block text-headline">{dayName(s.starts_at, s.tz)} · {timeOf(s.starts_at, s.tz)}</span>
              <span className="block text-footnote font-bold text-ink-secondary">{s.waitlisted ? t('On the waitlist') : t('Signed up')} · {s.venue}</span>
            </span>
            <Icon name="chevronRight" className="size-4 text-ink-tertiary" />
          </Link>
        ))
      )}
    </section>
  );
}

/** 附近球馆：最近的 3 家 + 总数，点进球馆页 */
function NearbyCourts() {
  const area = useArea();
  const [courts, setCourts] = useState<NearbyVenue[]>();
  useEffect(() => {
    if (!area) return;
    supabase!.rpc('venues_near', { lat: area.lat, lng: area.lon, radius_km: 15, max_results: 50 }).then(({ data }) => setCourts((data ?? []) as NearbyVenue[]));
  }, [area?.lat, area?.lon]);

  return (
    <section aria-labelledby="courts" className="grid gap-2">
      <SectionTitle id="courts" title={t('Nearby venues')} detail={courts ? t('{n} within {distance}', { n: courts.length, distance: km(15_000) }) : undefined} action={{ label: t('Map'), to: '/courts/' }} />
      {!area ? (
        <AreaPrompt />
      ) : (
        <div className="sticker grid p-2">
          {courts === undefined && [0, 1, 2].map((i) => <div key={i} className="skeleton m-2 h-12" />)}
          {courts?.length === 0 && <p className="p-3 text-footnote text-ink-secondary">{t('No courts within {distance} yet', { distance: km(15_000) })}</p>}
          {courts?.slice(0, 3).map(({ venue, distance_m }) => (
            <Link key={venue.id} to={`/courts/?venue=${venue.id}`} className="press flex items-center gap-3 rounded-[14px] p-2 hover:bg-surface-muted/70">
              <IconTile icon="pin" tint="sky" size="sm" />
              <span className="min-w-0 flex-1">
                <span className="block truncate font-bold">{venue.name}</span>
                <span className="block truncate text-footnote text-ink-secondary">{venue.city}</span>
              </span>
              <span className="shrink-0 text-footnote font-bold text-ink-secondary tabular-nums">{km(distance_m)}</span>
            </Link>
          ))}
        </div>
      )}
    </section>
  );
}

/** 还不知道你在哪：用定位（不存坐标到服务器，只存在这个浏览器） */
export function AreaPrompt({ tint = 'sky' }: { tint?: Tint }) {
  const [busy, setBusy] = useState(false);
  function locate() {
    setBusy(true);
    navigator.geolocation.getCurrentPosition(
      (p) => {
        setBusy(false);
        setArea({ lat: p.coords.latitude, lon: p.coords.longitude } satisfies Centre);
      },
      () => {
        setBusy(false);
        toast(t('Location is off. Search an area instead.'), 'error');
      },
      { timeout: 10000 },
    );
  }
  return (
    <div className={`tile grid gap-3 p-4 ${fill[tint]}`}>
      <p className="flex items-center gap-3 text-footnote font-bold">
        <IconTile icon="locate" tint="surface" />
        {t('Show what’s near you. Your location stays in this browser.')}
      </p>
      <span className="flex flex-wrap gap-2">
        <button type="button" onClick={locate} disabled={busy} className="button button-sm button-quiet">{t('Use my location')}</button>
        <Link to="/courts/" className="button button-sm button-quiet">{t('Search an area')}</Link>
      </span>
    </div>
  );
}

// MARK: 没登录时的首页：先把 Badie 讲清楚，一节只讲一件事、留足空白；能用的功能直接用，要账号的先去登录

const steps: { icon: IconName; tint: Tint; title: string; text: string }[] = [
  { icon: 'level', tint: 'lavender', title: 'Set your level', text: 'A 2-minute quiz places you on a 1–9 scale. Players you meet confirm it after games.' },
  { icon: 'bolt', tint: 'lime', title: 'Get matched', text: 'Pick the courts you can reach and when you’re free. Badie finds players at your level with the same window.' },
  { icon: 'trophy', tint: 'peach', title: 'Play, then confirm', text: 'After the game both sides confirm who won. Only matching results count toward win rate and leaderboards.' },
];

const ways: { icon: IconName; tint: Tint; title: string; text: string; to: string }[] = [
  { icon: 'bolt', tint: 'lime', title: 'Quick Match', text: 'Finds buddies for you by level and time', to: '/play/' },
  { icon: 'court', tint: 'peach', title: 'Nearby games', text: 'Booked a court but short on players? Start one and nearby players will see it.', to: '/rooms/' },
  { icon: 'group', tint: 'sky', title: 'Regular games', text: 'Same time and venue every week. Sign up in one tap; join the waitlist automatically when full', to: '/groups/' },
];

const lead = 'text-[1.0625rem] leading-relaxed text-ink-secondary lg:text-[1.1875rem]';

/** 介绍页每一节的开头：小标题 + 大标题 + 一段说明 */
function Intro({ id, kicker, title, children }: { id: string; kicker?: string; title: string; children?: ReactNode }) {
  return (
    <div className="grid max-w-2xl gap-3">
      {kicker && <p className="kicker text-ink-secondary">{kicker}</p>}
      <h2 id={id} className="text-title lg:text-[2.5rem]">{title}</h2>
      {children && <p className={lead}>{children}</p>}
    </div>
  );
}

function Welcome() {
  return (
    <div className="grid gap-20 pb-4 lg:gap-28">
      <header className="grid items-center gap-10 lg:min-h-[28rem] lg:grid-cols-[minmax(0,1fr)_auto] lg:gap-16">
        <div className="grid justify-items-start gap-6">
          <ul className="flex flex-wrap gap-2">
            {[['heart', 'pink', 'Free and nonprofit'], ['eyeSlash', 'sky', 'No ads, no tracking']].map(([icon, tint, text]) => (
              <li key={text} className={`chip px-3! py-1.5! text-footnote! ${fill[tint as Tint]}`}><Icon name={icon as IconName} className="size-4" />{t(text)}</li>
            ))}
          </ul>
          <Headline size="text-[3rem] sm:text-[3.75rem] lg:text-[4.5rem]" />
          <p className={`max-w-xl ${lead}`}>{t('A free, nonprofit app for finding badminton partners at your level and courts near you. No ads.')}</p>
          <div className="flex flex-wrap gap-3">
            <Link to={signInFirst('/play/')} className="button button-lg">{t('Start matching')}<Icon name="arrowRight" className="size-5" /></Link>
            <Link to="/courts/" className="button button-lg button-quiet">{t('Courts near you')}</Link>
          </div>
        </div>
        <div className="max-sm:-my-4 lg:px-12"><CardFan className="max-sm:scale-[0.8] lg:scale-125" /></div>
      </header>

      <section aria-labelledby="how" className="grid gap-8">
        <Intro id="how" title={t('How Badie works')} />
        <ol className="grid gap-4 lg:grid-cols-3">
          {steps.map((s, i) => (
            <li key={s.title} className={`sticker grid content-start gap-4 p-6 lg:p-8 ${fill[s.tint]}`}>
              <span className="flex items-center gap-3">
                <span className="grid size-10 place-items-center rounded-full bg-[#17140f] text-headline font-black text-lime">{i + 1}</span>
                <IconTile icon={s.icon} tint="surface" />
              </span>
              <h3 className="text-title3">{t(s.title)}</h3>
              <p className="text-subhead">{t(s.text)}</p>
            </li>
          ))}
        </ol>
      </section>

      <section aria-labelledby="levels" className="grid items-center gap-10 lg:grid-cols-2 lg:gap-16">
        <div className="grid justify-items-start gap-5">
          <Intro id="levels" kicker={t('Matched by level')} title={t('What level am I?')}>
            {t('Levels 1–9 described by what you can actually do on court, from first rallies to national level.')}
          </Intro>
          <Link to="/levels/" className="button button-quiet">{t('See the levels')}</Link>
        </div>
        <LevelLadder />
      </section>

      <section aria-labelledby="ways" className="grid gap-8">
        <Intro id="ways" title={t('Three ways to get a game')}>{t('Find a buddy with Quick Match, or start a game for nearby players to join.')}</Intro>
        <ul className="grid gap-4 lg:grid-cols-3">
          {ways.map((w) => (
            <li key={w.title}>
              <Link to={signInFirst(w.to)} className={`sticker lift grid h-full content-start gap-4 p-6 lg:p-8 ${fill[w.tint]}`}>
                <IconTile icon={w.icon} tint="surface" size="lg" />
                <span className="text-title3">{t(w.title)}</span>
                <span className="text-subhead">{t(w.text)}</span>
                <Icon name="arrowRight" className="size-6" />
              </Link>
            </li>
          ))}
        </ul>
      </section>

      <section aria-labelledby="values" className="grid gap-8">
        <Intro id="values" kicker={t('About Badie')} title={t('Built by a player, for players')} />
        <AboutFacts heading="h3" className="sm:grid-cols-2 lg:grid-cols-4" />
      </section>

      <section aria-labelledby="find-courts" className="grid items-start gap-10 lg:grid-cols-2 lg:gap-16">
        <div className="grid justify-items-start gap-5">
          <Intro id="find-courts" title={t('Find courts around you')}>{t('Browse every court we list, with hours, prices and directions.')}</Intro>
          <Link to="/courts/" className="button button-quiet">{t('Browse by country')}</Link>
        </div>
        <NearbyCourts />
      </section>

      <section aria-labelledby="ready" className="sticker grid gap-6 bg-[#17140f] p-8 text-[#f5f0e6] lg:grid-cols-[minmax(0,1fr)_auto] lg:items-center lg:p-12">
        <div className="grid gap-3">
          <h2 id="ready" className="text-title lg:text-[2.5rem]">{t('Ready to play?')}</h2>
          <p className="max-w-xl text-[1.0625rem] leading-relaxed">{t('Sign in with your email to get matched, join games and chat with players. No password needed.')}</p>
        </div>
        <Link to="/signin/" className="button button-lg justify-self-start">{t('Sign in')}</Link>
      </section>
    </div>
  );
}

/** 1–9 级的台阶，你上下 1 级的范围亮起来：只和水平相当的人配到一起 */
function LevelLadder() {
  const mine = 5;
  return (
    <div aria-hidden="true" className="sticker grid gap-5 bg-lavender p-6 text-on-accent lg:p-8">
      <span className="chip justify-self-start bg-white">{t('Level ±1')}</span>
      <div className="flex h-56 items-end gap-1.5 sm:gap-2">
        {Array.from({ length: 9 }, (_, i) => i + 1).map((level) => (
          <div key={level} className="flex h-full flex-1 flex-col items-center justify-end gap-2">
            <div style={{ height: `${level * 10}%` }} className={`w-full rounded-t-[10px] border-2 border-stroke ${Math.abs(level - mine) <= 1 ? 'bg-lime' : 'bg-white'}`} />
            <span className="text-footnote font-black tabular-nums">{level}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
