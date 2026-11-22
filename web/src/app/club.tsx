// 当晚（排场 / 比赛 / 收款）几个页面共用的：接口的类型、小工具和小组件。接口见 Badie-iOS/docs/CLUB_NIGHT.md 最后一节
import qrcode from 'qrcode-generator';
import { useEffect, useMemo, useState } from 'react';
import { loadTokens } from './GuestSignup';
import { t } from './i18n';
import { Icon } from './icons';
import { Sheet } from './Nearby';
import { problem } from './supabase';
import { Button, toast } from './ui';

// MARK: 类型

export type Attendance = 'absent' | 'here' | 'resting' | 'left';
export type Handles = { venmo?: string; cashapp?: string; paypal?: string; zelle?: string };

export interface NightPerson {
  /** 报名那一行的 id（访客也有） */
  id: string;
  name: string;
  user_id: string | null;
  guest: boolean;
  status: Attendance;
  waitlisted: boolean;
  games: number;
  on_court: number | null;
  next_up: boolean;
  /** 等候的人排第几（从 1 起，和排人的顺序一样）；不在等候的为 null */
  queue: number | null;
}

export interface NightState {
  session_id: string;
  group_id: string;
  group: string;
  venue: string;
  tz: string | null;
  starts_at: string;
  ends_at: string;
  role: 'organizer' | 'helper';
  /** 开场前 1 小时到结束后 3 小时 */
  open: boolean;
  started: boolean;
  courts: number;
  doubles: boolean;
  balance: boolean;
  board_code: string | null;
  match_id: string | null;
  match_live: boolean;
  helpers: { id: string; nickname: string }[];
  undo_until: string | null;
  people: NightPerson[];
  /** 双打 players 前两个一队 */
  games: { id: number; court: number; players: string[]; started_at: string }[];
  next: string[][];
}

export interface NightPay {
  amount: number | null;
  amount_set: boolean;
  payee: string | null;
  payee_is_me: boolean;
  has_handles: boolean;
  reminded_at: string | null;
  can_remind: boolean;
  people: { id: string; name: string; guest: boolean; status: Attendance; email: boolean; owes: boolean; paid: boolean; paid_self: boolean }[];
}

/** 球群页的当天场次（group_tonight） */
export interface TonightSession {
  id: string;
  starts_at: string;
  ends_at: string;
  can_run: boolean;
  board: string | null;
  pay: { to: string; amount: number | null; handles: Handles; paid: boolean; paid_self: boolean } | null;
  unpaid: number | null;
}

/** 我还没付的一场（my_dues）：开过的、写了金额的场次，60 天内 */
export interface Due {
  session_id: string;
  group_id: string;
  group: string;
  starts_at: string;
  ends_at: string;
  tz: string | null;
  amount: number;
  to: string;
  to_id: string;
  handles: Handles;
}

/** 收款记录（group_ledger）：开过的场次，第一页还有谁还欠着 */
export interface Ledger {
  sessions: LedgerSession[];
  owed: OwedPerson[] | null;
}

export interface LedgerSession {
  id: string;
  starts_at: string;
  ends_at: string;
  venue: string;
  tz: string | null;
  amount: number | null;
  payee: string | null;
  owes: number;
  paid: number;
}

/** 谁还欠着：注册用户按人、访客按名字合起来；signups 是那几行报名 */
export interface OwedPerson {
  id: string | null;
  name: string;
  guest: boolean;
  sessions: number;
  amount: number;
  signups: string[];
}

/** 球局页的“今晚”卡（my_tonight） */
export type MyTonight =
  | { kind: 'night'; session_id: string; group_id: string; name: string; board_code: string; status: 'court' | 'next' | 'waiting' | 'resting'; court: number | null; games: number }
  | { kind: 'match'; match_id: string; name: string; board_code: string; status: 'court' | 'next' | 'waiting'; court: number | null; round: number | null; games: number };

/** 访客的付款（guest_payment） */
export interface GuestPayment {
  token: string;
  session_id: string;
  group_id: string;
  group: string;
  starts_at: string;
  ends_at: string;
  venue: string;
  tz: string | null;
  to: string;
  amount: number | null;
  handles: Handles;
  paid: boolean;
  paid_self: boolean;
}

/** 赛制：循环 / 小组赛 + 淘汰赛 / 瑞士轮 / 单淘汰 */
export type MatchFormat = 'round_robin' | 'groups' | 'swiss' | 'knockout';
/** 参赛方式：单打 / 双打固定搭档 / 双打轮换搭档（只配循环） */
export type MatchPlay = 'singles' | 'fixed' | 'rotating';

export interface MatchGame {
  id: number;
  round: number;
  /** 淘汰赛是 ko（ko_size：这一轮几个签位，2 = 决赛），三四名决赛是 third */
  stage: 'pool' | 'ko' | 'third';
  pool?: number;
  ko_size?: number;
  slot?: number;
  /** 轮空：不是一场球，不显示 */
  bye?: boolean;
  /** 中途退赛的一边 */
  retired?: 1 | 2;
  a: string[];
  b: string[];
  court?: number;
  status: 'queued' | 'playing' | 'done' | 'cancelled' | 'skipped';
  /** 每局两个数 [a1, b1, a2, b2…] */
  scores?: number[];
  winner?: 1 | 2;
  walkover?: boolean;
  /** 谁填的、谁改的（名字） */
  scored_by?: string;
  edited_by?: string;
  /** 下面两项只有组织者、帮手看得到 */
  version?: number;
  flagged?: boolean;
}

export interface Standing {
  key: string;
  name: string;
  members: string[];
  pool: number | null;
  played: number;
  wins: number;
  losses: number;
  pf: number;
  pa: number;
  diff: number;
  rank: number;
  tied: boolean;
  withdrawn: boolean;
}

export interface MatchView {
  kind: 'match';
  id: string;
  name: string;
  format: MatchFormat;
  play: MatchPlay;
  third_place: boolean;
  doubles: boolean;
  points: 11 | 15 | 21;
  best_of: 1 | 3;
  win_by_two: boolean;
  courts: number;
  rounds: number;
  round: number | null;
  pools: number | null;
  advance: number | null;
  status: 'live' | 'done';
  created_at: string;
  ended_at: string | null;
  board_code: string;
  session_id: string | null;
  venue: string | null;
  tie_at_cut: boolean;
  players: { id: string; name: string; team: number | null; pool: number | null; withdrawn: boolean }[];
  games: MatchGame[];
  standings: Standing[];
  ranking: Standing[] | null;
  /** 看板：这台设备或登录的人对上的那一个；比赛页：我的参赛 id */
  me?: string | null;
}

export interface MatchState extends MatchView {
  /** 组织者、帮手看到的参赛的人多一个 user_id（注册用户才有） */
  players: (MatchView['players'][number] & { user_id?: string | null })[];
  role: 'organizer' | 'helper' | 'player';
  helpers: { id: string; nickname: string }[];
  undo_until: string | null;
}

// MARK: 小工具

/** 这台设备上访客报名的凭证（报名页存的，最多 50 个） */
export const deviceTokens = () => Object.values(loadTokens()).slice(-50);

/** $12 / $12.50 */
export const money = (amount: number) => `$${Number.isInteger(amount) ? amount : amount.toFixed(2)}`;

/** 每场的价格：0 写“免费”，null 不写 */
export const priceText = (price: number | null | undefined) =>
  price === null || price === undefined ? null : price === 0 ? t('Free') : t('{amount} each', { amount: money(price) });

/** 看板的链接（二维码也是它） */
export const boardLink = (code: string) => `${location.origin}/live/${code}/`;

/** 一队的名字：“Kevin · Amy” */
export const teamName = (ids: string[], names: Map<string, string>) => ids.map((id) => names.get(id) ?? '?').join(' · ');

/** 双打的一场拆成两队（前两个一队），单打一人一边 */
export const sides = (players: string[]) => (players.length === 4 ? [players.slice(0, 2), players.slice(2)] : [players.slice(0, 1), players.slice(1)]);

/** 比分 [21, 18, 19, 21] → “21–18 19–21” */
export const scoreText = (scores: number[] | undefined) =>
  (scores ?? []).reduce<string[]>((games, n, i) => (i % 2 ? [...games.slice(0, -1), `${games.at(-1)}–${n}`] : [...games, String(n)]), []).join(' ');

export const structureName = (format: MatchFormat) =>
  ({ round_robin: t('Round robin'), groups: t('Groups + knockout'), swiss: t('Swiss'), knockout: t('Knockout') })[format];

export const playName = (play: MatchPlay) =>
  ({ singles: t('Singles'), fixed: t('Doubles, fixed partners'), rotating: t('Doubles, rotating partners') })[play];

/** “循环 · 单打”；轮换搭档只有循环，就写“双打轮换搭档” */
export const formatName = (format: MatchFormat, play: MatchPlay) => (play === 'rotating' ? playName(play) : `${structureName(format)} · ${playName(play)}`);

// MARK: 比分规则（和服务器的 score_winner、retire_scores_ok 一样）

/** 加分时打到几封顶：21 → 30、15 → 21、11 → 15 */
export const capOf = (points: number) => ({ 21: 30, 15: 21, 11: 15 } as Record<number, number>)[points] ?? points;

const gameDone = (hi: number, lo: number, points: number, winByTwo: boolean) =>
  lo >= 0 && hi > lo && (!winByTwo ? hi === points
    : (hi === points && lo <= points - 2) || (hi > points && hi <= capOf(points) && (hi - lo === 2 || (hi === capOf(points) && lo === hi - 1))));

/** 打得出来、但还没打完的一局 */
const unfinished = (hi: number, lo: number, points: number, winByTwo: boolean) =>
  hi < points || (winByTwo && lo >= points - 1 && hi - lo <= 1 && hi < capOf(points));

/** 打得出来的比分不合规时说哪里不对 */
function gameProblem(a: number, b: number, n: number, rules: { points: number; best_of: number; win_by_two: boolean }) {
  const hi = Math.max(a, b);
  const lo = Math.min(a, b);
  const score = `${a}–${b}`;
  const text = unfinished(hi, lo, rules.points, rules.win_by_two) ? t('{score} isn’t finished yet.', { score })
    : rules.win_by_two ? t('{score} can’t happen: games go to {points}, win by 2, up to {cap}.', { score, points: rules.points, cap: capOf(rules.points) })
    : t('{score} can’t happen: games end at {points}.', { score, points: rules.points });
  return rules.best_of === 1 ? text : t('Game {n}: {text}', { n, text });
}

/** 去掉后面没填的局（0–0） */
export const playedGames = (scores: number[]) => {
  let end = scores.length;
  while (end >= 2 && scores[end - 1] === 0 && scores[end - 2] === 0) end -= 2;
  return scores.slice(0, end);
};

/** 输的比分：合规返回赢的一边；不合规返回哪里不对；还没填返回 null */
export function checkScore(scores: number[], rules: { points: number; best_of: number; win_by_two: boolean }): { winner: 1 | 2 } | { problem: string } | null {
  if (scores.length === 0) return null;
  const need = Math.floor(rules.best_of / 2) + 1;
  const wins = [0, 0];
  for (let i = 0; i < scores.length / 2; i++) {
    if (wins[0] === need || wins[1] === need) return { problem: t('Game 3 isn’t needed. The first two decide it.') };
    const [a, b] = [scores[2 * i], scores[2 * i + 1]];
    if (!gameDone(Math.max(a, b), Math.min(a, b), rules.points, rules.win_by_two)) return { problem: gameProblem(a, b, i + 1, rules) };
    wins[a > b ? 0 : 1] += 1;
  }
  if (wins[0] < need && wins[1] < need) return { problem: t('Best of 3: someone has to win 2 games.') };
  return { winner: wins[0] === need ? 1 : 2 };
}

/** 中途退赛的比分：前面的局打完了、还没分出胜负，最后一局可以没打完。合规返回 undefined */
export function retireProblem(scores: number[], rules: { points: number; best_of: number; win_by_two: boolean }) {
  const need = Math.floor(rules.best_of / 2) + 1;
  const wins = [0, 0];
  const games = scores.length / 2;
  for (let i = 0; i < games; i++) {
    const [a, b] = [scores[2 * i], scores[2 * i + 1]];
    const [hi, lo] = [Math.max(a, b), Math.min(a, b)];
    if (gameDone(hi, lo, rules.points, rules.win_by_two)) wins[a > b ? 0 : 1] += 1;
    else if (i < games - 1 || !unfinished(hi, lo, rules.points, rules.win_by_two)) return gameProblem(a, b, i + 1, rules);
  }
  if (wins[0] >= need || wins[1] >= need) return t('That match is already decided. Save it as a normal score.');
  return undefined;
}

/** 当晚页、比赛页的错误：not_allowed 在这里是没权限，不是约球里的意思 */
export const clubProblem = (error: { message: string }) =>
  error.message === 'not_allowed' ? t('Only the organizer and helpers can do this.') : problem(error);

/** 复制一段文字；浏览器不让复制时直接显示出来 */
export async function copyText(text: string, done: string) {
  try {
    await navigator.clipboard.writeText(text);
    toast(done);
  } catch {
    toast(text);
  }
}

/** 每隔一会儿重新渲染（“几分钟”“几分钟前更新”） */
export function useNow(every = 15_000) {
  const [now, setNow] = useState(Date.now);
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), every);
    return () => clearInterval(timer);
  }, [every]);
  return now;
}

/** 上一次拿到数据的时间（useLive 每次成功都给一份新对象） */
export function useUpdatedAt(data: unknown) {
  const [at, setAt] = useState(Date.now);
  useEffect(() => {
    if (data !== undefined) setAt(Date.now());
  }, [data]);
  return at;
}

// MARK: 小组件

/** “1 分钟前更新”：网差时保留上一份，超过 1 分钟变成提示色 */
export function Updated({ at }: { at: number }) {
  const now = useNow();
  const minutes = Math.floor((now - at) / 60_000);
  return (
    <p role="status" className={`justify-self-center text-caption font-bold ${minutes >= 1 ? 'chip bg-butter' : 'text-ink-tertiary'}`}>
      {minutes < 1 ? t('Updated just now') : t('Updated {n} min ago', { n: minutes })}
    </p>
  );
}

/** 撤销：undo_until 之前底部出一条，到时间消失 */
export function UndoBar({ until, onUndo }: { until: string | null; onUndo: () => Promise<unknown> }) {
  const now = useNow(1000);
  const [busy, setBusy] = useState(false);
  if (!until || new Date(until).getTime() <= now) return null;
  return (
    <div className="fixed inset-x-0 bottom-[calc(var(--tabbar)+0.75rem)] z-40 flex justify-center px-5 lg:bottom-6">
      <div className="flex items-center gap-3 rounded-[16px] border-2 border-stroke bg-inverse py-2 pr-2 pl-4 text-on-inverse shadow-low">
        <span className="text-subhead font-bold">{t('Done. Tapped by mistake?')}</span>
        <Button className="button-sm button-quiet" busy={busy} onClick={async () => {
          setBusy(true);
          await onUndo();
          setBusy(false);
        }}>{t('Undo')}</Button>
      </div>
    </div>
  );
}

/** 加减数字（场地数、只打几轮） */
export function Stepper({ label, value, min, max, onChange, text }: {
  label: string;
  value: number;
  min: number;
  max: number;
  onChange: (value: number) => void;
  /** 中间显示的字（“2 片”） */
  text: string;
}) {
  const button = 'press grid size-10 place-items-center rounded-[12px] border-2 border-stroke bg-surface disabled:opacity-40';
  return (
    <div className="flex min-h-14 items-center gap-3">
      <span className="flex-1 font-bold">{label}</span>
      <button type="button" className={button} disabled={value <= min} onClick={() => onChange(value - 1)} aria-label={t('Fewer')}>
        <Icon name="minus" className="size-4" />
      </button>
      <span className="min-w-14 text-center text-headline tabular-nums" aria-live="polite">{text}</span>
      <button type="button" className={button} disabled={value >= max} onClick={() => onChange(value + 1)} aria-label={t('More')}>
        <Icon name="plus" className="size-4" />
      </button>
    </div>
  );
}

/** 开关（和设置页的一样） */
export function Switch({ checked, onChange, title, text }: { checked: boolean; onChange: (value: boolean) => void; title: string; text?: string }) {
  return (
    <label className="flex min-h-14 cursor-pointer items-center gap-3 py-2">
      <span className="min-w-0 flex-1">
        <span className="block font-bold">{title}</span>
        {text && <span className="block text-footnote text-ink-secondary">{text}</span>}
      </span>
      <input type="checkbox" role="switch" checked={checked} onChange={(e) => onChange(e.target.checked)}
             className="relative h-7 w-12 shrink-0 cursor-pointer appearance-none rounded-full border-2 border-stroke bg-surface-muted transition-colors duration-[var(--dur-1)] before:absolute before:top-0.5 before:left-0.5 before:size-5 before:rounded-full before:border-2 before:border-stroke before:bg-white before:transition-transform before:duration-[var(--dur-2)] checked:bg-lime checked:before:translate-x-5" />
    </label>
  );
}

/** 二维码：白底黑块（深色模式下也是白底，扫得出来） */
export function QrCode({ text, className = 'size-56' }: { text: string; className?: string }) {
  const { size, path } = useMemo(() => {
    const qr = qrcode(0, 'M');
    qr.addData(text);
    qr.make();
    const n = qr.getModuleCount();
    let d = '';
    for (let row = 0; row < n; row++) for (let col = 0; col < n; col++) if (qr.isDark(row, col)) d += `M${col},${row}h1v1h-1z`;
    return { size: n, path: d };
  }, [text]);
  return (
    <svg viewBox={`-3 -3 ${size + 6} ${size + 6}`} className={`rounded-[12px] bg-white ${className}`} role="img" aria-label={t('QR code')} shapeRendering="crispEdges">
      <path d={path} fill="#17140f" />
    </svg>
  );
}

/** 看板的二维码和链接（半屏） */
export function QrSheet({ open, onClose, code, title }: { open: boolean; onClose: () => void; code: string; title: string }) {
  const link = boardLink(code);
  return (
    <Sheet open={open} onClose={onClose} labelledBy="qr-title">
      <h2 id="qr-title" className="text-title3">{title}</h2>
      <p className="text-subhead text-ink-secondary">{t('Anyone can scan this to see the courts. No account needed.')}</p>
      <div className="grid justify-items-center rounded-[16px] border-2 border-stroke bg-white p-4">
        <QrCode text={link} className="size-64 max-w-full" />
      </div>
      <p className="text-center text-footnote font-bold break-all">{link}</p>
      <Button variant="quiet" onClick={() => copyText(link, t('Link copied'))}><Icon name="copy" className="size-4" />{t('Copy link')}</Button>
    </Sheet>
  );
}
