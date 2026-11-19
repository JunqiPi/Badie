// 不登录也能用的排表：和服务器的排法一样（每对只打一次、轮空平均、同一轮没有人打两场）
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { cleanNames, countProblem, roundRobinPairs, schedule, type Plan } from '../src/lib/tournament.ts';

const names = (n: number) => Array.from({ length: n }, (_, i) => `P${i + 1}`);
const base: Omit<Plan, 'format' | 'players'> = { courts: 2, points: 21, bestOf: 1, pools: 2, advance: 1 };
const key = (a: string[], b: string[]) => [a.join('+'), b.join('+')].sort().join(' v ');

test('圆桌法：m 个人 m−1 轮，每两人正好一次', () => {
  for (const m of [2, 4, 6, 10]) {
    const seen = new Set<string>();
    for (let r = 0; r < m - 1; r++) for (const [a, b] of roundRobinPairs(m, r)) seen.add([a, b].sort().join('-'));
    assert.equal(seen.size, (m * (m - 1)) / 2);
  }
});

test('单打循环：每两人打一场，单数时每轮一人轮空', () => {
  for (const n of [5, 6]) {
    const s = schedule({ ...base, format: 'singles', players: names(n) });
    const games = s.rounds.flatMap((r) => r.games);
    assert.equal(games.length, (n * (n - 1)) / 2);
    assert.equal(new Set(games.map((g) => key(g.a, g.b))).size, games.length);
    assert.equal(s.rounds.length, n % 2 ? n : n - 1);
    for (const r of s.rounds) assert.equal(r.resting.length, n % 2);
  }
});

test('只打几轮', () => {
  const s = schedule({ ...base, format: 'singles', players: names(8), rounds: 3 });
  assert.equal(s.rounds.length, 3);
  assert.equal(s.fullRounds, 7);
});

test('固定搭档：按名单两两一队，每队和每队打一场', () => {
  const s = schedule({ ...base, format: 'fixed', players: names(8) });
  const games = s.rounds.flatMap((r) => r.games);
  assert.equal(games.length, 6);
  for (const g of games) for (const side of [g.a, g.b]) assert.ok(['P1+P2', 'P3+P4', 'P5+P6', 'P7+P8'].includes(side.join('+')));
});

test('轮换搭档：同一轮没人打两场，轮空次数最多差 1，先和没搭过的人搭', () => {
  for (const n of [4, 5, 6, 7, 8, 9, 10, 12, 13, 16]) {
    const s = schedule({ ...base, format: 'rotating', players: names(n) });
    assert.equal(s.rounds.length, n + (n % 2) - 1);
    const rests = new Map(names(n).map((p) => [p, 0]));
    const partnered = new Map<string, number>();
    for (const r of s.rounds) {
      const busy = r.games.flatMap((g) => [...g.a, ...g.b]);
      assert.equal(new Set(busy).size, busy.length, `第 ${r.round} 轮有人打两场（${n} 人）`);
      assert.equal(r.games.length, Math.floor(n / 4));
      assert.equal(r.resting.length, n % 4);
      for (const p of r.resting) rests.set(p, rests.get(p)! + 1);
      for (const g of r.games) for (const side of [g.a, g.b]) {
        const k = [...side].sort().join('+');
        partnered.set(k, (partnered.get(k) ?? 0) + 1);
      }
    }
    const counts = [...rests.values()];
    assert.ok(Math.max(...counts) - Math.min(...counts) <= 1, `${n} 人轮空不平均：${counts}`);
    // 搭档两次以上的，只在已经和所有人都搭过之后才会有
    if (n % 4 === 0) assert.ok([...partnered.values()].every((c) => c === 1), `${n} 人有人重复搭档`);
  }
});

test('分组循环：蛇形分组，组内循环，再打淘汰赛', () => {
  const s = schedule({ ...base, format: 'groups', players: names(8), pools: 2, advance: 1 });
  assert.deepEqual(s.pools, [['P1', 'P4', 'P5', 'P8'], ['P2', 'P3', 'P6', 'P7']]);
  const games = s.rounds.flatMap((r) => r.games);
  assert.equal(games.length, 12);
  for (const g of games) assert.equal(s.pools[g.pool! - 1].includes(g.a[0]) && s.pools[g.pool! - 1].includes(g.b[0]), true);
  assert.deepEqual(s.knockout, ['final']);
  assert.deepEqual(schedule({ ...base, format: 'groups', players: names(9), pools: 3, advance: 1 }).knockout, ['semi', 'semi', 'final']);
});

test('预计时间和服务器的 match_preview 一样', () => {
  assert.equal(schedule({ ...base, format: 'rotating', players: names(8) }).minutes, 105);
  assert.equal(schedule({ ...base, format: 'singles', players: names(6), courts: 3, points: 11, bestOf: 3 }).minutes, Math.ceil(5 * 1 * 7 * 2.5));
  // 2 组各 4 人：3 轮，每轮 4 场、2 片场地分 2 批，加一场决赛
  assert.equal(schedule({ ...base, format: 'groups', players: names(8) }).minutes, (3 * 2 + 1) * 15);
});

test('名字：一行一个或逗号分开，重名加数字', () => {
  assert.deepEqual(cleanNames('Amy\n  Ben  Lee ,amy\n\nAmy'), ['Amy', 'Ben Lee', 'amy 2', 'Amy 3']);
  assert.equal(countProblem('fixed', 5, 2), 'fixedEven');
  assert.equal(countProblem('groups', 5, 3), 'groups');
  assert.equal(countProblem('rotating', 4, 2), undefined);
});
