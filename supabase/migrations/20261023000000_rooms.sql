-- 球局（房间）：订好场地缺人时发起，规则和 iOS 的 MockBackend+Rooms 一致。
-- - 公开局：附近的人能看到，水平在范围内就能直接加入；满员后最多 4 人候补，有人退出按顺序递补
-- - 私密局：只能凭 6 位房间码或房主 / 成员的邀请加入（受邀的人不看水平范围）
-- - 房主可以改时间和球馆、移出成员、解散；人齐后开局，生成一场正式球局（签到、赛果、互评、群聊都沿用球局的）
-- - 有时间的局到开始时间还没开局就关闭；没设时间的私密局 30 分钟没有动静就关闭
-- 所有读写都走下面的函数，表不对客户端开放

create type public.room_visibility as enum ('private', 'public');
create type public.room_status as enum ('open', 'started', 'closed');

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  code char(6) not null unique,
  owner_id uuid not null references auth.users (id) on delete cascade,
  mode public.game_mode not null,
  visibility public.room_visibility not null,
  venue_id text references public.venues (id),
  starts_at timestamptz,
  ends_at timestamptz,
  level_min smallint not null check (level_min between 1 and 9),
  level_max smallint not null check (level_max between 1 and 9),
  tags text[] not null default '{}'
    check (tags <@ array['beginner_friendly', 'casual', 'competitive', 'women_friendly', 'coaching']),
  note text not null default '' check (char_length(note) <= 80),
  status public.room_status not null default 'open',
  closed_reason text check (closed_reason in ('expired', 'owner_closed', 'start_time_passed')),
  game_id uuid references public.games (id) on delete set null,
  created_at timestamptz not null default now(),
  last_activity_at timestamptz not null default now(),
  check (level_min <= level_max),
  check ((starts_at is null) = (ends_at is null)),
  check (visibility = 'private' or (venue_id is not null and starts_at is not null))
);

create index rooms_open_idx on public.rooms (starts_at) where status = 'open';
create index rooms_owner_idx on public.rooms (owner_id);

-- 候补按加入时间排队
create table public.room_members (
  room_id uuid not null references public.rooms (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  waitlisted boolean not null default false,
  joined_at timestamptz not null default clock_timestamp(),
  primary key (room_id, user_id)
);

create index room_members_user_idx on public.room_members (user_id);

create table public.room_invites (
  room_id uuid not null references public.rooms (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  invited_by uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
alter table public.room_invites enable row level security;
revoke all on public.rooms, public.room_members, public.room_invites from anon, authenticated;
grant all on public.rooms, public.room_members, public.room_invites to service_role;

-- ---------------------------------------------------------------------------
-- 小工具
-- ---------------------------------------------------------------------------

create function public.room_capacity(p_mode public.game_mode)
returns int language sql immutable set search_path = '' as $$
  select case when p_mode = 'singles' then 2 else 4 end
$$;

-- 房间码和群号在 App 里用同一个框输入：同一个生成器，两张表都不重复
create or replace function public.new_invite_code()
returns char(6) language plpgsql set search_path = '' as $$
declare
  candidate text;
begin
  loop
    candidate := (select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::int, 1), '') from generate_series(1, 6));
    exit when not exists (select 1 from public.play_groups where invite_code = candidate)
          and not exists (select 1 from public.rooms r where r.code = candidate);
  end loop;
  return candidate;
end
$$;

-- 时间：1–8 小时、还没开始、14 天内；球馆要存在且没在审核中
create function public.check_room_details(p_venue text, p_starts_at timestamptz, p_ends_at timestamptz)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if p_starts_at is null and p_ends_at is null then return; end if;
  if p_starts_at is null or p_ends_at is null or p_ends_at - p_starts_at not between interval '1 hour' and interval '8 hours' then
    raise exception 'invalid_slot' using errcode = '22023';
  end if;
  if p_starts_at <= now() then raise exception 'already_started' using errcode = '22023'; end if;
  if p_starts_at > now() + interval '14 days' then raise exception 'too_far' using errcode = '22023'; end if;
  if p_venue is not null and not exists (select 1 from public.venues where id = p_venue and merged_into is null and not hidden_pending_review) then
    raise exception 'invalid_venues' using errcode = '22023';
  end if;
end
$$;

create function public.room_status_of(p_room uuid, p_user uuid)
returns text language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select case when r.owner_id = p_user then 'owner' when m.waitlisted then 'waitlisted' else 'member' end
     from public.rooms r join public.room_members m on m.room_id = r.id and m.user_id = p_user where r.id = p_room),
    (select 'invited' from public.room_invites where room_id = p_room and user_id = p_user))
$$;

-- 列表和详情共用的一段：成员名单只给自己人看，其他人只看到人数和房主
create function public.room_summary(p_room uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', r.id, 'mode', r.mode, 'visibility', r.visibility, 'status', r.status, 'closed_reason', r.closed_reason,
    'game_id', r.game_id, 'starts_at', r.starts_at, 'ends_at', r.ends_at, 'level_min', r.level_min, 'level_max', r.level_max,
    'tags', r.tags, 'note', r.note, 'capacity', public.room_capacity(r.mode), 'last_activity_at', r.last_activity_at,
    'going', (select count(*) from public.room_members m where m.room_id = r.id and not m.waitlisted),
    'waitlist', (select count(*) from public.room_members m where m.room_id = r.id and m.waitlisted),
    'owner', (select jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', p.rating) from public.profiles p where p.id = r.owner_id),
    'venue', (select jsonb_build_object('id', v.id, 'name', v.name, 'city', v.city, 'street', v.street, 'tz', v.time_zone_id,
                                        'lat', v.lat, 'lon', v.lon, 'pricing', v.pricing, 'country', v.country_code)
              from public.venues v where v.id = r.venue_id),
    'my_status', public.room_status_of(r.id, auth.uid()))
  from public.rooms r where r.id = p_room
$$;

-- 关闭房间并告诉房间里的人（房主自己解散时不通知房主）
create function public.close_room(p_room uuid, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  r public.rooms;
  member record;
  title text;
  body text;
begin
  update public.rooms set status = 'closed', closed_reason = p_reason where id = p_room and status = 'open' returning * into r;
  if r.id is null then return; end if;
  title := case when p_reason = 'owner_closed' and r.starts_at is not null then 'Game cancelled'
                when p_reason = 'start_time_passed' then 'Game didn’t start' else 'Room closed' end;
  body := case
    when p_reason = 'owner_closed' and r.starts_at is not null then 'The host cancelled {when} · {court}.'
    when p_reason = 'owner_closed' then 'The host closed the room.'
    when p_reason = 'start_time_passed' then '{when} · {court} didn’t fill up in time, so it was closed.'
    else 'Nothing happened for 30 minutes, so the room was closed.' end;
  for member in select user_id from public.room_members where room_id = p_room
                 and not (p_reason = 'owner_closed' and user_id = r.owner_id) loop
    perform public.notify(member.user_id, 'room_closed', title, body, '/app/rooms/' || p_room || '/',
      coalesce(public.slot(r.starts_at, r.venue_id), '{}'));
  end loop;
end
$$;

-- 空出的位子按候补顺序补上
create function public.promote_room_waitlist(p_room uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  r public.rooms;
  next_up uuid;
begin
  select * into r from public.rooms where id = p_room and status = 'open';
  if r.id is null then return; end if;
  while (select count(*) from public.room_members where room_id = p_room and not waitlisted) < public.room_capacity(r.mode) loop
    select user_id into next_up from public.room_members where room_id = p_room and waitlisted order by joined_at limit 1;
    exit when next_up is null;
    update public.room_members set waitlisted = false where room_id = p_room and user_id = next_up;
    perform public.notify(next_up, 'room_promoted', 'You’re off the waitlist',
      'A spot opened up for {when} · {court}. If you can’t make it, cancel early.', '/app/rooms/' || p_room || '/',
      public.slot(r.starts_at, r.venue_id));
    next_up := null;
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- 读
-- ---------------------------------------------------------------------------

-- 房间页：自己人看全部（含房间码和名单）；别人只能看公开局的概要
create function public.room_page(p_room uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  r public.rooms;
  status text;
begin
  select * into r from public.rooms where id = p_room;
  status := public.room_status_of(p_room, me);
  if me is null or r.id is null or public.blocked_between(me, r.owner_id) or (r.visibility = 'private' and status is null) then
    return null;
  end if;
  return public.room_summary(p_room) || jsonb_build_object(
    'code', case when status is not null then r.code end,
    'members', case when status is not null then coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', p.rating, 'waitlisted', m.waitlisted,
                                          'me', p.id = me) order by m.waitlisted, m.joined_at)
      from public.room_members m join public.profiles p on p.id = m.user_id where m.room_id = p_room), '[]') end);
end
$$;

-- 附近还没开始的公开局（屏蔽关系双方都看不到）
create function public.rooms_near(lat double precision, lng double precision, radius_km double precision default 30)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(public.room_summary(x.id) order by x.starts_at), '[]')
  from (select r.id, r.starts_at
        from public.rooms r join public.venues v on v.id = r.venue_id
        where r.visibility = 'public' and r.status = 'open' and r.starts_at > now()
          and extensions.st_dwithin(v.location, extensions.st_makepoint(rooms_near.lng, rooms_near.lat)::extensions.geography,
                                    least(radius_km, 100) * 1000)
          and not public.blocked_between(auth.uid(), r.owner_id)
        order by r.starts_at
        limit 50) x
  where auth.uid() is not null
$$;

-- 我在里面（或候补、或被邀请）的房间
create function public.my_rooms()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(public.room_summary(r.id) order by r.starts_at nulls last, r.created_at), '[]')
  from public.rooms r
  where r.status = 'open'
    and (exists (select 1 from public.room_members m where m.room_id = r.id and m.user_id = auth.uid())
         or exists (select 1 from public.room_invites i where i.room_id = r.id and i.user_id = auth.uid()))
$$;

-- ---------------------------------------------------------------------------
-- 写
-- ---------------------------------------------------------------------------

create function public.create_room(p_mode public.game_mode, p_visibility public.room_visibility, p_venue text,
                                   p_starts_at timestamptz, p_ends_at timestamptz, p_level_min int, p_level_max int,
                                   p_tags text[] default '{}', p_note text default '')
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  level int;
  new_room uuid;
begin
  select round(rating) into level from public.profiles where id = me;
  if level is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if p_visibility = 'public' and (p_venue is null or p_starts_at is null) then raise exception 'missing_details' using errcode = '22023'; end if;
  perform public.check_room_details(p_venue, p_starts_at, p_ends_at);
  if p_level_min is null or p_level_max is null or p_level_min not between 1 and 9 or p_level_max not between p_level_min and 9 then
    raise exception 'invalid_level_range' using errcode = '22023';
  end if;
  if coalesce(p_note, '') ~* '(https?:|www\.|@|\d{7,})' then raise exception 'no_contact_info' using errcode = '22023'; end if;
  if (select count(*) from public.rooms where owner_id = me and status = 'open') >= 3 then
    raise exception 'too_many_rooms' using errcode = '54000';
  end if;
  if p_starts_at is not null and public.has_game_between(me, p_starts_at, p_ends_at) then
    raise exception 'overlapping' using errcode = '23P01';
  end if;

  -- 房主自己的水平一定在范围内
  insert into public.rooms (code, owner_id, mode, visibility, venue_id, starts_at, ends_at, level_min, level_max, tags, note)
    values (public.new_invite_code(), me, p_mode, p_visibility, p_venue, p_starts_at, p_ends_at,
            least(p_level_min, level), greatest(p_level_max, level),
            coalesce((select array_agg(distinct t) from unnest(p_tags) t), '{}'), btrim(coalesce(p_note, '')))
    returning id into new_room;
  insert into public.room_members (room_id, user_id) values (new_room, me);
  return new_room;
end
$$;

-- 加入（公开局或受邀）。凭房间码加入时私密局也能进，但公开局仍要看水平。返回 'member' 或 'waitlisted'
create function public.join_room_internal(p_room uuid, p_via_code boolean)
returns text language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  r public.rooms;
  level int;
  invited boolean;
  going int;
  my_status text;
begin
  select * into r from public.rooms where id = p_room for update;
  if me is null or r.id is null or public.blocked_between(me, r.owner_id) then raise exception 'room_not_found' using errcode = 'P0002'; end if;
  my_status := public.room_status_of(p_room, me);
  if my_status in ('owner', 'member', 'waitlisted') then return case when my_status = 'waitlisted' then 'waitlisted' else 'member' end; end if;
  invited := my_status is not distinct from 'invited';
  if r.visibility = 'private' and not invited and not p_via_code then raise exception 'room_not_found' using errcode = 'P0002'; end if;
  -- 过了开始时间还没开局的，定时任务稍后会关闭
  if r.status <> 'open' or r.starts_at <= now() then raise exception 'room_closed' using errcode = 'P0002'; end if;

  select round(rating) into level from public.profiles where id = me;
  if level is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if r.visibility = 'public' and not invited and level not between r.level_min and r.level_max then
    raise exception 'level_out_of_range' using errcode = '22023';
  end if;
  if r.starts_at is not null and public.has_game_between(me, r.starts_at, r.ends_at) then
    raise exception 'overlapping' using errcode = '23P01';
  end if;
  if (select count(*) from public.room_members m join public.rooms o on o.id = m.room_id where m.user_id = me and o.status = 'open') >= 10 then
    raise exception 'too_many_rooms' using errcode = '54000';
  end if;

  going := (select count(*) from public.room_members where room_id = p_room and not waitlisted);
  if going >= public.room_capacity(r.mode) then
    if r.visibility = 'private' or (select count(*) from public.room_members where room_id = p_room and waitlisted) >= 4 then
      raise exception 'room_full' using errcode = '54000';
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
  return case when going >= public.room_capacity(r.mode) then 'waitlisted' else 'member' end;
end
$$;

create function public.join_room(p_room uuid)
returns text language sql security definer set search_path = '' as $$
  select public.join_room_internal(p_room, false)
$$;

-- 凭房间码加入：找不到（或已结束）报 room_not_found，App 再去找同号的球群
create function public.join_room_code(p_code text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  found uuid;
begin
  select id into found from public.rooms where code = upper(btrim(p_code)) and status = 'open';
  if found is null or auth.uid() is null then raise exception 'room_not_found' using errcode = 'P0002'; end if;
  perform public.join_room_internal(found, true);
  return found;
end
$$;

-- 退出：房主退出等于解散；成员退出后候补递补
create function public.leave_room(p_room uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  r public.rooms;
begin
  select * into r from public.rooms where id = p_room for update;
  if r.id is null or r.status <> 'open' then return; end if;
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

create function public.remove_room_member(p_room uuid, p_user uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  r public.rooms;
begin
  select * into r from public.rooms where id = p_room for update;
  if r.id is null or r.owner_id is distinct from auth.uid() or r.status <> 'open' then raise exception 'not_room_owner' using errcode = '42501'; end if;
  if p_user = r.owner_id then return; end if;
  delete from public.room_members where room_id = p_room and user_id = p_user;
  if not found then return; end if;
  delete from public.room_invites where room_id = p_room and user_id = p_user;
  perform public.notify(p_user, 'room_removed', 'You were removed from a game', 'The host changed the lineup. Find another game nearby.',
    '/app/play/');
  update public.rooms set last_activity_at = now() where id = p_room;
  perform public.promote_room_waitlist(p_room);
end
$$;

-- 邀请球友（只能邀请好友；已在房间里的跳过）。返回邀请了几个人
create function public.invite_to_room(p_room uuid, p_users uuid[])
returns int language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  r public.rooms;
  friend uuid;
  sent int := 0;
begin
  select * into r from public.rooms where id = p_room;
  if r.id is null or r.status <> 'open' or coalesce(public.room_status_of(p_room, me), '') not in ('owner', 'member') then
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

-- 房主改时间和球馆（公开局必须有）
create function public.update_room(p_room uuid, p_venue text, p_starts_at timestamptz, p_ends_at timestamptz)
returns void language plpgsql security definer set search_path = '' as $$
declare
  r public.rooms;
  member record;
begin
  select * into r from public.rooms where id = p_room for update;
  if r.id is null or r.owner_id is distinct from auth.uid() or r.status <> 'open' then raise exception 'not_room_owner' using errcode = '42501'; end if;
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

-- 人齐开局：生成正式球局。双打按水平 1、4 名一队，2、3 名一队；候补的人告诉他们这次没排上
create function public.start_room(p_room uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  r public.rooms;
  new_game uuid;
  player record;
begin
  select * into r from public.rooms where id = p_room for update;
  if r.id is null or r.owner_id is distinct from auth.uid() or r.status <> 'open' then raise exception 'not_room_owner' using errcode = '42501'; end if;
  if r.venue_id is null or r.starts_at is null then raise exception 'missing_details' using errcode = '22023'; end if;
  if r.starts_at <= now() then raise exception 'already_started' using errcode = '22023'; end if;
  if (select count(*) from public.room_members where room_id = p_room and not waitlisted) <> public.room_capacity(r.mode) then
    raise exception 'not_enough_players' using errcode = '22023';
  end if;
  if exists (select 1 from public.room_members m where m.room_id = p_room and not m.waitlisted
             and public.has_game_between(m.user_id, r.starts_at, r.ends_at)) then
    raise exception 'overlapping' using errcode = '23P01';
  end if;

  insert into public.games (mode, starts_at, ends_at, venue_id) values (r.mode, r.starts_at, r.ends_at, r.venue_id) returning id into new_game;
  insert into public.game_players (game_id, user_id, team, rating)
    select new_game, ranked.user_id,
           case when r.mode = 'singles' then ranked.n when ranked.n in (1, 4) then 1 else 2 end, ranked.rating
    from (select m.user_id, p.rating, row_number() over (order by p.rating desc, m.joined_at)::smallint as n
          from public.room_members m join public.profiles p on p.id = m.user_id
          where m.room_id = p_room and not m.waitlisted) ranked;
  update public.rooms set status = 'started', game_id = new_game where id = p_room;

  for player in select user_id, waitlisted from public.room_members where room_id = p_room and user_id <> r.owner_id loop
    if player.waitlisted then
      perform public.notify(player.user_id, 'room_closed', 'The game is full',
        '{when} · {court} started without the waitlist. Find another game nearby.', '/app/play/', public.slot(r.starts_at, r.venue_id));
    else
      perform public.notify(player.user_id, 'matched', 'Game on!', '{when} · {court}. Everyone confirmed.',
        '/app/games/' || new_game || '/', public.slot(r.starts_at, r.venue_id));
    end if;
  end loop;
  return new_game;
end
$$;

-- 每 5 分钟：到开始时间还没开局的关闭；没设时间的私密局 30 分钟没有动静就关闭
create function public.expire_rooms()
returns void language plpgsql security definer set search_path = '' as $$
declare
  r record;
begin
  for r in select id, starts_at from public.rooms
           where status = 'open' and ((starts_at is not null and starts_at <= now())
                                      or (starts_at is null and last_activity_at < now() - interval '30 minutes')) loop
    perform public.close_room(r.id, case when r.starts_at is null then 'expired' else 'start_time_passed' end);
  end loop;
end
$$;

-- 注销账号时：自己建的房间解散（通知其他人），参加的房间退出（候补递补）
create or replace function public.delete_account()
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  item record;
  heir uuid;
begin
  if me is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  -- 管理员的审核记录要保留：先由人工撤掉管理员身份
  if public.is_admin() then raise exception 'admin_account' using errcode = '42501'; end if;

  for item in select t.id from public.match_tickets t where t.user_id = me and t.status in ('searching', 'offered', 'paused') loop
    perform public.cancel_ticket(item.id);
  end loop;

  for item in select g.id from public.games g join public.game_players gp on gp.game_id = g.id
              where gp.user_id = me and g.status = 'scheduled' and g.starts_at > now() loop
    perform public.cancel_game(item.id);
  end loop;

  for item in select m.room_id from public.room_members m join public.rooms r on r.id = m.room_id
              where m.user_id = me and r.status = 'open' loop
    perform public.leave_room(item.room_id);
  end loop;

  for item in select id, name from public.play_groups where owner_id = me loop
    select m.user_id into heir from public.group_members m
      where m.group_id = item.id and m.user_id <> me and not m.pending
      order by m.role = 'organizer' desc, m.joined_at
      limit 1;
    continue when heir is null;
    update public.play_groups set owner_id = heir where id = item.id;
    update public.group_members set role = 'owner' where group_id = item.id and user_id = heir;
    perform public.notify(heir, 'group', 'You now run {group}', 'The owner left Badie, so the group is yours now.',
      '/app/groups/' || item.id || '/', jsonb_build_object('group', item.name));
  end loop;

  for item in delete from public.session_signups s using public.group_sessions gs
              where s.session_id = gs.id and s.user_id = me and gs.starts_at > now()
              returning s.session_id loop
    perform public.promote_waitlist(item.session_id);
  end loop;

  delete from auth.users where id = me;
end
$$;

-- 通知译文
insert into public.notification_texts (locale, english, translated) values
  ('zh-Hans', 'Game didn’t start', '球局没有开成'),
  ('zh-Hans', 'Room closed', '房间已关闭'),
  ('zh-Hans', 'The host cancelled {when} · {court}.', '房主取消了 {when} · {court} 这场。'),
  ('zh-Hans', 'The host closed the room.', '房主解散了房间。'),
  ('zh-Hans', '{when} · {court} didn’t fill up in time, so it was closed.', '{when} · {court} 到开始时间还没凑齐人，已关闭。'),
  ('zh-Hans', 'Nothing happened for 30 minutes, so the room was closed.', '房间 30 分钟没有动静，已自动关闭。'),
  ('zh-Hans', 'You’re off the waitlist', '候补成功，你已加入球局'),
  ('zh-Hans', '{name} joined your game', '{name} 加入了你的球局'),
  ('zh-Hans', '{going} of {capacity} players so far.', '目前 {going}/{capacity} 人。'),
  ('zh-Hans', 'You were removed from a game', '你已被移出球局'),
  ('zh-Hans', 'The host changed the lineup. Find another game nearby.', '房主调整了人员，去看看附近其他球局吧。'),
  ('zh-Hans', '{name} invited you to play', '{name} 邀请你打球'),
  ('zh-Hans', 'Open Badie to join.', '打开 Badie 加入。'),
  ('zh-Hans', '{when} · {court}. Open Badie to join.', '{when} · {court}。打开 Badie 加入。'),
  ('zh-Hans', 'Game details changed', '球局信息有变'),
  ('zh-Hans', 'Now {when} · {court}.', '改为 {when} · {court}。'),
  ('zh-Hans', 'The game is full', '球局已满员'),
  ('zh-Hans', '{when} · {court} started without the waitlist. Find another game nearby.', '{when} · {court} 已开局，候补这次没排上。去看看附近其他球局吧。'),
  ('zh-Hant', 'Game didn’t start', '球局沒有開成'),
  ('zh-Hant', 'Room closed', '房間已關閉'),
  ('zh-Hant', 'The host cancelled {when} · {court}.', '房主取消了 {when} · {court} 這場。'),
  ('zh-Hant', 'The host closed the room.', '房主解散了房間。'),
  ('zh-Hant', '{when} · {court} didn’t fill up in time, so it was closed.', '{when} · {court} 到開始時間還沒湊齊人，已關閉。'),
  ('zh-Hant', 'Nothing happened for 30 minutes, so the room was closed.', '房間 30 分鐘沒有動靜，已自動關閉。'),
  ('zh-Hant', 'You’re off the waitlist', '候補成功，你已加入球局'),
  ('zh-Hant', '{name} joined your game', '{name} 加入了你的球局'),
  ('zh-Hant', '{going} of {capacity} players so far.', '目前 {going}/{capacity} 人。'),
  ('zh-Hant', 'You were removed from a game', '你已被移出球局'),
  ('zh-Hant', 'The host changed the lineup. Find another game nearby.', '房主調整了人員，去看看附近其他球局吧。'),
  ('zh-Hant', '{name} invited you to play', '{name} 邀請你打球'),
  ('zh-Hant', 'Open Badie to join.', '打開 Badie 加入。'),
  ('zh-Hant', '{when} · {court}. Open Badie to join.', '{when} · {court}。打開 Badie 加入。'),
  ('zh-Hant', 'Game details changed', '球局資訊有變'),
  ('zh-Hant', 'Now {when} · {court}.', '改為 {when} · {court}。'),
  ('zh-Hant', 'The game is full', '球局已滿員'),
  ('zh-Hant', '{when} · {court} started without the waitlist. Find another game nearby.', '{when} · {court} 已開局，候補這次沒排上。去看看附近其他球局吧。'),
  ('ja', 'Game didn’t start', 'ゲームは成立しませんでした'),
  ('ja', 'Room closed', 'ルームは終了しました'),
  ('ja', 'The host cancelled {when} · {court}.', 'ホストが {when} · {court} のゲームを取り消しました。'),
  ('ja', 'The host closed the room.', 'ホストがルームを解散しました。'),
  ('ja', '{when} · {court} didn’t fill up in time, so it was closed.', '{when} · {court} は開始時刻までに人数がそろわなかったため、終了しました。'),
  ('ja', 'Nothing happened for 30 minutes, so the room was closed.', '30 分間動きがなかったため、ルームを自動終了しました。'),
  ('ja', 'You’re off the waitlist', '繰り上げでゲームに参加が確定しました'),
  ('ja', '{name} joined your game', '{name} さんがあなたのゲームに参加しました'),
  ('ja', '{going} of {capacity} players so far.', '現在 {going}/{capacity} 人です。'),
  ('ja', 'You were removed from a game', 'ゲームから外されました'),
  ('ja', 'The host changed the lineup. Find another game nearby.', 'ホストがメンバーを変更しました。近くの他のゲームを探してみましょう。'),
  ('ja', '{name} invited you to play', '{name} さんからゲームの招待が届きました'),
  ('ja', 'Open Badie to join.', 'Badie を開いて参加しましょう。'),
  ('ja', '{when} · {court}. Open Badie to join.', '{when} · {court}。Badie を開いて参加しましょう。'),
  ('ja', 'Game details changed', 'ゲームの内容が変わりました'),
  ('ja', 'Now {when} · {court}.', '変更後：{when} · {court}'),
  ('ja', 'The game is full', 'ゲームは満員になりました'),
  ('ja', '{when} · {court} started without the waitlist. Find another game nearby.', '{when} · {court} はキャンセル待ちなしで始まりました。近くの他のゲームを探してみましょう。'),
  ('ko', 'Game didn’t start', '게임이 성사되지 않았어요'),
  ('ko', 'Room closed', '방이 닫혔어요'),
  ('ko', 'The host cancelled {when} · {court}.', '방장이 {when} · {court} 게임을 취소했어요.'),
  ('ko', 'The host closed the room.', '방장이 방을 닫았어요.'),
  ('ko', '{when} · {court} didn’t fill up in time, so it was closed.', '{when} · {court} 게임은 시작 시간까지 인원이 차지 않아 닫혔어요.'),
  ('ko', 'Nothing happened for 30 minutes, so the room was closed.', '30분 동안 활동이 없어 방이 자동으로 닫혔어요.'),
  ('ko', 'You’re off the waitlist', '자리가 나서 게임에 참가됐어요'),
  ('ko', '{name} joined your game', '{name} 님이 내 게임에 참가했어요'),
  ('ko', '{going} of {capacity} players so far.', '지금 {going}/{capacity}명이에요.'),
  ('ko', 'You were removed from a game', '게임에서 제외됐어요'),
  ('ko', 'The host changed the lineup. Find another game nearby.', '방장이 인원을 조정했어요. 근처 다른 게임을 찾아보세요.'),
  ('ko', '{name} invited you to play', '{name} 님이 게임에 초대했어요'),
  ('ko', 'Open Badie to join.', 'Badie에서 참가하세요.'),
  ('ko', '{when} · {court}. Open Badie to join.', '{when} · {court}. Badie에서 참가하세요.'),
  ('ko', 'Game details changed', '게임 정보가 바뀌었어요'),
  ('ko', 'Now {when} · {court}.', '변경: {when} · {court}'),
  ('ko', 'The game is full', '게임 인원이 다 찼어요'),
  ('ko', '{when} · {court} started without the waitlist. Find another game nearby.', '{when} · {court} 게임이 대기자 없이 시작됐어요. 근처 다른 게임을 찾아보세요.'),
  ('id', 'Game didn’t start', 'Game tidak jadi'),
  ('id', 'Room closed', 'Room ditutup'),
  ('id', 'The host cancelled {when} · {court}.', 'Host membatalkan {when} · {court}.'),
  ('id', 'The host closed the room.', 'Host menutup room.'),
  ('id', '{when} · {court} didn’t fill up in time, so it was closed.', '{when} · {court} tidak penuh sampai waktu mulai, jadi ditutup.'),
  ('id', 'Nothing happened for 30 minutes, so the room was closed.', 'Tidak ada aktivitas selama 30 menit, jadi room ditutup.'),
  ('id', 'You’re off the waitlist', 'Ada slot kosong, kamu masuk ke game'),
  ('id', '{name} joined your game', '{name} bergabung ke game-mu'),
  ('id', '{going} of {capacity} players so far.', 'Sejauh ini {going} dari {capacity} pemain.'),
  ('id', 'You were removed from a game', 'Kamu dikeluarkan dari game'),
  ('id', 'The host changed the lineup. Find another game nearby.', 'Host mengubah susunan pemain. Cari game lain di dekatmu.'),
  ('id', '{name} invited you to play', '{name} mengajakmu main'),
  ('id', 'Open Badie to join.', 'Buka Badie untuk bergabung.'),
  ('id', '{when} · {court}. Open Badie to join.', '{when} · {court}. Buka Badie untuk bergabung.'),
  ('id', 'Game details changed', 'Detail game berubah'),
  ('id', 'Now {when} · {court}.', 'Sekarang {when} · {court}.'),
  ('id', 'The game is full', 'Game sudah penuh'),
  ('id', '{when} · {court} started without the waitlist. Find another game nearby.', '{when} · {court} sudah dimulai tanpa daftar tunggu. Cari game lain di dekatmu.'),
  ('ms', 'Game didn’t start', 'Permainan tidak jadi'),
  ('ms', 'Room closed', 'Bilik ditutup'),
  ('ms', 'The host cancelled {when} · {court}.', 'Hos membatalkan {when} · {court}.'),
  ('ms', 'The host closed the room.', 'Hos telah menutup bilik.'),
  ('ms', '{when} · {court} didn’t fill up in time, so it was closed.', '{when} · {court} tidak cukup pemain sebelum masa mula, jadi ditutup.'),
  ('ms', 'Nothing happened for 30 minutes, so the room was closed.', 'Tiada aktiviti selama 30 minit, jadi bilik ditutup.'),
  ('ms', 'You’re off the waitlist', 'Ada tempat kosong, anda kini dalam permainan'),
  ('ms', '{name} joined your game', '{name} menyertai permainan anda'),
  ('ms', '{going} of {capacity} players so far.', 'Setakat ini {going} daripada {capacity} pemain.'),
  ('ms', 'You were removed from a game', 'Anda telah dikeluarkan daripada permainan'),
  ('ms', 'The host changed the lineup. Find another game nearby.', 'Hos telah menukar senarai pemain. Cari permainan lain berdekatan.'),
  ('ms', '{name} invited you to play', '{name} menjemput anda bermain'),
  ('ms', 'Open Badie to join.', 'Buka Badie untuk menyertai.'),
  ('ms', '{when} · {court}. Open Badie to join.', '{when} · {court}. Buka Badie untuk menyertai.'),
  ('ms', 'Game details changed', 'Butiran permainan berubah'),
  ('ms', 'Now {when} · {court}.', 'Kini {when} · {court}.'),
  ('ms', 'The game is full', 'Permainan sudah penuh'),
  ('ms', '{when} · {court} started without the waitlist. Find another game nearby.', '{when} · {court} telah bermula tanpa senarai menunggu. Cari permainan lain berdekatan.'),
  ('th', 'Game didn’t start', 'เกมไม่ได้เริ่ม'),
  ('th', 'Room closed', 'ห้องปิดแล้ว'),
  ('th', 'The host cancelled {when} · {court}.', 'เจ้าของห้องยกเลิก {when} · {court} แล้ว'),
  ('th', 'The host closed the room.', 'เจ้าของห้องปิดห้องแล้ว'),
  ('th', '{when} · {court} didn’t fill up in time, so it was closed.', '{when} · {court} ผู้เล่นไม่ครบก่อนเวลาเริ่ม จึงปิดแล้ว'),
  ('th', 'Nothing happened for 30 minutes, so the room was closed.', 'ไม่มีความเคลื่อนไหว 30 นาที ห้องจึงปิดอัตโนมัติ'),
  ('th', 'You’re off the waitlist', 'มีที่ว่างแล้ว คุณได้เข้าร่วมเกม'),
  ('th', '{name} joined your game', '{name} เข้าร่วมเกมของคุณ'),
  ('th', '{going} of {capacity} players so far.', 'ตอนนี้มีผู้เล่น {going}/{capacity} คน'),
  ('th', 'You were removed from a game', 'คุณถูกนำออกจากเกม'),
  ('th', 'The host changed the lineup. Find another game nearby.', 'เจ้าของห้องปรับรายชื่อผู้เล่นแล้ว ลองหาเกมอื่นใกล้ ๆ นะ'),
  ('th', '{name} invited you to play', '{name} ชวนคุณมาเล่น'),
  ('th', 'Open Badie to join.', 'เปิด Badie เพื่อเข้าร่วม'),
  ('th', '{when} · {court}. Open Badie to join.', '{when} · {court} เปิด Badie เพื่อเข้าร่วม'),
  ('th', 'Game details changed', 'รายละเอียดเกมเปลี่ยนแล้ว'),
  ('th', 'Now {when} · {court}.', 'เปลี่ยนเป็น {when} · {court}'),
  ('th', 'The game is full', 'เกมเต็มแล้ว'),
  ('th', '{when} · {court} started without the waitlist. Find another game nearby.', '{when} · {court} เริ่มแล้วโดยไม่มีผู้เล่นสำรอง ลองหาเกมอื่นใกล้ ๆ นะ'),
  ('vi', 'Game didn’t start', 'Trận không diễn ra'),
  ('vi', 'Room closed', 'Phòng đã đóng'),
  ('vi', 'The host cancelled {when} · {court}.', 'Chủ phòng đã hủy {when} · {court}.'),
  ('vi', 'The host closed the room.', 'Chủ phòng đã đóng phòng.'),
  ('vi', '{when} · {court} didn’t fill up in time, so it was closed.', '{when} · {court} không đủ người trước giờ bắt đầu nên đã đóng.'),
  ('vi', 'Nothing happened for 30 minutes, so the room was closed.', 'Không có hoạt động trong 30 phút nên phòng đã tự đóng.'),
  ('vi', 'You’re off the waitlist', 'Đã có chỗ, bạn đã vào trận'),
  ('vi', '{name} joined your game', '{name} đã tham gia trận của bạn'),
  ('vi', '{going} of {capacity} players so far.', 'Hiện có {going}/{capacity} người.'),
  ('vi', 'You were removed from a game', 'Bạn đã bị mời ra khỏi trận'),
  ('vi', 'The host changed the lineup. Find another game nearby.', 'Chủ phòng đã thay đổi đội hình. Hãy tìm trận khác gần bạn.'),
  ('vi', '{name} invited you to play', '{name} mời bạn chơi'),
  ('vi', 'Open Badie to join.', 'Mở Badie để tham gia.'),
  ('vi', '{when} · {court}. Open Badie to join.', '{when} · {court}. Mở Badie để tham gia.'),
  ('vi', 'Game details changed', 'Thông tin trận đã thay đổi'),
  ('vi', 'Now {when} · {court}.', 'Giờ là {when} · {court}.'),
  ('vi', 'The game is full', 'Trận đã đủ người'),
  ('vi', '{when} · {court} started without the waitlist. Find another game nearby.', '{when} · {court} đã bắt đầu mà không có người chờ. Hãy tìm trận khác gần bạn.'),
  ('hi', 'Game didn’t start', 'गेम शुरू नहीं हुआ'),
  ('hi', 'Room closed', 'रूम बंद है'),
  ('hi', 'The host cancelled {when} · {court}.', 'होस्ट ने {when} · {court} रद्द कर दिया।'),
  ('hi', 'The host closed the room.', 'होस्ट ने रूम बंद कर दिया।'),
  ('hi', '{when} · {court} didn’t fill up in time, so it was closed.', '{when} · {court} समय पर पूरा नहीं भरा, इसलिए बंद कर दिया गया।'),
  ('hi', 'Nothing happened for 30 minutes, so the room was closed.', '30 मिनट तक कोई गतिविधि नहीं हुई, इसलिए रूम बंद हो गया।'),
  ('hi', 'You’re off the waitlist', 'जगह खाली हुई, आप गेम में शामिल हो गए'),
  ('hi', '{name} joined your game', '{name} आपके गेम में शामिल हुए'),
  ('hi', '{going} of {capacity} players so far.', 'अभी तक {capacity} में से {going} खिलाड़ी।'),
  ('hi', 'You were removed from a game', 'आपको एक गेम से हटा दिया गया'),
  ('hi', 'The host changed the lineup. Find another game nearby.', 'होस्ट ने खिलाड़ी बदल दिए। पास में कोई दूसरा गेम ढूँढें।'),
  ('hi', '{name} invited you to play', '{name} ने आपको खेलने बुलाया'),
  ('hi', 'Open Badie to join.', 'शामिल होने के लिए Badie खोलें।'),
  ('hi', '{when} · {court}. Open Badie to join.', '{when} · {court}। शामिल होने के लिए Badie खोलें।'),
  ('hi', 'Game details changed', 'गेम की जानकारी बदल गई'),
  ('hi', 'Now {when} · {court}.', 'अब {when} · {court}।'),
  ('hi', 'The game is full', 'गेम भर गया'),
  ('hi', '{when} · {court} started without the waitlist. Find another game nearby.', '{when} · {court} वेटलिस्ट के बिना शुरू हो गया। पास में कोई दूसरा गेम ढूँढें।');

-- ---------------------------------------------------------------------------
-- 权限与定时任务
-- ---------------------------------------------------------------------------

revoke execute on function public.room_capacity(public.game_mode),
  public.check_room_details(text, timestamptz, timestamptz), public.room_status_of(uuid, uuid), public.room_summary(uuid),
  public.close_room(uuid, text), public.promote_room_waitlist(uuid), public.join_room_internal(uuid, boolean), public.expire_rooms()
  from public, anon, authenticated;

revoke execute on function public.room_page(uuid), public.rooms_near(double precision, double precision, double precision), public.my_rooms(),
  public.create_room(public.game_mode, public.room_visibility, text, timestamptz, timestamptz, int, int, text[], text),
  public.join_room(uuid), public.join_room_code(text), public.leave_room(uuid), public.remove_room_member(uuid, uuid),
  public.invite_to_room(uuid, uuid[]), public.update_room(uuid, text, timestamptz, timestamptz), public.start_room(uuid)
  from public, anon;
grant execute on function public.room_page(uuid), public.rooms_near(double precision, double precision, double precision), public.my_rooms(),
  public.create_room(public.game_mode, public.room_visibility, text, timestamptz, timestamptz, int, int, text[], text),
  public.join_room(uuid), public.join_room_code(text), public.leave_room(uuid), public.remove_room_member(uuid, uuid),
  public.invite_to_room(uuid, uuid[]), public.update_room(uuid, text, timestamptz, timestamptz), public.start_room(uuid)
  to authenticated;

select cron.schedule('expire-rooms', '*/5 * * * *', 'select public.expire_rooms()');
