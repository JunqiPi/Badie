// 不登录也能用的排表：和服务器的排法一样（每对只打一次、轮空平均、同一轮没有人打两场、签位和轮空）
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { bracketOrder, cleanNames, countProblem, roundRobinPairs, schedule, type Plan } from '../src/lib/tournament.ts';

const names = (n: number) => Array.from({ length: n }, (_, i) => `P${i + 1}`);
const base: Omit<Plan, 'play' | 'format' | 'players'> = { courts: 2, points: 21, bestOf: 1, pools: 2, advance: 1, thirdPlace: false };
const key = (a: string[], b: string[]) => [a.join('+'), b.join('+')].sort().join(' v ');
const allGames = (p: Plan) => schedule(p).blocks.flatMap((b) => b.games);

test('圆桌法：m 个人 m−1 轮，每两人正好一次', () => {
  for (const m of [2, 4, 6, 10]) {
    const seen = new Set<string>();
    for (let r = 0; r < m - 1; r++) for (const [a, b] of roundRobinPairs(m, r)) seen.add([a, b].sort().join('-'));
    assert.equal(seen.size, (m * (m - 1)) / 2);
  }
});

test('循环（单打）：每两人打一场，单数时每轮一人轮空；打两遍时第二遍换边', () => {
  for (const n of [5, 6]) {
    const s = schedule({ ...base, play: 'singles', format: 'round_robin', players: names(n) });
    const games = s.blocks.flatMap((b) => b.games);
    assert.equal(games.length, (n * (n - 1)) / 2);
    assert.equal(new Set(games.map((g) => key(g.a, g.b))).size, games.length);
    assert.equal(s.blocks.length, n % 2 ? n : n - 1);
    for (const b of s.blocks) assert.equal(b.resting.length, n % 2);
  }
  const twice = schedule({ ...base, play: 'singles', format: 'round_robin', players: names(4), rounds: 6 });
  assert.equal(twice.maxRounds, 6);
  const [first, second] = [twice.blocks[0].games[0], twice.blocks[3].games[0]];
  assert.deepEqual([second.a, second.b], [first.b, first.a]);
  assert.equal(schedule({ ...base, play: 'singles', format: 'round_robin', players: names(8), rounds: 3 }).blocks.length, 3);
});

test('固定搭档：按名单两两一队，每队和每队打一场', () => {
  const games = allGames({ ...base, play: 'fixed', format: 'round_robin', players: names(8) });
  assert.equal(games.length, 6);
  for (const g of games) for (const side of [g.a, g.b]) assert.ok(['P1+P2', 'P3+P4', 'P5+P6', 'P7+P8'].includes(side.join('+')));
});

test('轮换搭档：同一轮没人打两场，轮空次数最多差 1，先和没搭过的人搭；最多 30 轮', () => {
  for (const n of [4, 5, 6, 7, 8, 9, 10, 12, 13, 16]) {
    const s = schedule({ ...base, play: 'rotating', format: 'swiss', players: names(n) });
    assert.equal(s.blocks.length, n + (n % 2) - 1);
    const rests = new Map(names(n).map((p) => [p, 0]));
    const partnered = new Map<string, number>();
    for (const b of s.blocks) {
      const busy = b.games.flatMap((g) => [...g.a, ...g.b]);
      assert.equal(new Set(busy).size, busy.length, `第 ${b.round} 轮有人打两场（${n} 人）`);
      assert.equal(b.games.length, Math.floor(n / 4));
      assert.equal(b.resting.length, n % 4);
      for (const p of b.resting) rests.set(p, rests.get(p)! + 1);
      for (const g of b.games) for (const side of [g.a, g.b]) {
        const k = [...side].sort().join('+');
        partnered.set(k, (partnered.get(k) ?? 0) + 1);
      }
    }
    const counts = [...rests.values()];
    assert.ok(Math.max(...counts) - Math.min(...counts) <= 1, `${n} 人轮空不平均：${counts}`);
    if (n % 4 === 0) assert.ok([...partnered.values()].every((c) => c === 1), `${n} 人有人重复搭档`);
  }
  assert.equal(schedule({ ...base, play: 'rotating', format: 'round_robin', players: names(8), rounds: 99 }).blocks.length, 30);
});

test('小组赛 + 淘汰赛：蛇形分组，组内循环，签位按出线人数', () => {
  const s = schedule({ ...base, play: 'singles', format: 'groups', players: names(8) });
  assert.deepEqual(s.pools, [['P1', 'P4', 'P5', 'P8'], ['P2', 'P3', 'P6', 'P7']]);
  assert.equal(s.blocks.flatMap((b) => b.games).length, 12);
  assert.deepEqual(s.koLater, [2]);
  const big = schedule({ ...base, play: 'singles', format: 'groups', players: names(24), pools: 3, advance: 2, thirdPlace: true });
  assert.deepEqual(big.koLater, [8, 4, 2]);
  assert.equal(big.third, true);
});

test('单淘汰：1 号和 2 号在两头，签位不够的给前几号种子轮空', () => {
  assert.deepEqual(bracketOrder(8), [1, 8, 4, 5, 2, 7, 3, 6]);
  const s = schedule({ ...base, play: 'singles', format: 'knockout', players: names(6), thirdPlace: true });
  assert.equal(s.blocks[0].ko, 8);
  assert.deepEqual(s.blocks[0].byes, ['P1', 'P2']);
  assert.deepEqual(s.blocks[0].games.map((g) => key(g.a, g.b)), ['P4 v P5', 'P3 v P6']);
  assert.deepEqual(s.koLater, [4, 2]);
  assert.equal(s.third, true);
});

test('瑞士轮：第 1 轮上半区打下半区，单数时最后一个轮空，默认 log2(人数) 轮', () => {
  const s = schedule({ ...base, play: 'singles', format: 'swiss', players: names(7) });
  assert.deepEqual(s.blocks[0].games.map((g) => key(g.a, g.b)), ['P1 v P4', 'P2 v P5', 'P3 v P6']);
  assert.deepEqual(s.blocks[0].byes, ['P7']);
  assert.equal(s.defaultRounds, 3);
  assert.deepEqual(s.swissLater, [2, 3]);
});

test('预计时间和服务器的 match_preview 一样', () => {
  assert.equal(schedule({ ...base, play: 'rotating', format: 'round_robin', players: names(8) }).minutes, 105);
  assert.equal(schedule({ ...base, play: 'singles', format: 'round_robin', players: names(6), courts: 3, points: 11, bestOf: 3 }).minutes, Math.ceil(5 * 7 * 2.5));
  // 2 组各 4 人：3 轮，每轮 4 场、2 片场地分 2 批，加一场决赛
  const groups = schedule({ ...base, play: 'singles', format: 'groups', players: names(8) });
  assert.equal(groups.minutes, (3 * 2 + 1) * 15);
  assert.equal(groups.rounds, 4);
  // 单淘汰 6 人：第一轮 2 场（1 批）、半决赛 2 场（1 批）、决赛加三四名 2 场（1 批）
  assert.equal(schedule({ ...base, play: 'singles', format: 'knockout', players: names(6), thirdPlace: true }).minutes, 3 * 15);
});

test('名字和人数', () => {
  assert.deepEqual(cleanNames('Amy\n  Ben  Lee ,amy\n\nAmy'), ['Amy', 'Ben Lee', 'amy 2', 'Amy 3']);
  assert.equal(countProblem('round_robin', 'fixed', 5, 2, 1)?.code, 'fixedEven');
  assert.deepEqual(countProblem('groups', 'singles', 5, 3, 1), { code: 'groups', n: 6 });
  assert.deepEqual(countProblem('swiss', 'fixed', 4, 2, 1), { code: 'swiss', n: 6 });
  assert.equal(countProblem('round_robin', 'rotating', 4, 2, 1), undefined);
});
