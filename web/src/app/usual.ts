import { currentLocale, t } from './i18n';
import { clock, day, dayName, timeOf, today, wallClock, zoned } from './time';

// 空闲时间（profiles.usual_times）和邀请局的大概时间（窗口）。时间都按球馆当地时间

/** 一段空闲时间：weekday 1 = 周日 … 7 = 周六（和 iOS、服务器一样），start / end 是 "HH:MM"（end 可以是 "24:00"） */
export interface UsualTime {
  weekday: number;
  start: string;
  end: string;
}

export type Daypart = 'morning' | 'afternoon' | 'evening';
/** 上午 08–12、下午 14–18、晚上 18–22（从 0 点起的分钟） */
export const PARTS: Record<Daypart, [number, number]> = { morning: [480, 720], afternoon: [840, 1080], evening: [1080, 1320] };
const TWO_HOURS = 120 * 60000;

export const toMinutes = (hhmm: string) => {
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + m;
};
export const toHHMM = (minutes: number) => `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`;

/** 一段时间算上午、下午还是晚上：按中点 */
export function partOf(slot: { start: string; end: string }): Daypart {
  const mid = (toMinutes(slot.start) + toMinutes(slot.end)) / 2;
  return mid < 720 ? 'morning' : mid < 1080 ? 'afternoon' : 'evening';
}

export const partName = (p: Daypart) => ({ morning: t('Morning'), afternoon: t('Afternoon'), evening: t('Evening') })[p];
const partLower = (p: Daypart) => ({ morning: t('morning'), afternoon: t('afternoon'), evening: t('evening') })[p];
const partPlural = (p: Daypart) => ({ morning: t('mornings'), afternoon: t('afternoons'), evening: t('evenings') })[p];

/** 星期几的简称，1 = 周日 */
export const weekdayShort = (w: number) => new Intl.DateTimeFormat(currentLocale(), { weekday: 'short', timeZone: 'UTC' }).format(Date.UTC(2000, 0, 1 + w));
/** 某天（YYYY-MM-DD）是星期几，1 = 周日 */
export const weekdayOf = (date: string) => new Date(`${date}T12:00:00Z`).getUTCDay() + 1;
const mondayFirst = (w: number) => (w + 5) % 7;

/** 卡片上的小标签：“周六下午” */
export const slotLabel = (u: UsualTime) => t('{day} {time}', { day: weekdayShort(u.weekday), time: partLower(partOf(u)) });

function daysText(days: number[]) {
  const set = new Set(days);
  if (set.size === 7) return t('daily');
  if (set.size === 5 && [2, 3, 4, 5, 6].every((d) => set.has(d))) return t('weekday');
  if (set.size === 2 && set.has(1) && set.has(7)) return t('weekend');
  return [...set].sort((a, b) => mondayFirst(a) - mondayFirst(b)).map(weekdayShort).join(t(', '));
}

/** “工作日晚上 · 周末下午”：按时段归纳，最多两段，多了加“等”。没填返回 null */
export function freeSummary(times: UsualTime[] | null | undefined) {
  if (!times?.length) return null;
  const groups = new Map<Daypart, Set<number>>();
  for (const u of times) groups.set(partOf(u), (groups.get(partOf(u)) ?? new Set()).add(u.weekday));
  const order: Daypart[] = ['morning', 'afternoon', 'evening'];
  const segments = [...groups]
    .sort(([a, x], [b, y]) => y.size - x.size || order.indexOf(a) - order.indexOf(b))
    .map(([part, days]) => t('{days} {time}', { days: daysText([...days]), time: partPlural(part) }));
  const list = segments.slice(0, 2).join(' · ');
  return segments.length > 2 ? t('{list} and more', { list }) : list;
}

/** 最早能开始的时刻：现在 + 30 分钟，按半小时对齐（和服务器一样） */
const earliest = (now = Date.now()) => Math.ceil((now + 30 * 60000) / 1800000) * 1800000;

/** 这段空闲时间最近的一次（还来得及打 2 小时的）：日期 + 开始、结束分钟。不够 2 小时的按 2 小时算 */
export function nextOccurrence(u: UsualTime, tz: string, now = Date.now()) {
  const from = toMinutes(u.start);
  const to = Math.min(1440, Math.max(toMinutes(u.end), from + 120));
  for (let i = 0; i < 8; i++) {
    const date = today(tz, i);
    if (weekdayOf(date) !== u.weekday) continue;
    if (zoned(date, to, tz).getTime() - Math.max(zoned(date, from, tz).getTime(), earliest(now)) >= TWO_HOURS) return { date, from, to };
  }
}

/** 带大概时间的球局、邀请、聊天（服务器给的字段） */
export interface Windowed {
  time_set?: boolean | null;
  window_start?: string | null;
  window_end?: string | null;
  daypart?: Daypart | null;
}

/** 还没定具体时间（有窗口） */
export const unset = (w: Windowed): w is Windowed & { window_start: string; window_end: string } =>
  w.time_set === false && Boolean(w.window_start) && Boolean(w.window_end);

/** 结束前一分钟：24:00 结束的算当天 */
const lastMinute = (iso: string) => new Date(new Date(iso).getTime() - 60000).toISOString();

/** 大字：“周六 · 下午”“周末 · 晚上”“工作日 · 晚上” */
export function windowTitle(w: Windowed & { window_start: string; window_end: string }, tz?: string | null) {
  const zone = tz ?? Intl.DateTimeFormat().resolvedOptions().timeZone;
  const s = wallClock(w.window_start, zone).date;
  const e = wallClock(lastMinute(w.window_end), zone).date;
  const days = s === e ? dayName(w.window_start, tz)
    : weekdayOf(s) === 7 && weekdayOf(e) === 1 ? t('Weekend')
    : weekdayOf(s) === 2 && weekdayOf(e) === 6 ? t('Weekdays')
    : `${day(w.window_start, tz)} – ${day(lastMinute(w.window_end), tz)}`;
  return w.daypart ? `${days} · ${partName(w.daypart)}` : days;
}

/** 小字：“14:00–18:00 之间”，跨几天的写日期 */
export function windowDetail(w: Windowed & { window_start: string; window_end: string }, tz?: string | null) {
  const zone = tz ?? Intl.DateTimeFormat().resolvedOptions().timeZone;
  const s = wallClock(w.window_start, zone).date;
  const e = wallClock(lastMinute(w.window_end), zone).date;
  if (s === e) return t('Between {from} and {to}', { from: timeOf(w.window_start, tz), to: timeOf(w.window_end, tz) });
  const range = `${day(w.window_start, tz)} – ${day(lastMinute(w.window_end), tz)}`;
  return w.daypart ? `${range} · ${clock(PARTS[w.daypart][0])}–${clock(PARTS[w.daypart][1])}` : range;
}

/** 定时间能选的开始时刻：窗口里、整段在时段里、至少半小时后，按半小时；早上 6 点前不列 */
export function startOptions(w: Windowed & { window_start: string; window_end: string }, tz: string, now = Date.now()) {
  const from = new Date(w.window_start).getTime();
  const to = new Date(w.window_end).getTime();
  const first = wallClock(w.window_start, tz).date;
  const last = wallClock(lastMinute(w.window_end), tz).date;
  const result: { date: string; starts: Date[] }[] = [];
  for (let i = 0, date = first; i < 8; i++) {
    const starts: Date[] = [];
    for (let m = 360; m + 120 <= 1440; m += 30) {
      if (w.daypart && (m < PARTS[w.daypart][0] || m + 120 > PARTS[w.daypart][1])) continue;
      const start = zoned(date, m, tz);
      const time = start.getTime();
      if (time >= from && time + TWO_HOURS <= to && time >= now + 30 * 60000) starts.push(start);
    }
    if (starts.length) result.push({ date, starts });
    if (date === last) break;
    const [y, mo, d] = date.split('-').map(Number);
    date = new Date(Date.UTC(y, mo - 1, d + 1)).toISOString().slice(0, 10);
  }
  return result;
}
