// 不登录也能用的排表（/badminton-tournament-maker/）：和服务器排对阵的规则一样（supabase/migrations/ 里 20261228000000_club_night.sql 的
// round_robin_pairs、match_schedule_rotating，20261229000000_match_formats.sql 的 match_plan、match_preview、match_schedule_rr、
// match_swiss_round 第 1 轮、bracket_order、match_bracket），只是不记比分，所以瑞士轮第 2 轮起和淘汰赛后面的轮次排不出来。
// 没有等级可参考：名单顺序就是种子顺序，固定搭档按名单两两一队
/** 排表页点“在 Badie 里开始”时存到 sessionStorage，新建比赛页（Match.tsx 的 NewMatch）读一次，一小时内有效 */
export const makerKey = 'badie.maker';

export type Play = 'singles' | 'fixed' | 'rotating';
export type Structure = 'round_robin' | 'groups' | 'swiss' | 'knockout';

export interface Plan {
  play: Play;
  /** 轮换搭档只有循环 */
  format: Structure;
  players: string[];
  courts: number;
  points: 21 | 15 | 11;
  bestOf: 1 | 3;
  /** 循环、瑞士轮、轮换搭档打几轮；不填用默认 */
  rounds?: number;
  pools: number;
  advance: number;
  thirdPlace: boolean;
}

export interface Game {
  pool?: number;
  a: string[];
  b: string[];
}

export interface Block {
  /** 第几轮，或者淘汰赛这一轮的签位数（2 = 决赛） */
  round?: number;
  ko?: number;
  games: Game[];
  resting: string[];
  /** 淘汰赛第一轮直接晋级的、瑞士轮轮空的（算赢一场） */
  byes: string[];
}

export interface Schedule {
  blocks: Block[];
  /** 小组赛：每组的人（队） */
  pools: string[][];
  /** 瑞士轮第 2 轮起按积分榜配，排不出来：[从第几轮, 到第几轮] */
  swissLater?: [number, number];
  /** 还排不出来的淘汰赛轮次（签位数，2 = 决赛）和要不要打三四名 */
  koLater: number[];
  third: boolean;
  fullRounds: number;
  defaultRounds: number;
  maxRounds: number;
  /** 一共几轮（含淘汰赛） */
  rounds: number;
  minutes: number;
}

/** 同名的加数字（Amy、Amy 2），和服务器一样；最长 20 个字（服务器的 clean_player_name） */
export function cleanNames(text: string): string[] {
  const names: string[] = [];
  for (const raw of text.split(/\n|,/)) {
    const name = raw.trim().replace(/\s+/g, ' ').slice(0, 20);
    if (!name) continue;
    const same = names.filter((n) => n.toLowerCase() === name.toLowerCase() || n.toLowerCase().startsWith(`${name.toLowerCase()} `)).length;
    names.push(same ? `${name.slice(0, 17)} ${same + 1}` : name);
  }
  return names;
}

export const effectiveFormat = (play: Play, format: Structure): Structure => (play === 'rotating' ? 'round_robin' : format);

/** 人数不对时的问题（和 Match.tsx 的 countProblem 一样） */
export function countProblem(format: Structure, play: Play, n: number, pools: number, advance: number) {
  const per = play === 'fixed' ? 2 : 1;
  const entries = Math.floor(n / per);
  if (n > 64) return { code: 'max' } as const;
  if (n < 2) return { code: 'min2' } as const;
  if (play === 'rotating' && n < 4) return { code: 'rotating4' } as const;
  if (play === 'fixed' && n < 4) return { code: 'fixed4' } as const;
  if (play === 'fixed' && n % 2) return { code: 'fixedEven' } as const;
  if (format === 'swiss' && entries < 3) return { code: 'swiss', n: 3 * per } as const;
  if (format === 'groups' && entries < pools * (advance + 1)) return { code: 'groups', n: pools * (advance + 1) * per } as const;
  return undefined;
}

/** 圆桌法第 round 轮（从 0 开始）的对阵，m 是双数 */
export function roundRobinPairs(m: number, round: number): [number, number][] {
  const pairs: [number, number][] = [[round % (m - 1), m - 1]];
  for (let i = 1; i <= m / 2 - 1; i++) pairs.push([(round + i) % (m - 1), (round - i + m - 1) % (m - 1)]);
  return pairs;
}

/** 签位顺序：第 i 个签位放几号种子。4 → 1,4,2,3；8 → 1,8,4,5,2,7,3,6 */
export function bracketOrder(size: number): number[] {
  let order = [1];
  for (let n = 2; n <= size; n *= 2) order = order.flatMap((x) => [x, n + 1 - x]);
  return order;
}

/** match_plan */
export function matchPlan(format: Structure, play: Play, players: number, pools = 2, advance = 1) {
  const entries = play === 'fixed' ? Math.floor(players / 2) : players;
  const perRound = play === 'rotating' ? Math.floor(players / 4) : Math.floor(entries / 2);
  let fullRounds = 0;
  let defaultRounds = 0;
  let maxRounds = 0;
  let qualifiers = 0;
  if (play === 'rotating') {
    fullRounds = players + (players % 2) - 1;
    defaultRounds = Math.min(fullRounds, 30);
    maxRounds = 30;
  } else if (format === 'round_robin') {
    fullRounds = entries + (entries % 2) - 1;
    defaultRounds = fullRounds;
    maxRounds = Math.min(2 * fullRounds, 60);
  } else if (format === 'swiss') {
    fullRounds = entries + (entries % 2) - 1;
    defaultRounds = 1;
    while (2 ** defaultRounds < entries) defaultRounds++;
    defaultRounds = Math.min(defaultRounds, fullRounds);
    maxRounds = fullRounds;
  } else if (format === 'groups') {
    const size = Math.floor((entries + pools - 1) / pools);
    fullRounds = size + (size % 2) - 1;
    defaultRounds = fullRounds;
    maxRounds = fullRounds;
    qualifiers = Math.min(pools * advance, entries);
  } else {
    qualifiers = entries;
  }
  let bracket = 0;
  if (qualifiers >= 2) for (bracket = 2; bracket < qualifiers; bracket *= 2);
  return { entries, fullRounds, defaultRounds, maxRounds, perRound, qualifiers, bracket };
}

/** 双打轮换搭档（match_schedule_rotating）：轮空最少的人轮空；先给“还没搭过的人”最少的人配，挑搭过最少的；两队配成一场时挑交手最少的 */
function rotating(names: string[], rounds: number): Game[][] {
  const n = names.length;
  const partners = Array.from({ length: n }, () => new Array<number>(n).fill(0));
  const rivals = Array.from({ length: n }, () => new Array<number>(n).fill(0));
  const played = new Array<number>(n).fill(0);
  const out: Game[][] = [];
  for (let r0 = 0; r0 < rounds; r0++) {
    const order = [...names.keys()].sort((x, y) => r0 - played[x] - (r0 - played[y]) || mod(x - r0 * (n % 4), n) - mod(y - r0 * (n % 4), n));
    let left = order.slice(n % 4).sort((x, y) => x - y);
    const fresh = new Array<number>(n).fill(0);
    for (const a of left) fresh[a] = left.filter((y) => y !== a && partners[a][y] === 0).length;
    const pairs: [number, number][] = [];
    while (left.length) {
      const a = minBy(left, (x) => fresh[x] * 100 + mod(x + r0, n));
      left = left.filter((x) => x !== a);
      for (const q of left) if (partners[a][q] === 0) fresh[q]--;
      const q = minBy(left, (x) => partners[a][x] * 10000 + fresh[x] * 100 + mod(x - a + r0, n));
      left = left.filter((x) => x !== q);
      for (const t of left) if (partners[q][t] === 0) fresh[t]--;
      pairs.push([a, q]);
      partners[a][q]++;
      partners[q][a]++;
      played[a]++;
      played[q]++;
    }
    const games: Game[] = [];
    while (pairs.length) {
      const first = pairs.shift()!;
      const other = minBy(pairs, ([x, y]) => rivals[first[0]][x] + rivals[first[0]][y] + rivals[first[1]][x] + rivals[first[1]][y]);
      games.push({ a: first.map((i) => names[i]), b: other.map((i) => names[i]) });
      for (const i of first) for (const j of other) {
        rivals[i][j]++;
        rivals[j][i]++;
      }
      pairs.splice(pairs.indexOf(other), 1);
    }
    out.push(games);
  }
  return out;
}

/** 循环和小组赛（match_schedule_rr）：圆桌法；循环超过一遍时第二遍换边；单数时每轮一个人（一队）轮空 */
function roundRobin(pools: string[][][], rounds: (m: number) => number): Game[][] {
  const out: Game[][] = [];
  pools.forEach((pool, p) => {
    const m = pool.length + (pool.length % 2);
    for (let r = 0; r < rounds(m); r++) {
      const flip = Math.floor(r / (m - 1)) % 2 === 1;
      for (const [a, b] of roundRobinPairs(m, r % (m - 1)).sort((x, y) => x[0] - y[0])) {
        if (a >= pool.length || b >= pool.length) continue;
        (out[r] ??= []).push({ pool: pools.length > 1 ? p + 1 : undefined, a: flip ? pool[b] : pool[a], b: flip ? pool[a] : pool[b] });
      }
    }
  });
  return out;
}

const mod = (x: number, n: number) => ((x % n) + n) % n;
function minBy<T>(list: T[], key: (item: T) => number): T {
  let best = list[0];
  let bestKey = key(best);
  for (const item of list.slice(1)) {
    const k = key(item);
    if (k < bestKey) [best, bestKey] = [item, k];
  }
  return best;
}

export function schedule(p: Plan): Schedule {
  const format = effectiveFormat(p.play, p.format);
  const plan = matchPlan(format, p.play, p.players.length, p.pools, p.advance);
  const byRounds = format === 'round_robin' || format === 'swiss';
  const rounds = byRounds ? Math.min(Math.max(p.rounds ?? plan.defaultRounds, 1), plan.maxRounds) : plan.fullRounds;
  const entries = p.play === 'fixed'
    ? Array.from({ length: plan.entries }, (_, i) => p.players.slice(i * 2, i * 2 + 2))
    : p.players.map((name) => [name]);

  const blocks: Block[] = [];
  const everyone = new Set(p.players);
  const block = (round: number | undefined, ko: number | undefined, games: Game[], byes: string[] = []): Block => {
    const busy = new Set([...games.flatMap((g) => [...g.a, ...g.b]), ...byes]);
    return { round, ko, games, byes, resting: ko ? [] : [...everyone].filter((name) => !busy.has(name)) };
  };

  let pools: string[][][] = [];
  let swissLater: [number, number] | undefined;
  let koLater: number[] = [];
  if (p.play === 'rotating') {
    rotating(p.players, rounds).forEach((games, i) => blocks.push(block(i + 1, undefined, games)));
  } else if (format === 'round_robin') {
    roundRobin([entries], () => rounds).forEach((games, i) => blocks.push(block(i + 1, undefined, games)));
  } else if (format === 'groups') {
    // 蛇形分组：第 1、4、5、8… 个进第 1 组
    pools = Array.from({ length: p.pools }, () => []);
    entries.forEach((entry, i) => pools[Math.floor(i / p.pools) % 2 === 0 ? i % p.pools : p.pools - 1 - (i % p.pools)].push(entry));
    roundRobin(pools, (m) => m - 1).forEach((games, i) => blocks.push(block(i + 1, undefined, games)));
    for (let s = plan.bracket; s >= 2; s /= 2) koLater.push(s);
  } else if (format === 'swiss') {
    // 第 1 轮：上半区打下半区；单数时最后一个轮空
    const order = [...entries];
    const bye = order.length % 2 ? order.pop()! : undefined;
    const half = order.length / 2;
    blocks.push(block(1, undefined, order.slice(0, half).map((a, i) => ({ a, b: order[i + half] })), bye ?? []));
    if (rounds > 1) swissLater = [2, rounds];
  } else {
    // 单淘汰：签位不够的给前几号种子轮空
    const size = plan.bracket;
    const slots = bracketOrder(size).map((seed) => entries[seed - 1]);
    const games: Game[] = [];
    const byes: string[] = [];
    for (let k = 0; k < size / 2; k++) {
      const [x, y] = [slots[2 * k], slots[2 * k + 1]];
      if (x && y) games.push({ a: x, b: y });
      else byes.push(...(x ?? y));
    }
    blocks.push(block(undefined, size, games, byes));
    for (let s = size / 2; s >= 2; s /= 2) koLater.push(s);
  }

  const third = format !== 'round_robin' && format !== 'swiss' && p.thirdPlace && plan.qualifiers >= 4;
  return {
    blocks,
    pools: pools.map((pool) => pool.map((entry) => entry.join(' · '))),
    swissLater,
    koLater,
    third,
    fullRounds: plan.fullRounds,
    defaultRounds: plan.defaultRounds,
    maxRounds: plan.maxRounds,
    ...preview(p, plan, rounds),
  };
}

/** match_preview：每轮按场地数分几批，每批 21 分 15 分钟、15 分 10 分钟、11 分 7 分钟，三局两胜乘 2.5 */
function preview(p: Plan, plan: ReturnType<typeof matchPlan>, rounds: number) {
  const courts = Math.max(p.courts, 1);
  let batches = rounds * Math.ceil(plan.perRound / courts);
  let koRounds = 0;
  for (let s = plan.bracket; s >= 2 && plan.bracket >= 2; s /= 2) {
    let n = s === plan.bracket ? plan.qualifiers - s / 2 : s / 2;
    if (s === 2 && p.thirdPlace && plan.qualifiers >= 4) n++;
    batches += Math.ceil(n / courts);
    koRounds++;
  }
  const batch = { 21: 15, 15: 10, 11: 7 }[p.points] * (p.bestOf === 3 ? 2.5 : 1);
  return { rounds: rounds + koRounds, minutes: Math.ceil(batches * batch) };
}
