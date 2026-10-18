import { useEffect, useState } from 'react';
import { tier } from './assessment';
import { currentLocale, t } from './i18n';
import { Link } from './router';
import { supabase, useLive, type BoardEntry, type VenueBoard, type WeeklyBoard } from './supabase';
import { EmptyState, PageHeader, Skeleton } from './ui';

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
    <div>
      <PageHeader back="/games/" title={t('Leaderboard')}>
        {t('Every confirmed game earns points, wins or losses, so playing more counts. Results both sides confirmed only.')}
      </PageHeader>

      <div className="grid gap-10 lg:grid-cols-[minmax(0,1fr)_22rem] lg:items-start">
        <section aria-labelledby="weekly" className="grid gap-4">
          <div className="flex flex-wrap items-end justify-between gap-3">
            <div>
              <h2 id="weekly" className="text-xl font-black">{t(weeks[week])}</h2>
              <p className="text-sm text-ink-tertiary">{t('Resets every Monday (UTC). Loss 10, win 15, more against stronger players.')}</p>
            </div>
            <Periods labels={weeks} value={week} onChange={setWeek} />
          </div>
          <div role="group" aria-label={t('Who to compare with')} className="flex flex-wrap gap-2">
            {scopes.map(([value, label]) => (
              <button key={value} onClick={() => setScope(value)} aria-pressed={scope === value} className="toggle">{t(label)}</button>
            ))}
          </div>
          {board && <MyPosition board={board} past={week > 0} />}
          {!board ? <Skeleton className="h-64" /> : board.entries.length === 0 ? (
            week > 0 ? <EmptyState title={t('No one made the board last week')} /> : (
              <EmptyState title={t('No one on the board yet')}>{t('Players appear after 3 confirmed games against 2 or more opponents this week.')}</EmptyState>
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

/** 本期 / 上一期 */
function Periods({ labels, value, onChange }: { labels: readonly string[]; value: number; onChange: (value: number) => void }) {
  return (
    <div role="group" aria-label={t('Period')} className="flex gap-2">
      {labels.map((label, i) => (
        <button key={label} onClick={() => onChange(i)} aria-pressed={value === i} className="toggle">{t(label)}</button>
      ))}
    </div>
  );
}

function MyPosition({ board, past }: { board: WeeklyBoard; past: boolean }) {
  if (past) {
    return board.me ? <p role="status" className="tile bg-lavender p-4 font-bold text-on-accent">{t('You finished #{rank} with {points} points.', { ...board.me })}</p> : null;
  }
  const text = !board.eligible
    ? t('You’re not on the boards: new accounts join after 7 days, and you can turn boards on in Me.')
    : board.me
      ? t('You’re #{rank} with {points} points.', { rank: board.me.rank, points: board.me.points })
      : board.progress
        ? t('{points} points so far. You’ll appear after 3 games against 2 different opponents (now {games} and {opponents}).', { ...board.progress })
        : t('Play 3 confirmed games against 2 different opponents this week to appear.');
  return <p role="status" className="tile bg-lavender p-4 font-bold text-on-accent">{text}</p>;
}

function Board({ entries, unit }: { entries: BoardEntry[]; unit: 'pts' | 'games' }) {
  return (
    <ol className="tile divide-y-2 divide-stroke/10 overflow-hidden bg-surface">
      {entries.map((e) => (
        <li key={e.id} className={`flex items-center gap-3 px-4 py-3 ${e.me ? 'bg-butter/40' : ''}`}>
          <span className={`w-8 shrink-0 text-center font-black tabular-nums ${e.rank <= 3 ? 'text-lg' : 'text-ink-tertiary'}`}>{e.rank}</span>
          <Link to={`/players/${e.id}/`} className="min-w-0 flex-1">
            <span className="block truncate font-black">{e.me ? t('{name} (you)', { name: e.nickname }) : e.nickname}</span>
            <span className="text-sm text-ink-tertiary">
              {[t('Level {level}', { level: tier(e.rating).label }), unit === 'pts' && t('{n} game|{n} games', { n: e.games }), t('{n} win|{n} wins', { n: e.wins })].filter(Boolean).join(' · ')}
            </span>
          </Link>
          <span className="shrink-0 text-lg font-black tabular-nums">{unit === 'pts' ? t('{n} pts', { n: e.points ?? 0 }) : t('{n} game|{n} games', { n: e.games })}</span>
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
    <section aria-labelledby="courts" className="grid gap-4">
      <div>
        <h2 id="courts" className="text-xl font-black">{t('Court champions')}</h2>
        <p className="text-sm text-ink-tertiary">{t('Most confirmed games at a court this month, by level. Up to 3 a day and 4 against the same opponent.')}</p>
      </div>
      {courts?.length === 0 && (
        <EmptyState title={t('Save a court first')} action={<Link to="/courts/" className="button button-quiet">{t('Courts')}</Link>}>
          {t('Boards show for the courts you’ve starred.')}
        </EmptyState>
      )}
      {courts && courts.length > 0 && (
        <>
          <select aria-label={t('Court')} value={court} onChange={(e) => setCourt(e.target.value)} className="field">
            {courts.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
          <Periods labels={months} value={month} onChange={setMonth} />
        </>
      )}
      {court && !board && <Skeleton className="h-40" />}
      {court && board && board.bands.length === 0 && (
        <p className="text-ink-secondary">{month > 0 ? t('No one qualified last month.') : t('No one qualifies yet this month: 3 games against 2 opponents.')}</p>
      )}
      {court && board?.bands.map((b) => (
        <div key={b.band} className="grid gap-2">
          <p className="eyebrow">{t(bands[b.band])}</p>
          {b.entries[0] && <p className="font-bold">{t('Champion: {names}', { names: new Intl.ListFormat(currentLocale()).format(b.entries.filter((e) => e.rank === 1).map((e) => e.nickname)) })}</p>}
          <Board entries={b.entries} unit="games" />
        </div>
      ))}
    </section>
  );
}
