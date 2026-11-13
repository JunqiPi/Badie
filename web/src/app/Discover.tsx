import { useState } from 'react';
import { Deck } from './DayCards';
import type { Profile } from './supabase';
import { nextDays } from './time';

/** 发现（登录后的第一个 tab，iOS 的 DiscoverView）：左上角附近范围，右上角球馆和筛选，一排附近的人的圆头像，下面是一叠卡片。
 *  筛选里选的哪天记在地址里（/?day=2026-11-14）；旧地址 /day/…/ 和 /nearby/ 跳到这里 */
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
  return <Deck date={day} days={days} onDate={pick} profile={profile} onProfile={onProfile} />;
}
