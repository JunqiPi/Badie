import { useSyncExternalStore } from 'react';
import type { Centre } from './pickers';

// 你在哪一带（定位或搜的城市）：首页、球馆、附近球局共用。只存在这个浏览器里，读不到就重新问

/** 附近范围的默认值（和附近球局、球群一样） */
export const NEARBY_KM = 30;

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

// 附近范围（iOS 设置里的“附近范围”）：发现页的卡片和日期上的人数用多大范围。只存在这个浏览器里
export const RANGES = [10, 30, 50, 100];
const rangeKey = 'badie-nearby-km';
const rangeListeners = new Set<() => void>();
let range = NEARBY_KM;
try {
  const saved = Number(localStorage.getItem(rangeKey));
  if (RANGES.includes(saved)) range = saved;
} catch {
  // 读不到就用默认的
}

export function setNearbyKm(km: number) {
  range = km;
  try {
    localStorage.setItem(rangeKey, String(km));
  } catch {
    // 存不下就只在这次打开时生效
  }
  rangeListeners.forEach((notify) => notify());
}

export function useNearbyKm() {
  return useSyncExternalStore(
    (notify) => {
      rangeListeners.add(notify);
      return () => rangeListeners.delete(notify);
    },
    () => range,
    () => NEARBY_KM,
  );
}
