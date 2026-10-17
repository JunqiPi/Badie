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
export type Player = { id: string; nickname: string; rating: number; team: 1 | 2; me: boolean; checked_in?: boolean; reviewed?: boolean };
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
  review_until: string;
  players: Player[];
}

export interface PlayRecord {
  wins: number;
  losses: number;
  games_played: number;
  no_shows: number;
  late_cancels: number;
}

// 社交

export interface PlayerCard {
  id: string;
  nickname: string;
  rating: number;
  assessed: boolean;
  games_band: string;
  new_player: boolean;
  reliable: boolean;
  tags: string[];
  relationship: 'self' | 'friend' | 'requested' | 'incoming' | 'blocked' | 'none';
  games_together: number;
  last_game: { starts_at: string; venue: string; tz: string | null } | null;
  mutual_friends: number;
}

export type ThreadKind = 'game' | 'dm';

export interface ThreadSummary {
  kind: ThreadKind;
  id: string;
  starts_at: string | null;
  venue: string | null;
  tz: string | null;
  nickname: string | null;
  access: 'open' | 'closed';
  last: { body: string; created_at: string; mine: boolean } | null;
  unread: number;
}

export interface Thread {
  access: 'open' | 'closed';
  friend: boolean;
  game: { starts_at: string; ends_at: string; venue: string; tz: string | null } | null;
  members: { id: string; nickname: string; me: boolean }[];
  messages: { id: number; body: string; created_at: string; sender: string; mine: boolean }[];
}

export type Friend = { id: string; nickname: string; rating: number; created_at?: string };
export type InboxCounts = { messages: number; updates: number; requests: number };

export interface Update {
  id: number;
  kind: string;
  title: string;
  body: string;
  link: string | null;
  created_at: string;
  read_at: string | null;
}

/** 调用数据库函数；页面可见时定时（默认 30 秒）、切回页面时自动刷新（别人确认了、约成了能及时看到） */
export function useLive<T>(fn: string, { args, every = 30_000 }: { args?: Record<string, unknown>; every?: number } = {}) {
  const [data, setData] = useState<T>();
  const [failed, setFailed] = useState(false);
  const key = JSON.stringify(args ?? {});
  const refresh = useCallback(async () => {
    const { data, error } = await supabase!.rpc(fn, JSON.parse(key));
    setFailed(Boolean(error));
    if (!error) setData(data as T);
  }, [fn, key]);
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
  cannot_review: 'Reviews are open for 48 hours after the game.',
  already_reviewed: 'You’ve already reviewed this player.',
  chat_closed: 'This chat is closed.',
  invalid_message: 'Type a message first (up to 1,000 characters).',
  too_many_messages: 'You’re sending messages too fast. Wait a minute.',
  not_allowed: 'You can only do this with players you’ve been matched with.',
  blocked: 'Unblock this player first.',
  no_request: 'This friend request is no longer open.',
};
export const problem = (error: { message: string }) => problems[error.message] ?? 'Something went wrong. Try again.';
