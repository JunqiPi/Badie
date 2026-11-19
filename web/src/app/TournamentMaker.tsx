// 不登录也能用的排表（/badminton-tournament-maker/）：填名字、选赛制，马上排出全部对阵，可以打印、复制链接。
// 排法和登录后的“比赛”一样（src/lib/tournament.ts）；要输比分、看实时看板就点“在 Badie 里开始”，名单带到新建比赛页
import { useEffect, useMemo, useState } from 'react';
import { cleanNames, countProblem, makerKey, schedule, type Format, type Plan } from '../lib/tournament';
import { copyText, formatName, Stepper } from './club';
import { t, useLocale } from './i18n';
import { Icon } from './icons';
import { Segmented } from './kit';
import { Button } from './ui';

const example = 'Amy\nBen\nCara\nDan\nEva\nFinn\nGia\nHugo';
const formats: Format[] = ['rotating', 'singles', 'fixed', 'groups'];

interface Settings {
  text: string;
  format: Format;
  courts: number;
  points: 21 | 15 | 11;
  bestOf: 1 | 3;
  pools: number;
  advance: number;
  rounds?: number;
}

const defaults: Settings = { text: example, format: 'rotating', courts: 2, points: 21, bestOf: 1, pools: 2, advance: 1 };

/** 分享链接：设置放在 # 后面，不经过服务器 */
function toHash(s: Settings) {
  const q = new URLSearchParams({ p: cleanNames(s.text).join(','), f: s.format, c: String(s.courts), pt: String(s.points), b: String(s.bestOf) });
  if (s.format === 'groups') q.set('g', `${s.pools}-${s.advance}`);
  if (s.rounds && s.format !== 'groups') q.set('r', String(s.rounds));
  return q.toString();
}

function fromHash(hash: string): Settings | undefined {
  const q = new URLSearchParams(hash.replace(/^#/, ''));
  if (!q.get('p')) return undefined;
  const pick = <T,>(value: T, allowed: readonly T[], fallback: T) => (allowed.includes(value) ? value : fallback);
  const [pools, advance] = (q.get('g') ?? '2-1').split('-').map(Number);
  return {
    text: cleanNames(q.get('p')!).join('\n'),
    format: pick(q.get('f') as Format, formats, 'rotating'),
    courts: Math.min(Math.max(Number(q.get('c')) || 2, 1), 12),
    points: pick(Number(q.get('pt')) as 21 | 15 | 11, [21, 15, 11], 21),
    bestOf: pick(Number(q.get('b')) as 1 | 3, [1, 3], 1),
    pools: pick(pools, [2, 3, 4], 2),
    advance: pools === 2 ? pick(advance, [1, 2], 1) : 1,
    rounds: Number(q.get('r')) || undefined,
  };
}

const problemText = {
  max: () => t('Up to 64 players.'),
  min2: () => t('Add at least 2 players.'),
  rotating4: () => t('Rotating partners need at least 4 players.'),
  fixed4: () => t('Fixed partners need at least 4 players.'),
  fixedEven: () => t('Fixed partners need an even number. Add 1 more player.'),
  groups: (pools: number) => t('{pools} groups need at least {n} players.', { pools, n: pools * 2 }),
};

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
  const problem = countProblem(s.format, players.length, s.pools);
  const plan: Plan = { format: s.format, players, courts: s.courts, points: s.points, bestOf: s.bestOf, pools: s.pools, advance: s.advance, rounds: s.rounds };
  const result = useMemo(() => (problem ? undefined : schedule(plan)), [JSON.stringify(plan), problem]);
  const rounds = s.rounds && result ? Math.min(s.rounds, result.fullRounds) : undefined;

  function runLive() {
    try {
      sessionStorage.setItem(makerKey, JSON.stringify({ ...plan, rounds, at: Date.now() }));
    } catch {
      // 存不了就只带不过去名单，新建比赛页照常能用
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
          {problem && players.length > 0 && <p className="text-footnote font-bold text-danger">{problemText[problem](s.pools)}</p>}
        </section>

        <section aria-labelledby="maker-format" className="grid gap-3">
          <h2 id="maker-format" className="text-title3">{t('Match format')}</h2>
          <div className="grid grid-cols-2 gap-2">
            {formats.map((f) => (
              <button key={f} type="button" aria-pressed={s.format === f} className="toggle min-h-12 whitespace-normal" onClick={() => set({ format: f, rounds: undefined })}>
                {formatName(f)}
              </button>
            ))}
          </div>
          {s.format === 'groups' && (
            <div className="sticker grid gap-3 p-4">
              <Segmented label={t('Number of groups')} value={String(s.pools)} onChange={(v) => set({ pools: Number(v), advance: v === '2' ? s.advance : 1 })}
                         options={[2, 3, 4].map((n) => ({ value: String(n), label: t('{n} groups', { n }) }))} />
              {s.pools === 2 ? (
                <Segmented label={t('Who goes through')} value={String(s.advance)} onChange={(v) => set({ advance: Number(v) })}
                           options={[{ value: '1', label: t('Top 1 of each group') }, { value: '2', label: t('Top 2 of each group') }]} />
              ) : <p className="text-footnote text-ink-secondary">{s.pools === 3 ? t('Group winners and the best runner-up play the semifinals.') : t('Group winners play the semifinals.')}</p>}
            </div>
          )}
          {s.format === 'fixed' && <p className="text-footnote text-ink-secondary">{t('Pairs follow the list: 1st with 2nd, 3rd with 4th.')}</p>}
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
            {result && s.format !== 'groups' && result.fullRounds > 1 && (
              <Stepper label={t('Rounds')} value={rounds ?? result.fullRounds} min={1} max={result.fullRounds} text={String(rounds ?? result.fullRounds)}
                       onChange={(n) => set({ rounds: n === result.fullRounds ? undefined : n })} />
            )}
          </div>
        </section>
      </div>

      {result && (
        <section aria-labelledby="maker-schedule" className="grid gap-4">
          <div className="grid gap-3">
            <h2 id="maker-schedule" className="text-title2">{formatName(s.format)}</h2>
            <p className="flex items-center gap-2 text-footnote font-bold">
              <Icon name="clock" className="size-4" />
              {t('About {n} round, {minutes} min|About {n} rounds, {minutes} min', { n: result.rounds.length + (result.knockout.length ? (result.knockout.length > 1 ? 2 : 1) : 0), minutes: result.minutes })}
            </p>
            <div className="flex flex-wrap gap-2 print:hidden">
              <Button onClick={runLive}>{t('Run it live in Badie')}</Button>
              <Button variant="quiet" onClick={() => {
                history.replaceState(null, '', `#${toHash({ ...s, rounds })}`);
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
            {result.rounds.map((r) => (
              <li key={r.round} className="sticker break-inside-avoid p-4">
                <h3 className="text-headline">{t('Round {n}', { n: r.round })}</h3>
                <ol className="mt-2 grid gap-1.5">
                  {r.games.map((g, i) => (
                    <li key={i} className="flex flex-wrap items-baseline gap-x-2 tabular-nums">
                      {g.pool && <span className="text-caption font-bold text-ink-secondary">{t('Group {n}', { n: g.pool })}</span>}
                      <span className="font-bold">{g.a.join(' · ')}</span>
                      <span className="text-footnote text-ink-tertiary">{t('vs')}</span>
                      <span className="font-bold">{g.b.join(' · ')}</span>
                    </li>
                  ))}
                </ol>
                {r.resting.length > 0 && <p className="mt-2 text-footnote text-ink-secondary">{t('Resting: {names}', { names: r.resting.join(', ') })}</p>}
              </li>
            ))}
            {result.knockout.length > 0 && (
              <li className="sticker break-inside-avoid p-4">
                <h3 className="text-headline">{result.knockout.map((k) => (k === 'semi' ? t('Semifinal') : t('Final'))).filter((x, i, all) => all.indexOf(x) === i).join(' · ')}</h3>
                <p className="mt-1 text-footnote text-ink-secondary">{t('Knockout games are set once the group games are done.')}</p>
              </li>
            )}
          </ol>
        </section>
      )}
    </div>
  );
}
