import { createClient } from '@supabase/supabase-js';
import { useCallback, useEffect, useState } from 'react';
import { t, type Locale } from './i18n';

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
  show_on_boards: boolean;
  challenge_policy: 'everyone' | 'similar' | 'friends' | 'nobody';
  /** 通知和邮件用的语言 */
  locale: Locale;
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

/** 本月胜率：只算双方确认、分出胜负的比赛；满 5 场才对别人公开 */
export interface WinRate {
  games: number;
  wins: number;
  opponents: number;
  /** 对手平均比我方强多少级（负数 = 偏弱） */
  gap: number;
  public: boolean;
}

export interface PlayRecord extends WinRate {
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
  win_rate: WinRate | null;
  /** 'available'、'hidden'（不显示按钮）或不能挑战的原因 */
  challenge: string;
}

// 榜单与约战

export type BoardEntry = { id: string; nickname: string; rating: number; rank: number; points?: number; games: number; wins: number; me: boolean };

export interface WeeklyBoard {
  week_starts: string;
  entries: BoardEntry[];
  me: { rank: number; points: number } | null;
  progress: { games: number; opponents: number; points: number } | null;
  eligible: boolean;
}

export interface VenueBoard {
  venue: { id: string; name: string; city: string };
  bands: { band: number; entries: BoardEntry[] }[];
}

type ChallengeBase = {
  id: string;
  starts_at: string;
  ends_at: string;
  venue: { name: string; tz: string | null };
  player: { id: string; nickname: string; rating: number };
};

export interface MyChallenges {
  incoming: (ChallengeBase & { message: string; expires_at: string })[];
  outgoing: (ChallengeBase & { status: 'pending' | 'accepted' | 'not_happening'; game_id: string | null })[];
}

export type ThreadKind = 'game' | 'group' | 'dm';

export interface ThreadSummary {
  kind: ThreadKind;
  id: string;
  starts_at: string | null;
  venue: string | null;
  tz: string | null;
  /** 球群名或私信对象的昵称 */
  name: string | null;
  access: 'open' | 'closed';
  last: { body: string; created_at: string; mine: boolean } | null;
  unread: number;
}

export interface Thread {
  access: 'open' | 'closed';
  friend: boolean;
  game: { starts_at: string; ends_at: string; venue: string; tz: string | null } | null;
  group: { name: string; venue: string } | null;
  members: { id: string; nickname: string; me: boolean }[];
  messages: { id: number; body: string; created_at: string; sender: string; mine: boolean }[];
}

// 球群

export type Schedule = { weekday: number; start: number; end: number; capacity: number; fee: string | null };

export interface GroupSummary {
  id: string;
  name: string;
  summary: string;
  level_min: number;
  level_max: number;
  join_policy: 'open' | 'approval';
  venue: { id: string; name: string; city: string; tz: string | null };
  schedules: Schedule[];
  activity: { sessions: number; average: number };
  my_role: 'owner' | 'organizer' | 'member' | 'pending' | null;
}

export interface GroupSession {
  id: string;
  starts_at: string;
  ends_at: string;
  capacity: number;
  cancelled: boolean;
  confirmed: number;
  waitlist: number;
  /** 'confirmed' 或 'waitlisted:2' */
  my_status: string | null;
  players: { id: string; nickname: string; waitlisted: boolean }[] | null;
}

export interface GroupDetail extends GroupSummary {
  invite_code: string | null;
  sessions: GroupSession[];
  members: { id: string; nickname: string; rating: number; role: 'owner' | 'organizer' | 'member' }[] | null;
  pending: { id: string; nickname: string; rating: number }[] | null;
}

export interface MyGroups {
  groups: GroupSummary[];
  sessions: { id: string; group_id: string; group: string; venue: string; tz: string | null; starts_at: string; ends_at: string; waitlisted: boolean }[];
}

// 球局（房间）：有场地缺人时发起

export type RoomTag = 'beginner_friendly' | 'casual' | 'competitive' | 'women_friendly' | 'coaching';

export interface RoomSummary {
  id: string;
  mode: Mode;
  visibility: 'public' | 'private';
  status: 'open' | 'started' | 'closed';
  closed_reason: 'expired' | 'owner_closed' | 'start_time_passed' | null;
  game_id: string | null;
  /** 私密局可以先不定时间和球馆 */
  starts_at: string | null;
  ends_at: string | null;
  level_min: number;
  level_max: number;
  tags: RoomTag[];
  note: string;
  capacity: number;
  going: number;
  waitlist: number;
  owner: { id: string; nickname: string; rating: number };
  venue: { id: string; name: string; city: string; street: string; tz: string | null } | null;
  my_status: 'owner' | 'member' | 'waitlisted' | 'invited' | null;
}

export interface RoomDetail extends RoomSummary {
  /** 只有房间里的人和受邀的人看得到 */
  code: string | null;
  members: { id: string; nickname: string; rating: number; waitlisted: boolean; me: boolean }[] | null;
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
  invalid_schedule: 'Add 1 to 3 weekly sessions.',
  no_contact_info: 'Leave out phone numbers and links.',
  too_many_groups: 'You’ve reached the limit for groups.',
  group_not_found: 'Group not found.',
  level_out_of_range: 'Your level is outside the range they accept.',
  owner_cannot_leave: 'The owner can’t leave their own group.',
  not_organizer: 'Only organizers can do this.',
  not_member: 'Join the group first.',
  session_closed: 'This session is closed.',
  challenge_closed: 'This challenge is no longer open.',
  friends_only: 'They only accept challenges from friends.',
  already_pending: 'You’ve already challenged them. Wait for their answer.',
  cooldown: 'You can challenge them again a week after the last one.',
  too_many_outgoing: 'You can have 3 open challenges at a time.',
  daily_limit: 'You’ve used today’s challenges.',
  target_busy: 'They have too many open challenges. Try later.',
  admin_account: 'Admin accounts can’t be deleted here. Ask another admin to remove your access first.',
  already_started: 'Pick a start time that hasn’t passed.',
  missing_details: 'Public games need a court and a time.',
  invalid_level_range: 'The lowest level can’t be above the highest.',
  too_many_rooms: 'You have too many open games. Finish or cancel one first.',
  room_not_found: 'Game not found. Check the code.',
  room_closed: 'This game is no longer open.',
  room_full: 'This game is full.',
  not_room_owner: 'Only the host can do this.',
  not_enough_players: 'Start when every spot is filled.',
  too_many_invites: 'Invite up to 10 friends at a time.',
};
export const problem = (error: { message: string }) => t(problems[error.message] ?? 'Something went wrong. Try again.');
