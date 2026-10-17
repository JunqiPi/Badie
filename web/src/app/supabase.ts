import { createClient } from '@supabase/supabase-js';
import { useCallback, useEffect, useState } from 'react';

const url = import.meta.env.PUBLIC_SUPABASE_URL as string | undefined;
// 只用 publishable key（sb_publishable_…）；secret key 绝不进前端
const key = import.meta.env.PUBLIC_SUPABASE_PUBLISHABLE_KEY as string | undefined;

export const supabase = url && key ? createClient(url, key) : undefined;

export interface Profile {
  id: string;
  nickname: string;
  country_code: string | null;
  /** 3.67 = 4−；没做问卷是 3 */
  rating: number;
  assessed_at: string | null;
}

export interface Venue {
  id: string;
  name: string;
  aliases: string[];
  street: string;
  unit: string | null;
  city: string;
  region: string;
  postal_code: string;
  country_code: string;
  time_zone_id: string | null;
  court_count: number | null;
  pricing: { perPerson?: number; perCourtHour?: number } | null;
  phone: string | null;
  website: string | null;
  status: 'verified' | 'confirmed' | 'unconfirmed';
  source: string;
  attribution: string | null;
  location_approximate: boolean;
  kind: 'dedicated' | 'multi_sport' | 'rec_center' | 'school' | 'community_hall' | null;
  play_times: string | null;
  lat: number;
  lon: number;
}

export interface NearbyVenue {
  venue: Venue;
  distance_m: number;
}

// 约球（数据都来自数据库函数，只含本人能看的内容）

export type Mode = 'singles' | 'doubles';
export type Player = { nickname: string; rating: number; team: 1 | 2; me: boolean; checked_in?: boolean };
type Place = { id: string; name: string; city: string; street?: string; tz?: string | null };

export interface Ticket {
  id: string;
  mode: Mode;
  starts_at: string;
  ends_at: string;
  status: 'searching' | 'offered' | 'matched' | 'paused' | 'expired' | 'cancelled';
  skill_tolerance: 1 | 2 | 8;
  auto_accept: boolean;
  game_id: string | null;
  venues: Place[];
  offer: null | {
    id: string;
    starts_at: string;
    ends_at: string;
    respond_by: string;
    my_response: 'pending' | 'accepted';
    venue: Place;
    accepted: number;
    players: Player[];
  };
}

export type Outcome = 'team1' | 'team2' | 'friendly';

export interface Game {
  id: string;
  mode: Mode;
  starts_at: string;
  ends_at: string;
  status: 'scheduled' | 'cancelled';
  venue: Place & { lat: number; lon: number; pricing: Venue['pricing']; country: string };
  my_team: 1 | 2;
  checked_in: boolean;
  my_report: { outcome: Outcome | null } | null;
  result: { status: 'awaiting' | 'verified' | 'disputed' | 'unsure' | 'expired'; outcome: Outcome | null };
  players: Player[];
}

export interface PlayRecord {
  wins: number;
  losses: number;
  games_played: number;
  late_cancels: number;
}

/** 调用数据库函数；页面可见时每 30 秒、切回页面时自动刷新（别人确认了、约成了能及时看到） */
export function useLive<T>(fn: string, every = 30_000) {
  const [data, setData] = useState<T>();
  const [failed, setFailed] = useState(false);
  const refresh = useCallback(async () => {
    const { data, error } = await supabase!.rpc(fn);
    setFailed(Boolean(error));
    if (!error) setData(data as T);
  }, [fn]);
  useEffect(() => {
    refresh();
    const visible = () => document.visibilityState === 'visible' && refresh();
    const timer = setInterval(visible, every);
    document.addEventListener('visibilitychange', visible);
    return () => {
      clearInterval(timer);
      document.removeEventListener('visibilitychange', visible);
    };
  }, [refresh, every]);
  return { data, failed, refresh };
}

/** 数据库函数报的错 → 给人看的话 */
const problems: Record<string, string> = {
  too_soon: 'Pick a start at least 2½ hours from now.',
  too_far: 'You can plan up to two weeks ahead.',
  invalid_slot: 'Pick a time window between 1 and 8 hours.',
  invalid_venues: 'Pick 1 to 3 courts.',
  too_many_requests: 'You have 5 open requests already. Cancel one first.',
  overlapping: 'You already have a request or game at that time.',
  offer_closed: 'This match is no longer open.',
  not_active: 'This request has already ended.',
  not_paused: 'This request can’t be resumed anymore.',
  cannot_cancel: 'This game can’t be cancelled anymore.',
  cannot_check_in: 'Check-in opens 30 minutes before the start.',
  cannot_report: 'Results can be reported from the start until 7 days after the game.',
  result_locked: 'Both sides already agreed on this result.',
  retake_too_soon: 'You can retake the quiz 90 days after your last one.',
};
export const problem = (error: { message: string }) => problems[error.message] ?? 'Something went wrong. Try again.';
