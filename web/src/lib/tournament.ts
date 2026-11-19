// 不登录也能用的排表（/badminton-tournament-maker/）：和服务器排对阵的规则一样（supabase/migrations/20261228000000_club_night.sql 的
// round_robin_pairs、match_schedule_rr、match_schedule_rotating、create_match 的分组、match_preview 的时间），只是不记比分。
// 没有等级可参考：固定搭档按名单两两一队，分组按名单顺序蛇形分
/** 排表页点“在 Badie 里开始”时存到 sessionStorage，新建比赛页（Match.tsx 的 NewMatch）读一次，一小时内有效 */
export const makerKey = 'badie.maker';

export type Format = 'singles' | 'fixed' | 'rotating' | 'groups';

export interface Plan {
  format: Format;
  players: string[];
  courts: number;
  points: 21 | 15 | 11;
  bestOf: 1 | 3;
  /** 不填就打满 */
  rounds?: number;
  pools: number;
  advance: number;
}

export interface Game {
  round: number;
  pool?: number;
  a: string[];
  b: string[];
}

export interface Schedule {
  rounds: { round: number; games: Game[]; resting: string[] }[];
  /** 分组循环：每组的人 */
  pools: string[][];
  /** 分组循环之后的淘汰赛：1 场决赛，或 2 场半决赛加决赛 */
  knockout: ('semi' | 'final')[];
  fullRounds: number;
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

/** 人数不对时的问题（和 Match.tsx 的 countProblem 一样） */
export function countProblem(format: Format, n: number, pools: number): 'max' | 'min2' | 'rotating4' | 'fixed4' | 'fixedEven' | 'groups' | undefined {
  if (n > 64) return 'max';
  if (format === 'singles' && n < 2) return 'min2';
  if (format === 'rotating' && n < 4) return 'rotating4';
  if (format === 'fixed' && n < 4) return 'fixed4';
  if (format === 'fixed' && n % 2) return 'fixedEven';
  if (format === 'groups' && n < pools * 2) return 'groups';
  return undefined;
}

/** 圆桌法第 round 轮（从 0 开始）的对阵，m 是双数 */
export function roundRobinPairs(m: number, round: number): [number, number][] {
  const pairs: [number, number][] = [[round % (m - 1), m - 1]];
  for (let i = 1; i <= m / 2 - 1; i++) pairs.push([(round + i) % (m - 1), (round - i + m - 1) % (m - 1)]);
  return pairs;
}

/** 打满是几轮、每轮几场（match_plan） */
function plan(format: Format, players: number, pools: number) {
  const entries = format === 'fixed' ? Math.floor(players / 2) : players;
  const size = Math.floor((entries + pools - 1) / pools);
  if (format === 'rotating') return { fullRounds: players + (players % 2) - 1, perRound: Math.floor(players / 4) };
  if (format === 'groups') return { fullRounds: size + (size % 2) - 1, perRound: Math.floor(entries / 2) };
  return { fullRounds: entries + (entries % 2) - 1, perRound: Math.floor(entries / 2) };
}

/** 预计多少分钟（match_preview）：每轮按场地数分几批，每批 21 分 15 分钟、15 分 10 分钟、11 分 7 分钟，三局两胜乘 2.5 */
function minutes(p: Plan, rounds: number, perRound: number) {
  const knockout = p.format !== 'groups' ? 0 : p.pools * p.advance === 2 ? 1 : Math.ceil(2 / Math.max(p.courts, 1)) + 1;
  const batch = { 21: 15, 15: 10, 11: 7 }[p.points] * (p.bestOf === 3 ? 2.5 : 1);
  return Math.ceil((rounds * Math.ceil(perRound / Math.max(p.courts, 1)) + knockout) * batch);
}

/** 循环赛（单打、固定搭档、小组赛）：每组圆桌法排，单数时每轮一人（一队）轮空 */
function roundRobin(entries: string[][][], rounds: number) {
  const out = new Map<number, Game[]>();
  entries.forEach((pool, p) => {
    const m = pool.length + (pool.length % 2);
    for (let r = 0; r <= Math.min(m - 2, rounds - 1); r++) {
      for (const [a, b] of roundRobinPairs(m, r).sort((x, y) => x[0] - y[0])) {
        if (a >= pool.length || b >= pool.length) continue;
        out.set(r + 1, [...(out.get(r + 1) ?? []), { round: r + 1, pool: entries.length > 1 ? p + 1 : undefined, a: pool[a], b: pool[b] }]);
      }
    }
  });
  return out;
}

/**
 * 双打轮换搭档（match_schedule_rotating）：人数不是 4 的倍数时，轮空最少的人轮空；
 * 先给“还没搭过的人”最少的人配，挑搭过最少的；两队配成一场时挑交手最少的
 */
function rotating(names: string[], rounds: number) {
  const n = names.length;
  const partners = Array.from({ length: n }, () => new Array<number>(n).fill(0));
  const rivals = Array.from({ length: n }, () => new Array<number>(n).fill(0));
  const played = new Array<number>(n).fill(0);
  const out = new Map<number, Game[]>();
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
      const [first] = pairs;
      const rest = pairs.slice(1);
      const other = minBy(rest, ([x, y]) => rivals[first[0]][x] + rivals[first[0]][y] + rivals[first[1]][x] + rivals[first[1]][y]);
      games.push({ round: r0 + 1, a: first.map((i) => names[i]), b: other.map((i) => names[i]) });
      for (const i of first) for (const j of other) {
        rivals[i][j]++;
        rivals[j][i]++;
      }
      pairs.splice(pairs.indexOf(other), 1);
      pairs.shift();
    }
    out.set(r0 + 1, games);
  }
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
  const { fullRounds, perRound } = plan(p.format, p.players.length, p.pools);
  const rounds = Math.max(p.format === 'groups' ? fullRounds : Math.min(fullRounds, p.rounds ?? fullRounds), 1);
  let pools: string[][] = [];
  let games: Map<number, Game[]>;
  if (p.format === 'rotating') {
    games = rotating(p.players, rounds);
  } else if (p.format === 'groups') {
    // 蛇形分组：第 1、4、5、8… 个进第 1 组
    pools = Array.from({ length: p.pools }, () => []);
    p.players.forEach((name, i) => pools[Math.floor(i / p.pools) % 2 === 0 ? i % p.pools : p.pools - 1 - (i % p.pools)].push(name));
    games = roundRobin(pools.map((pool) => pool.map((name) => [name])), rounds);
  } else {
    const entries = p.format === 'fixed'
      ? Array.from({ length: Math.floor(p.players.length / 2) }, (_, i) => p.players.slice(i * 2, i * 2 + 2))
      : p.players.map((name) => [name]);
    games = roundRobin([entries], rounds);
  }
  const everyone = new Set(p.players);
  return {
    rounds: [...games.entries()].map(([round, list]) => {
      const busy = new Set(list.flatMap((g) => [...g.a, ...g.b]));
      return { round, games: list, resting: [...everyone].filter((name) => !busy.has(name)) };
    }),
    pools,
    knockout: p.format !== 'groups' ? [] : p.pools * p.advance === 2 ? ['final'] : ['semi', 'semi', 'final'],
    fullRounds,
    minutes: minutes(p, rounds, perRound),
  };
}
