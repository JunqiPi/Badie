// 定级问卷：与 iOS SkillAssessmentTests.swift 同样的用例，保证两边算出同样的等级
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { archetypeInfo, axes, axisLevel, evaluate, playStyle, questionTitle, tier, tierSlug } from '../src/app/assessment.ts';
import { clearPending, loadPending, loadRef, rememberRef, saveArgs, savePending } from '../src/app/quizStore.ts';

/** 选项序号（A = 0）。技术：高远、杀球、吊球、反手、网前、平抽、步法；比赛：被动球、双打、稳定性、战术 */
function answers(technique: number[], game: number[], { standing = 0, experience = 0, returning = false } = {}) {
  const [clear, smash, drop, backhand, net, drive, footwork] = technique;
  const [passive, doubles, stability, tactics] = game;
  return { clear, smash, drop, backhand, net, drive, footwork, passive, doubles, stability, tactics, standing, experience, recency: returning ? 1 : 0 };
}
const code = (a: Record<string, number>) => tier(evaluate(a)!.rating).label;

// 典型的几类球友
const beginner = answers([1, 1, 1, 1, 1, 1, 1], [0, 1, 1, 0]);
const middle = answers([3, 3, 3, 2, 2, 2, 3], [2, 2, 3, 2]);
const strong = answers([4, 4, 4, 3, 3, 3, 4], [3, 3, 4, 3]);
const top = answers([5, 5, 5, 4, 4, 4, 5], [4, 4, 5, 4]);

test('没答完不出结果', () => {
  const partial: Record<string, number> = { ...middle };
  delete partial.standing;
  assert.equal(evaluate(partial), undefined);
});

test('完全的新手', () => {
  assert.equal(code(answers([0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0])), '1−');
  assert.equal(code(answers([0, 0, 0, 0, 1, 0, 0], [0, 1, 0, 0])), '1');
});

test('中间的选项不会一下子到 5', () => {
  assert.equal(code(beginner), '2');
  assert.equal(code(middle), '3+');
  assert.equal(code(strong), '5−');
});

test('短板限制等级，结果里点名', () => {
  const noBackhand = evaluate(answers([3, 3, 3, 0, 2, 2, 3], [2, 2, 3, 2]))!;
  assert.equal(tier(noBackhand.rating).label, '3−');
  assert.match(noBackhand.limitingGate!, /^To reach level 3, work on: backhand back court/);
});

test('技术好但比赛能力弱：以弱的为准', () => {
  const result = evaluate(answers([4, 4, 4, 3, 3, 3, 4], [1, 2, 3, 1]))!;
  assert.equal(tier(result.rating).label, '4−');
  assert.match(result.limitingGate!, /^To reach level 4, work on: smash defense/);
});

test('5+ 往上看俱乐部里的位置', () => {
  const unknown = evaluate(top)!;
  assert.equal(tier(unknown.rating).label, '5+');
  assert.match(unknown.limitingGate!, /strongest players in your club/);
  assert.equal(code({ ...top, standing: 3 }), '6−');
  assert.equal(code({ ...top, standing: 4 }), '6');
  // 俱乐部霸主还要有比赛或青训经历
  const ace = evaluate({ ...top, standing: 5 })!;
  assert.equal(tier(ace.rating).label, '6');
  assert.match(ace.limitingGate!, /tournament or junior training/);
  assert.equal(code({ ...top, standing: 5, experience: 3 }), '6+');
  // 位置再高，技术没到也不是 6
  assert.equal(code({ ...strong, standing: 5 }), '5−');
});

test('经历保底，回归球友减 1 级', () => {
  const active = evaluate({ ...beginner, experience: 3 })!;
  assert.equal(tier(active.rating).label, '5−');
  assert.equal(active.needsCalibration, true);
  const returning = evaluate({ ...beginner, experience: 3, recency: 1 })!;
  assert.equal(tier(returning.rating).level, tier(active.rating).level - 1);
  assert.equal(returning.isReturning, true);
});

test('档位显示', () => {
  assert.deepEqual([3, 3.67, 4.33, 0.67].map((r) => tier(r).label), ['3', '4−', '4+', '1−']);
  assert.equal(tier(6).name, 'Club expert');
});

// 打法：和 iOS PlayStyleTests.swift 用同一组用例（改了一边，另一边也要改）
// [名字, 技术, 比赛, 等级, 打法, 六项能力（进攻、网前、防守、速度、步法、战术）, 卡片上的数字, 最强一拍, 离下一级还差]
const fixtures: [string, number[], number[], string, string, number[], number[], string, [number, string] | null][] = [
  ['demo', [4, 4, 4, 2, 3, 3, 4], [2, 2, 3, 2], '4', 'allround', [4, 4, 4, 4, 4, 3.75], [4, 4, 4, 4, 4, 4], 'clear', [5, 'backhand']],
  ['cannon', [4, 5, 4, 2, 3, 3, 4], [2, 2, 3, 2], '4', 'cannon', [6, 4, 4, 4, 4, 3.75], [6, 4, 4, 4, 4, 4], 'smash', [5, 'backhand']],
  ['net', [3, 2, 5, 2, 4, 2, 3], [2, 2, 3, 2], '4−', 'net', [2.5, 6, 4, 2.5, 3, 3.75], [3, 6, 4, 3, 3, 4], 'drop', [4, 'smash']],
  ['wall', [3, 2, 2, 2, 2, 2, 3], [4, 2, 5, 2], '3+', 'wall', [2.5, 2.5, 6, 2.5, 3, 3.75], [3, 3, 6, 3, 3, 4], 'clear', [4, 'drop']],
  ['quick', [3, 2, 2, 2, 2, 4, 3], [1, 1, 2, 1], '3', 'quick', [2.5, 2.5, 3, 6, 3, 2.75], [3, 3, 3, 6, 3, 3], 'drive', [4, 'drop']],
  ['engine', [3, 2, 2, 2, 2, 2, 5], [1, 1, 2, 1], '3', 'engine', [2.5, 2.5, 3, 2.5, 6, 2.75], [3, 3, 3, 3, 6, 3], 'footwork', [4, 'drop']],
  ['captain', [3, 2, 2, 2, 2, 2, 3], [1, 4, 2, 4], '3+', 'captain', [2.5, 2.5, 3, 2.5, 3, 6], [3, 3, 3, 3, 3, 6], 'clear', [4, 'drop']],
  // 进攻和网前一样高：按顺序取进攻；杀球和吊球一样好：按题目顺序取杀球
  ['tieAttackNet', [3, 4, 4, 2, 3, 2, 2], [0, 0, 1, 0], '3−', 'cannon', [4, 4, 2, 2.5, 2.5, 1.75], [4, 4, 2, 3, 3, 2], 'smash', [3, 'doubles']],
  // 最高和最低差半级：还是六边形战士
  ['allroundHalf', [4, 4, 4, 2, 3, 3, 4], [2, 2, 2, 2], '4−', 'allround', [4, 4, 3.5, 4, 4, 3.75], [4, 4, 4, 4, 4, 4], 'clear', [4, 'backhand']],
  // 差 0.75 级：看最高的一项
  ['cannonEdge', [4, 4, 4, 2, 3, 3, 4], [2, 2, 3, 1], '4−', 'cannon', [4, 4, 4, 4, 4, 3.25], [4, 4, 4, 4, 4, 3], 'clear', [4, 'backhand']],
  // 完全的新手（1−）：总等级 1–2 级是新星，不看六项；网前 0.5 显示成 1；没有“还差”
  ['brandNew', [0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0], '1−', 'rookie', [1, 0.5, 1.5, 1, 1, 1.75], [1, 1, 2, 1, 1, 2], 'clear', null],
  // 2 级：新星（六项看是指挥官也不算）；杀球和步法一样弱：按题目顺序取杀球
  ['tieGap', [1, 1, 2, 1, 1, 1, 1], [0, 1, 1, 0], '2', 'rookie', [1.5, 2, 2, 2, 1.5, 2.25], [2, 2, 2, 2, 2, 2], 'clear', [3, 'smash']],
  // 2 级的入门球友：新星
  ['beginner', [1, 1, 1, 1, 1, 1, 1], [0, 1, 1, 0], '2', 'rookie', [1.5, 1.5, 2, 2, 1.5, 2.25], [2, 2, 2, 2, 2, 2], 'clear', [3, 'drop']],
  // 5+ 往上看俱乐部位置：没有“还差”的那一项
  ['top', [5, 5, 5, 4, 4, 4, 5], [4, 4, 5, 4], '5+', 'allround', [6, 6, 6, 6, 6, 6], [6, 6, 6, 6, 6, 6], 'clear', null],
];

test('打法：和 iOS 同一组用例', () => {
  for (const [name, technique, game, label, archetype, scores, shown, shot, gap] of fixtures) {
    const given = answers(technique, game);
    assert.equal(code(given), label, name);
    const style = playStyle(given)!;
    assert.equal(style.archetype, archetype, name);
    assert.deepEqual(axes.map((a) => style.scores[a]), scores, name);
    assert.deepEqual(axes.map((a) => axisLevel(style.scores[a])), shown, name);
    assert.equal(style.bestShot, shot, name);
    const next = evaluate(given)!.next;
    assert.deepEqual(next ? [next.level, next.id] : null, gap, name);
  }
  assert.equal(questionTitle('smash'), 'Forehand smash');
});

test('打法：要答完全部题目（新星要看问卷定出的等级）', () => {
  for (const id of ['tactics', 'standing']) {
    const partial: Record<string, number> = answers([4, 4, 4, 2, 3, 3, 4], [2, 2, 3, 2]);
    delete partial[id];
    assert.equal(playStyle(partial), undefined, id);
  }
});

test('打法：最佳搭档', () => {
  const partners = Object.fromEntries(Object.entries(archetypeInfo).map(([k, v]) => [k, v.partner ?? null]));
  assert.deepEqual(partners, { cannon: 'net', net: 'cannon', wall: 'quick', quick: 'wall', engine: 'captain', captain: 'engine', allround: null, rookie: null });
});

test('离下一级还差：最弱的一项', () => {
  const result = evaluate(answers([3, 3, 3, 0, 2, 2, 3], [2, 2, 3, 2]))!;
  assert.equal(tier(result.rating).label, '3−');
  assert.deepEqual(result.next, { level: 3, skill: 'Backhand back court', id: 'backhand' });
  assert.match(result.limitingGate!, /^To reach level 3, work on: backhand back court/);
});

test('每一档页面的地址', () => {
  assert.deepEqual([0.67, 1, 4.33, 3.67, 6.33, 8].map(tierSlug), ['1-minus', '1', '4-plus', '4-minus', '6-plus', '8']);
});

// 不登录测级：答案存在本机，注册后存的和登录后直接存的是同一份
test('没登录和登录后存的等级一样', () => {
  const memory = new Map<string, string>();
  const store = { getItem: (k: string) => memory.get(k) ?? null, setItem: (k: string, v: string) => void memory.set(k, v), removeItem: (k: string) => void memory.delete(k) };
  for (const a of [beginner, middle, strong, top, { ...top, standing: 5, experience: 3 }, { ...beginner, experience: 3, recency: 1 }]) {
    savePending(a, store);
    const restored = loadPending(store)!;
    assert.deepEqual(saveArgs(restored), saveArgs(a));
    assert.equal(tier(saveArgs(restored)!.p_rating).label, code(a));
  }
  clearPending(store);
  assert.equal(loadPending(store), undefined);
  // 答案不完整或被改坏了不用
  store.setItem('badie-quiz-answers', JSON.stringify({ ...middle, clear: 9 }));
  assert.equal(loadPending(store), undefined);
  store.setItem('badie-quiz-answers', '{');
  assert.equal(loadPending(store), undefined);
});

test('来源链接只记第一次', () => {
  const memory = new Map<string, string>();
  const store = { getItem: (k: string) => memory.get(k) ?? null, setItem: (k: string, v: string) => void memory.set(k, v), removeItem: (k: string) => void memory.delete(k) };
  rememberRef('?x=1', store);
  assert.equal(loadRef(store), undefined);
  rememberRef('?ref=<script>', store);
  assert.equal(loadRef(store), undefined);
  rememberRef('?ref=Card', store);
  rememberRef('?ref=other', store);
  assert.equal(loadRef(store), 'card');
});
