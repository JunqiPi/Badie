// 示例球友：附近的真人太少时，补在真人后面，让刚来的人看懂发现页是干什么的。
// 卡片的照片位是写着“示例”的占位图，其他和正常卡片一样；不能约、不能加球友、没有资料页，点了会说明这是示例。
// 只在浏览器里生成，不进数据库；附近的真人到 ENOUGH 个就不再出现，不用清理。
import type { NearbyPlayer, NearbyVenue } from './supabase';

/** 附近有这么多真人就不放示例了 */
export const ENOUGH = 6;
/** 真人加示例一共凑到这么多张 */
const FILL = 20;

const names = ['Kevin', 'Mei', 'Sam', 'Bella', 'Danny', 'Ivy', 'Jason', 'Emily', 'Leo', 'Zoe', 'Ryan', 'Tina', 'Eric', 'Chloe', 'Alan', 'Nina', 'Marcus', 'Grace', 'Tony', 'Amy'];
const offsets = [-0.67, 0, 0.33, -0.33, 0.67, 1, -1];
const starts = [18, 19, 9, 14, 20];
const clock = (hour: number) => `${String(hour).padStart(2, '0')}:00`;

export const isSample = (id: string) => id.startsWith('sample-');

/** real：附近真人有几个；rating：我的等级（示例的等级在我上下一级以内）；venues：我附近真实的球馆（示例“常去”的就是这些） */
export function samplePlayers(real: number, rating: number, venues: NearbyVenue[]): NearbyPlayer[] {
  if (real >= ENOUGH) return [];
  return names.slice(0, FILL - real).map((nickname, i) => {
    const near = venues.length ? [venues[i % venues.length], venues[(i + 1) % venues.length]].filter((v, k, all) => all.indexOf(v) === k).slice(0, 1 + (i % 2)) : [];
    const start = starts[i % starts.length];
    return {
      user: {
        id: `sample-${i}`,
        nickname,
        tag: null,
        rating: Math.min(6.33, Math.max(1, rating + offsets[i % offsets.length])),
        gender: null,
        recent_no_shows: 0,
        avatar: null,
        card_color: null,
        card_photo: null,
        preferred_mode: i % 3 === 0 ? 'singles' : 'doubles',
        usual_times: [
          { weekday: 1 + ((i * 3) % 7), start: clock(start), end: clock(start + 2) },
          { weekday: 1 + ((i * 3 + 2) % 7), start: clock(starts[(i + 2) % starts.length]), end: clock(starts[(i + 2) % starts.length] + 2) },
        ],
      },
      venues: near.map((v) => ({ id: v.venue.id, name: v.venue.name, km: v.distance_m / 1000 })),
      shared_venues: 0,
      is_friend: false,
      friend_request: null,
    };
  });
}
