// 公开看板（/live/<码>/）：不用登录，场边扫二维码看。排场看板（场地、接下来、等候）或比赛看板（对阵、积分榜）。
// 只有名字。顶上“我是…”选自己的名字（只记在这台手机上，只用来高亮）；这台手机报过名的自动认出来
import { useState } from 'react';
import { deviceTokens, formatName, sides, teamName, Updated, useNow, useUpdatedAt, type MatchView } from './club';
import { t } from './i18n';
import { Empty, Notice, Tag } from './kit';
import { Final, MatchBody } from './Match';
import { Sheet } from './Nearby';
import { useLive } from './supabase';
import { hours } from './time';
import { Button, Skeleton } from './ui';

type NightBoard = {
  kind: 'night';
  group: string;
  venue: string;
  tz: string | null;
  starts_at: string;
  ends_at: string;
  started: boolean;
  doubles: boolean;
  courts: { court: number; players: string[]; started_at: string }[];
  next: string[][];
  /** 按排队的顺序 */
  people: { id: string; name: string; status: 'absent' | 'here' | 'resting' | 'left'; games: number; on_court: number | null }[];
  me: string | null;
  match: (MatchView & { me: string | null }) | null;
};
type Board = NightBoard | (MatchView & { me: string | null });

const pickKey = (code: string) => `badie.liveMe.${code}`;

function loadPick(code: string) {
  try {
    return localStorage.getItem(pickKey(code));
  } catch {
    return null;
  }
}

function savePick(code: string, id: string | null) {
  try {
    if (id) localStorage.setItem(pickKey(code), id);
    else localStorage.removeItem(pickKey(code));
  } catch {}
}

export function LiveBoard({ code }: { code: string }) {
  const [tokens] = useState(deviceTokens);
  const { data: b } = useLive<Board | null>('live_board', { args: { p_code: code, p_tokens: tokens }, every: 10_000 });
  const updated = useUpdatedAt(b);
  const [picked, setPicked] = useState(() => loadPick(code));
  const [choosing, setChoosing] = useState(false);

  if (b === undefined) return <Skeleton className="mx-auto h-96 max-w-2xl" />;
  if (b === null) {
    return (
      <Empty icon="court" tint="sky" title={t('This board has closed')} action={{ label: t('Home'), to: '/' }}>
        {t('Court boards close 24 hours after the session. Match results stay up for 7 days.')}
      </Empty>
    );
  }

  const people = b.kind === 'night' ? b.people.map((p) => ({ id: p.id, name: p.name })) : b.players.filter((p) => !p.withdrawn);
  const me = (picked && people.some((p) => p.id === picked) ? picked : null) ?? b.me;
  const choose = (id: string | null) => {
    savePick(code, id);
    setPicked(id);
    setChoosing(false);
  };

  return (
    <div className="mx-auto grid w-full max-w-2xl gap-4 pb-12">
      <header className="grid gap-1">
        <h1 className="text-title lg:text-display">{b.kind === 'night' ? b.group : b.name}</h1>
        <p className="text-footnote font-bold text-ink-secondary">
          {b.kind === 'night' ? `${b.venue} · ${hours(b.starts_at, b.ends_at, b.tz)}` : [formatName(b.format, b.play), b.venue].filter(Boolean).join(' · ')}
        </p>
      </header>

      <div className="flex flex-wrap items-center gap-2">
        <p className="min-w-0 flex-1 font-black">{me ? <You b={b} me={me} /> : t('Tap “I am…” to see your next game.')}</p>
        <Button variant="quiet" className="button-sm" onClick={() => setChoosing(true)}>{t('I am…')}</Button>
      </div>

      {b.kind === 'night' ? <NightView b={b} me={me} /> : b.status === 'done' ? <Final m={b} share={false} /> : <MatchBody m={b} me={me} />}
      <Updated at={updated} />

      <Sheet open={choosing} onClose={() => setChoosing(false)} labelledBy="me-title">
        <h2 id="me-title" className="text-title3">{t('Which one is you?')}</h2>
        <p className="text-footnote text-ink-secondary">{t('Only saved on this phone, to highlight your games.')}</p>
        <ul className="flex flex-wrap gap-2">
          {people.map((p) => (
            <li key={p.id}><button type="button" className="toggle" aria-pressed={p.id === me} onClick={() => choose(p.id)}>{p.name}</button></li>
          ))}
        </ul>
        {picked && <Button variant="quiet" onClick={() => choose(null)}>{t('Clear')}</Button>}
      </Sheet>
    </div>
  );
}

/** 最上面一行：“你：场地 2” / “你：下一场” / “你：等候中 · 今晚 2 场” */
function You({ b, me }: { b: Board; me: string }) {
  if (b.kind === 'night') {
    const p = b.people.find((x) => x.id === me);
    if (!p) return null;
    if (p.on_court) return <>{t('You: court {n}', { n: p.on_court })}</>;
    if (b.next[0]?.includes(me)) return <>{t('You: next game')}</>;
    if (p.status === 'resting') return <>{t('You: resting')}</>;
    if (p.status === 'here') return <>{t('You: waiting · {n} game tonight|You: waiting · {n} games tonight', { n: p.games })}</>;
    return <>{p.name}</>;
  }
  const mine = b.games.filter((g) => [...g.a, ...g.b].includes(me));
  const playing = mine.find((g) => g.status === 'playing');
  if (playing) return <>{t('You: court {n}', { n: playing.court ?? '' })}</>;
  const first = b.games.find((g) => g.status === 'queued');
  if (first && mine.includes(first)) return <>{t('You: next game')}</>;
  const later = mine.find((g) => g.status === 'queued');
  if (later) return <>{t('You: round {n}', { n: later.round })}</>;
  return <>{b.players.find((p) => p.id === me)?.name}</>;
}

function NightView({ b, me }: { b: NightBoard; me: string | null }) {
  const now = useNow(30_000);
  const names = new Map(b.people.map((p) => [p.id, p.name]));
  // 从当晚开的比赛在打：看板显示比赛（“我是…”选的是报名，比赛里按名字对上）
  if (b.match) {
    const matchMe = b.match.me ?? b.match.players.find((p) => p.name === names.get(me ?? ''))?.id ?? null;
    return <MatchBody m={b.match} me={matchMe} />;
  }
  if (!b.started) return <Notice icon="clock" tint="butter">{t('The courts haven’t started yet.')}</Notice>;
  const waiting = b.people.filter((p) => p.status === 'here' && p.on_court === null);
  const resting = b.people.filter((p) => p.status === 'resting');
  return (
    <>
      <div className="grid gap-3">
        {b.courts.length === 0 && <p className="text-footnote text-ink-secondary">{t('Waiting for players')}</p>}
        {b.courts.map((c) => (
          <article key={c.court} className={`sticker grid gap-1 py-3 pr-3 pl-4 ${me && c.players.includes(me) ? 'ring-4 ring-lime' : ''}`}>
            <div className="flex items-center gap-2">
              <span className="chip bg-sky text-footnote font-black">{t('Court {n}', { n: c.court })}</span>
              <span className="text-footnote font-bold text-ink-secondary tabular-nums">{t('{n} min', { n: Math.max(0, Math.floor((now - new Date(c.started_at).getTime()) / 60_000)) })}</span>
            </div>
            {sides(c.players).map((team, i) => <p key={i} className="text-headline">{teamName(team, names)}</p>)}
          </article>
        ))}
      </div>
      {b.next.length > 0 && (
        <section aria-labelledby="board-next" className="tile grid gap-1.5 bg-surface px-4 py-3">
          <h2 id="board-next" className="text-footnote font-bold text-ink-secondary">{t('Up next')}</h2>
          {b.next.map((group, i) => {
            const [x, y] = sides(group);
            return (
              <p key={i} className="flex flex-wrap items-center gap-x-2 text-headline">
                <span>{teamName(x, names)}</span><span className="text-caption text-ink-secondary">{t('vs')}</span><span>{teamName(y, names)}</span>
              </p>
            );
          })}
        </section>
      )}
      <section aria-labelledby="board-waiting" className="grid gap-2">
        <h2 id="board-waiting" className="text-footnote font-bold text-ink-secondary">{t('Waiting · games tonight')}</h2>
        <ul className="flex flex-wrap gap-2">
          {[...waiting, ...resting].map((p) => (
            <li key={p.id} className={`flex h-10 items-center gap-2 rounded-full border-[1.5px] border-stroke pr-1 pl-3 ${p.id === me ? 'bg-lime' : p.status === 'resting' ? 'bg-surface-muted text-ink-secondary' : 'bg-surface'}`}>
              <span className="font-black">{p.name}</span>
              {p.status === 'resting' && <Tag>{t('Resting')}</Tag>}
              <span className="grid size-7 place-items-center rounded-full bg-surface-muted text-footnote font-black tabular-nums" aria-label={t('{n} game tonight|{n} games tonight', { n: p.games })}>{p.games}</span>
            </li>
          ))}
        </ul>
      </section>
    </>
  );
}
