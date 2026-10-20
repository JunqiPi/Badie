// 定级问卷：与 iOS SkillAssessmentTests.swift 同样的用例，保证两边算出同样的等级
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { evaluate, tier } from '../src/app/assessment.ts';

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
