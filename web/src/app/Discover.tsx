import { useEffect, useState } from 'react';
import { useArea, useNearbyKm } from './area';
import { Deck } from './DayCards';
import { currentLocale, t } from './i18n';
import { Icon } from './icons';
import { InviteStories } from './Invites';
import { IconButton, Story } from './kit';
import { Sheet } from './Nearby';
import { supabase, useLive, type Friend, type MyChallenges, type Profile, type Ticket } from './supabase';
import { capitalize, dateChip, nextDays } from './time';

/** 发现（登录后的第一个 tab，iOS 的 DiscoverView）：左上角“附近 · 什么时候 / 在哪 ▾”，一排圆头像（约球、等我回的人），下面是一叠卡片。
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
    <Deck date={day} profile={profile} onProfile={onProfile} place={(people) => <When days={days} day={day} people={people} onPick={pick} />}>
      <Stories />
    </Deck>
  );
}

/** 左上角：小字“附近 · 任何时间”，大字是在哪一带。点开选什么时候：任何时间（附近的人），或者接下来的某一天，后面是那天附近有几个人在找。
 *  一周以内写今天、明天、星期几；再往后只列有人的天，写几月几号 */
function When({ days, day, people, onPick }: { days: string[]; day?: string; people?: number; onPick: (day?: string) => void }) {
  const area = useArea();
  const km = useNearbyKm();
  const [open, setOpen] = useState(false);
  const [counts, setCounts] = useState<Record<string, number>>();
  useEffect(() => {
    if (!area) return;
    let stale = false;
    supabase!
      .rpc('pool_by_day', { p_lat: area.lat, p_lon: area.lon, p_radius_km: km, p_tz: Intl.DateTimeFormat().resolvedOptions().timeZone })
      .then(({ data }) => !stale && setCounts((data ?? {}) as Record<string, number>));
    return () => {
      stale = true;
    };
  }, [area?.lat, area?.lon, km]);

  const label = (d: string, i: number) =>
    i === 1 ? capitalize(new Intl.RelativeTimeFormat(currentLocale(), { numeric: 'auto' }).format(1, 'day'))
    : i < 7 ? dateChip(d, i).label
    : new Intl.DateTimeFormat(currentLocale(), { month: 'short', day: 'numeric', timeZone: 'UTC' }).format(new Date(`${d}T12:00:00Z`));
  const choose = (next?: string) => {
    setOpen(false);
    if (next !== day) onPick(next);
  };
  const row = (on: boolean) =>
    `press flex min-h-12 items-center gap-3 rounded-[14px] border-2 border-stroke px-4 text-left text-headline ${on ? 'bg-lime text-on-accent' : 'bg-surface'}`;

  return (
    <>
      <button type="button" aria-haspopup="dialog" onClick={() => setOpen(true)} className="press grid min-w-0 flex-1 justify-items-start text-left">
        <span className="max-w-full truncate text-caption font-bold text-ink-secondary">
          {t('Nearby')} · {day ? label(day, days.indexOf(day)) : t('Any time')}
        </span>
        <span className="flex max-w-full items-center gap-1 text-title3">
          <span className="truncate">{area?.label || t('Nearby')}</span>
          <Icon name="chevronDown" className="size-4 shrink-0" />
        </span>
      </button>
      <Sheet open={open} onClose={() => setOpen(false)} labelledBy="when-title">
        <div className="flex items-center gap-3">
          <h2 id="when-title" className="flex-1 text-title3">{t('When')}</h2>
          <IconButton icon="x" label={t('Close')} onClick={() => setOpen(false)} />
        </div>
        <div className="grid gap-2">
          <button type="button" aria-pressed={!day} onClick={() => choose(undefined)} className={row(!day)}>
            <span className="flex-1">{t('Any time')}</span>
            {Boolean(people) && <span className="text-footnote font-bold tabular-nums">{people}</span>}
          </button>
          {days.map((d, i) => {
            const n = counts?.[d] ?? 0;
            if (i >= 7 && !n && d !== day) return null;
            const full = dateChip(d, i).full;
            return (
              <button key={d} type="button" aria-pressed={day === d} onClick={() => choose(d)} className={row(day === d)}
                      aria-label={counts ? full + t(', {n} available', { n }) : full}>
                <span className="flex-1">{label(d, i)}</span>
                {n > 0 && <span aria-hidden="true" className="text-footnote font-bold tabular-nums">{n}</span>}
              </button>
            );
          })}
        </div>
      </Sheet>
    </>
  );
}

/** 一排圆头像（原来的待办小标签）：第一个是约球，后面是等我回的人：约我的、想加我的、挑战我的、等我确认的。
 *  点一个打开原来小标签打开的地方，只看这一件事。没有人的通知不放这里，铃铛里有 */
function Stories() {
  const { data: friends } = useLive<{ requests: Friend[] }>('my_friends', { every: 60_000 });
  const { data: challenges } = useLive<MyChallenges>('my_challenges', { every: 60_000 });
  const { data: requests } = useLive<Ticket[]>('my_matchmaking');
  const offers = requests?.filter((r) => r.offer?.my_response === 'pending') ?? [];
  return (
    <div className="rail gap-3! py-0.5!">
      <Story icon="plus" ring="lime" title={t('Play')} label={t('Send a match request')} to="/play/" />
      <InviteStories />
      {friends?.requests.map((f) => (
        <Story key={f.id} person={f} ring="lavender" icon="userPlus" title={f.nickname}
               label={t('{name} wants to be friends.', { name: f.nickname })} to={`/players/${f.id}/`} />
      ))}
      {challenges?.incoming.map((c) => (
        <Story key={c.id} person={c.player} ring="peach" icon="challenge" title={c.player.nickname}
               label={`${t('Challenges')}: ${c.player.nickname}`} to="/challenges/" />
      ))}
      {offers.map((r) => {
        const other = r.offer!.players.find((p) => !p.me);
        return (
          <Story key={r.id} person={other} ring="sky" icon="bolt" title={t('To confirm')}
                 label={other ? `${t('To confirm')}: ${other.nickname}` : t('To confirm')} to="/play/" />
        );
      })}
    </div>
  );
}
