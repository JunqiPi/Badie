import { useSyncExternalStore } from 'react';
import type { Centre } from './pickers';

// 你在哪一带（定位或搜的城市）：首页、球馆、附近球局共用。只存在这个浏览器里，读不到就重新问

const key = 'badie-area';
const listeners = new Set<() => void>();
let area: Centre | undefined;

try {
  area = JSON.parse(localStorage.getItem(key) ?? 'null') ?? undefined;
} catch {
  area = undefined;
}

export function setArea(next: Centre) {
  area = next;
  try {
    localStorage.setItem(key, JSON.stringify(next));
  } catch {
    // 存不下就只在这次打开时生效
  }
  listeners.forEach((notify) => notify());
}

export function useArea() {
  return useSyncExternalStore(
    (notify) => {
      listeners.add(notify);
      return () => listeners.delete(notify);
    },
    () => area,
    () => undefined,
  );
}
