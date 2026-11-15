import { useEffect, useState } from 'react';
import { useArea } from './area';
import { Deck } from './DayCards';
import type { Profile } from './supabase';
import { nextDays } from './time';
import { ensureUsualCourt } from './usualCourt';

/** 发现（登录后的第一个 tab，iOS 的 DiscoverView）：左上角附近范围，右上角球馆和筛选，一排附近的人的圆头像，下面是一叠卡片。
 *  筛选里选的哪天记在地址里（/?day=2026-11-14）；旧地址 /day/…/ 和 /nearby/ 跳到这里 */
export function Discover({ profile, onProfile }: { profile: Profile; onProfile: (p: Profile) => void }) {
  const days = nextDays(30);
  const [day, setDay] = useState(() => {
    const asked = new URLSearchParams(location.search).get('day');
    return asked && days.includes(asked) ? asked : undefined;
  });
  // 以前注册、一家球馆都没收藏的人：拿到真实定位（不是搜的城市）时补上最近的一家，附近的人才看得到你
  const area = useArea();
  useEffect(() => {
    if (area && !area.label) void ensureUsualCourt(profile.id, area);
  }, [profile.id, area?.lat, area?.lon, area?.label]);
  function pick(next?: string) {
    setDay(next);
    history.replaceState(null, '', next ? `/?day=${next}` : '/');
  }
  return <Deck date={day} days={days} onDate={pick} profile={profile} onProfile={onProfile} />;
}
