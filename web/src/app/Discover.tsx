import { useEffect, useState } from 'react';
import { useArea, useNearbyKm } from './area';
import { km as distance } from './Courts';
import { Deck, RangePicker, ShowChoice } from './DayCards';
import { GroupCard } from './Groups';
import { AreaPrompt } from './Home';
import { t } from './i18n';
import { Empty, IconButton } from './kit';
import { Icon } from './icons';
import { Sheet } from './Nearby';
import { supabase, type NearbyGroup, type Profile } from './supabase';
import { nextDays } from './time';
import { Skeleton } from './ui';
import { ensureUsualCourt } from './usualCourt';

type View = 'players' | 'groups';

// 筛选里选的“球友 / 球群”记在这个浏览器里，读不到就是球友
const viewKey = 'badie-discover-view';
function loadView(): View {
  try {
    return localStorage.getItem(viewKey) === 'groups' ? 'groups' : 'players';
  } catch {
    return 'players';
  }
}

/** 发现（登录后的第一个 tab，iOS 的 DiscoverView）：筛选里可以换成看附近的球群。
 *  球友：左上角附近范围，右上角球馆和筛选，一排附近的人的圆头像，下面是一叠卡片。
 *  筛选里选的哪天记在地址里（/?day=2026-11-14）；旧地址 /day/…/ 和 /nearby/ 跳到这里 */
export function Discover({ profile, onProfile }: { profile: Profile; onProfile: (p: Profile) => void }) {
  const days = nextDays(30);
  const [day, setDay] = useState(() => {
    const asked = new URLSearchParams(location.search).get('day');
    return asked && days.includes(asked) ? asked : undefined;
  });
  const [view, setViewState] = useState<View>(loadView);
  // 以前注册、一家球馆都没收藏的人：拿到真实定位（不是搜的城市）时补上最近的一家，附近的人才看得到你
  const area = useArea();
  useEffect(() => {
    if (area && !area.label) void ensureUsualCourt(profile.id, area);
  }, [profile.id, area?.lat, area?.lon, area?.label]);
  function pick(next?: string) {
    setDay(next);
    history.replaceState(null, '', next ? `/?day=${next}` : '/');
  }
  function setView(next: View) {
    setViewState(next);
    try {
      localStorage.setItem(viewKey, next);
    } catch {
      // 存不下就只在这次打开时生效
    }
  }
  if (view === 'groups') return <NearbyGroups onPlayers={() => setView('players')} />;
  return <Deck date={day} days={days} onDate={pick} profile={profile} onProfile={onProfile} onGroups={() => setView('groups')} />;
}

/** 附近的球群：附近范围和球友一样，任何一个球馆在范围内都算，近的在前 */
function NearbyGroups({ onPlayers }: { onPlayers: () => void }) {
  const area = useArea();
  const km = useNearbyKm();
  const [ranging, setRanging] = useState(false);
  const [filtering, setFiltering] = useState(false);
  const [groups, setGroups] = useState<NearbyGroup[]>();

  useEffect(() => {
    if (!area) return;
    let stale = false;
    setGroups(undefined);
    supabase!
      .rpc('groups_near', { lat: area.lat, lng: area.lon, radius_km: km })
      .then(({ data, error }) => !stale && setGroups(error ? [] : ((data ?? []) as NearbyGroup[])));
    return () => {
      stale = true;
    };
  }, [area?.lat, area?.lon, km]);

  return (
    <div className="mx-auto grid w-full max-w-md content-start gap-3">
      {/* 和看球友时同一个头：附近范围、球馆、筛选；选了球群的筛选条件像其他条件一样，点 ✕ 回到球友 */}
      <header className="flex items-center gap-2.5">
        <h1 className="sr-only">{t('Nearby groups')}</h1>
        <RangePicker open={ranging} onOpen={() => setRanging(true)} onClose={() => setRanging(false)} />
        <IconButton icon="building" label={t('Courts')} to="/courts/" />
        <IconButton icon="filter" label={t('Filters · {n}', { n: 1 })} badge={1} onClick={() => setFiltering(true)} />
      </header>
      <div className="rail gap-2! py-0!">
        <button type="button" onClick={onPlayers} aria-label={t('Remove {name}', { name: t('Groups') })}
                className="press flex min-h-9 items-center gap-1 rounded-full border-2 border-stroke bg-lime px-3 text-footnote font-bold text-on-accent">
          {t('Groups')} <Icon name="x" className="size-3" />
        </button>
      </div>
      <Sheet open={filtering} onClose={() => setFiltering(false)} labelledBy="groups-filter-title">
        <div className="flex items-center gap-3">
          <h2 id="groups-filter-title" className="flex-1 text-title3">{t('Filters')}</h2>
          <IconButton icon="x" label={t('Close')} onClick={() => setFiltering(false)} />
        </div>
        <ShowChoice value="groups" onPick={(v) => { setFiltering(false); if (v === 'players') onPlayers(); }} />
      </Sheet>
      {!area ? (
        <AreaPrompt />
      ) : !groups ? (
        <Skeleton className="h-40" />
      ) : groups.length === 0 ? (
        <Empty icon="group" tint="lavender" title={t('No groups within {distance} yet', { distance: distance(km * 1000) })}
               action={{ label: t('Start a group'), to: '/groups/new/' }}>
          {t('Start one at the court you play at.')}
        </Empty>
      ) : (
        <div className="grid gap-3">{groups.map((g) => <GroupCard key={g.id} group={g} distance={g.distance_m} />)}</div>
      )}
    </div>
  );
}
