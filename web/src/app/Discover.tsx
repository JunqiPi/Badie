import { useEffect, useState } from 'react';
import { useArea, useNearbyKm } from './area';
import { Deck } from './DayCards';
import { currentLocale, t } from './i18n';
import { InvitePill } from './Invites';
import { CountPill } from './kit';
import { supabase, useLive, type InboxCounts, type MyChallenges, type Profile, type Ticket } from './supabase';
import { capitalize, dateChip, nextDays } from './time';

/** 发现（登录后的第一个 tab，iOS 的 DiscoverView）：一排“附近的人 / 今天 N / 明天 N …”、待办小标签，下面是一叠卡片。
 *  选的哪天记在地址里（/?day=2026-11-14）；旧地址 /day/…/ 和 /nearby/ 跳到这里 */
export function Discover({ profile, onProfile }: { profile: Profile; onProfile: (p: Profile) => void }) {
  const days = nextDays(30);
  const [day, setDay] = useState(() => {
    const asked = new URLSearchParams(location.search).get('day');
    return asked && days.includes(asked) ? asked : undefined;
  });
  function pick(next?: string) {
    setDay(next);
    history.replaceState(null, '', next ? `/?day=${next}` : '/');
  }
  return (
    <Deck date={day} profile={profile} onProfile={onProfile}>
      <DayChips days={days} day={day} onPick={pick} />
      <Todos />
    </Deck>
  );
}

/** 附近的人（默认）+ 接下来几天，每天附近有几个人在找。一周以内写今天、明天、星期几；再往后只列有人的天，写几月几号 */
function DayChips({ days, day, onPick }: { days: string[]; day?: string; onPick: (day?: string) => void }) {
  const area = useArea();
  const km = useNearbyKm();
  const [counts, setCounts] = useState<Record<string, number>>();
  useEffect(() => {
    if (!area) return;
    supabase!
      .rpc('pool_by_day', { p_lat: area.lat, p_lon: area.lon, p_radius_km: km, p_tz: Intl.DateTimeFormat().resolvedOptions().timeZone })
      .then(({ data }) => setCounts((data ?? {}) as Record<string, number>));
  }, [area?.lat, area?.lon, km]);

  const label = (d: string, i: number) =>
    i === 1 ? capitalize(new Intl.RelativeTimeFormat(currentLocale(), { numeric: 'auto' }).format(1, 'day'))
    : i < 7 ? dateChip(d, i).label
    : new Intl.DateTimeFormat(currentLocale(), { month: 'short', day: 'numeric', timeZone: 'UTC' }).format(new Date(`${d}T12:00:00Z`));
  const chip = (on: boolean) =>
    `press flex min-h-10 items-center gap-1.5 rounded-full border-2 border-stroke px-3.5 text-footnote font-bold whitespace-nowrap ${on ? 'bg-[#17140f] text-lime' : 'bg-surface hover:bg-surface-muted'}`;

  return (
    <div role="group" aria-label={t('Date')} className="rail gap-2! py-0.5!">
      <button type="button" aria-pressed={!day} onClick={() => onPick(undefined)} className={chip(!day)}>{t('People nearby')}</button>
      {days.map((d, i) => {
        const n = counts?.[d] ?? 0;
        if (i >= 7 && !n && d !== day) return null;
        const full = dateChip(d, i).full;
        return (
          <button key={d} type="button" aria-pressed={day === d} onClick={() => onPick(d)} className={chip(day === d)}
                  aria-label={counts ? full + t(', {n} available', { n }) : full}>
            {label(d, i)}
            {n > 0 && <span aria-hidden="true" className="tabular-nums">{n}</span>}
          </button>
        );
      })}
    </div>
  );
}

/** 待办：一排带数字的小标签（邀请、挑战、好友申请、待确认）。没有待办时整行不占地方 */
function Todos() {
  const { data: counts } = useLive<InboxCounts>('inbox_counts', { every: 60_000 });
  const { data: challenges } = useLive<MyChallenges>('my_challenges', { every: 60_000 });
  const { data: requests } = useLive<Ticket[]>('my_matchmaking');
  const incoming = challenges?.incoming.length ?? 0;
  const friends = counts?.requests ?? 0;
  const confirm = requests?.filter((r) => r.offer?.my_response === 'pending').length ?? 0;
  return (
    // 邀请的半屏在 InvitePill 里，所以这一行一直在，只是没有小标签时不显示
    <div className="hidden flex-wrap gap-2 has-[>a]:flex has-[>button]:flex">
      <InvitePill />
      {incoming > 0 && <CountPill icon="challenge" title={t('Challenges')} count={incoming} to="/challenges/" />}
      {friends > 0 && <CountPill icon="userPlus" title={t('Friend requests')} count={friends} to="/messages/?tab=friends" />}
      {confirm > 0 && <CountPill icon="bolt" title={t('To confirm')} count={confirm} to="/play/" />}
    </div>
  );
}
