import { useEffect, useState, type ReactNode } from 'react';
import { tier } from './assessment';
import { setArea, useArea } from './area';
import { GameTicket, RequestCard, RoomCard } from './cards';
import { km } from './Courts';
import { t } from './i18n';
import { Icon, type IconName } from './icons';
import { ArrowLabel, Avatar, Empty, IconTile, LevelBadge, Notice, SectionTitle, StatTile, fill, type Tint } from './kit';
import type { Centre } from './pickers';
import { Link } from './router';
import { signInFirst } from './Shell';
import { supabase, useLive, type Game, type MyChallenges, type MyGroups, type NearbyVenue, type PlayRecord, type Profile, type Regular, type RoomSummary, type Ticket, type WeeklyBoard } from './supabase';
import { dateChip, dayName, nextDays, timeOf } from './time';
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
function Headline({ children }: { children?: ReactNode }) {
  const parts = t('Up for *a game* tonight?').split('*');
  return (
    <div className="min-w-0">
      {children}
      <h1 className="display mt-1 text-[2.375rem] whitespace-pre-line sm:text-[2.75rem] lg:text-[3.25rem]">
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
    <div className="grid gap-6 lg:gap-8">
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

      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_22rem] lg:items-start lg:gap-8 xl:grid-cols-[minmax(0,1fr)_24rem]">
        <div className="grid min-w-0 gap-6">
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

          <DateStrip signedIn />
          <PublicGames />
        </div>

        <aside className="grid min-w-0 gap-6" aria-label={t('More')}>
          <WeeklyCard />
          <GroupsCard />
          <Regulars />
          <NearbyCourts />
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

/** 哪天有空：接下来 7 天，点一天去约那天 */
function DateStrip({ signedIn = false }: { signedIn?: boolean }) {
  return (
    <section aria-labelledby="days" className="grid gap-2">
      <SectionTitle id="days" title={t('Which days work for you?')} detail={t('Pick a day to find players')} />
      <ul className="rail lg:mx-0 lg:grid lg:grid-cols-7 lg:overflow-visible lg:px-0">
        {nextDays(7).map((date, i) => {
          const chip = dateChip(date, i);
          const to = `/play/?date=${date}`;
          return (
            <li key={date}>
              <Link
                to={signedIn ? to : signInFirst(to)}
                className={`press grid w-[3.5rem] justify-items-center gap-0.5 rounded-[16px] border-2 border-stroke py-2 lg:w-auto ${i === 0 ? 'bg-lime text-on-accent shadow-low' : 'bg-surface hover:bg-surface-muted'}`}
              >
                <span className="text-caption">{chip.label}</span>
                <span className="text-[1.25rem] leading-tight font-black tabular-nums">{chip.day}</span>
              </Link>
            </li>
          );
        })}
      </ul>
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
        <div className="rail">{[0, 1].map((i) => <div key={i} className="skeleton h-44 w-[17rem]" />)}</div>
      ) : rooms.length === 0 ? (
        <Empty icon="court" tint="peach" title={t('No open games nearby right now')} action={{ label: t('Start a game'), to: '/rooms/new/' }}>
          {t('Booked a court but short on players? Start one and nearby players will see it.')}
        </Empty>
      ) : (
        <ul className="rail">{rooms.map((r) => <li key={r.id}><RoomCard room={r} /></li>)}</ul>
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

/** 同馆常客：常去同一家球馆、自己开启了展示的球友 */
function Regulars() {
  const { data: regulars } = useLive<Regular[]>('venue_regulars', { every: 300_000 });
  return (
    <section aria-labelledby="regulars" className="grid gap-2">
      <SectionTitle id="regulars" title={t('Venue regulars')} detail={regulars?.length ? t('{n} players', { n: regulars.length }) : undefined} />
      {regulars?.length ? (
        <ul className="rail lg:mx-0 lg:grid lg:grid-cols-3 lg:gap-3 lg:overflow-visible lg:px-0">
          {regulars.slice(0, 12).map((r) => (
            <li key={r.id}>
              <Link to={`/players/${r.id}/`} className="press grid w-[4.5rem] justify-items-center gap-1 text-center lg:w-auto">
                <Avatar id={r.id} name={r.nickname} size={58} />
                <span className="w-full truncate text-footnote font-bold">{r.nickname}</span>
                <LevelBadge rating={r.rating} named={false} compact />
                <span className="w-full truncate text-caption text-ink-secondary">{r.venue.name}</span>
              </Link>
            </li>
          ))}
        </ul>
      ) : (
        <Notice icon="heart" tint="muted" action={{ label: t('Courts'), to: '/courts/' }}>
          {t('Once you set your usual venues, players who also go there will show up here (if they’ve turned it on).')}
        </Notice>
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

// MARK: 没登录时的首页：同样的 App，能看的都能看，要账号的按钮先去登录

const steps: { icon: IconName; tint: Tint; title: string; text: string }[] = [
  { icon: 'level', tint: 'lavender', title: 'Set your level', text: 'A 2-minute quiz places you on a 1–9 scale. Players you meet confirm it after games.' },
  { icon: 'bolt', tint: 'lime', title: 'Get matched', text: 'Pick the courts you can reach and when you’re free. Badie finds players at your level with the same window.' },
  { icon: 'trophy', tint: 'peach', title: 'Play, then confirm', text: 'After the game both sides confirm who won. Only matching results count toward win rate and leaderboards.' },
];

function Welcome() {
  return (
    <div className="grid gap-6 lg:gap-8">
      <header className="grid gap-5 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-end">
        <Headline>
          <p className="text-subhead font-bold text-ink-secondary">{greeting()}</p>
        </Headline>
        <ul className="flex flex-wrap gap-2 lg:max-w-[26rem] lg:justify-end">
          {[['heart', 'pink', 'Free and nonprofit'], ['eyeSlash', 'sky', 'No ads, no tracking'], ['level', 'lavender', 'Matched by level'], ['reliable', 'mint', 'Reliability that counts']].map(([icon, tint, text]) => (
            <li key={text} className={`chip px-3! py-1.5! text-footnote! ${fill[tint as Tint]}`}><Icon name={icon as IconName} className="size-4" />{t(text)}</li>
          ))}
        </ul>
      </header>

      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_22rem] lg:items-start lg:gap-8 xl:grid-cols-[minmax(0,1fr)_24rem]">
        <div className="grid min-w-0 gap-6">
          <div className="grid items-start gap-6 xl:grid-cols-2">
            <QuickMatch guest />
            <section aria-labelledby="how" className="grid content-start gap-3">
              <h2 id="how" className="text-title3">{t('How Badie works')}</h2>
              <ol className="grid gap-2.5">
                {steps.map((s, i) => (
                  <li key={s.title} className={`tile flex gap-3 p-3.5 ${fill[s.tint]}`}>
                    <span className="relative">
                      <IconTile icon={s.icon} tint="surface" />
                      <span className="absolute -top-2 -left-2 grid size-6 place-items-center rounded-full border-2 border-stroke bg-[#17140f] text-caption font-black text-lime">{i + 1}</span>
                    </span>
                    <span className="min-w-0">
                      <span className="block text-headline">{t(s.title)}</span>
                      <span className="block text-footnote">{t(s.text)}</span>
                    </span>
                  </li>
                ))}
              </ol>
            </section>
          </div>
          <DateStrip />
          <Link to="/levels/" className="sticker lift grid gap-3 bg-lavender p-5 text-on-accent sm:grid-cols-[auto_1fr_auto] sm:items-center">
            <IconTile icon="level" tint="surface" size="lg" />
            <span>
              <span className="block text-title3">{t('What level am I?')}</span>
              <span className="block text-footnote">{t('Levels 1–9 described by what you can actually do on court, from first rallies to national level.')}</span>
            </span>
            <span className="button button-sm button-quiet justify-self-start">{t('See the levels')}</span>
          </Link>
        </div>

        <aside className="grid min-w-0 gap-6" aria-label={t('More')}>
          <section aria-labelledby="signin" className="sticker grid gap-3 bg-[#17140f] p-5 text-[#f5f0e6]">
            <h2 id="signin" className="text-title3">{t('Ready to play?')}</h2>
            <p className="text-footnote">{t('Sign in with your email to get matched, join games and chat with players. No password needed.')}</p>
            <Link to="/signin/" className="button button-lg">{t('Sign in')}</Link>
          </section>
          <NearbyCourts />
          <Link to="/courts/" className="sticker lift flex items-center gap-3 bg-mint p-4 text-on-accent">
            <IconTile icon="globe" tint="surface" />
            <span className="min-w-0 flex-1">
              <span className="block text-headline">{t('Courts by country')}</span>
              <span className="block text-footnote">{t('Browse every court we list, with hours, prices and directions.')}</span>
            </span>
            <Icon name="chevronRight" className="size-4" />
          </Link>
          <Link to="/about/" className="sticker lift flex items-center gap-3 p-4">
            <IconTile icon="heart" tint="pink" />
            <span className="min-w-0 flex-1">
              <span className="block text-headline">{t('About Badie')}</span>
              <span className="block text-footnote text-ink-secondary">{t('Built by a player, for players. Where our data comes from.')}</span>
            </span>
            <Icon name="chevronRight" className="size-4 text-ink-tertiary" />
          </Link>
        </aside>
      </div>
    </div>
  );
}
