import { tier } from './assessment';
import { t } from './i18n';
import type { Gender } from './gender';
import type { DayCandidate, NearbyPlayer } from './supabase';
import { partOf } from './usual';

/** 按天看人的筛选（iOS 的 DayCardFilter）：项目、球馆、等级、时间、对方性别、只看没爽约过的。记在本机 */
export interface DayFilter {
  event: 'any' | 'singles' | 'doubles' | 'mixed';
  /** 空 = 全部球馆 */
  venues: string[];
  /** 选过的球馆的名字（这天没人约那家时，也能看到并去掉） */
  venueNames: Record<string, string>;
  minLevel: number;
  maxLevel: number;
  /** 空 = 不限 */
  times: TimeOfDay[];
  gender: Gender | null;
  reliableOnly: boolean;
}

export type TimeOfDay = 'morning' | 'afternoon' | 'evening';

export const emptyFilter: DayFilter = { event: 'any', venues: [], venueNames: {}, minLevel: 1, maxLevel: 9, times: [], gender: null, reliableOnly: false };

export const eventLabels = (): Record<DayFilter['event'], string> => ({ any: t('All'), singles: t('Singles'), doubles: t('Doubles'), mixed: t('Mixed doubles') });
export const timeLabels = (): Record<TimeOfDay, string> => ({ morning: t('Morning'), afternoon: t('Afternoon'), evening: t('Evening') });

/** 按开始时间：12 点前上午，18 点前下午，之后晚上（本地时间） */
export function timeOfDay(iso: string): TimeOfDay {
  const hour = new Date(iso).getHours();
  return hour < 12 ? 'morning' : hour < 18 ? 'afternoon' : 'evening';
}

export function activeCount(f: DayFilter) {
  return [f.event !== 'any', f.venues.length > 0, f.minLevel > 1 || f.maxLevel < 9, f.times.length > 0, f.gender !== null, f.reliableOnly].filter(Boolean).length;
}

export function matches(f: DayFilter, card: DayCandidate) {
  if (f.event === 'singles' && card.mode !== 'singles') return false;
  if (f.event === 'doubles' && (card.mode !== 'doubles' || card.mixed)) return false;
  if (f.event === 'mixed' && !card.mixed) return false;
  if (f.venues.length && !(card.venues ?? []).some((v) => f.venues.includes(v.id))) return false;
  const level = tier(card.user.rating).level;
  if (level < f.minLevel || level > f.maxLevel) return false;
  if (f.times.length && !f.times.includes(timeOfDay(card.starts_at))) return false;
  if (f.gender && card.user.gender !== f.gender) return false;
  if (f.reliableOnly && (card.user.recent_no_shows ?? 0) > 0) return false;
  return true;
}

/** 附近的人：球馆看 TA 常去的；项目看 TA 偏好的（没填的都算，混双算双打）；时间看 TA 的空闲时间（没填的不算） */
export function matchesNearby(f: DayFilter, card: NearbyPlayer) {
  const mode = card.user.preferred_mode;
  if (mode && f.event !== 'any' && mode !== (f.event === 'singles' ? 'singles' : 'doubles')) return false;
  if (f.venues.length && !(card.venues ?? []).some((v) => f.venues.includes(v.id))) return false;
  const level = tier(card.user.rating).level;
  if (level < f.minLevel || level > f.maxLevel) return false;
  if (f.times.length && !(card.user.usual_times ?? []).some((u) => f.times.includes(partOf(u)))) return false;
  if (f.gender && card.user.gender !== f.gender) return false;
  if (f.reliableOnly && (card.user.recent_no_shows ?? 0) > 0) return false;
  return true;
}

/** 约在哪家：选了球馆就用选的那家，否则离我最近的 */
export function inviteVenue(f: DayFilter, card: { venues: DayCandidate['venues'] }) {
  const sorted = [...(card.venues ?? [])].sort((a, b) => (a.km ?? Infinity) - (b.km ?? Infinity));
  return sorted.find((v) => f.venues.includes(v.id)) ?? sorted[0];
}

const KEY = 'badie.dayFilter';

export function loadFilter(): DayFilter {
  try {
    return { ...emptyFilter, ...JSON.parse(localStorage.getItem(KEY) ?? '{}') };
  } catch {
    return emptyFilter;
  }
}

export function saveFilter(f: DayFilter) {
  try {
    localStorage.setItem(KEY, JSON.stringify(f));
  } catch {}
}
