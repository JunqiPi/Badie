// 时间一律按球馆所在时区显示（人在外地也看到球馆当地的时间）

const format = (tz: string | null | undefined, options: Intl.DateTimeFormatOptions) =>
  new Intl.DateTimeFormat('en-US', { timeZone: tz ?? undefined, ...options });

/** “Sat, Oct 18” */
export const day = (iso: string, tz?: string | null) => format(tz, { weekday: 'short', month: 'short', day: 'numeric' }).format(new Date(iso));

/** “7:00 PM – 9:00 PM”（跨午夜也只显示时间，不带日期） */
export function hours(start: string, end: string, tz?: string | null) {
  const time = format(tz, { hour: 'numeric', minute: '2-digit' });
  return `${time.format(new Date(start))} – ${time.format(new Date(end))}`;
}

/** “Fri 9:00 PM” */
export const moment = (iso: string, tz?: string | null) => format(tz, { weekday: 'short', hour: 'numeric', minute: '2-digit' }).format(new Date(iso));

const relativeFormat = new Intl.RelativeTimeFormat('en', { numeric: 'auto' });
/** “in 3 hours” / “in 25 minutes” */
export function relative(iso: string) {
  const minutes = Math.round((new Date(iso).getTime() - Date.now()) / 60000);
  if (Math.abs(minutes) < 60) return relativeFormat.format(minutes, 'minute');
  if (Math.abs(minutes) < 48 * 60) return relativeFormat.format(Math.round(minutes / 60), 'hour');
  return relativeFormat.format(Math.round(minutes / 1440), 'day');
}

/** 某个时区里的“日期 + 第几分钟”对应的时刻（处理夏令时：先按 UTC 猜，再用该时区的偏移修正两次） */
export function zoned(date: string, minutes: number, tz: string) {
  const [y, m, d] = date.split('-').map(Number);
  const wall = Date.UTC(y, m - 1, d, 0, minutes);
  const offset = (t: number) => {
    const parts = Object.fromEntries(format(tz, { hourCycle: 'h23', year: 'numeric', month: 'numeric', day: 'numeric', hour: 'numeric', minute: 'numeric' })
      .formatToParts(t).map((p) => [p.type, Number(p.value)]));
    return Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute) - t;
  };
  let t = wall - offset(wall);
  t = wall - offset(t);
  return new Date(t);
}

/** 某个时区今天的日期 “2026-10-17” */
export const today = (tz: string, plusDays = 0) =>
  new Intl.DateTimeFormat('en-CA', { timeZone: tz }).format(Date.now() + plusDays * 86400000);

/** 从 0 点起的分钟数 → “7:30 PM” */
export const clock = (minutes: number) =>
  new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit', timeZone: 'UTC' }).format(Date.UTC(2000, 0, 1, 0, minutes));

export const weekdays = ['Sundays', 'Mondays', 'Tuesdays', 'Wednesdays', 'Thursdays', 'Fridays', 'Saturdays'];

/** 7:30 PM 这样的半点选项 */
export const halfHours = Array.from({ length: 36 }, (_, i) => 360 + i * 30).map((minutes) => ({
  minutes,
  label: clock(minutes),
}));
