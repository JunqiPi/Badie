// 不登录也能用的排表（/badminton-tournament-maker/）：填名字、选参赛方式和赛制，马上排出对阵，可以打印、复制链接。
// 排法和登录后的“比赛”一样（src/lib/tournament.ts）；瑞士轮第 2 轮起、淘汰赛第 2 轮起要看比分，这里只写出有哪几轮。
// 要输比分、看实时看板就点“在 Badie 里开始”，名单和设置带到新建比赛页
import { useEffect, useMemo, useState } from 'react';
import { cleanNames, countProblem, effectiveFormat, makerKey, schedule, type Game, type Plan, type Play, type Structure } from '../lib/tournament';
import { copyText, formatName, playName, Stepper, structureName, Switch } from './club';
import { t, useLocale } from './i18n';
import { Icon } from './icons';
import { Segmented } from './kit';
import { Button } from './ui';

const example = 'Amy\nBen\nCara\nDan\nEva\nFinn\nGia\nHugo';
const plays: Play[] = ['singles', 'fixed', 'rotating'];
const formats: Structure[] = ['round_robin', 'groups', 'swiss', 'knockout'];

interface Settings {
  text: string;
  play: Play;
  format: Structure;
  courts: number;
  points: 21 | 15 | 11;
  bestOf: 1 | 3;
  pools: number;
  advance: number;
  thirdPlace: boolean;
  rounds?: number;
}

const defaults: Settings = { text: example, play: 'rotating', format: 'round_robin', courts: 2, points: 21, bestOf: 1, pools: 2, advance: 1, thirdPlace: false };

/** 分享链接：设置放在 # 后面，不经过服务器 */
function toHash(s: Settings) {
  const q = new URLSearchParams({ p: cleanNames(s.text).join(','), m: s.play, f: s.format, c: String(s.courts), pt: String(s.points), b: String(s.bestOf) });
  if (s.format === 'groups') q.set('g', `${s.pools}-${s.advance}`);
  if (s.thirdPlace) q.set('t', '1');
  if (s.rounds) q.set('r', String(s.rounds));
  return q.toString();
}

function fromHash(hash: string): Settings | undefined {
  const q = new URLSearchParams(hash.replace(/^#/, ''));
  if (!q.get('p')) return undefined;
  const pick = <T,>(value: T, allowed: readonly T[], fallback: T) => (allowed.includes(value) ? value : fallback);
  const [pools, advance] = (q.get('g') ?? '2-1').split('-').map(Number);
  return {
    text: cleanNames(q.get('p')!).join('\n'),
    play: pick(q.get('m') as Play, plays, 'rotating'),
    format: pick(q.get('f') as Structure, formats, 'round_robin'),
    courts: Math.min(Math.max(Number(q.get('c')) || 2, 1), 12),
    points: pick(Number(q.get('pt')) as 21 | 15 | 11, [21, 15, 11], 21),
    bestOf: pick(Number(q.get('b')) as 1 | 3, [1, 3], 1),
    pools: Math.min(Math.max(pools || 2, 2), 8),
    advance: pick(advance, [1, 2], 1),
    thirdPlace: q.get('t') === '1',
    rounds: Number(q.get('r')) || undefined,
  };
}

function problemText(problem: NonNullable<ReturnType<typeof countProblem>>, pools: number) {
  switch (problem.code) {
    case 'max': return t('Up to 64 players.');
    case 'min2': return t('Add at least 2 players.');
    case 'rotating4': return t('Rotating partners need at least 4 players.');
    case 'fixed4': return t('Fixed partners need at least 4 players.');
    case 'fixedEven': return t('Fixed partners need an even number. Add 1 more player.');
    case 'swiss': return t('Swiss needs at least {n} players.', { n: problem.n });
    case 'groups': return t('{pools} groups need at least {n} players.', { pools, n: problem.n });
  }
}

/** 淘汰赛这一轮的名字（和 Match.tsx 的 gameLabel 一样） */
const koName = (size: number) =>
  size === 2 ? t('Final') : size === 4 ? t('Semifinal') : size === 8 ? t('Quarterfinal') : t('Round of {n}', { n: size });

function GameRow({ g }: { g: Game }) {
  return (
    <li className="flex flex-wrap items-baseline gap-x-2 tabular-nums">
      {g.pool && <span className="text-caption font-bold text-ink-secondary">{t('Group {n}', { n: g.pool })}</span>}
      <span className="font-bold">{g.a.join(' · ')}</span>
      <span className="text-footnote text-ink-tertiary">{t('vs')}</span>
      <span className="font-bold">{g.b.join(' · ')}</span>
    </li>
  );
}

export function TournamentMaker() {
  useLocale();
  const [s, setS] = useState<Settings>(defaults);
  const set = (patch: Partial<Settings>) => setS((old) => ({ ...old, ...patch }));

  // 打开分享的链接：用链接里的设置（放在 effect 里，服务器渲染的是示例）
  useEffect(() => {
    const shared = fromHash(location.hash);
    if (shared) setS(shared);
  }, []);

  const players = useMemo(() => cleanNames(s.text), [s.text]);
  const format = effectiveFormat(s.play, s.format);
  const byRounds = format === 'round_robin' || format === 'swiss';
  const knockout = format === 'groups' || format === 'knockout';
  const problem = countProblem(format, s.play, players.length, s.pools, s.advance);
  const plan: Plan = { ...s, format, players, thirdPlace: knockout && s.thirdPlace, rounds: byRounds ? s.rounds : undefined };
  const result = useMemo(() => (problem ? undefined : schedule(plan)), [JSON.stringify(plan), problem]);
  const rounds = result && byRounds ? Math.min(Math.max(s.rounds ?? result.defaultRounds, 1), result.maxRounds) : undefined;

  function runLive() {
    try {
      sessionStorage.setItem(makerKey, JSON.stringify({ ...plan, at: Date.now() }));
    } catch {
      // 存不了就带不过去名单，新建比赛页照常能用
    }
    location.href = '/matches/new/';
  }

  return (
    <div className="grid gap-6">
      <div className="grid gap-6 print:hidden">
        <section aria-labelledby="maker-players" className="grid gap-2">
          <div className="flex items-baseline gap-2">
            <label id="maker-players" htmlFor="maker-names" className="text-title3 flex-1">{t('Players, one per line')}</label>
            <span className="text-footnote font-bold text-ink-secondary">{t('{n} player|{n} players', { n: players.length })}</span>
            {s.text && <button type="button" className="link text-footnote" onClick={() => set({ text: '' })}>{t('Clear')}</button>}
          </div>
          <textarea id="maker-names" className="field min-h-44 font-bold" value={s.text} onChange={(e) => set({ text: e.target.value })}
                    spellCheck={false} autoCapitalize="words" />
          {problem && players.length > 0 && <p className="text-footnote font-bold text-danger">{problemText(problem, s.pools)}</p>}
        </section>

        <section aria-labelledby="maker-format" className="grid gap-3">
          <h2 id="maker-format" className="text-title3">{t('Match format')}</h2>
          <div className="grid grid-cols-3 gap-2" role="group" aria-label={t('Singles or doubles')}>
            {plays.map((p) => (
              <button key={p} type="button" aria-pressed={s.play === p} className="toggle min-h-12 whitespace-normal" onClick={() => set({ play: p, rounds: undefined })}>
                {playName(p)}
              </button>
            ))}
          </div>
          {s.play !== 'rotating' && (
            <div className="grid grid-cols-2 gap-2" role="group" aria-label={t('Match format')}>
              {formats.map((f) => (
                <button key={f} type="button" aria-pressed={format === f} className="toggle min-h-12 whitespace-normal" onClick={() => set({ format: f, rounds: undefined })}>
                  {structureName(f)}
                </button>
              ))}
            </div>
          )}
          {(format === 'groups' || knockout) && (
            <div className="sticker grid px-4">
              {format === 'groups' && (
                <>
                  <Stepper label={t('Number of groups')} value={s.pools} min={2} max={8} text={t('{n} groups', { n: s.pools })} onChange={(pools) => set({ pools })} />
                  <div className="pb-3">
                    <Segmented label={t('Who goes through')} value={String(s.advance)} onChange={(v) => set({ advance: Number(v) })}
                               options={[{ value: '1', label: t('Top 1 of each group') }, { value: '2', label: t('Top 2 of each group') }]} />
                  </div>
                </>
              )}
              <Switch checked={s.thirdPlace} onChange={(thirdPlace) => set({ thirdPlace })} title={t('Play for third place')} />
            </div>
          )}
          {s.play === 'fixed' && <p className="text-footnote text-ink-secondary">{t('Pairs follow the list: 1st with 2nd, 3rd with 4th.')}</p>}
          {s.play !== 'rotating' && format !== 'round_robin' && <p className="text-footnote text-ink-secondary">{t('List order is the seeding. Put the strongest first.')}</p>}
        </section>

        <section aria-labelledby="maker-game" className="grid gap-3">
          <h2 id="maker-game" className="text-title3">{t('Each game')}</h2>
          <div className="grid gap-2 sm:grid-cols-2">
            <Segmented label={t('Points')} value={String(s.points)} onChange={(v) => set({ points: Number(v) as 21 | 15 | 11 })}
                       options={[21, 15, 11].map((n) => ({ value: String(n), label: String(n) }))} />
            <Segmented label={t('Games per match')} value={String(s.bestOf)} onChange={(v) => set({ bestOf: Number(v) as 1 | 3 })}
                       options={[{ value: '1', label: t('One game') }, { value: '3', label: t('Best of 3') }]} />
          </div>
          <div className="sticker px-4">
            <Stepper label={t('Number of courts')} value={s.courts} min={1} max={12} text={String(s.courts)} onChange={(courts) => set({ courts })} />
            {result && rounds !== undefined && result.maxRounds > 1 && (
              <Stepper label={t('Rounds')} value={rounds} min={1} max={result.maxRounds} text={String(rounds)} onChange={(n) => set({ rounds: n })} />
            )}
            {result && format === 'round_robin' && s.play !== 'rotating' && result.fullRounds > 0 && (
              <p className="pb-3 text-footnote text-ink-secondary">{t('One full round robin is {n} rounds.', { n: result.fullRounds })}</p>
            )}
          </div>
        </section>
      </div>

      {result && (
        <section aria-labelledby="maker-schedule" className="grid gap-4">
          <div className="grid gap-3">
            <h2 id="maker-schedule" className="text-title2">{formatName(format, s.play)}</h2>
            <p className="flex items-center gap-2 text-footnote font-bold">
              <Icon name="clock" className="size-4" />
              {t('About {n} round, {minutes} min|About {n} rounds, {minutes} min', { n: result.rounds, minutes: result.minutes })}
            </p>
            <div className="flex flex-wrap gap-2 print:hidden">
              <Button onClick={runLive}>{t('Run it live in Badie')}</Button>
              <Button variant="quiet" onClick={() => {
                history.replaceState(null, '', `#${toHash({ ...s, format, rounds })}`);
                void copyText(location.href, t('Link copied'));
              }}><Icon name="link" className="size-4" />{t('Copy link')}</Button>
              <Button variant="quiet" onClick={() => window.print()}>{t('Print')}</Button>
            </div>
          </div>

          {result.pools.length > 0 && (
            <div className="grid gap-2 sm:grid-cols-2">
              {result.pools.map((pool, i) => (
                <div key={i} className="sticker p-4">
                  <h3 className="text-headline">{t('Group {n}', { n: i + 1 })}</h3>
                  <p className="text-subhead">{pool.join(', ')}</p>
                </div>
              ))}
            </div>
          )}

          <ol className="grid gap-3">
            {result.blocks.map((b, i) => (
              <li key={i} className="sticker break-inside-avoid p-4">
                <h3 className="text-headline">{b.ko ? koName(b.ko) : t('Round {n}', { n: b.round! })}</h3>
                <ol className="mt-2 grid gap-1.5">{b.games.map((g, j) => <GameRow key={j} g={g} />)}</ol>
                {b.byes.length > 0 && <p className="mt-2 text-footnote text-ink-secondary">{t('Bye: {names}', { names: b.byes.join(', ') })}</p>}
                {b.resting.length > 0 && <p className="mt-2 text-footnote text-ink-secondary">{t('Resting: {names}', { names: b.resting.join(', ') })}</p>}
              </li>
            ))}
            {result.swissLater && (
              <li className="sticker break-inside-avoid p-4">
                <h3 className="text-headline">
                  {t('Round {n}', { n: result.swissLater[0] === result.swissLater[1] ? result.swissLater[0] : `${result.swissLater[0]}–${result.swissLater[1]}` })}
                </h3>
                <p className="mt-1 text-footnote text-ink-secondary">{t('Paired by the standings after each round.')}</p>
              </li>
            )}
            {(result.koLater.length > 0 || result.third) && (
              <li className="sticker break-inside-avoid p-4">
                <h3 className="text-headline">{[...result.koLater.map(koName), ...(result.third ? [t('Third place')] : [])].join(' · ')}</h3>
                <p className="mt-1 text-footnote text-ink-secondary">
                  {format === 'groups' ? t('Knockout games are set once the group games are done.') : t('Winners move on to the next round.')}
                </p>
              </li>
            )}
          </ol>
        </section>
      )}
    </div>
  );
}
