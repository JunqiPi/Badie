import { useEffect, useState } from 'react';
import { tier } from './assessment';
import { Link } from './router';
import { supabase, useLive, type BoardEntry, type VenueBoard, type WeeklyBoard } from './supabase';
import { EmptyState, PageHeader, Skeleton } from './ui';

/** “我的球局”下的两个页面 */
export function GamesTabs({ current }: { current: 'games' | 'rankings' }) {
  return (
    <nav aria-label="Games" className="mb-8 flex gap-2">
      <Link to="/app/games/" aria-current={current === 'games' ? 'page' : undefined} className="toggle aria-[current=page]:bg-butter aria-[current=page]:text-on-accent">My games</Link>
      <Link to="/app/rankings/" aria-current={current === 'rankings' ? 'page' : undefined} className="toggle aria-[current=page]:bg-butter aria-[current=page]:text-on-accent">Rankings</Link>
    </nav>
  );
}

const scopes = [['global', 'Everyone'], ['country', 'My country'], ['level', 'My level']] as const;
const bands = ['', 'Levels 1–2', 'Levels 3–4', 'Levels 5–6', 'Levels 7+'];

export function Rankings() {
  const [scope, setScope] = useState<(typeof scopes)[number][0]>('global');
  const { data: board } = useLive<WeeklyBoard>('weekly_board', { args: { p_scope: scope }, every: 120_000 });

  return (
    <div>
      <PageHeader eyebrow="My games" title="Rankings">
        Every confirmed game earns points, wins or losses, so playing more counts. Results both sides confirmed only.
      </PageHeader>
      <GamesTabs current="rankings" />

      <div className="grid gap-10 lg:grid-cols-[minmax(0,1fr)_22rem] lg:items-start">
        <section aria-labelledby="weekly" className="grid gap-4">
          <div className="flex flex-wrap items-end justify-between gap-3">
            <div>
              <h2 id="weekly" className="text-xl font-black">This week</h2>
              <p className="text-sm text-ink-tertiary">Resets every Monday (UTC). Loss 10, win 15, more against stronger players.</p>
            </div>
            <div role="group" aria-label="Who to compare with" className="flex flex-wrap gap-2">
              {scopes.map(([value, label]) => (
                <button key={value} onClick={() => setScope(value)} aria-pressed={scope === value} className="toggle">{label}</button>
              ))}
            </div>
          </div>
          {board && <MyPosition board={board} />}
          {!board ? <Skeleton className="h-64" /> : board.entries.length === 0 ? (
            <EmptyState title="No one on the board yet">Players appear after 3 confirmed games against 2 or more opponents this week.</EmptyState>
          ) : (
            <Board entries={board.entries} unit="pts" />
          )}
        </section>

        <CourtBoards />
      </div>
    </div>
  );
}

function MyPosition({ board }: { board: WeeklyBoard }) {
  const text = !board.eligible
    ? 'You’re not on the boards: new accounts join after 7 days, and you can turn boards on in Me.'
    : board.me
      ? `You’re #${board.me.rank} with ${board.me.points} points.`
      : board.progress
        ? `${board.progress.points} points so far. You’ll appear after 3 games against 2 different opponents (now ${board.progress.games} and ${board.progress.opponents}).`
        : 'Play 3 confirmed games against 2 different opponents this week to appear.';
  return <p role="status" className="tile bg-lavender p-4 font-bold text-on-accent">{text}</p>;
}

function Board({ entries, unit }: { entries: BoardEntry[]; unit: 'pts' | 'games' }) {
  return (
    <ol className="tile divide-y-2 divide-stroke/10 overflow-hidden bg-surface">
      {entries.map((e) => (
        <li key={e.id} className={`flex items-center gap-3 px-4 py-3 ${e.me ? 'bg-butter/40' : ''}`}>
          <span className={`w-8 shrink-0 text-center font-black tabular-nums ${e.rank <= 3 ? 'text-lg' : 'text-ink-tertiary'}`}>{e.rank}</span>
          <Link to={`/app/players/${e.id}/`} className="min-w-0 flex-1">
            <span className="block truncate font-black">{e.me ? `${e.nickname} (you)` : e.nickname}</span>
            <span className="text-sm text-ink-tertiary">Level {tier(e.rating).label} · {unit === 'pts' ? `${e.games} games · ` : ''}{e.wins} wins</span>
          </Link>
          <span className="shrink-0 text-lg font-black tabular-nums">{unit === 'pts' ? `${e.points} pts` : `${e.games} games`}</span>
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
  const { data: board } = useLive<VenueBoard>('venue_board', { args: { p_venue: court ?? '' }, every: 300_000 });

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
        <h2 id="courts" className="text-xl font-black">Court champions</h2>
        <p className="text-sm text-ink-tertiary">Most confirmed games at a court this month, by level. Up to 3 a day and 4 against the same opponent.</p>
      </div>
      {courts?.length === 0 && (
        <EmptyState title="Save a court first" action={<Link to="/app/courts/" className="button button-quiet">Courts</Link>}>
          Boards show for the courts you’ve starred.
        </EmptyState>
      )}
      {courts && courts.length > 0 && (
        <select aria-label="Court" value={court} onChange={(e) => setCourt(e.target.value)} className="field">
          {courts.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </select>
      )}
      {court && !board && <Skeleton className="h-40" />}
      {court && board && board.bands.length === 0 && <p className="text-ink-secondary">No one qualifies yet this month: 3 games against 2 opponents.</p>}
      {court && board?.bands.map((b) => (
        <div key={b.band} className="grid gap-2">
          <p className="eyebrow">{bands[b.band]}</p>
          {b.entries[0] && <p className="font-bold">Champion: {b.entries.filter((e) => e.rank === 1).map((e) => e.nickname).join(', ')}</p>}
          <Board entries={b.entries} unit="games" />
        </div>
      ))}
    </section>
  );
}
