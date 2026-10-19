import { useEffect, useState } from 'react';
import { tier } from './assessment';
import { currentLocale, t } from './i18n';
import { Icon } from './icons';
import { Avatar, Empty, Notice, ScreenHeader, Segmented } from './kit';
import { Link } from './router';
import { supabase, useLive, type BoardEntry, type VenueBoard, type WeeklyBoard } from './supabase';
import { Skeleton } from './ui';

const scopes = [['global', 'Everyone'], ['country', 'My country'], ['level', 'My level']] as const;
const weeks = ['This week', 'Last week'] as const;
const months = ['This month', 'Last month'] as const;
const bands = ['', 'Levels 1–2', 'Levels 3–4', 'Levels 5–6', 'Levels 7+'];

export function Rankings() {
  const [scope, setScope] = useState<(typeof scopes)[number][0]>('global');
  // 0 = 本周，1 = 上周
  const [week, setWeek] = useState(0);
  const { data: board } = useLive<WeeklyBoard>('weekly_board', { args: { p_scope: scope, p_offset: week }, every: 120_000 });

  return (
    <div className="grid gap-6">
      <ScreenHeader title={t('Leaderboard')} back="/games/" />
      <div className="grid grid-cols-1 gap-8 lg:grid-cols-[minmax(0,1fr)_24rem] lg:items-start">
        <section aria-labelledby="weekly" className="grid grid-cols-1 gap-3">
          <h2 id="weekly" className="sr-only">{t(weeks[week])}</h2>
          <Segmented label={t('Who to compare with')} value={scope} onChange={setScope} options={scopes.map(([value, label]) => ({ value, label: t(label) }))} />
          <Segmented label={t('Period')} value={String(week)} onChange={(v) => setWeek(Number(v))} options={weeks.map((label, i) => ({ value: String(i), label: t(label) }))} />
          <p className="text-footnote text-ink-secondary">{t('Resets every Monday (UTC). Loss 10, win 15, more against stronger players.')}</p>
          {board && <MyPosition board={board} past={week > 0} />}
          {!board ? <Skeleton className="h-64" /> : board.entries.length === 0 ? (
            week > 0 ? <Empty icon="trophy" tint="butter" title={t('No one made the board last week')} /> : (
              <Empty icon="trophy" tint="butter" title={t('No one on the board yet')}>{t('Players appear after 3 confirmed games against 2 or more opponents this week.')}</Empty>
            )
          ) : (
            <Board entries={board.entries} unit="pts" />
          )}
        </section>

        <CourtBoards />
      </div>
    </div>
  );
}

function MyPosition({ board, past }: { board: WeeklyBoard; past: boolean }) {
  const mine = board.entries.find((e) => e.me);
  if (past) {
    return board.me ? <p role="status" className="sticker bg-lime p-4 font-bold text-on-accent">{t('You finished #{rank} with {points} points.', { ...board.me })}</p> : null;
  }
  if (board.eligible && board.me) {
    return (
      <div role="status" className="sticker flex items-center gap-3 bg-lime p-4 text-on-accent">
        {mine && <Avatar id={mine.id} name={mine.nickname} size={44} />}
        <div>
          <p className="kicker">{t('My rank')}</p>
          <p className="text-title3">{t('#{rank} · {points} points', { rank: board.me.rank, points: board.me.points })}</p>
          {mine && <p className="text-footnote font-bold">{t('{n} game|{n} games', { n: mine.games })} · {t('{n} win|{n} wins', { n: mine.wins })}</p>}
        </div>
      </div>
    );
  }
  const text = !board.eligible
    ? t('You’re not on the boards: new accounts join after 7 days, and you can turn boards on in Me.')
    : board.progress
      ? t('{points} points so far. You’ll appear after 3 games against 2 different opponents (now {games} and {opponents}).', { ...board.progress })
      : t('Play 3 confirmed games against 2 different opponents this week to appear.');
  return <Notice icon="info" tint="lavender">{text}</Notice>;
}

const medal = ['bg-butter', 'bg-sky', 'bg-peach'];

function Board({ entries, unit }: { entries: BoardEntry[]; unit: 'pts' | 'games' }) {
  return (
    <ol className="grid grid-cols-1 gap-2">
      {entries.map((e) => (
        <li key={e.id}>
          <Link to={`/players/${e.id}/`} className={`sticker lift flex items-center gap-3 p-3 ${e.me ? 'bg-lime/45' : ''}`}>
            <span className={`grid size-8 shrink-0 place-items-center rounded-full text-footnote font-black tabular-nums ${e.rank <= 3 ? `border-2 border-stroke text-on-accent ${medal[e.rank - 1]}` : 'text-ink-secondary'}`}>{e.rank}</span>
            <Avatar id={e.id} name={e.nickname} size={40} />
            <span className="min-w-0 flex-1">
              <span className="block truncate font-bold">{e.me ? t('{name} (you)', { name: e.nickname }) : e.nickname}</span>
              <span className="block truncate text-footnote text-ink-secondary">
                {[`Lv.${tier(e.rating).label} ${tier(e.rating).name}`, unit === 'pts' && t('{n} game|{n} games', { n: e.games }), t('{n} win|{n} wins', { n: e.wins })].filter(Boolean).join(' · ')}
              </span>
            </span>
            <span className="shrink-0 text-headline tabular-nums">{unit === 'pts' ? t('{n} pts', { n: e.points ?? 0 }) : t('{n} game|{n} games', { n: e.games })}</span>
          </Link>
        </li>
      ))}
    </ol>
  );
}

type Court = { id: string; name: string };

/** 场馆月榜：我收藏的球馆 */
function CourtBoards() {
  const [courts, setCourts] = useState<Court[]>();
  const [court, setCourt] = useState<string>();
  const [month, setMonth] = useState(0);
  const { data: board } = useLive<VenueBoard>('venue_board', { args: { p_venue: court ?? '', p_offset: month }, every: 300_000 });

  useEffect(() => {
    supabase!.from('favorite_venues').select('venues(id, name)').then(({ data }) => {
      const list = (data ?? []).flatMap((f) => (f.venues ? [f.venues as unknown as Court] : []));
      setCourts(list);
      setCourt(list[0]?.id);
    });
  }, []);

  return (
    <section aria-labelledby="courts" className="grid grid-cols-1 gap-4">
      <div>
        <h2 id="courts" className="text-title3">{t('Court champions')}</h2>
        <p className="text-footnote text-ink-secondary">{t('Most confirmed games at a court this month, by level. Up to 3 a day and 4 against the same opponent.')}</p>
      </div>
      {courts?.length === 0 && (
        <Empty icon="heart" tint="pink" title={t('Save a court first')} action={{ label: t('Courts'), to: '/courts/' }}>
          {t('Boards show for the courts you’ve starred.')}
        </Empty>
      )}
      {courts && courts.length > 0 && (
        <>
          <select aria-label={t('Court')} value={court} onChange={(e) => setCourt(e.target.value)} className="field">
            {courts.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
          <Segmented label={t('Period')} value={String(month)} onChange={(v) => setMonth(Number(v))} options={months.map((label, i) => ({ value: String(i), label: t(label) }))} />
        </>
      )}
      {court && !board && <Skeleton className="h-40" />}
      {court && board && board.bands.length === 0 && (
        <p className="text-footnote text-ink-secondary">{month > 0 ? t('No one qualified last month.') : t('No one qualifies yet this month: 3 games against 2 opponents.')}</p>
      )}
      {court && board?.bands.map((b) => (
        <div key={b.band} className="grid grid-cols-1 gap-2">
          <p className="text-footnote font-bold text-ink-secondary">{t(bands[b.band])}</p>
          {b.entries[0] && <p className="flex items-center gap-2 font-bold"><Icon name="crown" className="size-4" />{t('Champion: {names}', { names: new Intl.ListFormat(currentLocale()).format(b.entries.filter((e) => e.rank === 1).map((e) => e.nickname)) })}</p>}
          <Board entries={b.entries} unit="games" />
        </div>
      ))}
    </section>
  );
}
