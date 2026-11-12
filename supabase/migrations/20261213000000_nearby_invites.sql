-- 常在附近 v2：附近的人（大厅）+ 右滑发邀请局，替换 v1 的“想一起打”
-- - 大厅里出现：打开了“在附近的人里显示我”（show_as_regular）、定过级、收藏的球馆在我附近的人；球友也出现。
--   不出现自己、拉黑（任一方）、举报过的、30 天内我跳过的、30 天内拒绝过（任一方）的、和我之间有还没回复的邀请的
-- - 右滑 = 发一个只有两个人的单打邀请局：用现有的房间（私密、单打、房主 = 发邀请的人、room_invites 里是对方），
--   多了时间窗口：window_start / window_end（可以跨几天）+ 时段（上午 / 下午 / 晚上，可不填）+ 打多久（固定 2 小时）。
--   窗口正好 2 小时就是定好的时间（time_set = true）
-- - 收到的人：好（成局，群聊照旧）/ 换个时间（改窗口，轮到对方回复）/ 不了（30 天内两边在大厅里都不再出现）
-- - 成局后没定具体时间：任一方在窗口里挑开始时间（半点）；到“窗口结束 − 2 小时”还没定就自动取消，谁都不记临时取消
-- - 没定时间的球局：starts_at / ends_at 先填窗口，签到按窗口；不占时间（撞车在定时间时再查）
-- - 每天最多发 10 个（换个时间不算）
-- - 常用时间（usual_times）存到服务器，别人能看到；用两人的常用时间推荐窗口
-- 只能通过下面的函数读写

-- ---------------------------------------------------------------------------
-- 常用时间：[{weekday 1–7（1 = 周日 … 7 = 周六，和 iOS 的 Calendar 一样）, start "HH:MM", end "HH:MM"（可到 24:00）}]，最多 14 段
-- ---------------------------------------------------------------------------

create function public.valid_usual_times(p jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select jsonb_typeof(p) = 'array' and jsonb_array_length(p) <= 14
    and not exists (
      select 1 from jsonb_array_elements(p) e
      where not (jsonb_typeof(e) = 'object'
                 and (select count(*) from jsonb_object_keys(e)) = 3
                 and coalesce(e ->> 'weekday', '') in ('1', '2', '3', '4', '5', '6', '7')
                 and jsonb_typeof(e -> 'weekday') = 'number'
                 and coalesce(e ->> 'start', '') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
                 and coalesce(e ->> 'end', '') ~ '^(([01][0-9]|2[0-3]):[0-5][0-9]|24:00)$'
                 and e ->> 'start' < e ->> 'end'))
$$;

alter table public.profiles add column usual_times jsonb not null default '[]'
  constraint profiles_usual_times_check check (public.valid_usual_times(usual_times));
grant update (usual_times) on public.profiles to authenticated;

-- ---------------------------------------------------------------------------
-- 时间窗口：房间和球局上都有。普通的房间 / 球局 time_set = true，窗口是 null
-- ---------------------------------------------------------------------------

alter table public.rooms
  add column invitee_id uuid references auth.users (id) on delete cascade,
  add column awaiting_id uuid references auth.users (id) on delete set null,
  add column invite_rounds smallint not null default 0,
  add column window_start timestamptz,
  add column window_end timestamptz,
  add column duration_minutes smallint not null default 120 check (duration_minutes between 60 and 480),
  add column daypart text check (daypart in ('morning', 'afternoon', 'evening')),
  add column time_set boolean not null default true,
  add constraint rooms_window_check check (time_set or (window_start is not null and window_end is not null)),
  add constraint rooms_invite_check check (invitee_id is null or (mode = 'singles' and visibility = 'private' and invitee_id <> owner_id));
alter table public.rooms drop constraint rooms_closed_reason_check,
  add constraint rooms_closed_reason_check check (closed_reason in ('expired', 'owner_closed', 'start_time_passed', 'declined'));
create index rooms_invitee_idx on public.rooms (invitee_id) where invitee_id is not null;
create index rooms_owner_invites_idx on public.rooms (owner_id, created_at) where invitee_id is not null;

alter table public.games
  add column window_start timestamptz,
  add column window_end timestamptz,
  add column duration_minutes smallint not null default 120 check (duration_minutes between 60 and 480),
  add column daypart text check (daypart in ('morning', 'afternoon', 'evening')),
  add column time_set boolean not null default true,
  add constraint games_window_check check (time_set or (window_start is not null and window_end is not null));
create index games_unset_idx on public.games (window_end) where not time_set and status = 'scheduled';

-- ---------------------------------------------------------------------------
-- 小工具（客户端不能直接调用）
-- ---------------------------------------------------------------------------

-- 定过级（做过问卷或认证过）；没定级的不进大厅
create function public.has_level(p_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select p.assessed_at is not null or p.verified_rating is not null from public.profiles p where p.id = p_user), false)
$$;

-- 这个开始时间在球馆当地是不是落在时段里（上午 8–12、下午 14–18、晚上 18–22，整场都在里面）；没有时段都行
create function public.daypart_fits(p_start timestamptz, p_minutes int, p_daypart text, p_tz text)
returns boolean language sql stable set search_path = '' as $$
  select p_daypart is null or coalesce((
    select s >= h.f * 3600 and s + p_minutes * 60 <= h.t * 3600
    from (select extract(epoch from (p_start at time zone coalesce(p_tz, 'UTC'))::time) as s) l,
         (values ('morning', 8, 12), ('afternoon', 14, 18), ('evening', 18, 22)) h (n, f, t)
    where h.n = p_daypart), false)
$$;

-- 窗口里（不早于 p_after）第一个能开始的半点；没有就是 null
create function public.first_window_start(p_from timestamptz, p_to timestamptz, p_minutes int, p_daypart text, p_tz text,
                                          p_after timestamptz)
returns timestamptz language sql stable set search_path = '' as $$
  select s from generate_series(to_timestamp(ceil(extract(epoch from greatest(p_from, p_after)) / 1800) * 1800),
                                p_to - make_interval(mins => p_minutes), interval '30 minutes') s
  where public.daypart_fits(s, p_minutes, p_daypart, p_tz)
  order by s limit 1
$$;

-- 通知里的时间窗口：同一天“11月15日 周六 14:00–18:00”，跨天“… – …”
create function public.window_text(p_from timestamptz, p_to timestamptz, p_tz text, p_locale text)
returns text language sql stable set search_path = '' as $$
  select case when (p_from at time zone coalesce(p_tz, 'UTC'))::date = (p_to at time zone coalesce(p_tz, 'UTC'))::date
    then public.when_text(p_from, p_tz, p_locale) || '–'
         || to_char(p_to at time zone coalesce(p_tz, 'UTC'),
                    case when p_locale = 'id' then 'HH24.MI' when p_locale = 'hi' then 'FMHH12:MI am'
                         when p_locale in ('zh-Hans', 'zh-Hant', 'ja', 'ko', 'ms', 'th', 'vi') then 'HH24:MI'
                         else 'FMHH12:MI AM' end)
    else public.when_text(p_from, p_tz, p_locale) || ' – ' || public.when_text(p_to, p_tz, p_locale) end
$$;

-- 参数里的时间对象多了 {at, to, tz}：写成时间窗口
create or replace function public.render_text(p_locale text, p_text text, p_params jsonb default '{}')
returns text language sql stable security definer set search_path = '' as $$
  select coalesce(string_agg(case when jsonb_typeof(v) = 'object' and v ? 'to'
                                    then public.window_text((v ->> 'at')::timestamptz, (v ->> 'to')::timestamptz, v ->> 'tz', p_locale)
                                  when jsonb_typeof(v) = 'object' then public.when_text((v ->> 'at')::timestamptz, v ->> 'tz', p_locale)
                                  when v is not null then v #>> '{}'
                                  else part end, '' order by n), '')
  from regexp_matches(coalesce((select translated from public.notification_texts where locale = p_locale and english = p_text), p_text),
                      '\{\w+\}|[^{]+|\{', 'g') with ordinality as m(token, n),
       lateral (select m.token[1] as part) p,
       lateral (select case when p.part ~ '^\{\w+\}$' then p_params -> substr(p.part, 2, length(p.part) - 2) end as v) x
$$;

-- 通知参数 {when, court}：定了时间写开始时间，没定写窗口
create function public.window_slot(p_start timestamptz, p_end timestamptz, p_time_set boolean, p_venue text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select case when p_time_set then public.slot(p_start, p_venue)
    else (select jsonb_build_object('when', jsonb_build_object('at', p_start, 'to', p_end, 'tz', coalesce(v.time_zone_id, 'UTC')),
                                    'court', v.name)
          from public.venues v where v.id = p_venue) end
$$;

create function public.game_slot(p_game uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select public.window_slot(g.starts_at, g.ends_at, g.time_set, g.venue_id) from public.games g where g.id = p_game
$$;

-- 卡片上的人：多了常用时间
create or replace function public.nearby_user(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', p.id, 'nickname', p.nickname, 'tag', p.tag, 'rating', p.rating, 'gender', p.gender,
                            'recent_no_shows', public.recent_no_shows(p.id), 'avatar', p.avatar_path,
                            'card_color', p.card_color, 'card_photo', p.card_photo_path, 'preferred_mode', p.preferred_mode,
                            'usual_times', p.usual_times)
  from public.profiles p where p.id = p_user
$$;

-- 两人之间有还没回复完的邀请（谁发的都算）
create function public.invite_open_between(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.rooms r
                 where r.status = 'open' and r.invitee_id is not null
                   and ((r.owner_id = a and r.invitee_id = b) or (r.owner_id = b and r.invitee_id = a)))
$$;

-- 30 天内有一方说过“不了”（谁拒绝谁都算）
create function public.invite_cooldown(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.rooms r
                 where r.invitee_id is not null and r.closed_reason = 'declined' and r.last_activity_at > now() - interval '30 days'
                   and ((r.owner_id = a and r.invitee_id = b) or (r.owner_id = b and r.invitee_id = a)))
$$;

-- a 能不能约 b：b 在大厅里（开了显示、定过级），没有拉黑 / 举报，不在冷却期。球友也能约
create function public.invite_allowed(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select a is not null and b is not null and a <> b
    and exists (select 1 from public.profiles p where p.id = b and p.show_as_regular)
    and public.has_level(b)
    and not public.hidden_from(a, b) and not public.hidden_from(b, a)
    and not public.invite_cooldown(a, b)
$$;

-- 收到邀请的人、大厅里的人能互相看资料、加球友
create or replace function public.related(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select a = b or public.are_friends(a, b)
    or exists (select 1 from public.game_players x join public.game_players y on y.game_id = x.game_id
               where x.user_id = a and y.user_id = b)
    or exists (select 1 from public.match_seats x join public.match_seats y on y.offer_id = x.offer_id
               where x.user_id = a and y.user_id = b)
    or exists (select 1 from public.friend_requests where (from_id = a and to_id = b) or (from_id = b and to_id = a))
    or exists (select 1 from public.group_members x join public.group_members y on y.group_id = x.group_id
               where x.user_id = a and y.user_id = b and not x.pending and not y.pending)
    or exists (select 1 from public.profiles where id = b and discoverable)
    or exists (select 1 from public.profiles p join public.favorite_venues fb on fb.user_id = p.id
               join public.favorite_venues fa on fa.venue_id = fb.venue_id and fa.user_id = a
               where p.id = b and p.show_as_regular)
    or exists (select 1 from public.friend_link_opens where viewer = a and owner = b)
    -- 首页卡片：b 正在找人、a 能约 b，就能看 b 的资料（卡片上的照片和“看资料”）
    or exists (select 1 from public.match_tickets t
               where t.user_id = b and t.status = 'searching' and t.lock_at > now() and public.can_invite(a, t))
    -- 附近的人：b 在大厅里（开了显示、定过级、收藏了球馆）。大厅按位置给任何登录的人看，资料也一样
    or (exists (select 1 from public.profiles p where p.id = b and p.show_as_regular
                and exists (select 1 from public.favorite_venues f where f.user_id = b))
        and public.has_level(b))
    -- 一对一的邀请（发过、收到过）
    or exists (select 1 from public.rooms r
               where r.invitee_id is not null and ((r.owner_id = a and r.invitee_id = b) or (r.owner_id = b and r.invitee_id = a)))
$$;

drop function public.wish_to_play(uuid);
drop function public.pending_play_wishes();
drop function public.respond_play_wish(uuid, boolean);
drop function public.play_wish_allowed(uuid, uuid);
drop function public.play_wish_cooldown(uuid, uuid);
drop function public.befriend(uuid, uuid);
drop table public.play_wishes;
delete from public.notification_texts where english in (
  '{name} wants to play with you', 'Say yes and you’ll be friends and can chat.', '{name} said yes to playing',
  'You’re now friends. Send a message to pick a time.', 'You both want to play',
  'You and {name} are now friends. Send a message to pick a time.');

-- 附近的人：收藏的球馆在我附近的人；共同球馆多的在前，再按水平接近、离我近，最多 30 位。
-- 多了 is_friend、friend_request（'sent' 我申请了 / 'received' TA 申请了我 / null），卡片上的“加球友”按钮用
create or replace function public.nearby_players(p_lat double precision, p_lon double precision, p_radius_km double precision)
returns jsonb language sql stable security definer set search_path = '' as $$
  with here as (
    select extensions.st_makepoint(p_lon, p_lat)::extensions.geography as g,
           (least(greatest(p_radius_km, 1), 100) * 1000)::double precision as m),
  me as (
    select p.id, public.open_rating(p.rating, p.gender) as level from public.profiles p where p.id = auth.uid()),
  near as (
    select f.user_id, v.id, v.name, extensions.st_distance(v.location, h.g) as dist
    from here h
    join public.venues v on extensions.st_dwithin(v.location, h.g, h.m)
    join public.favorite_venues f on f.venue_id = v.id
    where f.user_id <> auth.uid()),
  picked as (
    select p.id,
           (select count(*) from public.favorite_venues a join public.favorite_venues b on b.venue_id = a.venue_id and b.user_id = p.id
            where a.user_id = me.id)::int as shared,
           abs(public.open_rating(p.rating, p.gender) - me.level) as gap,
           (select min(n.dist) from near n where n.user_id = p.id) as nearest
    from me
    join public.profiles p on p.id in (select n.user_id from near n)
    where p.show_as_regular and (p.assessed_at is not null or p.verified_rating is not null)
      and not public.hidden_from(me.id, p.id) and not public.hidden_from(p.id, me.id)
      and not public.invite_cooldown(me.id, p.id)
      and not public.invite_open_between(me.id, p.id)
      and not exists (select 1 from public.nearby_skips s
                      where s.user_id = me.id and s.skipped_id = p.id and s.created_at > now() - interval '30 days')
    order by shared desc, gap, nearest, p.id
    limit 30)
  select coalesce(jsonb_agg(jsonb_build_object(
           'user', public.nearby_user(x.id),
           -- TA 收藏的、在我附近的球馆，近的在前
           'venues', (select jsonb_agg(jsonb_build_object('id', n.id, 'name', n.name, 'km', round((n.dist / 1000)::numeric, 1))
                                       order by n.dist, n.id)
                      from near n where n.user_id = x.id),
           'shared_venues', x.shared,
           'is_friend', public.are_friends(auth.uid(), x.id),
           'friend_request', case
             when exists (select 1 from public.friend_requests r where r.from_id = auth.uid() and r.to_id = x.id) then 'sent'
             when exists (select 1 from public.friend_requests r where r.from_id = x.id and r.to_id = auth.uid() and r.ignored_at is null)
               then 'received' end)
         order by x.shared desc, x.gap, x.nearest, x.id), '[]'::jsonb)
  from picked x
$$;

-- ---------------------------------------------------------------------------
-- 房间和球局的 JSON 带上时间窗口
-- ---------------------------------------------------------------------------

-- 房间概要：带上时间窗口和一对一邀请的信息
create or replace function public.room_summary(p_room uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', r.id, 'mode', r.mode, 'visibility', r.visibility, 'status', r.status, 'closed_reason', r.closed_reason,
    'game_id', r.game_id, 'starts_at', r.starts_at, 'ends_at', r.ends_at, 'level_min', r.level_min, 'level_max', r.level_max,
    'tags', r.tags, 'note', r.note, 'gender', r.gender, 'mixed', r.mixed, 'capacity', public.room_capacity(r.mode),
    'last_activity_at', r.last_activity_at,
    'going', (select count(*) from public.room_members m where m.room_id = r.id and not m.waitlisted),
    'mixed_going', case when r.mixed then jsonb_build_object('male', public.room_going(r.id, 'male'), 'female', public.room_going(r.id, 'female')) end,
    'waitlist', (select count(*) from public.room_members m where m.room_id = r.id and m.waitlisted),
    'owner', (select jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', p.rating) from public.profiles p where p.id = r.owner_id),
    'venue', (select jsonb_build_object('id', v.id, 'name', v.name, 'city', v.city, 'street', v.street, 'tz', v.time_zone_id,
                                        'lat', v.lat, 'lon', v.lon, 'pricing', v.pricing, 'country', v.country_code)
              from public.venues v where v.id = r.venue_id),
    'my_status', public.room_status_of(r.id, auth.uid()),
    -- 时间窗口：time_set = false 时 starts_at / ends_at 就是窗口，在里面打 duration_minutes 分钟
    'time_set', r.time_set, 'window_start', r.window_start, 'window_end', r.window_end,
    'duration_minutes', r.duration_minutes, 'daypart', r.daypart,
    -- 附近的人的一对一邀请（普通房间是 null）：awaiting = 该谁回复
    'invite', case when r.invitee_id is not null then jsonb_build_object(
      'from', public.nearby_user(r.owner_id), 'to', public.nearby_user(r.invitee_id),
      'awaiting_id', r.awaiting_id, 'awaiting_me', r.awaiting_id = auth.uid(), 'rounds', r.invite_rounds,
      'answer_by', r.window_end - make_interval(mins => r.duration_minutes)) end)
  from public.rooms r where r.id = p_room
$$;


-- ---------------------------------------------------------------------------
-- 邀请
-- ---------------------------------------------------------------------------

-- 检查并整理邀请的球馆和时间窗口（客户端不能直接调用）：
-- 球馆合并过的换成保留的那家；窗口两端对齐半点、最多跨 7 天、30 天内；开头早于“现在 + 30 分钟”的往后挪；
-- 时段 'any' / null = 不限；窗口里至少要有一个能打满 2 小时的开始时间。窗口正好 2 小时 = 定好的时间
create function public.invite_window(p_venue text, p_window_start timestamptz, p_window_end timestamptz, p_daypart text,
                                     out venue text, out tz text, out window_start timestamptz, out window_end timestamptz,
                                     out daypart text, out exact boolean)
language plpgsql stable security definer set search_path = '' as $$
begin
  select coalesce(v.merged_into, v.id) into venue from public.venues v where v.id = p_venue and not v.hidden_pending_review;
  if venue is null then raise exception 'invalid_venues' using errcode = '22023'; end if;
  select coalesce(v.time_zone_id, 'UTC') into tz from public.venues v where v.id = venue;
  daypart := nullif(p_daypart, 'any');
  if p_window_start is null or p_window_end is null
     or extract(epoch from p_window_start)::bigint % 1800 <> 0 or extract(epoch from p_window_end)::bigint % 1800 <> 0
     or p_window_end - p_window_start > interval '7 days'
     or (daypart is not null and daypart not in ('morning', 'afternoon', 'evening')) then
    raise exception 'invalid_window' using errcode = '22023';
  end if;
  if p_window_start > now() + interval '30 days' then raise exception 'too_far' using errcode = '22023'; end if;
  window_start := greatest(p_window_start, to_timestamp(ceil(extract(epoch from now() + interval '30 minutes') / 1800) * 1800));
  window_end := p_window_end;
  if public.first_window_start(window_start, window_end, 120, daypart, tz, window_start) is null then
    raise exception 'invalid_window' using errcode = '22023';
  end if;
  exact := window_end - window_start = interval '2 hours';
  if exact then daypart := null; end if;
end
$$;

-- 右滑发邀请：只有两个人的单打局（私密房间，对方在 room_invites 里），带时间窗口。每天最多 10 个
-- 返回 {room_id, remaining}
create function public.invite_player(p_user uuid, p_venue text, p_window_start timestamptz, p_window_end timestamptz,
                                     p_daypart text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  w record;
  sent int;
  new_room uuid;
begin
  if me is null or not exists (select 1 from public.profiles where id = me) then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if p_user is null then raise exception 'not_available' using errcode = 'P0002'; end if;
  -- 同一个人的邀请排队算个数；两个人同时互相右滑也只会有一个邀请
  perform pg_advisory_xact_lock(hashtextextended('nearby_invite:' || me::text, 0));
  perform pg_advisory_xact_lock(hashtextextended('nearby_pair:' || least(me, p_user)::text || ':' || greatest(me, p_user)::text, 0));
  if not (select p.show_as_regular from public.profiles p where p.id = me) then
    raise exception 'not_visible' using errcode = '22023';
  end if;
  if not public.invite_allowed(me, p_user) then raise exception 'not_available' using errcode = 'P0002'; end if;
  if public.invite_open_between(me, p_user) then raise exception 'already_invited' using errcode = '23505'; end if;
  sent := (select count(*) from public.rooms where owner_id = me and invitee_id is not null and created_at > now() - interval '1 day')::int;
  if sent >= 10 then raise exception 'invite_limit' using errcode = '54000'; end if;

  select * into w from public.invite_window(p_venue, p_window_start, p_window_end, p_daypart);
  if w.exact and public.has_game_between(me, w.window_start, w.window_end) then
    raise exception 'overlapping' using errcode = '23P01';
  end if;

  insert into public.rooms (code, owner_id, mode, visibility, venue_id, starts_at, ends_at, level_min, level_max,
                            invitee_id, awaiting_id, window_start, window_end, duration_minutes, daypart, time_set)
    values (public.new_invite_code(), me, 'singles', 'private', w.venue, w.window_start, w.window_end, 1, 9,
            p_user, p_user, w.window_start, w.window_end, 120, w.daypart, w.exact)
    returning id into new_room;
  insert into public.room_members (room_id, user_id) values (new_room, me);
  insert into public.room_invites (room_id, user_id, invited_by) values (new_room, p_user, me);

  perform public.notify(p_user, 'room', '{name} invited you to play', '{when} · {court}. Open Badie to join.',
    '/app/rooms/' || new_room || '/',
    jsonb_build_object('name', (select nickname from public.profiles where id = me))
      || public.window_slot(w.window_start, w.window_end, w.exact, w.venue));
  return jsonb_build_object('room_id', new_room, 'remaining', greatest(9 - sent, 0));
end
$$;

-- 不了（客户端不能直接调用）：关闭邀请，30 天内两边在大厅里都不再出现；轻轻告诉对方
create function public.decline_invite(p_room uuid, p_user uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  r public.rooms;
begin
  update public.rooms set status = 'closed', closed_reason = 'declined', awaiting_id = null, last_activity_at = now()
    where id = p_room and status = 'open' and invitee_id is not null and p_user in (owner_id, invitee_id)
    returning * into r;
  if r.id is null then return; end if;
  delete from public.room_invites where room_id = p_room;
  perform public.notify(case when p_user = r.owner_id then r.invitee_id else r.owner_id end, 'invite_declined',
    '{name} can’t make it this time', '{when} · {court}', '/app/play/',
    jsonb_build_object('name', (select nickname from public.profiles where id = p_user))
      || public.window_slot(r.starts_at, r.ends_at, r.time_set, r.venue_id));
end
$$;

-- 回复邀请（轮到我回复的时候）：好 = 成局（群聊照旧）；不了 = 关闭。返回 {status: 'accepted' | 'declined', game_id}
create function public.respond_invite(p_room uuid, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  r public.rooms;
  other uuid;
  new_game uuid;
begin
  if me is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  select * into r from public.rooms where id = p_room for update;
  if r.id is null or r.invitee_id is null or r.status <> 'open' or me not in (r.owner_id, r.invitee_id) or p_accept is null
     or public.hidden_from(r.owner_id, r.invitee_id) or public.hidden_from(r.invitee_id, r.owner_id) then
    raise exception 'not_available' using errcode = 'P0002';
  end if;
  if r.awaiting_id is distinct from me then raise exception 'not_your_turn' using errcode = '22023'; end if;
  other := case when me = r.owner_id then r.invitee_id else r.owner_id end;

  if not p_accept then
    perform public.decline_invite(p_room, me);
    return jsonb_build_object('status', 'declined', 'game_id', null);
  end if;

  if r.window_end - make_interval(mins => r.duration_minutes) <= now() then
    raise exception 'invite_expired' using errcode = 'P0002';
  end if;
  if r.time_set and (public.has_game_between(r.owner_id, r.starts_at, r.ends_at) or public.has_game_between(r.invitee_id, r.starts_at, r.ends_at)) then
    raise exception 'overlapping' using errcode = '23P01';
  end if;

  insert into public.room_members (room_id, user_id) values (p_room, r.invitee_id) on conflict do nothing;
  delete from public.room_invites where room_id = p_room;
  insert into public.games (mode, starts_at, ends_at, venue_id, window_start, window_end, duration_minutes, daypart, time_set)
    values ('singles', r.starts_at, r.ends_at, r.venue_id, r.window_start, r.window_end, r.duration_minutes, r.daypart, r.time_set)
    returning id into new_game;
  -- 和开局一样：水平高的是 1 队
  insert into public.game_players (game_id, user_id, team, rating)
    select new_game, x.id, row_number() over (order by public.open_rating(x.rating, x.gender) desc, x.id = r.owner_id desc)::smallint, x.rating
    from public.profiles x where x.id in (r.owner_id, r.invitee_id);
  update public.rooms set status = 'started', game_id = new_game, awaiting_id = null, last_activity_at = now() where id = p_room;

  perform public.notify(other, 'matched', 'Game confirmed',
    case when r.time_set then '{when} · {court}. Everyone confirmed.' else '{when} · {court}. Set the exact time when you’re ready.' end,
    '/app/games/' || new_game || '/', public.window_slot(r.starts_at, r.ends_at, r.time_set, r.venue_id));
  return jsonb_build_object('status', 'accepted', 'game_id', new_game);
end
$$;

-- 换个时间（轮到我回复的时候）：改窗口（球馆也能换），轮到对方回复。不占每天 10 个
create function public.counter_invite(p_room uuid, p_venue text, p_window_start timestamptz, p_window_end timestamptz,
                                      p_daypart text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  r public.rooms;
  w record;
  other uuid;
begin
  if me is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  select * into r from public.rooms where id = p_room for update;
  if r.id is null or r.invitee_id is null or r.status <> 'open' or me not in (r.owner_id, r.invitee_id)
     or public.hidden_from(r.owner_id, r.invitee_id) or public.hidden_from(r.invitee_id, r.owner_id) then
    raise exception 'not_available' using errcode = 'P0002';
  end if;
  if r.awaiting_id is distinct from me then raise exception 'not_your_turn' using errcode = '22023'; end if;
  other := case when me = r.owner_id then r.invitee_id else r.owner_id end;

  select * into w from public.invite_window(coalesce(p_venue, r.venue_id), p_window_start, p_window_end, p_daypart);
  if w.exact and public.has_game_between(me, w.window_start, w.window_end) then
    raise exception 'overlapping' using errcode = '23P01';
  end if;
  update public.rooms set venue_id = w.venue, starts_at = w.window_start, ends_at = w.window_end,
                          window_start = w.window_start, window_end = w.window_end, daypart = w.daypart, time_set = w.exact,
                          awaiting_id = other, invite_rounds = invite_rounds + 1, last_activity_at = now()
    where id = p_room;
  perform public.notify(other, 'invite_counter', '{name} suggested another time', '{when} · {court}. Open Badie to answer.',
    '/app/rooms/' || p_room || '/',
    jsonb_build_object('name', (select nickname from public.profiles where id = me))
      || public.window_slot(w.window_start, w.window_end, w.exact, w.venue));
end
$$;

-- 发出去、收到的还没结束的一对一邀请；轮到我回复的在前
create function public.nearby_invites()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(public.room_summary(r.id) order by r.awaiting_id = auth.uid() desc, r.last_activity_at desc), '[]')
  from public.rooms r
  where auth.uid() is not null and r.status = 'open' and r.invitee_id is not null
    and auth.uid() in (r.owner_id, r.invitee_id)
    and not public.hidden_from(r.owner_id, r.invitee_id) and not public.hidden_from(r.invitee_id, r.owner_id)
$$;

-- ---------------------------------------------------------------------------
-- 没定时间的球局
-- ---------------------------------------------------------------------------

-- 我成局（或定了时间）以后：和这场时间重叠、我发出去还在等回复的单打邀请自动撤回（这场本身的那份除外）
create function public.withdraw_invites_for(p_user uuid, p_game uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  g public.games;
  o record;
  seat record;
begin
  select * into g from public.games where id = p_game;
  -- 还没定具体时间：定时间的时候再撤（set_game_time）
  if g.id is null or not g.time_set then return; end if;
  for o in select mo.id, mo.starts_at, mo.venue_id from public.match_offers mo
           where mo.status = 'open' and mo.invited_by = p_user
             and mo.starts_at < g.ends_at and g.starts_at < mo.ends_at
             and not exists (select 1 from public.match_seats s
                             join public.game_players gp on gp.user_id = s.user_id and gp.game_id = p_game
                             where s.offer_id = mo.id and s.user_id <> p_user)
  loop
    update public.match_offers set status = 'failed' where id = o.id;
    -- 两边的请求都回到“在找人”（只为邀请建的那份会被 invite_only_tickets 触发器自动取消）
    update public.match_tickets m set status = 'searching', offer_id = null
      from public.match_seats s where s.offer_id = o.id and s.ticket_id = m.id and m.status = 'offered';
    for seat in select s.user_id from public.match_seats s where s.offer_id = o.id and s.user_id <> p_user loop
      perform public.notify(seat.user_id, 'requeued', 'Invite withdrawn', '{name} already has a game at {when}. Your request is still on.',
        '/app/play/', public.slot(o.starts_at, o.venue_id) || jsonb_build_object('name', (select nickname from public.profiles where id = p_user)));
    end loop;
  end loop;
end
$$;

create or replace function public.withdraw_overlapping_invites()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform public.withdraw_invites_for(new.user_id, new.game_id);
  return null;
end
$$;

-- 定时间：两个人谁都能定；在窗口（和时段）里挑一个半点开始，打 duration_minutes 分钟。定了就和普通球局一样
create function public.set_game_time(p_game uuid, p_starts_at timestamptz)
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  g public.games;
  tz text;
  new_end timestamptz;
  player record;
begin
  if me is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  select * into g from public.games where id = p_game for update;
  if g.id is null or g.status <> 'scheduled'
     or not exists (select 1 from public.game_players where game_id = p_game and user_id = me and cancelled_at is null) then
    raise exception 'not_available' using errcode = 'P0002';
  end if;
  if g.time_set then raise exception 'time_already_set' using errcode = '22023'; end if;
  select coalesce(time_zone_id, 'UTC') into tz from public.venues where id = g.venue_id;
  new_end := p_starts_at + make_interval(mins => g.duration_minutes);
  if p_starts_at is null or extract(epoch from p_starts_at)::bigint % 1800 <> 0
     or p_starts_at < g.window_start or new_end > g.window_end or p_starts_at < now() + interval '30 minutes'
     or not public.daypart_fits(p_starts_at, g.duration_minutes, g.daypart, tz) then
    raise exception 'invalid_slot' using errcode = '22023';
  end if;
  if exists (select 1 from public.game_players gp where gp.game_id = p_game and public.has_game_between(gp.user_id, p_starts_at, new_end)) then
    raise exception 'overlapping' using errcode = '23P01';
  end if;

  update public.games set starts_at = p_starts_at, ends_at = new_end, time_set = true where id = p_game;
  update public.rooms set starts_at = p_starts_at, ends_at = new_end, time_set = true where game_id = p_game;
  for player in select user_id from public.game_players where game_id = p_game loop
    perform public.withdraw_invites_for(player.user_id, p_game);
    continue when player.user_id = me;
    perform public.notify(player.user_id, 'game_time_set', '{name} set the time', '{when} · {court}', '/app/games/' || p_game || '/',
      jsonb_build_object('name', (select nickname from public.profiles where id = me)) || public.slot(p_starts_at, g.venue_id));
  end loop;
end
$$;

-- 到“窗口结束 − 打多久”还没定时间：自动取消，谁都不记临时取消，两个人都收到通知
create function public.expire_unset_games()
returns void language plpgsql security definer set search_path = '' as $$
declare
  g record;
  player record;
begin
  for g in update public.games set status = 'cancelled'
           where status = 'scheduled' and not time_set and window_end - make_interval(mins => duration_minutes) <= now()
           returning id, starts_at, ends_at, venue_id loop
    for player in select user_id from public.game_players where game_id = g.id and cancelled_at is null loop
      perform public.notify(player.user_id, 'cancelled', 'Game cancelled', 'No time was set for {when} · {court}, so it was cancelled.',
        '/app/games/', public.window_slot(g.starts_at, g.ends_at, false, g.venue_id));
    end loop;
  end loop;
end
$$;

-- 每 5 分钟：普通房间照旧；一对一的邀请到“窗口结束 − 打多久”还没回复就悄悄关闭；没定时间的球局到点取消
create or replace function public.expire_rooms()
returns void language plpgsql security definer set search_path = '' as $$
declare
  r record;
begin
  for r in select id, starts_at, invitee_id from public.rooms
           where status = 'open'
             and ((invitee_id is null and ((starts_at is not null and starts_at <= now())
                                           or (starts_at is null and last_activity_at < now() - interval '30 minutes')))
                  or (invitee_id is not null and window_end - make_interval(mins => duration_minutes) <= now())) loop
    if r.invitee_id is not null then
      update public.rooms set status = 'closed', closed_reason = 'expired', awaiting_id = null where id = r.id;
      delete from public.room_invites where room_id = r.id;
    else
      perform public.close_room(r.id, case when r.starts_at is null then 'expired' else 'start_time_passed' end);
    end if;
  end loop;
  perform public.expire_unset_games();
end
$$;

-- ---------------------------------------------------------------------------
-- 推荐时间：两个人常用时间重叠、能打满 2 小时的第一段（接下来 7 天，按球馆当地时间）
-- 返回 {window_start, window_end, daypart, venue_id, venue_name}；没有重叠就是 null。
-- 球馆：p_venue，没给就用两人都常去的，再没有就用我最早收藏的那家
-- ---------------------------------------------------------------------------

create function public.suggest_invite_window(p_user uuid, p_venue text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  venue text;
  tz text;
  earliest timestamptz := to_timestamp(ceil(extract(epoch from now() + interval '30 minutes') / 1800) * 1800);
  best record;
begin
  if me is null or p_user is null or me = p_user or public.hidden_from(me, p_user) or public.hidden_from(p_user, me) then
    return null;
  end if;
  venue := coalesce((select v.id from public.venues v where v.id = p_venue and not v.hidden_pending_review),
                    public.play_suggestion(me, p_user) ->> 'venue_id',
                    (select f.venue_id from public.favorite_venues f where f.user_id = me order by f.created_at, f.venue_id limit 1));
  select coalesce(v.time_zone_id, 'UTC') into tz from public.venues v where v.id = venue;
  tz := coalesce(tz, 'UTC');

  select x.s, x.e into best
  from (
    select greatest(to_timestamp(ceil(extract(epoch from ((days.d + greatest((a ->> 'start')::time, (b ->> 'start')::time)) at time zone tz)) / 1800) * 1800),
                    earliest) as s,
           to_timestamp(floor(extract(epoch from ((days.d + least((a ->> 'end')::interval, (b ->> 'end')::interval)) at time zone tz)) / 1800) * 1800) as e
    from (select (now() at time zone tz)::date + i as d from generate_series(0, 6) i) days,
         jsonb_array_elements((select usual_times from public.profiles where id = me)) a,
         jsonb_array_elements((select usual_times from public.profiles where id = p_user)) b
    where (a ->> 'weekday')::int = extract(dow from days.d)::int + 1 and (b ->> 'weekday')::int = (a ->> 'weekday')::int) x
  where x.e - x.s >= interval '2 hours'
  order by x.s, x.e desc
  limit 1;
  if best.s is null then return null; end if;

  return jsonb_build_object(
    'window_start', best.s, 'window_end', best.e,
    -- 整段都在一个时段里时给出时段，方便客户端选中对应的选项
    'daypart', (select h.n from (values ('morning', 8, 12), ('afternoon', 14, 18), ('evening', 18, 22)) h (n, f, t)
                where (best.s at time zone tz)::date = (best.e at time zone tz)::date
                  and extract(epoch from (best.s at time zone tz)::time) >= h.f * 3600
                  and extract(epoch from (best.e at time zone tz)::time) <= h.t * 3600
                  and (best.e at time zone tz)::time <> '00:00'
                limit 1),
    'venue_id', venue, 'venue_name', (select v.name from public.venues v where v.id = venue));
end
$$;

-- ---------------------------------------------------------------------------
-- 现有函数：一对一的邀请和没定时间的球局
-- ---------------------------------------------------------------------------

-- 自己开的房间最多 3 个：发出去的邀请不算
create or replace function public.create_room(p_mode public.game_mode, p_visibility public.room_visibility, p_venue text,
                                   p_starts_at timestamptz, p_ends_at timestamptz, p_level_min int, p_level_max int,
                                   p_tags text[] default '{}', p_note text default '', p_gender public.gender default null,
                                   p_mixed boolean default false)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  my_gender public.gender;
  level int;
  new_room uuid;
begin
  level := public.room_level(me, p_gender, p_mixed);
  if level is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  select gender into my_gender from public.profiles where id = me;
  if p_mixed and (p_mode <> 'doubles' or p_gender is not null or my_gender is null) then
    raise exception 'invalid_event' using errcode = '22023';
  end if;
  if not public.accepts(p_gender, my_gender) then
    raise exception 'gender_restricted' using errcode = '22023';
  end if;
  if p_visibility = 'public' and (p_venue is null or p_starts_at is null) then raise exception 'missing_details' using errcode = '22023'; end if;
  perform public.check_room_details(p_venue, p_starts_at, p_ends_at);
  if p_level_min is null or p_level_max is null or p_level_min not between 1 and 9 or p_level_max not between p_level_min and 9 then
    raise exception 'invalid_level_range' using errcode = '22023';
  end if;
  if coalesce(p_note, '') ~* '(https?:|www\.|@|\d{7,})' then raise exception 'no_contact_info' using errcode = '22023'; end if;
  if (select count(*) from public.rooms where owner_id = me and status = 'open' and invitee_id is null) >= 3 then
    raise exception 'too_many_rooms' using errcode = '54000';
  end if;
  if p_starts_at is not null and public.has_game_between(me, p_starts_at, p_ends_at) then
    raise exception 'overlapping' using errcode = '23P01';
  end if;

  -- 房主自己的水平一定在范围内
  insert into public.rooms (code, owner_id, mode, visibility, venue_id, starts_at, ends_at, level_min, level_max, tags, note, gender, mixed)
    values (public.new_invite_code(), me, p_mode, p_visibility, p_venue, p_starts_at, p_ends_at,
            least(p_level_min, level), greatest(p_level_max, level),
            coalesce((select array_agg(distinct t) from unnest(p_tags) t), '{}'), btrim(coalesce(p_note, '')), p_gender, p_mixed)
    returning id into new_room;
  insert into public.room_members (room_id, user_id) values (new_room, me);
  return new_room;
end
$$;

-- 加入房间：一对一的邀请不走这里；同时在的房间最多 10 个，发出去的邀请不算
create or replace function public.join_room_internal(p_room uuid, p_via_code boolean)
returns text language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  my_gender public.gender;
  r public.rooms;
  level int;
  invited boolean;
  going int;
  is_full boolean;
  my_status text;
begin
  select * into r from public.rooms where id = p_room for update;
  if me is null or r.id is null or public.blocked_between(me, r.owner_id) then raise exception 'room_not_found' using errcode = 'P0002'; end if;
  -- 一对一的邀请：只有轮到回复的受邀人能“加入”，等于答应（旧版 App 的加入按钮）；别人凭房间码也进不来
  if r.invitee_id is not null then
    if me = r.invitee_id and r.awaiting_id = me and r.status = 'open' then
      perform public.respond_invite(p_room, true);
      return 'member';
    end if;
    raise exception 'room_not_found' using errcode = 'P0002';
  end if;
  my_status := public.room_status_of(p_room, me);
  if my_status in ('owner', 'member', 'waitlisted') then return case when my_status = 'waitlisted' then 'waitlisted' else 'member' end; end if;
  invited := my_status is not distinct from 'invited';
  if r.visibility = 'private' and not invited and not p_via_code then raise exception 'room_not_found' using errcode = 'P0002'; end if;
  -- 过了开始时间还没开局的，定时任务稍后会关闭
  if r.status <> 'open' or r.starts_at <= now() then raise exception 'room_closed' using errcode = 'P0002'; end if;

  level := public.room_level(me, r.gender, r.mixed);
  if level is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  select gender into my_gender from public.profiles where id = me;
  if not public.accepts(r.gender, my_gender) or (r.mixed and my_gender is null) then
    raise exception 'gender_restricted' using errcode = '22023';
  end if;
  if r.visibility = 'public' and not invited and level not between r.level_min and r.level_max then
    raise exception 'level_out_of_range' using errcode = '22023';
  end if;
  if r.starts_at is not null and public.has_game_between(me, r.starts_at, r.ends_at) then
    raise exception 'overlapping' using errcode = '23P01';
  end if;
  if (select count(*) from public.room_members m join public.rooms o on o.id = m.room_id where m.user_id = me and o.status = 'open' and o.invitee_id is null) >= 10 then
    raise exception 'too_many_rooms' using errcode = '54000';
  end if;

  -- 满了进候补（私密局不排候补）。混双按自己这边的两个位子算
  going := (select count(*) from public.room_members where room_id = p_room and not waitlisted);
  is_full := going >= public.room_capacity(r.mode) or (r.mixed and public.room_going(p_room, my_gender) >= 2);
  if is_full then
    if r.visibility = 'private' or (select count(*) from public.room_members where room_id = p_room and waitlisted) >= 4 then
      raise exception '%', case when r.mixed and going < public.room_capacity(r.mode) then 'mixed_side_full' else 'room_full' end
        using errcode = '54000';
    end if;
    insert into public.room_members (room_id, user_id, waitlisted) values (p_room, me, true);
  else
    insert into public.room_members (room_id, user_id) values (p_room, me);
    perform public.notify(r.owner_id, 'room', '{name} joined your game', '{going} of {capacity} players so far.',
      '/app/rooms/' || p_room || '/',
      jsonb_build_object('name', (select nickname from public.profiles where id = me),
                         'going', going + 1, 'capacity', public.room_capacity(r.mode)));
  end if;
  delete from public.room_invites where room_id = p_room and user_id = me;
  update public.rooms set last_activity_at = now() where id = p_room;
  return case when is_full then 'waitlisted' else 'member' end;
end
$$;

-- 按天看人的“同一天最多等 3 个”不算附近的人的邀请（那边另有每天 10 个）
create or replace function public.pending_invites(p_user uuid, p_starts_at timestamptz, p_tz text)
returns int language sql stable security definer set search_path = '' as $$
  select (select count(*) from public.match_offers o
          where o.invited_by = p_user and o.status = 'open'
            and (o.starts_at at time zone p_tz)::date = (p_starts_at at time zone p_tz)::date)::int
       + (select count(*) from public.room_invites i join public.rooms r on r.id = i.room_id
          where i.invited_by = p_user and r.status = 'open' and r.starts_at is not null and r.invitee_id is null
            and (r.starts_at at time zone p_tz)::date = (p_starts_at at time zone p_tz)::date
            and not exists (select 1 from public.room_members m where m.room_id = r.id and m.user_id = i.user_id))::int
$$;

-- 房主改时间和球馆：一对一的邀请不行
create or replace function public.update_room(p_room uuid, p_venue text, p_starts_at timestamptz, p_ends_at timestamptz)
returns void language plpgsql security definer set search_path = '' as $$
declare
  r public.rooms;
  member record;
begin
  select * into r from public.rooms where id = p_room for update;
  if r.id is null or r.owner_id is distinct from auth.uid() or r.status <> 'open' then raise exception 'not_room_owner' using errcode = '42501'; end if;
  -- 一对一的邀请改时间走 counter_invite
  if r.invitee_id is not null then raise exception 'not_available' using errcode = 'P0002'; end if;
  if r.visibility = 'public' and (p_venue is null or p_starts_at is null) then raise exception 'missing_details' using errcode = '22023'; end if;
  perform public.check_room_details(p_venue, p_starts_at, p_ends_at);
  if p_venue is not distinct from r.venue_id and p_starts_at is not distinct from r.starts_at and p_ends_at is not distinct from r.ends_at then
    return;
  end if;
  update public.rooms set venue_id = p_venue, starts_at = p_starts_at, ends_at = p_ends_at, last_activity_at = now() where id = p_room;
  if p_starts_at is not null then
    for member in select user_id from public.room_members where room_id = p_room and user_id <> r.owner_id loop
      perform public.notify(member.user_id, 'room', 'Game details changed', 'Now {when} · {court}.', '/app/rooms/' || p_room || '/',
        public.slot(p_starts_at, p_venue));
    end loop;
  end if;
end
$$;

-- 邀请球友进房间：一对一的邀请不能再拉人
create or replace function public.invite_to_room(p_room uuid, p_users uuid[])
returns int language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  r public.rooms;
  friend uuid;
  sent int := 0;
begin
  select * into r from public.rooms where id = p_room;
  if r.id is null or r.status <> 'open' or r.invitee_id is not null or coalesce(public.room_status_of(p_room, me), '') not in ('owner', 'member') then
    raise exception 'room_not_found' using errcode = 'P0002';
  end if;
  if cardinality(p_users) > 10 then raise exception 'too_many_invites' using errcode = '54000'; end if;
  foreach friend in array coalesce(p_users, '{}') loop
    continue when not public.are_friends(me, friend) or public.blocked_between(me, friend)
               or public.room_status_of(p_room, friend) is not null;
    insert into public.room_invites (room_id, user_id, invited_by) values (p_room, friend, me);
    perform public.notify(friend, 'room', '{name} invited you to play',
      case when r.starts_at is null then 'Open Badie to join.' else '{when} · {court}. Open Badie to join.' end,
      '/app/rooms/' || p_room || '/',
      jsonb_build_object('name', (select nickname from public.profiles where id = me)) || coalesce(public.slot(r.starts_at, r.venue_id), '{}'));
    sent := sent + 1;
  end loop;
  if sent > 0 then update public.rooms set last_activity_at = now() where id = p_room; end if;
  return sent;
end
$$;

-- 退出：被邀请的人退出一对一的邀请等于“不了”；发邀请的人退出等于撤回（照旧）
create or replace function public.leave_room(p_room uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  r public.rooms;
begin
  select * into r from public.rooms where id = p_room for update;
  if r.id is null or r.status <> 'open' then return; end if;
  -- 一对一的邀请：被邀请的人退出 = 不了
  if r.invitee_id = me then
    perform public.decline_invite(p_room, me);
    return;
  end if;
  if r.owner_id = me then
    perform public.close_room(p_room, 'owner_closed');
    return;
  end if;
  delete from public.room_members where room_id = p_room and user_id = me;
  delete from public.room_invites where room_id = p_room and user_id = me;
  update public.rooms set last_activity_at = now() where id = p_room;
  perform public.promote_room_waitlist(p_room);
end
$$;

-- 凭房间码加入：一对一的邀请找不到
create or replace function public.join_room_code(p_code text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  found uuid;
begin
  select id into found from public.rooms where code = upper(btrim(p_code)) and status = 'open' and invitee_id is null;
  if found is null or auth.uid() is null then raise exception 'room_not_found' using errcode = 'P0002'; end if;
  perform public.join_room_internal(found, true);
  return found;
end
$$;

-- 取消球局：没定时间的不算临时取消（谁都没答应过具体几点）；通知里写时间窗口
create or replace function public.cancel_game(p_game uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  g public.games;
  other record;
  requeued boolean;
begin
  select * into g from public.games where id = p_game and status = 'scheduled' for update;
  -- 没定具体时间的：时间窗口里最晚能开始的时候之前都能取消
  if g.id is null or (g.time_set and g.starts_at <= now())
     or (not g.time_set and g.window_end - make_interval(mins => g.duration_minutes) <= now())
     or not exists (select 1 from public.game_players where game_id = p_game and user_id = auth.uid()) then
    raise exception 'cannot_cancel' using errcode = 'P0002';
  end if;
  update public.game_players set cancelled_at = now(), late_cancel = g.time_set and g.starts_at - now() < interval '2 hours'
    where game_id = p_game and user_id = auth.uid();
  update public.games set status = 'cancelled' where id = p_game;

  for other in select gp.user_id from public.game_players gp where gp.game_id = p_game and gp.user_id <> auth.uid() loop
    update public.match_tickets set status = 'searching', game_id = null, priority = true
      where game_id = p_game and user_id = other.user_id and lock_at > now();
    requeued := found;
    perform public.notify(other.user_id, 'cancelled', 'Game cancelled',
      case when requeued then 'A player can’t make {when} · {court}. We’re finding you another game.' else 'A player can’t make {when} · {court}.' end,
      '/app/games/', public.game_slot(g.id));
  end loop;
  perform public.match_ticket(t.id, now()) from public.match_tickets t where t.game_id is null and t.status = 'searching'
    and t.id in (select ticket_id from public.match_seats where offer_id = g.offer_id);
end
$$;

-- 时间撞车：还没定具体时间的球局不占时间（定时间的时候再查）
create or replace function public.has_game_between(p_user uuid, p_start timestamptz, p_end timestamptz)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.game_players gp join public.games g on g.id = gp.game_id
    where gp.user_id = p_user and g.status = 'scheduled' and g.time_set and g.starts_at < p_end and p_start < g.ends_at)
$$;

-- 我的球局：带上时间窗口（time_set = false 时 starts_at / ends_at 就是窗口）
create or replace function public.my_games()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(item order by starts_at desc), '[]') from (
    select g.starts_at, jsonb_build_object(
      'id', g.id, 'mode', g.mode, 'starts_at', g.starts_at, 'ends_at', g.ends_at, 'status', g.status,
      'time_set', g.time_set, 'window_start', g.window_start, 'window_end', g.window_end,
      'duration_minutes', g.duration_minutes, 'daypart', g.daypart,
      'set_time_by', case when not g.time_set then g.window_end - make_interval(mins => g.duration_minutes) end,
      'venue', jsonb_build_object('id', v.id, 'name', v.name, 'city', v.city, 'street', v.street, 'tz', v.time_zone_id,
                                  'lat', v.lat, 'lon', v.lon, 'pricing', v.pricing, 'country', v.country_code),
      'host_id', public.game_host(g.id),
      'my_team', me.team, 'checked_in', me.checked_in_at is not null,
      'my_report', (select jsonb_build_object('outcome', r.outcome, 'score', r.score, 'team1_games', r.team1_games, 'team2_games', r.team2_games)
                    from public.result_reports r where r.game_id = g.id and r.reporter_id = auth.uid()),
      'result', (select to_jsonb(gr) from public.game_result(g.id) gr),
      -- 最近一次填的比分（双方都填了以后来的为准）
      'score', (select case when rp.team = me.team then r.score
                            else regexp_replace(r.score, '(\d+)\s*([:/-])\s*(\d+)', '\3\2\1', 'g') end
                from public.result_reports r
                join public.game_players rp on rp.game_id = r.game_id and rp.user_id = r.reporter_id
                where r.game_id = g.id and r.score is not null
                order by (r.reporter_id = auth.uid()) desc, r.updated_at desc limit 1),
      -- 双方确认以后才给局数
      'rounds', (select jsonb_build_object('team1', x.team1, 'team2', x.team2) from public.game_rounds(g.id) x
                 where (select r.status from public.game_result(g.id) r) = 'verified'),
      'review_until', g.ends_at + interval '48 hours',
      'players', (select jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', gp.rating, 'team', gp.team,
                                                      'me', gp.user_id = auth.uid(), 'checked_in', gp.checked_in_at is not null,
                                                      'paid', gp.paid_at is not null,
                                                      'reviewed', exists (select 1 from public.game_reviews r where r.game_id = g.id
                                                                          and r.reviewer_id = auth.uid() and r.reviewee_id = gp.user_id))
                                   order by gp.team, gp.rating desc)
                  from public.game_players gp join public.profiles p on p.id = gp.user_id where gp.game_id = g.id)
    ) as item
    from public.games g
    join public.game_players me on me.game_id = g.id and me.user_id = auth.uid()
    join public.venues v on v.id = g.venue_id
    where g.ends_at > now() - interval '60 days'
  ) items
$$;

-- 球局群聊：带上时间窗口
create or replace function public.open_thread(p_kind text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  key text := public.thread_key(p_kind, p_id);
  access text := public.thread_access(p_kind, p_id, me);
  result jsonb;
begin
  if me is null or access is null then raise exception 'not_allowed' using errcode = '42501'; end if;
  select jsonb_build_object(
    'access', access,
    'friend', p_kind = 'dm' and public.are_friends(me, p_id),
    'request', case when p_kind = 'dm' then public.request_direction(me, p_id) end,
    'group_name', case when access = 'request' then public.message_option(me, p_id) ->> 'group' end,
    'game', (select jsonb_build_object('starts_at', g.starts_at, 'ends_at', g.ends_at, 'venue', v.name, 'tz', v.time_zone_id,
                                       'time_set', g.time_set, 'window_start', g.window_start, 'window_end', g.window_end,
                                       'daypart', g.daypart)
             from public.games g join public.venues v on v.id = g.venue_id where p_kind = 'game' and g.id = p_id),
    'group', (select jsonb_build_object('name', g.name, 'venue', v.name)
              from public.play_groups g join public.venues v on v.id = g.venue_id where p_kind = 'group' and g.id = p_id),
    'members', (select jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname, 'me', p.id = me) order by p.id = me, lower(p.nickname))
                from public.profiles p
                where (p_kind = 'game' and p.id in (select user_id from public.game_players where game_id = p_id))
                   or (p_kind = 'group' and p.id in (select user_id from public.group_members where group_id = p_id and not pending))
                   or (p_kind = 'dm' and p.id in (me, p_id))),
    'messages', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'body', m.body, 'created_at', m.created_at,
                                                             'sender', m.sender_id, 'mine', m.sender_id = me) order by m.id)
                          from (select * from public.messages where thread = key order by id desc limit 200) m), '[]'))
    into result;
  insert into public.thread_reads (user_id, thread, last_read_id)
    select me, key, max(id) from public.messages where thread = key having max(id) is not null
    on conflict on constraint thread_reads_pkey do update set last_read_id = excluded.last_read_id;
  return result;
end
$$;

-- 聊天列表：球局带上是否定了时间（没定时 starts_at 是窗口开始）
create or replace function public.my_threads()
returns jsonb language sql stable security definer set search_path = '' as $$
  with others as (
    select id, max(since) as since from (
      select case when f.user_a = auth.uid() then f.user_b else f.user_a end as id, f.created_at as since
      from public.friendships f where auth.uid() in (f.user_a, f.user_b)
      union all
      select case when r.from_id = auth.uid() then r.to_id else r.from_id end, null
      from public.message_requests r where r.from_id = auth.uid() or (r.to_id = auth.uid() and r.ignored_at is null)) x
    group by id),
  threads as (
    select 'game' as kind, g.id, 'game:' || g.id as thread, g.starts_at, v.name as venue, v.time_zone_id as tz, null::text as name,
           g.time_set, g.window_end, g.daypart,
           case when g.status = 'scheduled' and now() <= g.ends_at + interval '48 hours' then 'open' else 'closed' end as access
    from public.game_players gp join public.games g on g.id = gp.game_id join public.venues v on v.id = g.venue_id
    where gp.user_id = auth.uid() and g.ends_at > now() - interval '30 days'
    union all
    select 'group', g.id, 'group:' || g.id, null, v.name, v.time_zone_id, g.name, null::boolean, null::timestamptz, null::text, 'open'
    from public.group_members m join public.play_groups g on g.id = m.group_id join public.venues v on v.id = g.venue_id
    where m.user_id = auth.uid() and not m.pending
    union all
    select 'dm', p.id, 'dm:' || least(auth.uid(), p.id) || ':' || greatest(auth.uid(), p.id), o.since, null, null, p.nickname,
           null, null, null,
           coalesce(public.thread_access('dm', p.id, auth.uid()), 'closed')
    from others o join public.profiles p on p.id = o.id)
  select coalesce(jsonb_agg(jsonb_build_object(
      'kind', t.kind, 'id', t.id, 'starts_at', t.starts_at, 'venue', t.venue, 'tz', t.tz, 'name', t.name, 'access', t.access,
      'time_set', t.time_set, 'window_end', t.window_end, 'daypart', t.daypart,
      'request', case when t.kind = 'dm' then public.request_direction(auth.uid(), t.id) end,
      'last', (select jsonb_build_object('body', m.body, 'created_at', m.created_at, 'mine', m.sender_id = auth.uid()) from public.messages m
               where m.thread = t.thread order by m.id desc limit 1),
      'unread', (select count(*) from public.messages m where m.thread = t.thread and m.sender_id <> auth.uid()
                 and m.id > coalesce((select last_read_id from public.thread_reads r where r.user_id = auth.uid() and r.thread = t.thread), 0)))
    order by coalesce((select max(m.created_at) from public.messages m where m.thread = t.thread), t.starts_at, '-infinity') desc), '[]')
  from threads t
  where (t.kind in ('game', 'group') and t.access = 'open')
     or (t.kind = 'dm' and t.starts_at > now() - interval '7 days')
     or exists (select 1 from public.messages m where m.thread = t.thread)
$$;

-- 球员资料：带上常用时间
create or replace function public.player_card(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select base || jsonb_build_object(
    'win_rate', case when p_user = auth.uid() or (w ->> 'public')::boolean then w end,
    'challenge', public.challenge_availability(p_user),
    'message', public.message_option(auth.uid(), p_user) - 'group_id',
    'verified', pr.verified_kind,
    'avatar', case when not public.blocked_between(auth.uid(), p_user) then pr.avatar_path end,
    'gender', pr.gender,
    'tag', pr.tag,
    'card_color', pr.card_color,
    'card_photo', case when not public.blocked_between(auth.uid(), p_user) then pr.card_photo_path end,
    'recent_no_shows', public.recent_no_shows(p_user),
    'suspended_until', public.suspended_until(p_user),
    'usual_times', pr.usual_times)
  from public.player_card_base(p_user) base, public.win_rate(p_user) w, public.profiles pr
  where base is not null and pr.id = p_user
$$;


-- ---------------------------------------------------------------------------
-- 权限
-- ---------------------------------------------------------------------------

revoke execute on function public.valid_usual_times(jsonb), public.has_level(uuid), public.daypart_fits(timestamptz, int, text, text),
  public.first_window_start(timestamptz, timestamptz, int, text, text, timestamptz), public.window_text(timestamptz, timestamptz, text, text),
  public.window_slot(timestamptz, timestamptz, boolean, text), public.game_slot(uuid), public.invite_open_between(uuid, uuid),
  public.invite_cooldown(uuid, uuid), public.invite_allowed(uuid, uuid), public.invite_window(text, timestamptz, timestamptz, text),
  public.decline_invite(uuid, uuid), public.withdraw_invites_for(uuid, uuid), public.expire_unset_games()
  from public, anon, authenticated;
-- 表的检查约束要用：所有人都能执行（只是检查格式）
grant execute on function public.valid_usual_times(jsonb) to anon, authenticated, service_role;
revoke execute on function public.invite_player(uuid, text, timestamptz, timestamptz, text), public.respond_invite(uuid, boolean),
  public.counter_invite(uuid, text, timestamptz, timestamptz, text), public.nearby_invites(), public.set_game_time(uuid, timestamptz),
  public.suggest_invite_window(uuid, text)
  from public, anon;
grant execute on function public.invite_player(uuid, text, timestamptz, timestamptz, text), public.respond_invite(uuid, boolean),
  public.counter_invite(uuid, text, timestamptz, timestamptz, text), public.nearby_invites(), public.set_game_time(uuid, timestamptz),
  public.suggest_invite_window(uuid, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 通知译文
-- ---------------------------------------------------------------------------

insert into public.notification_texts (locale, english, translated)
select l.locale, t.english, t.translated
from (values
  ('zh-Hans', '{name} suggested another time', '{name} 想换个时间'),
  ('zh-Hans', '{when} · {court}. Open Badie to answer.', '{when} · {court}。打开 Badie 回复。'),
  ('zh-Hans', '{name} can’t make it this time', '{name} 这次来不了'),
  ('zh-Hans', '{when} · {court}. Set the exact time when you’re ready.', '{when} · {court}。具体几点，你们再定。'),
  ('zh-Hans', '{name} set the time', '{name} 定好了时间'),
  ('zh-Hans', 'No time was set for {when} · {court}, so it was cancelled.', '{when} · {court} 一直没定具体时间，已取消。'),
  ('zh-Hant', '{name} suggested another time', '{name} 想換個時間'),
  ('zh-Hant', '{when} · {court}. Open Badie to answer.', '{when} · {court}。打開 Badie 回覆。'),
  ('zh-Hant', '{name} can’t make it this time', '{name} 這次來不了'),
  ('zh-Hant', '{when} · {court}. Set the exact time when you’re ready.', '{when} · {court}。具體幾點，你們再定。'),
  ('zh-Hant', '{name} set the time', '{name} 定好了時間'),
  ('zh-Hant', 'No time was set for {when} · {court}, so it was cancelled.', '{when} · {court} 一直沒定具體時間，已取消。'),
  ('ja', '{name} suggested another time', '{name} さんが別の時間を提案しました'),
  ('ja', '{when} · {court}. Open Badie to answer.', '{when} · {court}。Badie を開いて返事してください。'),
  ('ja', '{name} can’t make it this time', '{name} さんは今回は来られません'),
  ('ja', '{when} · {court}. Set the exact time when you’re ready.', '{when} · {court}。何時にするかは、あとで決めましょう。'),
  ('ja', '{name} set the time', '{name} さんが時間を決めました'),
  ('ja', 'No time was set for {when} · {court}, so it was cancelled.', '{when} · {court} は時間が決まらなかったので、キャンセルになりました。'),
  ('ko', '{name} suggested another time', '{name}님이 다른 시간을 제안했어요'),
  ('ko', '{when} · {court}. Open Badie to answer.', '{when} · {court}. Badie에서 답해 주세요.'),
  ('ko', '{name} can’t make it this time', '{name}님은 이번에는 어려워요'),
  ('ko', '{when} · {court}. Set the exact time when you’re ready.', '{when} · {court}. 정확한 시간은 나중에 정하면 돼요.'),
  ('ko', '{name} set the time', '{name}님이 시간을 정했어요'),
  ('ko', 'No time was set for {when} · {court}, so it was cancelled.', '{when} · {court} 시간을 정하지 않아 취소됐어요.'),
  ('hi', '{name} suggested another time', '{name} ने दूसरा समय सुझाया'),
  ('hi', '{when} · {court}. Open Badie to answer.', '{when} · {court}. जवाब देने के लिए Badie खोलें।'),
  ('hi', '{name} can’t make it this time', '{name} इस बार नहीं आ पाएँगे'),
  ('hi', '{when} · {court}. Set the exact time when you’re ready.', '{when} · {court}. सही समय बाद में तय कर लें।'),
  ('hi', '{name} set the time', '{name} ने समय तय किया'),
  ('hi', 'No time was set for {when} · {court}, so it was cancelled.', '{when} · {court} का समय तय नहीं हुआ, इसलिए यह रद्द हो गया।'),
  ('id', '{name} suggested another time', '{name} mengusulkan waktu lain'),
  ('id', '{when} · {court}. Open Badie to answer.', '{when} · {court}. Buka Badie untuk menjawab.'),
  ('id', '{name} can’t make it this time', '{name} tidak bisa kali ini'),
  ('id', '{when} · {court}. Set the exact time when you’re ready.', '{when} · {court}. Jam pastinya bisa ditentukan nanti.'),
  ('id', '{name} set the time', '{name} sudah menentukan jamnya'),
  ('id', 'No time was set for {when} · {court}, so it was cancelled.', 'Jam untuk {when} · {court} tidak ditentukan, jadi dibatalkan.'),
  ('ms', '{name} suggested another time', '{name} mencadangkan masa lain'),
  ('ms', '{when} · {court}. Open Badie to answer.', '{when} · {court}. Buka Badie untuk menjawab.'),
  ('ms', '{name} can’t make it this time', '{name} tidak dapat datang kali ini'),
  ('ms', '{when} · {court}. Set the exact time when you’re ready.', '{when} · {court}. Masa tepat boleh ditetapkan kemudian.'),
  ('ms', '{name} set the time', '{name} sudah menetapkan masa'),
  ('ms', 'No time was set for {when} · {court}, so it was cancelled.', 'Masa untuk {when} · {court} tidak ditetapkan, jadi ia dibatalkan.'),
  ('th', '{name} suggested another time', '{name} เสนอเวลาอื่น'),
  ('th', '{when} · {court}. Open Badie to answer.', '{when} · {court} เปิด Badie เพื่อตอบ'),
  ('th', '{name} can’t make it this time', '{name} มาไม่ได้รอบนี้'),
  ('th', '{when} · {court}. Set the exact time when you’re ready.', '{when} · {court} ค่อยตกลงเวลาที่แน่นอนกันทีหลัง'),
  ('th', '{name} set the time', '{name} กำหนดเวลาแล้ว'),
  ('th', 'No time was set for {when} · {court}, so it was cancelled.', '{when} · {court} ไม่ได้กำหนดเวลา จึงยกเลิกแล้ว'),
  ('vi', '{name} suggested another time', '{name} đề xuất giờ khác'),
  ('vi', '{when} · {court}. Open Badie to answer.', '{when} · {court}. Mở Badie để trả lời.'),
  ('vi', '{name} can’t make it this time', '{name} lần này không đến được'),
  ('vi', '{when} · {court}. Set the exact time when you’re ready.', '{when} · {court}. Giờ cụ thể có thể chốt sau.'),
  ('vi', '{name} set the time', '{name} đã chốt giờ'),
  ('vi', 'No time was set for {when} · {court}, so it was cancelled.', '{when} · {court} chưa chốt giờ nên đã hủy.')
) as t(locale, english, translated)
join (select distinct locale from public.notification_texts) l on l.locale = t.locale;
