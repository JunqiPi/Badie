// 定级问卷：与 iOS SkillAssessmentTests.swift 同样的用例，保证两边算出同样的等级
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { evaluate, questions, tier } from '../src/app/assessment.ts';

const techniques = questions.filter((q) => q.kind === 'technique').map((q) => q.id);

/** 所有技术分项都在 level 级，overrides 单独调整某几项；其余是台阶题的选项序号 */
function profile(level: number, { overrides = {} as Record<string, number>, passive = 1, doubles = 2, stability = 2, tactics = 0, standing = 0, experience = 0, returning = false } = {}) {
  const answers: Record<string, number> = { passive, doubles, stability, tactics, standing, experience, recency: returning ? 1 : 0 };
  for (const id of techniques) answers[id] = Math.max(0, (overrides[id] ?? level) - (id === 'clear' || id === 'footwork' ? 1 : 2));
  return answers;
}
const code = (answers: Record<string, number>) => tier(evaluate(answers)!.rating).label;

test('没答完不出结果', () => {
  const partial = profile(3);
  delete partial.standing;
  assert.equal(evaluate(partial), undefined);
});

test('完全的新手', () => {
  assert.equal(code({ ...profile(1, { doubles: 0, stability: 0 }), net: 0 }), '1−');
});

test('技术题定出 4+ 以内的档位', () => {
  assert.equal(code(profile(3)), '3');
  assert.equal(code(profile(3, { overrides: { clear: 4, net: 4 } })), '3+');
  assert.equal(code(profile(4, { overrides: { backhand: 3, drop: 3 } })), '4−');
  assert.equal(code(profile(3, { overrides: { backhand: 2 } })), '3−');
  const weak = evaluate(profile(5, { overrides: { backhand: 3 } }))!;
  assert.equal(tier(weak.rating).label, '4−');
  assert.match(weak.limitingGate!, /backhand back court/);
  assert.equal(code(profile(4, { overrides: { smash: 5, net: 5 }, stability: 3 })), '4+');
  assert.equal(code(profile(4, { overrides: { smash: 5, net: 5 }, stability: 2 })), '4');
});

test('4 级要有双打意识', () => {
  const result = evaluate(profile(4, { doubles: 1 }))!;
  assert.equal(tier(result.rating).label, '4−');
  assert.match(result.limitingGate!, /doubles/);
});

test('被动球和战术推到 5', () => {
  const overrides = { smash: 5, net: 5 };
  assert.equal(code(profile(4, { overrides, passive: 1, stability: 3, tactics: 2 })), '4+');
  assert.equal(code(profile(4, { overrides, passive: 2, stability: 3, tactics: 2 })), '5−');
  assert.equal(code(profile(4, { overrides, passive: 3, stability: 3, tactics: 2 })), '5');
  assert.equal(code(profile(4, { overrides, passive: 3, stability: 3, tactics: 3 })), '5+');
  assert.equal(code(profile(4, { passive: 3, stability: 3, tactics: 3 })), '4');
});

test('俱乐部位置推到 6', () => {
  const overrides = { smash: 6, net: 6 };
  assert.equal(code(profile(5, { overrides, passive: 3, stability: 4, tactics: 3, standing: 4 })), '6');
  assert.equal(code(profile(5, { overrides, passive: 3, stability: 4, tactics: 3, standing: 3 })), '6−');
  const noSpecialty = evaluate(profile(5, { passive: 3, stability: 4, tactics: 3, standing: 4 }))!;
  assert.equal(tier(noSpecialty.rating).label, '6−');
  assert.match(noSpecialty.limitingGate!, /signature/);
  assert.equal(code(profile(4, { standing: 5 })), '4');
  const notYet = evaluate(profile(4, { overrides: { smash: 5, net: 5 }, passive: 3, stability: 4, tactics: 3, standing: 4 }))!;
  assert.equal(tier(notYet.rating).label, '5+');
  assert.match(notYet.limitingGate!, /most skills at level 5/);
});

test('问卷最高 6+', () => {
  assert.equal(code(profile(6, { passive: 4, doubles: 4, stability: 5, tactics: 4, standing: 5, experience: 4 })), '6+');
  const capped = evaluate(profile(6, { passive: 4, doubles: 4, stability: 5, tactics: 4, standing: 5 }))!;
  assert.equal(tier(capped.rating).label, '6');
  assert.match(capped.limitingGate!, /tournament or junior training/);
});

test('经历保底，回归球友减 1 级', () => {
  const active = evaluate(profile(2, { experience: 3 }))!;
  assert.equal(tier(active.rating).label, '5−');
  assert.equal(active.needsCalibration, true);
  const returning = evaluate(profile(2, { experience: 3, returning: true }))!;
  assert.equal(tier(returning.rating).level, tier(active.rating).level - 1);
  assert.equal(returning.isReturning, true);
});

test('档位显示', () => {
  assert.deepEqual([3, 3.67, 4.33, 0.67].map((r) => tier(r).label), ['3', '4−', '4+', '1−']);
  assert.equal(tier(6).name, 'Club expert');
});
