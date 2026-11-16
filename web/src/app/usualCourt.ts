import type { Centre } from './pickers';
import { supabase } from './supabase';

// 常去球馆：附近的人靠它知道你大概在哪打球（我们不存位置）。注册时必填，默认是离你最近的一家；
// 以前注册、一家都没收藏的人，拿到位置时自动补上最近的一家（每个账号只补一次，自己删了不会再补）

export type UsualCourt = { id: string; name: string; city: string };

/** 离这个位置最近的一家球馆（50 公里内，不要位置不准的；有室内的就不选露天场地，服务器已经把室内的排在前面） */
export async function nearestCourt(centre: Centre): Promise<UsualCourt | undefined> {
  const { data } = await supabase!.rpc('venues_near', { lat: centre.lat, lng: centre.lon, radius_km: 50, max_results: 5 });
  const venue = ((data ?? []) as { venue: UsualCourt & { location_approximate?: boolean } }[]).find((r) => !r.venue.location_approximate)?.venue;
  return venue && { id: venue.id, name: venue.name, city: venue.city };
}

export async function addUsualCourt(userId: string, venueId: string) {
  return supabase!.from('favorite_venues').upsert({ user_id: userId, venue_id: venueId }, { ignoreDuplicates: true });
}

const doneKey = (userId: string) => `badie-usual-court-${userId}`;

/** 一家都没收藏：补上离 centre 最近的一家。centre 要是真实的定位（不是搜的城市） */
export async function ensureUsualCourt(userId: string, centre: Centre) {
  try {
    if (localStorage.getItem(doneKey(userId))) return;
  } catch {
    // 读不到本地存储也照样查服务器
  }
  const { count, error } = await supabase!.from('favorite_venues').select('venue_id', { count: 'exact', head: true }).eq('user_id', userId);
  if (error) return;
  const court = count ? undefined : await nearestCourt(centre);
  if (court) await addUsualCourt(userId, court.id);
  if (count || court) {
    try {
      localStorage.setItem(doneKey(userId), '1');
    } catch {
      // 存不下：下次再查一遍服务器，已经有球馆就什么都不做
    }
  }
}
