// 不登录也能测级：答案只留在这个浏览器标签页里（sessionStorage），不传到服务器。
// 注册并建好资料后用同一份答案存一次（saveArgs），登录的人点“保存”也走 saveArgs，所以两边算出的等级一样。
// 带 .ts 后缀：这个文件也直接给 Node 跑单元测试
import { evaluate, questions } from './assessment.ts';

type Store = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>;

const answersKey = 'badie-quiz-answers';
const refKey = 'badie-ref';

function storage(kind: 'sessionStorage' | 'localStorage'): Store | undefined {
  try {
    return globalThis[kind];
  } catch {
    // 隐私模式等情况下读不了
    return undefined;
  }
}

/** 每题都答了、选项序号在范围内才算一份完整的答案 */
export function validAnswers(value: unknown): Record<string, number> | undefined {
  if (!value || typeof value !== 'object') return;
  const answers = value as Record<string, unknown>;
  const ok = questions.every((q) => Number.isInteger(answers[q.id]) && (answers[q.id] as number) >= 0 && (answers[q.id] as number) < q.options.length);
  return ok ? Object.fromEntries(questions.map((q) => [q.id, answers[q.id] as number])) : undefined;
}

export function savePending(answers: Record<string, number>, store = storage('sessionStorage')) {
  try {
    store?.setItem(answersKey, JSON.stringify(answers));
  } catch {
    // 存不下就只在这一页里有效
  }
}

export function loadPending(store = storage('sessionStorage')) {
  try {
    return validAnswers(JSON.parse(store?.getItem(answersKey) ?? 'null'));
  } catch {
    return undefined;
  }
}

export function clearPending(store = storage('sessionStorage')) {
  try {
    store?.removeItem(answersKey);
  } catch {
    // 同上
  }
}

/** save_assessment 的参数：等级在本机算，答案原样存（以后能重新算打法） */
export function saveArgs(answers: Record<string, number>) {
  const result = evaluate(answers);
  return result && { p_rating: result.rating, p_answers: answers };
}

/** 从哪个链接来的（?ref=card）：只记第一次，注册时写进资料。不含个人信息 */
export function rememberRef(search: string, store = storage('localStorage')) {
  const ref = new URLSearchParams(search).get('ref');
  if (!ref || !/^[a-z0-9_-]{1,32}$/i.test(ref)) return;
  try {
    if (!store?.getItem(refKey)) store?.setItem(refKey, ref.toLowerCase());
  } catch {
    // 存不下就不记
  }
}

export function loadRef(store = storage('localStorage')) {
  try {
    return store?.getItem(refKey) ?? undefined;
  } catch {
    return undefined;
  }
}
