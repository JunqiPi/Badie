-- 教练带课的球群（docs/COACHING.md 的小版本）：
-- 1. 球群可以标成“教练带课”：每场 1–40 人（普通群还是 4–40），水平范围只作提示，谁都能加入或申请
-- 2. 收费备注放宽到 120 字，教练写价格和自己的收款方式。Badie 不经手钱
-- 3. 管理员在 SQL 编辑器里看效果：select * from public.coached_group_stats();

alter table public.play_groups add column coached boolean not null default false;

alter table public.group_schedules drop constraint group_schedules_capacity_check;
alter table public.group_schedules add constraint group_schedules_capacity_check check (capacity between 1 and 40);
alter table public.group_schedules drop constraint group_schedules_fee_note_check;
alter table public.group_schedules add constraint group_schedules_fee_note_check check (char_length(fee_note) <= 120);

-- 每周场次：1–7 个，每个 1–12 小时、按半小时、同一天内结束；人数 4–40，教练带课的群 1–40（教练不报名，人数指学员）
drop function public.valid_schedules(jsonb);
create function public.valid_schedules(p jsonb, p_coached boolean)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(jsonb_typeof(p) = 'array' and jsonb_array_length(p) between 1 and 7
    and not exists (
      select 1 from jsonb_array_elements(p) s
      cross join lateral (select coalesce((s ->> 'weekday')::int, -1) as d, coalesce((s ->> 'start')::int, -1) as a,
                                 coalesce((s ->> 'end')::int, -1) as b, coalesce((s ->> 'capacity')::int, -1) as c) x
      where x.d not between 0 and 6 or x.a not between 0 and 1410 or x.a % 30 <> 0 or x.b not between 30 and 1440 or x.b % 30 <> 0
         or x.b - x.a not between 60 and 720 or x.c not between (case when p_coached then 1 else 4 end) and 40
         or char_length(coalesce(s ->> 'fee', '')) > 120), false)
$$;
revoke execute on function public.valid_schedules(jsonb, boolean) from public, anon, authenticated;

-- 建群：多一个 p_coached（旧版 App 不传，就是普通群）
drop function public.create_group(text, text, text, int, int, public.join_policy, jsonb, public.gender);
create function public.create_group(p_name text, p_venue text, p_summary text, p_level_min int, p_level_max int,
                                    p_policy public.join_policy, p_schedules jsonb, p_gender public.gender default null,
                                    p_coached boolean default false)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  venue text;
  new_group uuid;
begin
  if me is null or not exists (select 1 from public.profiles where id = me) then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if not public.accepts(p_gender, (select gender from public.profiles where id = me)) then
    raise exception 'gender_restricted' using errcode = '22023';
  end if;
  select coalesce(merged_into, id) into venue from public.venues where id = p_venue and not hidden_pending_review;
  if venue is null then raise exception 'invalid_venues' using errcode = '22023'; end if;
  if not public.valid_schedules(p_schedules, coalesce(p_coached, false)) then raise exception 'invalid_schedule' using errcode = '22023'; end if;
  if btrim(p_name) ~* '(https?:|www\.|@|\d{5,})' or coalesce(p_summary, '') ~* '(https?:|www\.|\d{7,})' then
    raise exception 'no_contact_info' using errcode = '22023';
  end if;

  insert into public.play_groups (name, venue_id, owner_id, summary, level_min, level_max, join_policy, invite_code, gender, coached)
    values (btrim(p_name), venue, me, btrim(coalesce(p_summary, '')), p_level_min, p_level_max, p_policy, public.new_invite_code(), p_gender,
            coalesce(p_coached, false))
    returning id into new_group;
  insert into public.group_members (group_id, user_id, role) values (new_group, me, 'owner');
  insert into public.group_schedules (group_id, weekday, start_minutes, end_minutes, capacity, fee_note)
    select new_group, (s ->> 'weekday')::smallint, (s ->> 'start')::smallint, (s ->> 'end')::smallint, (s ->> 'capacity')::smallint,
           nullif(btrim(s ->> 'fee'), '')
    from jsonb_array_elements(p_schedules) s;
  -- 防刷（放在写入之后，先报具体的输入错误）：每人最多当 10 个群的群主，每天最多建 5 个
  if (select count(*) from public.play_groups where owner_id = me) > 10
     or (select count(*) from public.play_groups where owner_id = me and created_at > now() - interval '1 day') > 5 then
    raise exception 'too_many_groups' using errcode = '54000';
  end if;
  perform public.ensure_sessions(new_group);
  return new_group;
end
$$;

-- 编辑球群：p_coached 不传（旧版 App）就保持原样
drop function public.update_group(uuid, text, text, int, int, public.join_policy, jsonb);
create function public.update_group(p_group uuid, p_name text, p_summary text, p_level_min int, p_level_max int,
                                    p_policy public.join_policy, p_schedules jsonb, p_coached boolean default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  old record;
  session uuid;
  is_coached boolean;
begin
  if public.group_role_of(p_group, auth.uid()) is distinct from 'owner' then raise exception 'not_organizer' using errcode = '42501'; end if;
  is_coached := coalesce(p_coached, (select g.coached from public.play_groups g where g.id = p_group));
  if not public.valid_schedules(p_schedules, is_coached) then raise exception 'invalid_schedule' using errcode = '22023'; end if;
  if btrim(p_name) ~* '(https?:|www\.|@|\d{5,})' or coalesce(p_summary, '') ~* '(https?:|www\.|\d{7,})' then
    raise exception 'no_contact_info' using errcode = '22023';
  end if;
  update public.play_groups set name = btrim(p_name), summary = btrim(coalesce(p_summary, '')),
         level_min = p_level_min, level_max = p_level_max, join_policy = p_policy, coached = is_coached
    where id = p_group;

  for old in select s.id from public.group_schedules s where s.group_id = p_group and not exists (
               select 1 from jsonb_array_elements(p_schedules) n
               where (n ->> 'weekday')::int = s.weekday and (n ->> 'start')::int = s.start_minutes and (n ->> 'end')::int = s.end_minutes
                 and (n ->> 'capacity')::int = s.capacity and nullif(btrim(n ->> 'fee'), '') is not distinct from s.fee_note) loop
    for session in select id from public.group_sessions where schedule_id = old.id and cancelled_at is null and starts_at > now() loop
      perform public.cancel_session(session);
    end loop;
    delete from public.group_schedules where id = old.id;
  end loop;
  insert into public.group_schedules (group_id, weekday, start_minutes, end_minutes, capacity, fee_note)
    select p_group, (n ->> 'weekday')::smallint, (n ->> 'start')::smallint, (n ->> 'end')::smallint, (n ->> 'capacity')::smallint,
           nullif(btrim(n ->> 'fee'), '')
    from jsonb_array_elements(p_schedules) n
    where not exists (select 1 from public.group_schedules s
                      where s.group_id = p_group and s.weekday = (n ->> 'weekday')::int and s.start_minutes = (n ->> 'start')::int
                        and s.end_minutes = (n ->> 'end')::int and s.capacity = (n ->> 'capacity')::int
                        and s.fee_note is not distinct from nullif(btrim(n ->> 'fee'), ''));
  perform public.ensure_sessions(p_group);
end
$$;

revoke execute on function public.create_group(text, text, text, int, int, public.join_policy, jsonb, public.gender, boolean),
  public.update_group(uuid, text, text, int, int, public.join_policy, jsonb, boolean) from public, anon;
grant execute on function public.create_group(text, text, text, int, int, public.join_policy, jsonb, public.gender, boolean),
  public.update_group(uuid, text, text, int, int, public.join_policy, jsonb, boolean) to authenticated;

-- 加入：教练带课的群不看水平（范围只是提示；要筛人就用“需要审批”）
create or replace function public.join_group(p_group uuid)
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
  if not public.accepts(g.gender, (select gender from public.profiles where id = me)) then
    raise exception 'gender_restricted' using errcode = '22023';
  end if;
  level := public.audience_level(me, g.gender);
  if level is null or (not g.coached and level not between g.level_min and g.level_max) then
    raise exception 'level_out_of_range' using errcode = '22023';
  end if;
  if (select count(*) from public.group_members where user_id = me) >= 20 then raise exception 'too_many_groups' using errcode = '54000'; end if;

  insert into public.group_members (group_id, user_id, pending) values (p_group, me, g.join_policy = 'approval');
  if g.join_policy = 'approval' then
    for organizer in select user_id from public.group_members where group_id = p_group and role in ('owner', 'organizer') loop
      perform public.notify(organizer.user_id, 'group', 'Join request: {group}', '{name} wants to join.', '/app/groups/' || p_group || '/',
        jsonb_build_object('group', g.name, 'name', (select nickname from public.profiles where id = me)));
    end loop;
    return 'pending';
  end if;
  return 'member';
end
$$;

-- 球群卡片：多一个 coached
create or replace function public.group_summary(p_group uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', g.id, 'name', g.name, 'summary', g.summary, 'level_min', g.level_min, 'level_max', g.level_max, 'join_policy', g.join_policy, 'gender', g.gender,
    'coached', g.coached,
    'venue', jsonb_build_object('id', v.id, 'name', v.name, 'city', v.city, 'tz', v.time_zone_id),
    'schedules', (select jsonb_agg(jsonb_build_object('weekday', s.weekday, 'start', s.start_minutes, 'end', s.end_minutes,
                                                      'capacity', s.capacity, 'fee', s.fee_note) order by s.weekday, s.start_minutes)
                  from public.group_schedules s where s.group_id = g.id),
    'activity', public.group_activity(g.id),
    'my_role', public.group_role_of(g.id, auth.uid()))
  from public.play_groups g join public.venues v on v.id = g.venue_id
  where g.id = p_group
$$;

-- 教练带课的群带来了多少人（只有管理员在 SQL 编辑器里能查，App 里调不到）：
-- students = 学员数（不算教练和等审批的）；new_users = 加群前 24 小时内才注册的；
-- new_users_who_played = 这些新用户里，加群后 14 天内发过约球请求、进过球局或房间的
create function public.coached_group_stats()
returns table (group_name text, venue text, coach text, created date, students bigint, new_users bigint, new_users_who_played bigint)
language sql stable security definer set search_path = '' as $$
  select g.name, v.name, c.nickname, g.created_at::date,
         count(m.user_id), count(m.user_id) filter (where x.is_new), count(m.user_id) filter (where x.is_new and x.played)
  from public.play_groups g
  join public.venues v on v.id = g.venue_id
  join public.profiles c on c.id = g.owner_id
  left join public.group_members m on m.group_id = g.id and m.user_id <> g.owner_id and not m.pending
  left join public.profiles p on p.id = m.user_id
  left join lateral (
    select p.created_at > m.joined_at - interval '24 hours' as is_new,
           exists (select 1 from public.match_tickets t
                   where t.user_id = m.user_id and t.created_at between m.joined_at and m.joined_at + interval '14 days')
           or exists (select 1 from public.game_players gp join public.games ga on ga.id = gp.game_id
                      where gp.user_id = m.user_id and ga.created_at between m.joined_at and m.joined_at + interval '14 days')
           or exists (select 1 from public.room_members r
                      where r.user_id = m.user_id and r.joined_at between m.joined_at and m.joined_at + interval '14 days') as played
  ) x on true
  where g.coached
  group by g.id, v.name, c.nickname
  order by g.created_at
$$;
revoke execute on function public.coached_group_stats() from public, anon, authenticated;
