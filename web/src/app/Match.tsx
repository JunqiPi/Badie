// 比赛（“+”菜单的“比赛 · 循环赛”，也能从当晚页开）：新建、进行中、输比分、最终排名、我的 → 比赛。
// 对阵和排名都是服务器排的；进行中的部分（MatchBody）公开看板也用，只是不能点
import { useEffect, useState, type SubmitEvent } from 'react';
import {
  clubProblem, formatName, QrSheet, scoreText, Stepper, Switch, UndoBar, Updated, useUpdatedAt,
  type MatchFormat, type MatchGame, type MatchState, type MatchView, type NightState, type Standing,
} from './club';
import { currentLocale, t } from './i18n';
import { Icon } from './icons';
import { Divider, Empty, IconButton, IconTile, Notice, Row, ScreenHeader, Segmented, Tag } from './kit';
import { Sheet } from './Nearby';
import { CourtSearch, type Court } from './pickers';
import { navigate } from './router';
import { problem, supabase, useLive, type Friend, type Profile } from './supabase';
import { renderStandings } from './standingsCard';
import { makerKey, type Plan } from '../lib/tournament';
import { day } from './time';
import { Button, Field, Skeleton, toast } from './ui';

// MARK: 小工具

/** 净胜分：+10 / −2 / 0 */
const signed = (n: number) => (n > 0 ? `+${n}` : n < 0 ? `−${-n}` : '0');

const namesOf = (m: MatchView) => new Map(m.players.map((p) => [p.id, p.name]));
const side = (ids: string[], names: Map<string, string>) => ids.map((id) => names.get(id) ?? '?').join(' · ');

function gameLabel(g: MatchGame) {
  if (g.stage === 'final') return t('Final');
  if (g.stage === 'semi') return t('Semifinal');
  return t('Round {n}', { n: g.round });
}

function statusLabel(g: MatchGame) {
  if (g.walkover) return t('Walkover');
  if (g.status === 'done') return scoreText(g.scores);
  if (g.status === 'playing') return t('Court {n}', { n: g.court ?? '' });
  if (g.status === 'cancelled') return t('Cancelled');
  if (g.status === 'skipped') return t('Not played');
  return '';
}

// MARK: 比赛页

export function MatchPage({ id }: { id: string }) {
  return (
    <div className="mx-auto grid w-full max-w-2xl gap-4 pb-24">
      <MatchLive id={id} />
    </div>
  );
}

/** 比赛页的内容（组织者、帮手、参赛的人）；当晚页的“比赛”分段也是它（embedded：不要返回按钮） */
export function MatchLive({ id, embedded = false }: { id: string; embedded?: boolean }) {
  const { data: m, refresh } = useLive<MatchState | null>('match_state', { args: { p_match: id }, every: 10_000 });
  const updated = useUpdatedAt(m);
  const [scoring, setScoring] = useState<number>();
  const [menu, setMenu] = useState(false);
  const [qr, setQr] = useState(false);
  const [qualify, setQualify] = useState(false);

  if (m === undefined) return <Skeleton className="h-96" />;
  if (m === null) {
    return <Empty icon="trophy" tint="butter" title={t('Match not found')} action={{ label: t('Matches'), to: '/matches/' }}>{t('It may have been deleted.')}</Empty>;
  }
  const manage = m.role !== 'player';
  const live = m.status === 'live';
  const subtitle = live
    ? [formatName(m.format), m.round && t('Round {n}/{total}', { n: m.round, total: m.rounds })].filter(Boolean).join(' · ')
    : `${m.name} · ${formatName(m.format)}`;
  const game = m.games.find((g) => g.id === scoring);
  const canScore = (g: MatchGame) =>
    manage ? g.status === 'playing' || g.status === 'done' : g.status === 'playing' && Boolean(m.me) && [...g.a, ...g.b].includes(m.me!);
  const buttons = (
    <>
      <IconButton icon="share" label={t('QR code and link')} onClick={() => setQr(true)} />
      {manage && <IconButton icon="dots" label={t('Match options')} onClick={() => setMenu(true)} />}
    </>
  );

  return (
    <>
      {embedded ? (
        <div className="flex items-center gap-3">
          <div className="min-w-0 flex-1">
            <h2 className="truncate text-title3">{m.name}</h2>
            <p className="text-footnote font-bold text-ink-secondary">{subtitle}</p>
          </div>
          {buttons}
        </div>
      ) : (
        <div className="grid gap-1">
          <ScreenHeader title={live ? m.name : t('Final standings')} back={m.session_id && manage ? `/night/${m.session_id}/?tab=match` : '/matches/'}>{buttons}</ScreenHeader>
          <p className="text-center text-footnote font-bold text-ink-secondary lg:text-left">{subtitle}</p>
        </div>
      )}

      {live && m.role === 'organizer' && m.tie_at_cut && !m.games.some((g) => g.stage !== 'pool' && g.status !== 'queued') && (
        <Notice icon="info" tint="butter" action={{ label: t('Choose'), onClick: () => setQualify(true) }}>
          {t('There’s a tie at the cut. You can choose who goes through.')}
        </Notice>
      )}

      {live ? (
        <MatchBody m={m} me={m.me ?? null} canScore={canScore} onScore={setScoring} manage={manage}
                   onFlag={async (g) => {
                     const { error } = await supabase!.rpc('match_flag', { p_game: g.id });
                     toast(error ? clubProblem(error) : t('Flagged. The organizer will check it.'), error ? 'error' : 'info');
                   }} />
      ) : (
        <Final m={m} />
      )}
      <Updated at={updated} />

      {game && <ScoreSheet key={game.id} m={m} game={game} onClose={() => setScoring(undefined)} onSaved={refresh} />}
      <QrSheet open={qr} onClose={() => setQr(false)} code={m.board_code} title={t('Match board')} />
      {manage && <MatchMenu open={menu} onClose={() => setMenu(false)} m={m} refresh={refresh} />}
      {m.role === 'organizer' && <QualifySheet open={qualify} onClose={() => setQualify(false)} m={m} refresh={refresh} />}
      {manage && <UndoBar until={m.undo_until} onUndo={async () => {
        const { error } = await supabase!.rpc('match_undo', { p_match: m.id });
        if (error) toast(clubProblem(error), 'error');
        await refresh();
      }} />}
    </>
  );
}

/** 进行中：正在打、下一场、积分榜、全部对阵。看板上没有 canScore，只能看 */
export function MatchBody({ m, me, canScore, onScore, onFlag, manage = false }: {
  m: MatchView;
  me: string | null;
  canScore?: (game: MatchGame) => boolean;
  onScore?: (game: number) => void;
  onFlag?: (game: MatchGame) => void;
  manage?: boolean;
}) {
  const names = namesOf(m);
  const playing = m.games.filter((g) => g.status === 'playing').sort((a, b) => (a.court ?? 0) - (b.court ?? 0));
  const queued = m.games.filter((g) => g.status === 'queued').slice(0, 3);
  const mine = (g: MatchGame) => Boolean(me) && [...g.a, ...g.b].includes(me!);
  return (
    <>
      <section aria-labelledby="playing" className="grid gap-3">
        <h2 id="playing" className="text-title3">{t('Playing now')}</h2>
        {playing.length === 0 && <p className="text-footnote text-ink-secondary">{t('No games on court right now.')}</p>}
        {playing.map((g) => (
          <article key={g.id} className={`sticker flex items-center gap-3 py-3 pr-3 pl-4 ${mine(g) ? 'ring-4 ring-lime' : ''}`}>
            <div className="grid min-w-0 flex-1 gap-1">
              <span className="chip w-fit bg-sky text-footnote font-black">{t('Court {n}', { n: g.court ?? '' })}</span>
              <p className="truncate text-headline">{side(g.a, names)}</p>
              <p className="truncate text-headline">{side(g.b, names)}</p>
            </div>
            {canScore?.(g) && <Button className="button-lg shrink-0" onClick={() => onScore?.(g.id)}>{t('Enter score')}</Button>}
          </article>
        ))}
      </section>

      {queued.length > 0 && (
        <section aria-labelledby="next-games" className="grid gap-2">
          <h2 id="next-games" className="text-title3">{t('Up next')}</h2>
          <ul className="tile grid divide-y-[1.5px] divide-divider bg-surface px-4">
            {queued.map((g) => (
              <li key={g.id} className={`flex flex-wrap items-center gap-x-2 py-2.5 font-black ${mine(g) ? 'text-ink' : ''}`}>
                <span>{side(g.a, names)}</span><span className="text-caption text-ink-secondary">{t('vs')}</span><span>{side(g.b, names)}</span>
                {mine(g) && <Tag tint="lime">{t('You')}</Tag>}
              </li>
            ))}
          </ul>
        </section>
      )}

      <Standings m={m} me={me} />

      <details className="tile bg-surface px-4 py-3">
        <summary className="cursor-pointer font-black">{t('All games ({n})', { n: m.games.length })}</summary>
        <ul className="mt-2 grid divide-y-[1.5px] divide-divider">
          {m.games.map((g) => {
            const open = canScore?.(g) && (manage || g.status === 'playing');
            return (
              <li key={g.id} className="flex flex-wrap items-center gap-2 py-2.5">
                <span className="w-24 shrink-0 text-caption font-bold text-ink-secondary">{gameLabel(g)}</span>
                <span className="min-w-0 flex-1 font-bold">
                  <span className={g.winner === 1 ? 'font-black' : ''}>{side(g.a, names)}</span>
                  <span className="text-caption text-ink-secondary"> {t('vs')} </span>
                  <span className={g.winner === 2 ? 'font-black' : ''}>{side(g.b, names)}</span>
                </span>
                <span className="text-footnote font-black tabular-nums">{statusLabel(g)}</span>
                {manage && g.flagged && <Tag tint="pink">{t('Check')}</Tag>}
                {/* 谁填的（“Amy 填的”），组织者、帮手改过的写“Kevin 改的” */}
                {g.status === 'done' && (g.edited_by || g.scored_by) && (
                  <span className="text-caption text-ink-secondary">
                    {g.edited_by ? t('Edited by {name}', { name: g.edited_by }) : t('Entered by {name}', { name: g.scored_by! })}
                  </span>
                )}
                {open && <Button variant="quiet" className="button-sm" onClick={() => onScore?.(g.id)}>{g.status === 'done' ? t('Edit') : t('Enter score')}</Button>}
                {!manage && onFlag && g.status === 'done' && !g.walkover && mine(g) && (
                  <button type="button" className="link text-caption" onClick={() => onFlag(g)}>{t('Not right')}</button>
                )}
              </li>
            );
          })}
        </ul>
      </details>
    </>
  );
}

/** 积分榜：分组循环每组一张；“?”里写排名规则 */
function Standings({ m, me }: { m: MatchView; me: string | null }) {
  const [rules, setRules] = useState(false);
  const pools = [...new Set(m.standings.map((s) => s.pool))];
  return (
    <section aria-labelledby="standings" className="grid gap-2">
      <div className="flex items-center gap-2">
        <h2 id="standings" className="text-title3">{t('Standings')}</h2>
        <button type="button" aria-expanded={rules} aria-label={t('How ranking works')} onClick={() => setRules(!rules)}
                className="press grid size-8 place-items-center rounded-full border-2 border-stroke bg-surface">
          <Icon name="question" className="size-4" />
        </button>
      </div>
      {rules && (
        <p className="tile bg-surface-muted p-3 text-footnote">
          {t('Ranked by wins. If people played a different number of games, by win rate. Then point difference, points scored, and the game between the two. If it’s still even, it’s a tie.')}
        </p>
      )}
      {pools.map((pool) => (
        <div key={pool ?? 0} className="grid gap-1.5">
          {pool !== null && pools.length > 1 && <h3 className="text-footnote font-bold text-ink-secondary">{t('Group {n}', { n: pool })}</h3>}
          <Table rows={m.standings.filter((s) => s.pool === pool)} me={me} />
        </div>
      ))}
    </section>
  );
}

function Table({ rows, me }: { rows: Standing[]; me: string | null }) {
  return (
    <table className="tile w-full border-separate border-spacing-0 overflow-hidden bg-surface text-left">
      <thead>
        <tr className="text-caption font-bold text-ink-secondary">
          <th scope="col" className="w-12 py-2 pl-4">#</th>
          <th scope="col" className="py-2">{t('Name')}</th>
          <th scope="col" className="py-2 text-right">{t('W–L')}</th>
          <th scope="col" className="py-2 pr-4 text-right">{t('+/−')}</th>
        </tr>
      </thead>
      <tbody>
        {rows.map((s) => (
          <tr key={s.key} className={`border-t ${me && s.members.includes(me) ? 'bg-lime/40' : ''} ${s.withdrawn ? 'text-ink-tertiary' : ''}`}>
            <td className="border-t-[1.5px] border-divider py-2.5 pl-4 font-black tabular-nums">{s.tied && s.played ? `=${s.rank}` : s.rank}</td>
            <td className="border-t-[1.5px] border-divider py-2.5 font-bold">
              {s.name}
              {s.withdrawn && <span className="ml-1.5 text-caption">{t('Withdrew')}</span>}
            </td>
            <td className="border-t-[1.5px] border-divider py-2.5 text-right font-bold tabular-nums">{s.wins}–{s.losses}</td>
            <td className="border-t-[1.5px] border-divider py-2.5 pr-4 text-right font-bold tabular-nums">{signed(s.diff)}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

/** 最终排名：冠军卡 + 列表 + 分享成图片 */
export function Final({ m, share = true }: { m: MatchView; share?: boolean }) {
  const ranking = m.ranking ?? m.standings;
  const [champion, ...rest] = ranking;
  const [busy, setBusy] = useState(false);

  async function shareImage() {
    setBusy(true);
    try {
      const blob = await renderStandings({
        title: m.name,
        subtitle: [formatName(m.format), m.venue, day(m.ended_at ?? m.created_at)].filter(Boolean).join(' · '),
        championLabel: t('Champion'),
        rows: ranking.map((s) => ({ rank: s.tied ? `=${s.rank}` : String(s.rank), name: s.name, record: `${s.wins}–${s.losses}`, diff: signed(s.diff) })),
        footer: 'BADIE.RSVP',
      });
      const file = new File([blob], 'badie-standings.png', { type: 'image/png' });
      if (typeof navigator.share === 'function' && navigator.canShare?.({ files: [file] })) {
        await navigator.share({ files: [file] });
      } else {
        // 电脑上不能分享文件：直接下载
        const link = document.createElement('a');
        link.href = URL.createObjectURL(blob);
        link.download = file.name;
        link.click();
        setTimeout(() => URL.revokeObjectURL(link.href), 10_000);
      }
    } catch (error) {
      if ((error as Error).name !== 'AbortError') toast(t('Couldn’t make the image. Try again.'), 'error');
    }
    setBusy(false);
  }

  if (!champion) return <p className="text-subhead text-ink-secondary">{t('No games were played.')}</p>;
  return (
    <>
      <section className="sticker flex items-center gap-4 bg-butter p-5 text-on-accent">
        <IconTile icon="trophy" tint="surface" size="lg" />
        <div className="min-w-0">
          <p className="text-footnote font-bold">{t('Champion')}</p>
          <p className="truncate text-title">{champion.name}</p>
          <p className="text-footnote font-bold">{t('{wins}–{losses} · {diff} points', { wins: champion.wins, losses: champion.losses, diff: signed(champion.diff) })}</p>
        </div>
      </section>
      {rest.length > 0 && <Table rows={rest} me={m.me ?? null} />}
      {share && <Button className="button-lg" busy={busy} onClick={shareImage}><Icon name="share" className="size-5" />{t('Share as image')}</Button>}
    </>
  );
}

// MARK: 输比分

function ScoreSheet({ m, game: g, onClose, onSaved }: { m: MatchState; game: MatchGame; onClose: () => void; onSaved: () => Promise<void> }) {
  const manage = m.role !== 'player';
  const names = namesOf(m);
  const [scores, setScores] = useState<number[]>(() => {
    const blank = Array<number>(m.best_of * 2).fill(0);
    return blank.map((zero, i) => g.scores?.[i] ?? zero);
  });
  const [set, setSet] = useState(0);
  const [typing, setTyping] = useState<number>();
  const [force, setForce] = useState(false);
  const [busy, setBusy] = useState<string>();
  const [leaving, setLeaving] = useState<string>();
  // 球员打开已经有比分的一场：只能看、点“不对”
  const readOnly = !manage && g.status === 'done';
  const cap = { 21: 30, 15: 21, 11: 15 }[m.points];

  const change = (i: number, value: number) => setScores(scores.map((x, j) => (j === i ? Math.max(0, Math.min(99, value)) : x)));

  async function save(confirmed = false) {
    // 三局两胜：只送打了的局
    const played = m.best_of === 1 ? scores : scores.filter((_, i) => scores[i - (i % 2)] + scores[i - (i % 2) + 1] > 0);
    setBusy('save');
    const { error } = await supabase!.rpc('match_score', { p_game: g.id, p_scores: played, p_version: g.version ?? 0, p_force: confirmed });
    setBusy(undefined);
    if (!error) {
      await onSaved();
      return onClose();
    }
    if (error.message === 'score_invalid' && manage) return setForce(true);
    if (error.message === 'score_taken' || error.message === 'score_changed') {
      toast(problem(error), 'error');
      await onSaved();
      return onClose();
    }
    // 网不好：数字留在原处
    toast(/fetch|network/i.test(error.message) ? t('Didn’t save. Try again.') : clubProblem(error), 'error');
  }

  async function withdraw(player: string) {
    setBusy(`out-${player}`);
    const { error } = await supabase!.rpc('match_withdraw', { p_player: player, p_game: g.id });
    setBusy(undefined);
    if (error) return toast(clubProblem(error), 'error');
    await onSaved();
    onClose();
  }

  return (
    <Sheet open onClose={onClose} labelledBy="score-title">
      <div>
        <h2 id="score-title" className="text-title3">{[g.court && t('Court {n}', { n: g.court }), gameLabel(g)].filter(Boolean).join(' · ')}</h2>
        <p className="text-footnote font-bold text-ink-secondary">
          {[t('{n} points', { n: m.points }), m.best_of === 3 ? t('Best of 3') : t('One game'), m.win_by_two && t('Win by 2, capped at {n}', { n: cap })].filter(Boolean).join(' · ')}
        </p>
      </div>

      {readOnly ? (
        <>
          <p className="text-title tabular-nums">{scoreText(g.scores) || t('Walkover')}</p>
          {(g.edited_by || g.scored_by) && (
            <p className="font-bold">{g.edited_by ? t('Edited by {name}', { name: g.edited_by }) : t('Entered by {name}', { name: g.scored_by! })}</p>
          )}
          <p className="text-subhead text-ink-secondary">{t('Someone already entered this score. If it’s wrong, let the organizer know.')}</p>
        </>
      ) : (
        <>
          {m.best_of === 3 && (
            <Segmented label={t('Which game')} value={String(set)} onChange={(v) => setSet(Number(v))}
                       options={[0, 1, 2].map((i) => ({ value: String(i), label: t('Game {n}', { n: i + 1 }) }))} />
          )}
          <div className="grid grid-cols-2 gap-3">
            {[g.a, g.b].map((team, k) => {
              const i = set * 2 + k;
              return (
                <div key={k} className="grid justify-items-center gap-2 text-center">
                  <span className="min-h-10 text-footnote font-black">{side(team, names)}</span>
                  {typing === i ? (
                    <input autoFocus type="number" inputMode="numeric" min={0} max={99} value={scores[i]} aria-label={t('Score for {name}', { name: side(team, names) })}
                           onChange={(e) => change(i, Number(e.target.value))} onBlur={() => setTyping(undefined)}
                           className="field h-24 text-center text-[3rem] font-black tabular-nums" />
                  ) : (
                    <button type="button" onClick={() => setTyping(i)} aria-label={t('Score for {name}. Tap to type.', { name: side(team, names) })}
                            className="sticker grid h-24 w-full place-items-center text-[3rem] font-black tabular-nums">{scores[i]}</button>
                  )}
                  <div className="flex gap-2">
                    <button type="button" aria-label={t('Minus 1')} onClick={() => change(i, scores[i] - 1)}
                            className="press grid size-12 place-items-center rounded-[14px] border-2 border-stroke bg-surface-muted"><Icon name="minus" className="size-5" /></button>
                    <button type="button" aria-label={t('Plus 1')} onClick={() => change(i, scores[i] + 1)}
                            className="press grid size-12 place-items-center rounded-[14px] border-2 border-stroke bg-surface"><Icon name="plus" className="size-5" /></button>
                  </div>
                </div>
              );
            })}
          </div>
          {force ? (
            <div role="alert" className="tile grid gap-2 bg-butter p-3 text-on-accent">
              <p className="font-black">{t('That score doesn’t look right. Save it anyway?')}</p>
              <div className="flex flex-wrap gap-2">
                <Button className="button-sm" busy={busy === 'save'} onClick={() => save(true)}>{t('Save anyway')}</Button>
                <Button variant="quiet" className="button-sm" onClick={() => setForce(false)}>{t('Fix it')}</Button>
              </div>
            </div>
          ) : (
            <Button className="button-lg" busy={busy === 'save'} onClick={() => save()}>{t('Save')}</Button>
          )}
          {manage && g.status !== 'done' && (
            <details>
              <summary className="cursor-pointer text-footnote font-bold">{t('Someone can’t keep playing')}</summary>
              <p className="mt-2 text-footnote text-ink-secondary">{t('They withdraw and the other side wins this game.')}</p>
              <div className="mt-2 flex flex-wrap gap-2">
                {[...g.a, ...g.b].map((p) => (leaving === p ? (
                  <Button key={p} variant="danger" className="button-sm" busy={busy === `out-${p}`} onClick={() => withdraw(p)}>
                    {t('{name} withdraws', { name: names.get(p) ?? '' })}
                  </Button>
                ) : (
                  <Button key={p} variant="quiet" className="button-sm" onClick={() => setLeaving(p)}>{names.get(p)}</Button>
                )))}
              </div>
            </details>
          )}
        </>
      )}
    </Sheet>
  );
}

// MARK: 组织者菜单

function MatchMenu({ open, onClose, m, refresh }: { open: boolean; onClose: () => void; m: MatchState; refresh: () => Promise<void> }) {
  const organizer = m.role === 'organizer';
  const live = m.status === 'live';
  const { data: friends } = useLive<{ friends: Friend[] }>(open && organizer ? 'my_friends' : '', { every: 300_000 });
  // 从当晚开的轮换搭档：加人时可以选这一晚报了名的注册用户
  const { data: night } = useLive<NightState | null>(open && live && m.format === 'rotating' && m.session_id ? 'night_state' : '', {
    args: { p_session: m.session_id }, every: 300_000,
  });
  const [courts, setCourts] = useState(m.courts);
  const [helpers, setHelpers] = useState<string[]>();
  const [name, setName] = useState('');
  const [leaving, setLeaving] = useState<string>();
  const [forfeit, setForfeit] = useState(false);
  const [confirm, setConfirm] = useState<'end' | 'delete'>();
  const [busy, setBusy] = useState<string>();
  const chosen = helpers ?? m.helpers.map((h) => h.id);
  // 帮手：参赛的注册用户在前，再是现在的帮手和球友
  const helperOptions = new Map<string, string>();
  m.players.forEach((p) => p.user_id && !p.withdrawn && helperOptions.set(p.user_id, p.name));
  m.helpers.forEach((h) => helperOptions.has(h.id) || helperOptions.set(h.id, h.nickname));
  (friends?.friends ?? []).forEach((f) => helperOptions.has(f.id) || helperOptions.set(f.id, f.nickname));
  const signedUp = (night?.people ?? []).filter((p) => p.user_id && !m.players.some((x) => x.user_id === p.user_id));

  async function run(key: string, fn: string, args: Record<string, unknown>, done?: string) {
    setBusy(key);
    const { error } = await supabase!.rpc(fn, args);
    setBusy(undefined);
    if (error) {
      toast(clubProblem(error), 'error');
      return false;
    }
    if (done) toast(done);
    await refresh();
    return true;
  }

  async function addPlayer(event: SubmitEvent<HTMLFormElement>) {
    event.preventDefault();
    if (name.trim() && (await run('add', 'match_add_player', { p_match: m.id, p_name: name.trim() }, t('{name} added', { name: name.trim() })))) setName('');
  }

  async function remove() {
    if (!(await run('delete', 'match_delete', { p_match: m.id }))) return;
    toast(t('Match deleted'));
    navigate(m.session_id ? `/night/${m.session_id}/?tab=match` : '/matches/', true);
  }

  return (
    <Sheet open={open} onClose={onClose} labelledBy="menu-title">
      <h2 id="menu-title" className="text-title3">{t('Match options')}</h2>
      {live && (
        <div className="sticker grid px-4">
          <Stepper label={t('Number of courts')} value={courts} min={1} max={12} text={String(courts)} onChange={setCourts} />
          {courts !== m.courts && (
            <div className="pb-3"><Button variant="quiet" className="w-full" busy={busy === 'courts'} onClick={() => run('courts', 'match_courts', { p_match: m.id, p_courts: courts }, t('Saved'))}>{t('Save')}</Button></div>
          )}
        </div>
      )}

      {organizer && live && (
        <section aria-labelledby="match-helpers" className="grid gap-2">
          <h3 id="match-helpers" className="text-headline">{t('Helpers')}</h3>
          <p className="text-footnote text-ink-secondary">{t('Up to 3 players or friends who can enter scores.')}</p>
          <ul className="flex flex-wrap gap-2">
            {[...helperOptions].map(([id, label]) => {
              const on = chosen.includes(id);
              return (
                <li key={id}>
                  <button type="button" className="toggle" aria-pressed={on} disabled={!on && chosen.length >= 3}
                          onClick={() => setHelpers(on ? chosen.filter((x) => x !== id) : [...chosen, id])}>{label}</button>
                </li>
              );
            })}
          </ul>
          {helpers && <Button variant="quiet" busy={busy === 'helpers'} onClick={() => run('helpers', 'match_helpers', { p_match: m.id, p_users: chosen }, t('Saved'))}>{t('Save helpers')}</Button>}
        </section>
      )}

      {live && m.format === 'rotating' && signedUp.length > 0 && (
        <ul className="flex flex-wrap gap-2" aria-label={t('Signed up tonight')}>
          {signedUp.map((p) => (
            <li key={p.id}>
              <button type="button" className="toggle" disabled={busy === p.id}
                      onClick={() => run(p.id, 'match_add_player', { p_match: m.id, p_user: p.user_id }, t('{name} added', { name: p.name }))}>
                <Icon name="plus" className="size-3.5" />{p.name}
              </button>
            </li>
          ))}
        </ul>
      )}
      {live && m.format === 'rotating' && (
        <form onSubmit={addPlayer} className="grid gap-2">
          <Field label={t('Add a player')} hint={t('They join from the next round.')}>
            {(props) => <input {...props} className="field" value={name} maxLength={20} onChange={(e) => setName(e.target.value)} />}
          </Field>
          <Button type="submit" variant="quiet" busy={busy === 'add'} disabled={!name.trim()}>{t('Add')}</Button>
        </form>
      )}
      {live && m.format !== 'rotating' && <p className="text-footnote text-ink-secondary">{t('Only rotating partners can add players after the start. For drop-ins, use the rotation.')}</p>}

      {live && (
        <details>
          <summary className="cursor-pointer font-bold">{t('Someone is leaving')}</summary>
          <div className="mt-2 grid gap-2">
            <div className="flex flex-wrap gap-2">
              {m.players.filter((p) => !p.withdrawn).map((p) => (
                <button key={p.id} type="button" className="toggle" aria-pressed={leaving === p.id} onClick={() => setLeaving(p.id)}>{p.name}</button>
              ))}
            </div>
            {m.format !== 'rotating' && (
              <Switch checked={forfeit} onChange={setForfeit} title={t('Count their unplayed games as losses')} text={t('Otherwise those games are cancelled.')} />
            )}
            {leaving && (
              <Button variant="danger" busy={busy === 'leave'} onClick={async () => {
                if (await run('leave', 'match_withdraw', { p_player: leaving, p_forfeit: forfeit }, t('Withdrawn'))) setLeaving(undefined);
              }}>{t('Withdraw {name}', { name: m.players.find((p) => p.id === leaving)?.name ?? '' })}</Button>
            )}
          </div>
        </details>
      )}

      {organizer && (
        <div className="grid gap-2">
          <Divider />
          {live && (confirm === 'end' ? (
            <Button variant="danger" busy={busy === 'end'} onClick={() => run('end', 'match_end', { p_match: m.id }).then((ok) => ok && onClose())}>
              {t('End now. Unplayed games won’t count.')}
            </Button>
          ) : (
            <Button variant="quiet" onClick={() => setConfirm('end')}>{t('End match')}</Button>
          ))}
          {confirm === 'delete' ? (
            <Button variant="danger" busy={busy === 'delete'} onClick={remove}>{t('Delete for everyone')}</Button>
          ) : (
            <button type="button" className="min-h-11 text-footnote font-bold text-danger hover:underline" onClick={() => setConfirm('delete')}>{t('Delete match')}</button>
          )}
        </div>
      )}
    </Sheet>
  );
}

/** 分组出线卡在并列上：组织者点选谁出线（按小组名次排好种子） */
function QualifySheet({ open, onClose, m, refresh }: { open: boolean; onClose: () => void; m: MatchView; refresh: () => Promise<void> }) {
  const need = (m.pools ?? 2) * (m.advance ?? 1) === 2 ? 2 : 4;
  const [picked, setPicked] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const rows = m.standings.filter((s) => !s.withdrawn);
  async function save() {
    // 种子按小组名次，再按积分榜的顺序
    const keys = rows.filter((s) => picked.includes(s.key)).sort((a, b) => a.rank - b.rank || rows.indexOf(a) - rows.indexOf(b)).map((s) => s.key);
    setBusy(true);
    const { error } = await supabase!.rpc('match_qualify', { p_match: m.id, p_keys: keys });
    setBusy(false);
    if (error) return toast(clubProblem(error), 'error');
    await refresh();
    onClose();
  }
  return (
    <Sheet open={open} onClose={onClose} labelledBy="qualify-title">
      <h2 id="qualify-title" className="text-title3">{t('Who goes through')}</h2>
      <p className="text-footnote text-ink-secondary">{t('Pick {n}.', { n: need })}</p>
      <ul className="flex flex-wrap gap-2">
        {rows.map((s) => {
          const on = picked.includes(s.key);
          return (
            <li key={s.key}>
              <button type="button" className="toggle" aria-pressed={on} disabled={!on && picked.length >= need}
                      onClick={() => setPicked(on ? picked.filter((k) => k !== s.key) : [...picked, s.key])}>
                {s.pool !== null && `${t('Group {n}', { n: s.pool })} · `}{s.name}
              </button>
            </li>
          );
        })}
      </ul>
      <Button busy={busy} disabled={picked.length !== need} onClick={save}>{t('Save')}</Button>
    </Sheet>
  );
}

// MARK: 新建

type Entry = { key: string; label: string; guest: boolean; user_id?: string; signup_id?: string; name?: string };

/** 人数够不够这个赛制：不够时返回给人看的话 */
function countProblem(format: MatchFormat, n: number, pools: number) {
  if (n > 64) return t('Up to 64 players.');
  if (format === 'singles' && n < 2) return t('Add at least 2 players.');
  if (format === 'rotating' && n < 4) return t('Rotating partners need at least 4 players.');
  if (format === 'fixed' && n < 4) return t('Fixed partners need at least 4 players.');
  if (format === 'fixed' && n % 2) return t('Fixed partners need an even number. Add 1 more player.');
  if (format === 'groups' && n < pools * 2) return t('{pools} groups need at least {n} players.', { pools, n: pools * 2 });
  return undefined;
}

/** 从排表页（/badminton-tournament-maker/）带过来的名单和设置：一小时内有效，读一次就删 */
function fromMaker(): Plan | undefined {
  try {
    const saved = JSON.parse(sessionStorage.getItem(makerKey) ?? 'null') as (Plan & { at: number }) | null;
    sessionStorage.removeItem(makerKey);
    return saved && Date.now() - saved.at < 3_600_000 && Array.isArray(saved.players) ? saved : undefined;
  } catch {
    return undefined;
  }
}

export function NewMatch({ profile }: { profile: Profile }) {
  const session = new URLSearchParams(location.search).get('session');
  const [maker] = useState(() => (session ? undefined : fromMaker()));
  const { data: night } = useLive<NightState | null>(session ? 'night_state' : '', { args: { p_session: session }, every: 600_000 });
  const [name, setName] = useState('');
  const [venue, setVenue] = useState<Court>();
  const [courts, setCourts] = useState(maker?.courts ?? 2);
  const [players, setPlayers] = useState<Entry[]>(() =>
    session ? []
    : maker ? maker.players.slice(0, 64).map((name, i) => ({ key: `name-${i}`, label: name, guest: true, name }))
    : [{ key: profile.id, label: profile.nickname, guest: false, user_id: profile.id }]);
  const [format, setFormat] = useState<MatchFormat>(maker?.format ?? 'rotating');
  const [points, setPoints] = useState<21 | 15 | 11>(maker?.points ?? 21);
  const [bestOf, setBestOf] = useState<1 | 3>(maker?.bestOf ?? 1);
  const [winByTwo, setWinByTwo] = useState(true);
  const [pools, setPools] = useState(maker?.pools ?? 2);
  const [advance, setAdvance] = useState(maker?.advance ?? 1);
  // 排表页的固定搭档是按名单两两一队
  const [autoPairs, setAutoPairs] = useState(maker?.format !== 'fixed');
  const [rounds, setRounds] = useState<number | undefined>(maker?.rounds);
  const [picking, setPicking] = useState(false);
  const [guest, setGuest] = useState('');
  const [busy, setBusy] = useState(false);
  const fallbackName = t('{date} match', { date: new Intl.DateTimeFormat(currentLocale(), { month: 'short', day: 'numeric' }).format(new Date()) });

  // 从当晚开：参赛的人预先填好到场的人，场地数用当晚的
  useEffect(() => {
    if (!night) return;
    setPlayers(night.people.filter((p) => p.status === 'here').map((p) => ({ key: p.id, label: p.name, guest: p.guest, signup_id: p.id })));
    setCourts(night.courts);
  }, [Boolean(night)]);

  const problemText = countProblem(format, players.length, pools);
  const { data: preview } = useLive<{ full_rounds: number; rounds: number; minutes: number }>(problemText ? '' : 'match_preview', {
    args: { p_format: format, p_players: players.length, p_courts: courts, p_points: points, p_best_of: bestOf, p_doubles: false,
            p_pools: format === 'groups' ? pools : null, p_advance: format === 'groups' ? advance : null, p_rounds: format === 'groups' ? null : (rounds ?? null) },
    every: 600_000,
  });

  const add = (entry: Entry) => setPlayers((list) => (list.some((p) => p.key === entry.key) ? list : [...list, entry]));
  const remove = (key: string) => setPlayers((list) => list.filter((p) => p.key !== key));

  function addGuest(event: SubmitEvent<HTMLFormElement>) {
    event.preventDefault();
    const clean = guest.trim().replace(/\s+/g, ' ');
    if (!clean) return;
    add({ key: `name-${Date.now()}`, label: clean, guest: true, name: clean });
    setGuest('');
  }

  async function start() {
    setBusy(true);
    const { data, error } = await supabase!.rpc('create_match', {
      p_name: name.trim() || fallbackName,
      p_venue: venue?.id ?? null,
      p_courts: courts,
      p_format: format,
      p_points: points,
      p_best_of: bestOf,
      p_win_by_two: winByTwo,
      // 固定搭档、不自动配：按名单顺序两两一队
      p_players: players.map((p, i) => ({
        ...(p.signup_id ? { signup_id: p.signup_id } : p.user_id ? { user_id: p.user_id } : { name: p.name }),
        ...(format === 'fixed' && !autoPairs ? { team: Math.floor(i / 2) + 1 } : {}),
      })),
      p_rounds: format === 'groups' ? null : (rounds ?? null),
      p_pools: format === 'groups' ? pools : null,
      p_advance: format === 'groups' ? advance : null,
      p_session: session,
    });
    setBusy(false);
    if (error) return toast(error.message === 'invalid_player_count' ? (countProblem(format, players.length, pools) ?? problem(error)) : clubProblem(error), 'error');
    navigate(session ? `/night/${session}/?tab=match` : `/matches/${data}/`, true);
  }

  const formats: MatchFormat[] = ['singles', 'fixed', 'rotating', 'groups'];
  return (
    <div className="mx-auto grid w-full max-w-2xl gap-6 pb-24">
      <ScreenHeader title={t('Match')} back={session ? `/night/${session}/?tab=match` : '/matches/'} />

      <div className="sticker grid px-4">
        <div className="py-3">
          <Field label={t('Name')}>
            {(props) => <input {...props} className="field" value={name} maxLength={40} placeholder={fallbackName} onChange={(e) => setName(e.target.value)} />}
          </Field>
        </div>
        <Divider />
        <div className="grid gap-2 py-3">
          {venue ? (
            <div className="flex items-center gap-2">
              <span className="flex-1 font-bold">{venue.name}</span>
              <button type="button" className="link text-footnote" onClick={() => setVenue(undefined)} aria-label={t('Remove {name}', { name: venue.name })}>{t('Remove')}</button>
            </div>
          ) : (
            <CourtSearch label={t('Venue (optional)')} onPick={setVenue} />
          )}
        </div>
        <Divider />
        <Stepper label={t('Number of courts')} value={courts} min={1} max={12} text={String(courts)} onChange={setCourts} />
      </div>

      <section aria-labelledby="players" className="grid gap-3">
        <div className="flex items-baseline gap-2">
          <h2 id="players" className="text-title3">{t('Who’s playing')}</h2>
          <span className="text-footnote font-bold text-ink-secondary">{t('{n} player|{n} players', { n: players.length })}</span>
        </div>
        {players.length > 0 && (
          <ul className="flex flex-wrap gap-2">
            {players.map((p, i) => (
              <li key={p.key} className="flex h-10 items-center gap-1.5 rounded-full border-[1.5px] border-stroke bg-surface pr-1 pl-3">
                {format === 'fixed' && !autoPairs && <span className="text-caption font-bold text-ink-secondary">{Math.floor(i / 2) + 1}</span>}
                <span className="font-bold">{p.label}</span>
                {p.guest && <Tag tint="mint">{t('Guest')}</Tag>}
                <button type="button" onClick={() => remove(p.key)} aria-label={t('Remove {name}', { name: p.label })}
                        className="press grid size-8 place-items-center rounded-full text-ink-tertiary hover:bg-surface-muted hover:text-ink">
                  <Icon name="x" className="size-3.5" />
                </button>
              </li>
            ))}
          </ul>
        )}
        <div className="grid gap-2 sm:grid-cols-2">
          <Button variant="quiet" onClick={() => setPicking(true)}><Icon name="users" className="size-4" />{t('Pick friends')}</Button>
          <form onSubmit={addGuest} className="flex gap-2">
            <input className="field min-h-[46px] flex-1" value={guest} maxLength={20} placeholder={t('Type a name')} aria-label={t('Type a name')} onChange={(e) => setGuest(e.target.value)} />
            <Button type="submit" variant="quiet" disabled={!guest.trim()}>{t('Add')}</Button>
          </form>
        </div>
        {problemText && players.length > 0 && <p className="text-footnote font-bold text-danger">{problemText}</p>}
      </section>

      <section aria-labelledby="format" className="grid gap-3">
        <h2 id="format" className="text-title3">{t('Match format')}</h2>
        <div className="grid grid-cols-2 gap-2">
          {formats.map((f) => (
            <button key={f} type="button" aria-pressed={format === f} className="toggle min-h-12 whitespace-normal" onClick={() => setFormat(f)}>{formatName(f)}</button>
          ))}
        </div>
        {format === 'groups' && (
          <div className="sticker grid gap-3 p-4">
            <Segmented label={t('Number of groups')} value={String(pools)} onChange={(v) => {
              setPools(Number(v));
              if (v !== '2') setAdvance(1);
            }} options={[2, 3, 4].map((n) => ({ value: String(n), label: t('{n} groups', { n }) }))} />
            {pools === 2 ? (
              <Segmented label={t('Who goes through')} value={String(advance)} onChange={(v) => setAdvance(Number(v))}
                         options={[{ value: '1', label: t('Top 1 of each group') }, { value: '2', label: t('Top 2 of each group') }]} />
            ) : <p className="text-footnote text-ink-secondary">{pools === 3 ? t('Group winners and the best runner-up play the semifinals.') : t('Group winners play the semifinals.')}</p>}
          </div>
        )}
        {format === 'fixed' && (
          <div className="sticker px-4">
            <Switch checked={autoPairs} onChange={setAutoPairs} title={t('Pair by level')}
                    text={autoPairs ? t('Strongest plays with weakest.') : t('Pairs follow the list: 1st with 2nd, 3rd with 4th.')} />
          </div>
        )}
      </section>

      <section aria-labelledby="scoring" className="grid gap-3">
        <h2 id="scoring" className="text-title3">{t('Each game')}</h2>
        <div className="grid gap-2 sm:grid-cols-2">
          <Segmented label={t('Points')} value={String(points)} onChange={(v) => setPoints(Number(v) as 21 | 15 | 11)}
                     options={[21, 15, 11].map((n) => ({ value: String(n), label: String(n) }))} />
          <Segmented label={t('Games per match')} value={String(bestOf)} onChange={(v) => setBestOf(Number(v) as 1 | 3)}
                     options={[{ value: '1', label: t('One game') }, { value: '3', label: t('Best of 3') }]} />
        </div>
        <div className="sticker px-4">
          <Switch checked={winByTwo} onChange={setWinByTwo} title={t('Win by 2')} text={t('Capped at {n}.', { n: { 21: 30, 15: 21, 11: 15 }[points] })} />
        </div>
      </section>

      <div className="grid gap-2">
        {preview && (
          <div className="flex flex-wrap items-center gap-2 text-footnote font-bold">
            <Icon name="clock" className="size-4" />
            <span className="flex-1">{t('About {n} round, {minutes} min|About {n} rounds, {minutes} min', { n: preview.rounds, minutes: preview.minutes })}</span>
            {format !== 'groups' && preview.full_rounds > 1 && rounds === undefined && (
              <button type="button" className="link" onClick={() => setRounds(Math.max(1, preview.full_rounds - 1))}>{t('Play fewer rounds')}</button>
            )}
          </div>
        )}
        {rounds !== undefined && format !== 'groups' && preview && (
          <div className="sticker px-4">
            <Stepper label={t('Rounds')} value={rounds} min={1} max={preview.full_rounds} text={String(rounds)} onChange={setRounds} />
            <button type="button" className="link mb-3 text-footnote" onClick={() => setRounds(undefined)}>{t('Play every round')}</button>
          </div>
        )}
        <Button className="button-lg" busy={busy} disabled={Boolean(problemText)} onClick={start}>{t('Start')}</Button>
      </div>

      <FriendPicker open={picking} onClose={() => setPicking(false)} chosen={players.map((p) => p.user_id).filter(Boolean) as string[]}
                    onPick={(f) => add({ key: f.id, label: f.nickname, guest: false, user_id: f.id })} onRemove={remove} />
    </div>
  );
}

function FriendPicker({ open, onClose, chosen, onPick, onRemove }: {
  open: boolean;
  onClose: () => void;
  chosen: string[];
  onPick: (friend: Friend) => void;
  onRemove: (id: string) => void;
}) {
  const { data } = useLive<{ friends: Friend[] }>(open ? 'my_friends' : '', { every: 300_000 });
  return (
    <Sheet open={open} onClose={onClose} labelledBy="friends-title">
      <h2 id="friends-title" className="text-title3">{t('Pick friends')}</h2>
      {data && data.friends.length === 0 && <p className="text-subhead text-ink-secondary">{t('No friends yet. Type their names instead.')}</p>}
      <ul className="flex flex-wrap gap-2">
        {(data?.friends ?? []).map((f) => {
          const on = chosen.includes(f.id);
          return (
            <li key={f.id}>
              <button type="button" className="toggle" aria-pressed={on} onClick={() => (on ? onRemove(f.id) : onPick(f))}>{f.nickname}</button>
            </li>
          );
        })}
      </ul>
      <Button variant="quiet" onClick={onClose}>{t('Done')}</Button>
    </Sheet>
  );
}

// MARK: 我的 → 比赛

type MyMatch = { id: string; name: string; format: MatchFormat; status: 'live' | 'done'; created_at: string; ended_at: string | null; players: number; rank: number | null };

export function MyMatches() {
  const { data } = useLive<MyMatch[]>('my_matches', { every: 60_000 });
  return (
    <div className="mx-auto grid w-full max-w-2xl gap-6">
      <ScreenHeader title={t('Matches')} back="/me/">
        <IconButton icon="plus" label={t('New match')} to="/matches/new/" />
      </ScreenHeader>
      {data === undefined ? <Skeleton className="h-60" /> : data.length === 0 ? (
        <Empty icon="trophy" tint="butter" title={t('No matches yet')} action={{ label: t('New match'), to: '/matches/new/' }}>
          {t('Round robins you run or play in show up here.')}
        </Empty>
      ) : (
        <nav aria-label={t('Matches')} className="sticker grid px-4 py-1">
          {data.map((m, i) => (
            <div key={m.id}>
              {i > 0 && <Divider />}
              <Row icon="trophy" tint={m.status === 'live' ? 'lime' : 'butter'} title={m.name} to={`/matches/${m.id}/`}
                   subtitle={[formatName(m.format), day(m.created_at), t('{n} player|{n} players', { n: m.players })].join(' · ')}
                   value={m.status === 'live' ? t('Live') : m.rank ? `#${m.rank}` : undefined} />
            </div>
          ))}
        </nav>
      )}
    </div>
  );
}
