-- 一个球群可以有几个球馆（最多 5 个）：
-- 1. group_venues 存球群所有的球馆，position 0 是主球馆；play_groups.venue_id 一直等于主球馆（旧版 App 只认它）
-- 2. 每周场次可以选在哪个球馆（group_schedules.venue_id，空 = 主球馆）；生成场次时把球馆写进 group_sessions.venue_id，
--    以后改主球馆、删球馆，已经生成的场次不会悄悄换地方
-- 3. 建群、编辑多一个 p_venues（按顺序的全部球馆，第一个是主球馆）；场次 jsonb 里可以带 "venue"
-- 4. group_summary 多 "venues"，场次多 "venue"；group_page 的每一场多 "venue"（这一场实际在哪个球馆）
-- 5. groups_near：任何一个球馆在范围内都算，按最近那个球馆的距离排（"distance_m"）

create table public.group_venues (
  group_id uuid not null references public.play_groups (id) on delete cascade,
  venue_id text not null references public.venues (id),
  position smallint not null check (position between 0 and 4),
  primary key (group_id, venue_id),
  unique (group_id, position)
);
create index group_venues_venue_idx on public.group_venues (venue_id);

-- 和 play_groups 一样：客户端不能直接读写，只能通过下面的函数
alter table public.group_venues enable row level security;
revoke all on public.group_venues from anon, authenticated;
grant all on public.group_venues to service_role;

insert into public.group_venues (group_id, venue_id, position) select id, venue_id, 0 from public.play_groups;

alter table public.group_schedules add column venue_id text references public.venues (id);
alter table public.group_sessions add column venue_id text references public.venues (id);
create index group_schedules_venue_idx on public.group_schedules (venue_id);
create index group_sessions_venue_idx on public.group_sessions (venue_id);
-- 已经生成的场次都在主球馆
update public.group_sessions s set venue_id = g.venue_id from public.play_groups g where g.id = s.group_id and s.venue_id is null;

-- 球群的球馆：按顺序，第一个是主球馆
create function public.group_courts(p_group uuid)
returns text[] language sql stable set search_path = '' as $$
  select coalesce(array_agg(venue_id order by position), '{}') from public.group_venues where group_id = p_group
$$;

-- 检查要设的球馆：1–5 个、不重复、都存在、没在待审核；合并过的换成合并后的。不合格返回 null
create function public.resolve_group_courts(p_venues text[])
returns text[] language plpgsql stable set search_path = '' as $$
declare
  result text[] := '{}'::text[];
  item text;
  resolved text;
begin
  if p_venues is null or cardinality(p_venues) not between 1 and 5
     or cardinality(p_venues) <> (select count(distinct x) from unnest(p_venues) x) then
    return null;
  end if;
  foreach item in array p_venues loop
    select coalesce(v.merged_into, v.id) into resolved from public.venues v where v.id = item and not v.hidden_pending_review;
    if resolved is null then return null; end if;
    -- 两个都合并进同一家：只算一次
    if not resolved = any(result) then result := result || resolved; end if;
  end loop;
  return result;
end
$$;

-- 把场次 jsonb 里的 "venue" 换成要存的值：主球馆存 null，别的球馆存 id。
-- p_old：编辑前的球馆，场次指向已经删掉的球馆时回到主球馆；p_group：编辑时，旧版 App 不带 "venue"，就沿用同一时间的那一场原来的球馆
create function public.normalize_group_schedules(p_schedules jsonb, p_courts text[], p_old text[], p_group uuid)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  result jsonb := '[]'::jsonb;
  item jsonb;
  raw text;
  court text;
begin
  for item in select value from jsonb_array_elements(p_schedules) loop
    if item ? 'venue' and jsonb_typeof(item -> 'venue') not in ('string', 'null') then
      raise exception 'invalid_schedule' using errcode = '22023';
    end if;
    raw := nullif(btrim(item ->> 'venue'), '');
    if raw is not null then
      select coalesce(v.merged_into, v.id) into court from public.venues v where v.id = raw;
      if court = any(p_courts) then
        null;
      elsif raw = any(coalesce(p_old, '{}')) or court = any(coalesce(p_old, '{}')) then
        court := null;
      else
        raise exception 'invalid_schedule' using errcode = '22023';
      end if;
    elsif not item ? 'venue' and p_group is not null then
      select s.venue_id into court from public.group_schedules s
        where s.group_id = p_group and s.weekday = (item ->> 'weekday')::int and s.start_minutes = (item ->> 'start')::int
          and s.end_minutes = (item ->> 'end')::int and s.capacity = (item ->> 'capacity')::int
          and s.fee_note is not distinct from nullif(btrim(item ->> 'fee'), '')
        order by s.venue_id nulls first limit 1;
      if not court = any(p_courts) then court := null; end if;
    else
      court := null;
    end if;
    if court = p_courts[1] then court := null; end if;
    result := result || jsonb_build_array(item || jsonb_build_object('venue', court));
  end loop;
  return result;
end
$$;

revoke execute on function public.group_courts(uuid), public.resolve_group_courts(text[]),
  public.normalize_group_schedules(jsonb, text[], text[], uuid) from public, anon, authenticated;

-- 生成场次：每一场记下在哪个球馆，按那个球馆的时区算
create or replace function public.ensure_sessions(p_group uuid)
returns void language sql security definer set search_path = '' as $$
  insert into public.group_sessions (group_id, schedule_id, starts_at, ends_at, capacity, venue_id)
    select s.group_id, s.id,
           (d + make_interval(mins => s.start_minutes)) at time zone tz.name,
           (d + make_interval(mins => s.end_minutes)) at time zone tz.name, s.capacity, v.id
    from public.group_schedules s
    join public.play_groups g on g.id = s.group_id
    join public.venues v on v.id = coalesce(s.venue_id, g.venue_id)
    cross join lateral (select coalesce(v.time_zone_id, 'UTC') as name) tz
    cross join lateral generate_series(date_trunc('day', now() at time zone tz.name), date_trunc('day', now() at time zone tz.name) + interval '13 days', interval '1 day') d
    where s.group_id = p_group and extract(dow from d) = s.weekday
      and (d + make_interval(mins => s.start_minutes)) at time zone tz.name > now()
  on conflict (schedule_id, starts_at) do nothing
$$;

-- 建群：多一个 p_venues（全部球馆，第一个是主球馆）。旧版 App 只传 p_venue，就是只有这一个球馆
drop function public.create_group(text, text, text, int, int, public.join_policy, jsonb, public.gender, boolean);
create function public.create_group(p_name text, p_venue text, p_summary text, p_level_min int, p_level_max int,
                                    p_policy public.join_policy, p_schedules jsonb, p_gender public.gender default null,
                                    p_coached boolean default false, p_venues text[] default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  courts text[];
  items jsonb;
  new_group uuid;
begin
  if me is null or not exists (select 1 from public.profiles where id = me) then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if not public.accepts(p_gender, (select gender from public.profiles where id = me)) then
    raise exception 'gender_restricted' using errcode = '22023';
  end if;
  courts := public.resolve_group_courts(coalesce(p_venues, array[p_venue]));
  if courts is null then raise exception 'invalid_venues' using errcode = '22023'; end if;
  if not public.valid_schedules(p_schedules, coalesce(p_coached, false)) then raise exception 'invalid_schedule' using errcode = '22023'; end if;
  items := public.normalize_group_schedules(p_schedules, courts, null, null);
  if btrim(p_name) ~* '(https?:|www\.|@|\d{5,})' or coalesce(p_summary, '') ~* '(https?:|www\.|\d{7,})' then
    raise exception 'no_contact_info' using errcode = '22023';
  end if;

  insert into public.play_groups (name, venue_id, owner_id, summary, level_min, level_max, join_policy, invite_code, gender, coached)
    values (btrim(p_name), courts[1], me, btrim(coalesce(p_summary, '')), p_level_min, p_level_max, p_policy, public.new_invite_code(), p_gender,
            coalesce(p_coached, false))
    returning id into new_group;
  insert into public.group_venues (group_id, venue_id, position)
    select new_group, c, (n - 1)::smallint from unnest(courts) with ordinality as x (c, n);
  insert into public.group_members (group_id, user_id, role) values (new_group, me, 'owner');
  insert into public.group_schedules (group_id, weekday, start_minutes, end_minutes, capacity, fee_note, venue_id)
    select new_group, (s ->> 'weekday')::smallint, (s ->> 'start')::smallint, (s ->> 'end')::smallint, (s ->> 'capacity')::smallint,
           nullif(btrim(s ->> 'fee'), ''), s ->> 'venue'
    from jsonb_array_elements(items) s;
  -- 防刷（放在写入之后，先报具体的输入错误）：每人最多当 10 个群的群主，每天最多建 5 个
  if (select count(*) from public.play_groups where owner_id = me) > 10
     or (select count(*) from public.play_groups where owner_id = me and created_at > now() - interval '1 day') > 5 then
    raise exception 'too_many_groups' using errcode = '54000';
  end if;
  perform public.ensure_sessions(new_group);
  return new_group;
end
$$;

-- 群主编辑：多一个 p_venues（null = 球馆不变）。场次没变的保留；去掉或改了的（包括换球馆），以后的场次取消（报了名的人收到通知），再按新的生成。
-- 删掉的球馆上的场次回到主球馆，已经生成、还没开始的那几场也一起改到主球馆
drop function public.update_group(uuid, text, text, int, int, public.join_policy, jsonb, boolean);
create function public.update_group(p_group uuid, p_name text, p_summary text, p_level_min int, p_level_max int,
                                    p_policy public.join_policy, p_schedules jsonb, p_coached boolean default null,
                                    p_venues text[] default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  old record;
  session uuid;
  is_coached boolean;
  before text[];
  courts text[];
  items jsonb;
begin
  if public.group_role_of(p_group, auth.uid()) is distinct from 'owner' then raise exception 'not_organizer' using errcode = '42501'; end if;
  before := public.group_courts(p_group);
  if p_venues is null then
    courts := before;
  else
    courts := public.resolve_group_courts(p_venues);
    if courts is null then raise exception 'invalid_venues' using errcode = '22023'; end if;
  end if;
  is_coached := coalesce(p_coached, (select g.coached from public.play_groups g where g.id = p_group));
  if not public.valid_schedules(p_schedules, is_coached) then raise exception 'invalid_schedule' using errcode = '22023'; end if;
  if btrim(p_name) ~* '(https?:|www\.|@|\d{5,})' or coalesce(p_summary, '') ~* '(https?:|www\.|\d{7,})' then
    raise exception 'no_contact_info' using errcode = '22023';
  end if;

  if courts is distinct from before then
    -- 主球馆换了：原来写“主球馆”的场次还在原来的球馆
    if courts[1] is distinct from before[1] and before[1] = any(courts) then
      update public.group_schedules set venue_id = before[1] where group_id = p_group and venue_id is null;
    end if;
    -- 删掉的球馆：那里的场次回到主球馆，还没开始的场次也改过去
    update public.group_schedules set venue_id = null where group_id = p_group and not venue_id = any(courts);
    update public.group_sessions s set venue_id = coalesce(sc.venue_id, courts[1])
      from public.group_schedules sc
      where sc.id = s.schedule_id and s.group_id = p_group and s.starts_at > now() and not s.venue_id = any(courts);
    update public.group_schedules set venue_id = null where group_id = p_group and venue_id = courts[1];
    delete from public.group_venues where group_id = p_group;
    insert into public.group_venues (group_id, venue_id, position)
      select p_group, c, (n - 1)::smallint from unnest(courts) with ordinality as x (c, n);
  end if;
  items := public.normalize_group_schedules(p_schedules, courts, before, p_group);

  update public.play_groups set name = btrim(p_name), summary = btrim(coalesce(p_summary, '')),
         level_min = p_level_min, level_max = p_level_max, join_policy = p_policy, coached = is_coached, venue_id = courts[1]
    where id = p_group;

  for old in select s.id from public.group_schedules s where s.group_id = p_group and not exists (
               select 1 from jsonb_array_elements(items) n
               where (n ->> 'weekday')::int = s.weekday and (n ->> 'start')::int = s.start_minutes and (n ->> 'end')::int = s.end_minutes
                 and (n ->> 'capacity')::int = s.capacity and nullif(btrim(n ->> 'fee'), '') is not distinct from s.fee_note
                 and (n ->> 'venue') is not distinct from s.venue_id) loop
    for session in select id from public.group_sessions where schedule_id = old.id and cancelled_at is null and starts_at > now() loop
      perform public.cancel_session(session);
    end loop;
    delete from public.group_schedules where id = old.id;
  end loop;
  insert into public.group_schedules (group_id, weekday, start_minutes, end_minutes, capacity, fee_note, venue_id)
    select p_group, (n ->> 'weekday')::smallint, (n ->> 'start')::smallint, (n ->> 'end')::smallint, (n ->> 'capacity')::smallint,
           nullif(btrim(n ->> 'fee'), ''), n ->> 'venue'
    from jsonb_array_elements(items) n
    where not exists (select 1 from public.group_schedules s
                      where s.group_id = p_group and s.weekday = (n ->> 'weekday')::int and s.start_minutes = (n ->> 'start')::int
                        and s.end_minutes = (n ->> 'end')::int and s.capacity = (n ->> 'capacity')::int
                        and s.fee_note is not distinct from nullif(btrim(n ->> 'fee'), '')
                        and s.venue_id is not distinct from (n ->> 'venue'));
  perform public.ensure_sessions(p_group);
end
$$;

revoke execute on function public.create_group(text, text, text, int, int, public.join_policy, jsonb, public.gender, boolean, text[]),
  public.update_group(uuid, text, text, int, int, public.join_policy, jsonb, boolean, text[]) from public, anon;
grant execute on function public.create_group(text, text, text, int, int, public.join_policy, jsonb, public.gender, boolean, text[]),
  public.update_group(uuid, text, text, int, int, public.join_policy, jsonb, boolean, text[]) to authenticated;

-- 球群信息：原来的键都在（"venue" 是主球馆），多 "venues"（按顺序，第一个是主球馆）；每个每周场次多 "venue"（null = 主球馆）
create or replace function public.group_summary(p_group uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', g.id, 'name', g.name, 'summary', g.summary, 'level_min', g.level_min, 'level_max', g.level_max, 'join_policy', g.join_policy, 'gender', g.gender,
    'coached', g.coached,
    'venue', jsonb_build_object('id', v.id, 'name', v.name, 'city', v.city, 'tz', v.time_zone_id),
    'venues', (select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'city', c.city, 'tz', c.time_zone_id) order by gv.position)
               from public.group_venues gv join public.venues c on c.id = gv.venue_id where gv.group_id = g.id),
    'schedules', (select jsonb_agg(jsonb_build_object('weekday', s.weekday, 'start', s.start_minutes, 'end', s.end_minutes,
                                                      'capacity', s.capacity, 'fee', s.fee_note, 'venue', s.venue_id) order by s.weekday, s.start_minutes)
                  from public.group_schedules s where s.group_id = g.id),
    'activity', public.group_activity(g.id),
    'my_role', public.group_role_of(g.id, auth.uid()))
  from public.play_groups g join public.venues v on v.id = g.venue_id
  where g.id = p_group
$$;

-- 附近的球群：任何一个球馆在范围内都算；"distance_m" 是到最近那个球馆的距离，近的在前
create or replace function public.groups_near(lat double precision, lng double precision, radius_km double precision default 30)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(y.item || jsonb_build_object('distance_m', round(x.distance)::int)
                            order by round(x.distance), (y.item -> 'activity' ->> 'sessions')::int desc, y.item ->> 'name'), '[]')
  from (select g.id, min(extensions.st_distance(v.location, here.point)) as distance
        from public.play_groups g
        join public.group_venues gv on gv.group_id = g.id
        join public.venues v on v.id = gv.venue_id
        cross join (select extensions.st_makepoint(groups_near.lng, groups_near.lat)::extensions.geography as point) here
        where extensions.st_dwithin(v.location, here.point, least(radius_km, 100) * 1000)
          and not public.blocked_between(auth.uid(), g.owner_id)
          and public.accepts(g.gender, (select gender from public.profiles where id = auth.uid()))
        group by g.id
        order by distance, g.id
        limit 50) x
  cross join lateral (select public.group_summary(x.id) as item) y
  where auth.uid() is not null
$$;

-- 球群页：每一场多 "venue"（这一场在哪个球馆的 id）
create or replace function public.group_page(p_group uuid)
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
        'venue', coalesce(s.venue_id, g.venue_id),
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
      from public.group_sessions s join public.play_groups g on g.id = s.group_id
      where s.group_id = p_group and s.ends_at > now() and s.starts_at < now() + interval '14 days'), '[]'),
    'members', case when member then (select jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', p.rating, 'role', m.role)
                                                       order by m.role, lower(p.nickname))
                                      from public.group_members m join public.profiles p on p.id = m.user_id
                                      where m.group_id = p_group and not m.pending) end,
    'pending', case when role in ('owner', 'organizer') then (
        select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', p.rating) order by m.joined_at), '[]')
        from public.group_members m join public.profiles p on p.id = m.user_id where m.group_id = p_group and m.pending) end);
end
$$;

-- 我报名的场次：球馆是这一场实际的球馆（"venue" 还是名字，多一个 "venue_id"）
create or replace function public.my_groups()
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
        'id', s.id, 'group_id', g.id, 'group', g.name, 'venue', v.name, 'venue_id', v.id, 'tz', v.time_zone_id,
        'starts_at', s.starts_at, 'ends_at', s.ends_at, 'waitlisted', su.waitlisted) order by s.starts_at)
      from public.session_signups su join public.group_sessions s on s.id = su.session_id
      join public.play_groups g on g.id = s.group_id join public.venues v on v.id = coalesce(s.venue_id, g.venue_id)
      where su.user_id = auth.uid() and s.cancelled_at is null and s.ends_at > now()), '[]'));
end
$$;

-- 通知里的球馆用这一场实际的球馆
create or replace function public.cancel_session(p_session uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  s record;
  player record;
begin
  select gs.id, gs.group_id, gs.starts_at, g.name, coalesce(gs.venue_id, g.venue_id) as court into s
    from public.group_sessions gs join public.play_groups g on g.id = gs.group_id
    where gs.id = p_session and gs.cancelled_at is null and gs.starts_at > now();
  if s.id is null then raise exception 'session_closed' using errcode = 'P0002'; end if;
  if not public.is_organizer(s.group_id, auth.uid()) then raise exception 'not_organizer' using errcode = '42501'; end if;
  update public.group_sessions set cancelled_at = now() where id = p_session;
  for player in select user_id from public.session_signups where session_id = p_session and user_id <> auth.uid() loop
    perform public.notify(player.user_id, 'group', 'Session cancelled: {group}',
      '{when} · {court} was cancelled by the organizer. Nothing counts against you.', '/app/groups/' || s.group_id || '/',
      public.slot(s.starts_at, s.court) || jsonb_build_object('group', s.name));
  end loop;
end
$$;

create or replace function public.promote_waitlist(p_session uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  s record;
  promoted uuid;
begin
  -- 锁住场次：两个人同时退出时只递补一次、不会补错人
  perform 1 from public.group_sessions where id = p_session for update;
  select gs.id, gs.group_id, gs.starts_at, gs.capacity, g.name, coalesce(gs.venue_id, g.venue_id) as court into s
    from public.group_sessions gs join public.play_groups g on g.id = gs.group_id where gs.id = p_session;
  if (select count(*) from public.session_signups where session_id = p_session and not waitlisted) >= s.capacity then return; end if;
  update public.session_signups set waitlisted = false
    where session_id = p_session and waitlisted and user_id = (select user_id from public.session_signups where session_id = p_session and waitlisted
                                                order by signed_up_at limit 1)
    returning user_id into promoted;
  if promoted is not null then
    perform public.notify(promoted, 'group', 'You’re in: {group}', 'A spot opened up for {when} · {court}. If you can’t make it, cancel early.',
      '/app/groups/' || s.group_id || '/', public.slot(s.starts_at, s.court) || jsonb_build_object('group', s.name));
  end if;
end
$$;
