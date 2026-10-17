-- 球群（固定局）：绑定球馆的每周固定场次，一键报名、满员候补、有人退出自动递补，群聊
-- 规则与 iOS 一致（Badie-iOS/docs/DESIGN.md §12，MockBackend+Groups.swift）：
-- - 对外只显示近 30 天开了几场、平均每场几人，不显示成员总数
-- - 开场前 2 小时内退出算临时取消；退群不算（但会让出名额）
-- - 6 位群号可以发到微信，别人凭群号找到并加入；可以设成需要组织者同意
-- 和 iOS 的差别：同球群的人之间不做“消息请求”，可以互看资料、加球友，成为球友后私信

-- ---------------------------------------------------------------------------
-- 表
-- ---------------------------------------------------------------------------

create type public.join_policy as enum ('open', 'approval');
create type public.group_role as enum ('owner', 'organizer', 'member');

create table public.play_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 20),
  venue_id text not null references public.venues (id),
  owner_id uuid not null references auth.users (id) on delete cascade,
  summary text not null default '' check (char_length(summary) <= 120),
  level_min smallint not null check (level_min between 1 and 9),
  level_max smallint not null check (level_max between 1 and 9),
  join_policy public.join_policy not null default 'open',
  invite_code char(6) not null unique,
  created_at timestamptz not null default now(),
  check (level_min <= level_max)
);

create index play_groups_venue_idx on public.play_groups (venue_id);

-- pending = 等组织者同意
create table public.group_members (
  group_id uuid not null references public.play_groups (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role public.group_role not null default 'member',
  pending boolean not null default false,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create index group_members_user_idx on public.group_members (user_id);

-- 每周固定场次，按球馆当地时间：星期（0 = 周日）和从 0 点起的分钟数
create table public.group_schedules (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.play_groups (id) on delete cascade,
  weekday smallint not null check (weekday between 0 and 6),
  start_minutes smallint not null check (start_minutes between 0 and 1410 and start_minutes % 30 = 0),
  end_minutes smallint not null check (end_minutes between 30 and 1440 and end_minutes % 30 = 0),
  capacity smallint not null check (capacity between 4 and 40),
  fee_note text check (char_length(fee_note) <= 40),
  check (end_minutes - start_minutes between 60 and 480)
);

create index group_schedules_group_idx on public.group_schedules (group_id);

-- 具体的某一场（按需生成未来 14 天）
create table public.group_sessions (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.play_groups (id) on delete cascade,
  schedule_id uuid not null references public.group_schedules (id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  capacity smallint not null,
  cancelled_at timestamptz,
  unique (schedule_id, starts_at)
);

create index group_sessions_group_idx on public.group_sessions (group_id, starts_at);

-- 报名：按报名时间排队，前 capacity 名报上，其余候补
create table public.session_signups (
  session_id uuid not null references public.group_sessions (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  waitlisted boolean not null default false,
  signed_up_at timestamptz not null default clock_timestamp(),
  primary key (session_id, user_id)
);

create index session_signups_user_idx on public.session_signups (user_id);

-- 开场前 2 小时内退出（计入履约记录）
create table public.session_late_cancels (
  session_id uuid not null references public.group_sessions (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  cancelled_at timestamptz not null default now(),
  primary key (session_id, user_id)
);

alter table public.play_groups enable row level security;
alter table public.group_members enable row level security;
alter table public.group_schedules enable row level security;
alter table public.group_sessions enable row level security;
alter table public.session_signups enable row level security;
alter table public.session_late_cancels enable row level security;

revoke all on public.play_groups, public.group_members, public.group_schedules, public.group_sessions,
  public.session_signups, public.session_late_cancels from anon, authenticated;
grant all on public.play_groups, public.group_members, public.group_schedules, public.group_sessions,
  public.session_signups, public.session_late_cancels to service_role;

-- 球群聊天：“group:<球群 id>”
alter table public.messages drop constraint messages_thread_check;
alter table public.messages add constraint messages_thread_check
  check (thread ~ '^((game|group):[0-9a-f-]{36}|dm:[0-9a-f-]{36}:[0-9a-f-]{36})$');

-- ---------------------------------------------------------------------------
-- 内部工具
-- ---------------------------------------------------------------------------

create function public.group_role_of(p_group uuid, p_user uuid)
returns text language sql stable security definer set search_path = '' as $$
  select case when pending then 'pending' else role::text end from public.group_members where group_id = p_group and user_id = p_user
$$;

create function public.is_organizer(p_group uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.group_role_of(p_group, p_user) in ('owner', 'organizer'), false)
$$;

-- 生成未来 14 天的场次（已有的不重复生成），按球馆当地时间
create function public.ensure_sessions(p_group uuid)
returns void language sql security definer set search_path = '' as $$
  insert into public.group_sessions (group_id, schedule_id, starts_at, ends_at, capacity)
    select s.group_id, s.id,
           (d + make_interval(mins => s.start_minutes)) at time zone tz.name,
           (d + make_interval(mins => s.end_minutes)) at time zone tz.name, s.capacity
    from public.group_schedules s
    join public.play_groups g on g.id = s.group_id
    join public.venues v on v.id = g.venue_id
    cross join lateral (select coalesce(v.time_zone_id, 'UTC') as name) tz
    cross join lateral generate_series(date_trunc('day', now() at time zone tz.name), date_trunc('day', now() at time zone tz.name) + interval '13 days', interval '1 day') d
    where s.group_id = p_group and extract(dow from d) = s.weekday
      and (d + make_interval(mins => s.start_minutes)) at time zone tz.name > now()
  on conflict (schedule_id, starts_at) do nothing
$$;

-- 6 位群号：去掉容易看错的 0/O、1/I
create function public.new_invite_code()
returns char(6) language plpgsql set search_path = '' as $$
declare
  code text;
begin
  loop
    code := (select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::int, 1), '') from generate_series(1, 6));
    exit when not exists (select 1 from public.play_groups where invite_code = code);
  end loop;
  return code;
end
$$;

-- 候补第一位递补，并通知
create function public.promote_waitlist(p_session uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  s record;
  promoted uuid;
begin
  select gs.*, g.name, g.venue_id into s from public.group_sessions gs join public.play_groups g on g.id = gs.group_id where gs.id = p_session;
  if (select count(*) from public.session_signups where session_id = p_session and not waitlisted) >= s.capacity then return; end if;
  update public.session_signups set waitlisted = false
    where session_id = p_session and user_id = (select user_id from public.session_signups where session_id = p_session and waitlisted
                                                order by signed_up_at limit 1)
    returning user_id into promoted;
  if promoted is not null then
    perform public.notify(promoted, 'group', 'You’re in: ' || s.name,
      'A spot opened up for ' || public.slot_text(s.starts_at, s.venue_id) || '. If you can’t make it, cancel early.', '/app/groups/' || s.group_id || '/');
  end if;
end
$$;

-- 在同一个球群里也算有交集（可以互看资料、加球友、拉黑、举报）
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
$$;

-- 临时取消也算上球群场次
create or replace function public.attendance_record(p_user uuid)
returns table (games_played bigint, no_shows bigint, late_cancels bigint)
language sql stable security definer set search_path = '' as $$
  with ended as (
    select gp.checked_in_at is null and exists (
             select 1 from public.game_reviews r where r.game_id = g.id and r.reviewee_id = p_user and r.attendance = 'no_show') as no_show
    from public.game_players gp join public.games g on g.id = gp.game_id
    where gp.user_id = p_user and g.status = 'scheduled' and g.ends_at < now())
  select count(*) filter (where not no_show), count(*) filter (where no_show),
         (select count(*) from public.game_players where user_id = p_user and late_cancel)
           + (select count(*) from public.session_late_cancels where user_id = p_user)
  from ended
$$;

-- ---------------------------------------------------------------------------
-- 建群、加入、退出、管理
-- ---------------------------------------------------------------------------

-- schedules：[{weekday, start, end, capacity, fee}]，1–3 个
create function public.create_group(p_name text, p_venue text, p_summary text, p_level_min int, p_level_max int,
                                    p_policy public.join_policy, p_schedules jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  venue text;
  new_group uuid;
begin
  if me is null or not exists (select 1 from public.profiles where id = me) then raise exception 'not_signed_in' using errcode = '42501'; end if;
  select coalesce(merged_into, id) into venue from public.venues where id = p_venue and not hidden_pending_review;
  if venue is null then raise exception 'invalid_venues' using errcode = '22023'; end if;
  if jsonb_typeof(p_schedules) is distinct from 'array' or jsonb_array_length(p_schedules) not between 1 and 3 then
    raise exception 'invalid_schedule' using errcode = '22023';
  end if;
  if btrim(p_name) ~* '(https?:|www\.|@|\d{5,})' or coalesce(p_summary, '') ~* '(https?:|www\.|\d{7,})' then
    raise exception 'no_contact_info' using errcode = '22023';
  end if;

  insert into public.play_groups (name, venue_id, owner_id, summary, level_min, level_max, join_policy, invite_code)
    values (btrim(p_name), venue, me, btrim(coalesce(p_summary, '')), p_level_min, p_level_max, p_policy, public.new_invite_code())
    returning id into new_group;
  insert into public.group_members (group_id, user_id, role) values (new_group, me, 'owner');
  insert into public.group_schedules (group_id, weekday, start_minutes, end_minutes, capacity, fee_note)
    select new_group, (s ->> 'weekday')::smallint, (s ->> 'start')::smallint, (s ->> 'end')::smallint, (s ->> 'capacity')::smallint,
           nullif(btrim(s ->> 'fee'), '')
    from jsonb_array_elements(p_schedules) s;
  -- 防刷（放在写入之后，先报具体的输入错误）：每人最多当 5 个群的群主，每天最多建 2 个
  if (select count(*) from public.play_groups where owner_id = me) > 5
     or (select count(*) from public.play_groups where owner_id = me and created_at > now() - interval '1 day') > 2 then
    raise exception 'too_many_groups' using errcode = '54000';
  end if;
  perform public.ensure_sessions(new_group);
  return new_group;
end
$$;

-- 凭群号找球群
create function public.find_group(p_code text)
returns uuid language sql stable security definer set search_path = '' as $$
  select id from public.play_groups where invite_code = upper(btrim(p_code)) and auth.uid() is not null
$$;

-- 加入：水平要在范围内；需要同意的群先进待审批。返回 'member' 或 'pending'
create function public.join_group(p_group uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  g public.play_groups;
  level int;
  organizer record;
begin
  select * into g from public.play_groups where id = p_group;
  if me is null or g.id is null or public.blocked_between(me, g.owner_id) then raise exception 'group_not_found' using errcode = 'P0002'; end if;
  if exists (select 1 from public.group_members where group_id = p_group and user_id = me) then
    return public.group_role_of(p_group, me);
  end if;
  select round(rating) into level from public.profiles where id = me;
  if level is null or level not between g.level_min and g.level_max then raise exception 'level_out_of_range' using errcode = '22023'; end if;
  if (select count(*) from public.group_members where user_id = me) >= 20 then raise exception 'too_many_groups' using errcode = '54000'; end if;

  insert into public.group_members (group_id, user_id, pending) values (p_group, me, g.join_policy = 'approval');
  if g.join_policy = 'approval' then
    for organizer in select user_id from public.group_members where group_id = p_group and role in ('owner', 'organizer') loop
      perform public.notify(organizer.user_id, 'group', 'Join request: ' || g.name,
        (select nickname from public.profiles where id = me) || ' wants to join.', '/app/groups/' || p_group || '/');
    end loop;
    return 'pending';
  end if;
  return 'member';
end
$$;

-- 退出：撤掉以后的报名（不算临时取消），候补递补。群主不能退
create function public.leave_group(p_group uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  freed uuid;
begin
  if public.group_role_of(p_group, auth.uid()) = 'owner' then raise exception 'owner_cannot_leave' using errcode = '22023'; end if;
  delete from public.group_members where group_id = p_group and user_id = auth.uid();
  for freed in delete from public.session_signups s using public.group_sessions gs
                 where s.session_id = gs.id and gs.group_id = p_group and s.user_id = auth.uid() and gs.starts_at > now()
                 returning s.session_id loop
    perform public.promote_waitlist(freed);
  end loop;
end
$$;

-- 组织者：同意或拒绝加入申请（拒绝不通知）
create function public.respond_join_request(p_group uuid, p_user uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_organizer(p_group, auth.uid()) then raise exception 'not_organizer' using errcode = '42501'; end if;
  if p_accept then
    update public.group_members set pending = false, joined_at = now() where group_id = p_group and user_id = p_user and pending;
    if found then
      perform public.notify(p_user, 'group', 'Welcome to ' || (select name from public.play_groups where id = p_group),
        'Your request was approved. You can sign up for sessions now.', '/app/groups/' || p_group || '/');
    end if;
  else
    delete from public.group_members where group_id = p_group and user_id = p_user and pending;
  end if;
end
$$;

-- 组织者：移出成员（群主不能被移出），撤掉以后的报名
create function public.remove_member(p_group uuid, p_user uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  freed uuid;
begin
  if not public.is_organizer(p_group, auth.uid()) or public.group_role_of(p_group, p_user) = 'owner' or p_user = auth.uid() then
    raise exception 'not_organizer' using errcode = '42501';
  end if;
  delete from public.group_members where group_id = p_group and user_id = p_user;
  for freed in delete from public.session_signups s using public.group_sessions gs
                 where s.session_id = gs.id and gs.group_id = p_group and s.user_id = p_user and gs.starts_at > now()
                 returning s.session_id loop
    perform public.promote_waitlist(freed);
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- 报名
-- ---------------------------------------------------------------------------

-- 报名一场：有名额直接报上，满了进候补。返回 'confirmed' 或 'waitlisted'
create function public.sign_up_session(p_session uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  s public.group_sessions;
  is_full boolean;
begin
  select * into s from public.group_sessions where id = p_session and cancelled_at is null and starts_at > now() for update;
  if s.id is null then raise exception 'session_closed' using errcode = 'P0002'; end if;
  if public.group_role_of(s.group_id, me) is null or public.group_role_of(s.group_id, me) = 'pending' then
    raise exception 'not_member' using errcode = '42501';
  end if;
  if exists (select 1 from public.session_signups where session_id = p_session and user_id = me) then
    return (select case when waitlisted then 'waitlisted' else 'confirmed' end from public.session_signups where session_id = p_session and user_id = me);
  end if;
  is_full := (select count(*) from public.session_signups where session_id = p_session and not waitlisted) >= s.capacity;
  insert into public.session_signups (session_id, user_id, waitlisted) values (p_session, me, is_full);
  return case when is_full then 'waitlisted' else 'confirmed' end;
end
$$;

-- 取消报名：开场前 2 小时内退出算临时取消；候补第一位自动递补
create function public.cancel_signup(p_session uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  s public.group_sessions;
  was_waitlisted boolean;
begin
  select * into s from public.group_sessions where id = p_session and cancelled_at is null and ends_at > now() for update;
  if s.id is null then raise exception 'session_closed' using errcode = 'P0002'; end if;
  delete from public.session_signups where session_id = p_session and user_id = auth.uid() returning waitlisted into was_waitlisted;
  if was_waitlisted is null or was_waitlisted then return; end if;
  if s.starts_at - now() < interval '2 hours' then
    insert into public.session_late_cancels (session_id, user_id) values (p_session, auth.uid()) on conflict do nothing;
  end if;
  if s.starts_at > now() then perform public.promote_waitlist(p_session); end if;
end
$$;

-- 组织者取消某一场（不影响任何人的记录）
create function public.cancel_session(p_session uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  s record;
  player record;
begin
  select gs.*, g.name, g.venue_id into s from public.group_sessions gs join public.play_groups g on g.id = gs.group_id
    where gs.id = p_session and gs.cancelled_at is null and gs.starts_at > now();
  if s.id is null then raise exception 'session_closed' using errcode = 'P0002'; end if;
  if not public.is_organizer(s.group_id, auth.uid()) then raise exception 'not_organizer' using errcode = '42501'; end if;
  update public.group_sessions set cancelled_at = now() where id = p_session;
  for player in select user_id from public.session_signups where session_id = p_session and user_id <> auth.uid() loop
    perform public.notify(player.user_id, 'group', 'Session cancelled: ' || s.name,
      public.slot_text(s.starts_at, s.venue_id) || ' was cancelled by the organizer. Nothing counts against you.', '/app/groups/' || s.group_id || '/');
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- 页面数据
-- ---------------------------------------------------------------------------

-- 近 30 天开了几场、平均每场几人（对外只显示这个）
create function public.group_activity(p_group uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('sessions', count(*),
                            'average', coalesce(round(avg((select count(*) from public.session_signups su where su.session_id = s.id and not su.waitlisted)), 1), 0))
  from public.group_sessions s
  where s.group_id = p_group and s.cancelled_at is null and s.ends_at <= now() and s.ends_at > now() - interval '30 days'
$$;

-- 球群卡片（列表用）
create function public.group_summary(p_group uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', g.id, 'name', g.name, 'summary', g.summary, 'level_min', g.level_min, 'level_max', g.level_max, 'join_policy', g.join_policy,
    'venue', jsonb_build_object('id', v.id, 'name', v.name, 'city', v.city, 'tz', v.time_zone_id),
    'schedules', (select jsonb_agg(jsonb_build_object('weekday', s.weekday, 'start', s.start_minutes, 'end', s.end_minutes,
                                                      'capacity', s.capacity, 'fee', s.fee_note) order by s.weekday, s.start_minutes)
                  from public.group_schedules s where s.group_id = g.id),
    'activity', public.group_activity(g.id),
    'my_role', public.group_role_of(g.id, auth.uid()))
  from public.play_groups g join public.venues v on v.id = g.venue_id
  where g.id = p_group
$$;

-- 球群页：非成员只看到名额数；成员能看到谁报了名、成员名单、群号；组织者还能看到加入申请
create function public.group_page(p_group uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  role text := public.group_role_of(p_group, me);
  member boolean := role in ('owner', 'organizer', 'member');
begin
  if me is null or not exists (select 1 from public.play_groups g where g.id = p_group and not public.blocked_between(me, g.owner_id)) then
    return null;
  end if;
  perform public.ensure_sessions(p_group);
  return public.group_summary(p_group) || jsonb_build_object(
    'invite_code', case when member then (select invite_code from public.play_groups where id = p_group) end,
    'sessions', coalesce((select jsonb_agg(jsonb_build_object(
        'id', s.id, 'starts_at', s.starts_at, 'ends_at', s.ends_at, 'capacity', s.capacity, 'cancelled', s.cancelled_at is not null,
        'confirmed', (select count(*) from public.session_signups su where su.session_id = s.id and not su.waitlisted),
        'waitlist', (select count(*) from public.session_signups su where su.session_id = s.id and su.waitlisted),
        'my_status', (select case when not su.waitlisted then 'confirmed'
                                  else 'waitlisted:' || (select count(*) from public.session_signups w
                                                         where w.session_id = s.id and w.waitlisted and w.signed_up_at <= su.signed_up_at) end
                      from public.session_signups su where su.session_id = s.id and su.user_id = me),
        'players', case when member then (select jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname, 'waitlisted', su.waitlisted)
                                                           order by su.waitlisted, su.signed_up_at)
                                          from public.session_signups su join public.profiles p on p.id = su.user_id where su.session_id = s.id) end)
        order by s.starts_at)
      from public.group_sessions s where s.group_id = p_group and s.ends_at > now() and s.starts_at < now() + interval '14 days'), '[]'),
    'members', case when member then (select jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', p.rating, 'role', m.role)
                                                       order by m.role, lower(p.nickname))
                                      from public.group_members m join public.profiles p on p.id = m.user_id
                                      where m.group_id = p_group and not m.pending) end,
    'pending', case when role in ('owner', 'organizer') then (
        select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', p.rating) order by m.joined_at), '[]')
        from public.group_members m join public.profiles p on p.id = m.user_id where m.group_id = p_group and m.pending) end);
end
$$;

-- 我的球群和接下来报名的场次
create function public.my_groups()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  g uuid;
begin
  for g in select group_id from public.group_members where user_id = auth.uid() and not pending loop
    perform public.ensure_sessions(g);
  end loop;
  return jsonb_build_object(
    'groups', coalesce((select jsonb_agg(public.group_summary(m.group_id) order by m.joined_at)
                        from public.group_members m where m.user_id = auth.uid()), '[]'),
    'sessions', coalesce((select jsonb_agg(jsonb_build_object(
        'id', s.id, 'group_id', g.id, 'group', g.name, 'venue', v.name, 'tz', v.time_zone_id,
        'starts_at', s.starts_at, 'ends_at', s.ends_at, 'waitlisted', su.waitlisted) order by s.starts_at)
      from public.session_signups su join public.group_sessions s on s.id = su.session_id
      join public.play_groups g on g.id = s.group_id join public.venues v on v.id = g.venue_id
      where su.user_id = auth.uid() and s.cancelled_at is null and s.ends_at > now()), '[]'));
end
$$;

-- 附近的球群（按近 30 天场次排序）；不含拉黑关系的群主
create function public.groups_near(lat double precision, lng double precision, radius_km double precision default 30)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(item order by (item -> 'activity' ->> 'sessions')::int desc, item ->> 'name'), '[]')
  from (select public.group_summary(g.id) as item
        from public.play_groups g join public.venues v on v.id = g.venue_id
        where extensions.st_dwithin(v.location, extensions.st_makepoint(groups_near.lng, groups_near.lat)::extensions.geography,
                                    least(radius_km, 100) * 1000)
          and not public.blocked_between(auth.uid(), g.owner_id)
        limit 50) x
  where auth.uid() is not null
$$;

-- ---------------------------------------------------------------------------
-- 群聊：成员可以看、可以发
-- ---------------------------------------------------------------------------

create or replace function public.thread_key(p_kind text, p_id uuid)
returns text language sql stable set search_path = '' as $$
  select case p_kind when 'game' then 'game:' || p_id
                     when 'group' then 'group:' || p_id
                     when 'dm' then 'dm:' || least(auth.uid(), p_id) || ':' || greatest(auth.uid(), p_id) end
$$;

create or replace function public.thread_access(p_kind text, p_id uuid, p_user uuid)
returns text language sql stable security definer set search_path = '' as $$
  select case p_kind
    when 'game' then (
      select case when g.status = 'scheduled' and now() <= g.ends_at + interval '48 hours' then 'open' else 'closed' end
      from public.games g join public.game_players gp on gp.game_id = g.id and gp.user_id = p_user where g.id = p_id)
    when 'group' then case when public.group_role_of(p_id, p_user) in ('owner', 'organizer', 'member') then 'open' end
    when 'dm' then case
      when p_user = p_id then null
      when public.are_friends(p_user, p_id) and not public.blocked_between(p_user, p_id) then 'open'
      when exists (select 1 from public.messages where thread = 'dm:' || least(p_user, p_id) || ':' || greatest(p_user, p_id)) then 'closed'
      end
    end
$$;

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
    'game', (select jsonb_build_object('starts_at', g.starts_at, 'ends_at', g.ends_at, 'venue', v.name, 'tz', v.time_zone_id)
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

-- 会话列表：球群聊天、有消息的私信、最近 30 天的球局群聊（开着的或有消息的）。name：球群名或对方昵称
create or replace function public.my_threads()
returns jsonb language sql stable security definer set search_path = '' as $$
  with threads as (
    select 'game' as kind, g.id, 'game:' || g.id as thread, g.starts_at, v.name as venue, v.time_zone_id as tz, null::text as name,
           case when g.status = 'scheduled' and now() <= g.ends_at + interval '48 hours' then 'open' else 'closed' end as access
    from public.game_players gp join public.games g on g.id = gp.game_id join public.venues v on v.id = g.venue_id
    where gp.user_id = auth.uid() and g.ends_at > now() - interval '30 days'
    union all
    select 'group', g.id, 'group:' || g.id, null, v.name, v.time_zone_id, g.name, 'open'
    from public.group_members m join public.play_groups g on g.id = m.group_id join public.venues v on v.id = g.venue_id
    where m.user_id = auth.uid() and not m.pending
    union all
    select 'dm', p.id, 'dm:' || least(auth.uid(), p.id) || ':' || greatest(auth.uid(), p.id), null, null, null, p.nickname,
           case when public.blocked_between(auth.uid(), p.id) then 'closed' else 'open' end
    from public.friendships f join public.profiles p on p.id = case when f.user_a = auth.uid() then f.user_b else f.user_a end
    where auth.uid() in (f.user_a, f.user_b))
  select coalesce(jsonb_agg(jsonb_build_object(
      'kind', t.kind, 'id', t.id, 'starts_at', t.starts_at, 'venue', t.venue, 'tz', t.tz, 'name', t.name, 'access', t.access,
      'last', (select jsonb_build_object('body', m.body, 'created_at', m.created_at, 'mine', m.sender_id = auth.uid()) from public.messages m
               where m.thread = t.thread order by m.id desc limit 1),
      'unread', (select count(*) from public.messages m where m.thread = t.thread and m.sender_id <> auth.uid()
                 and m.id > coalesce((select last_read_id from public.thread_reads r where r.user_id = auth.uid() and r.thread = t.thread), 0)))
    order by coalesce((select max(m.created_at) from public.messages m where m.thread = t.thread), t.starts_at, '-infinity') desc), '[]')
  from threads t
  where (t.kind in ('game', 'group') and t.access = 'open') or exists (select 1 from public.messages m where m.thread = t.thread)
$$;

-- ---------------------------------------------------------------------------
-- 权限与定时任务
-- ---------------------------------------------------------------------------

revoke execute on function public.group_role_of(uuid, uuid), public.is_organizer(uuid, uuid), public.ensure_sessions(uuid),
  public.new_invite_code(), public.promote_waitlist(uuid), public.group_activity(uuid), public.group_summary(uuid)
  from public, anon, authenticated;

revoke execute on function public.create_group(text, text, text, int, int, public.join_policy, jsonb), public.find_group(text),
  public.join_group(uuid), public.leave_group(uuid), public.respond_join_request(uuid, uuid, boolean), public.remove_member(uuid, uuid),
  public.sign_up_session(uuid), public.cancel_signup(uuid), public.cancel_session(uuid), public.group_page(uuid), public.my_groups(),
  public.groups_near(double precision, double precision, double precision)
  from public, anon;
grant execute on function public.create_group(text, text, text, int, int, public.join_policy, jsonb), public.find_group(text),
  public.join_group(uuid), public.leave_group(uuid), public.respond_join_request(uuid, uuid, boolean), public.remove_member(uuid, uuid),
  public.sign_up_session(uuid), public.cancel_signup(uuid), public.cancel_session(uuid), public.group_page(uuid), public.my_groups(),
  public.groups_near(double precision, double precision, double precision)
  to authenticated;

-- 每小时把各球群未来 14 天的场次补齐
select cron.schedule('ensure-group-sessions', '7 * * * *', 'select public.ensure_sessions(id) from public.play_groups');
