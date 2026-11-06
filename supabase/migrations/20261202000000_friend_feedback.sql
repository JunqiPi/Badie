-- 朋友试用后的一批改动：
-- 1. 约球、开局、约战可以选未来 30 天（原来 14 天）；约球时间段最长 16 小时（“任何时间”）
-- 2. 约球请求可以修改：取消旧的、提交新的在同一个事务里，新的不合格就都不变
-- 3. 球群：每周场次最多 7 个，时长不对时给出能看懂的错误；群主可以编辑球群和场次、解散球群；每人最多当 10 个群的群主

-- 每周场次：1–7 个，每个 1–8 小时、按半小时、同一天内结束
create function public.valid_schedules(p jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(jsonb_typeof(p) = 'array' and jsonb_array_length(p) between 1 and 7
    and not exists (
      select 1 from jsonb_array_elements(p) s
      cross join lateral (select coalesce((s ->> 'weekday')::int, -1) as d, coalesce((s ->> 'start')::int, -1) as a,
                                 coalesce((s ->> 'end')::int, -1) as b, coalesce((s ->> 'capacity')::int, -1) as c) x
      where x.d not between 0 and 6 or x.a not between 0 and 1410 or x.a % 30 <> 0 or x.b not between 30 and 1440 or x.b % 30 <> 0
         or x.b - x.a not between 60 and 480 or x.c not between 4 and 40 or char_length(coalesce(s ->> 'fee', '')) > 40), false)
$$;

-- 改场次时删掉旧的每周安排，已经过去的场次留着（报名和出勤记录还要用）
alter table public.group_sessions alter column schedule_id drop not null;
alter table public.group_sessions drop constraint group_sessions_schedule_id_fkey;
alter table public.group_sessions add constraint group_sessions_schedule_id_fkey
  foreign key (schedule_id) references public.group_schedules (id) on delete set null;

create or replace function public.submit_ticket(p_mode public.game_mode, p_starts_at timestamptz, p_ends_at timestamptz,
                                     p_venue_ids text[], p_skill_tolerance int, p_auto_accept boolean,
                                     p_play_with public.gender default null, p_mixed boolean default false)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  my_gender public.gender;
  venues text[];
  hurried boolean := p_starts_at < now() + interval '150 minutes';
  new_ticket uuid;
begin
  if me is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if not exists (select 1 from public.profiles where id = me) then raise exception 'no_profile' using errcode = 'P0002'; end if;
  select gender into my_gender from public.profiles where id = me;
  if p_mixed and (p_mode <> 'doubles' or p_play_with is not null or my_gender is null) then
    raise exception 'invalid_event' using errcode = '22023';
  end if;
  if p_play_with is not null and p_play_with is distinct from my_gender then
    raise exception 'gender_restricted' using errcode = '22023';
  end if;
  if p_starts_at < now() + interval '30 minutes' then raise exception 'too_soon' using errcode = '22023'; end if;
  if p_starts_at > now() + interval '30 days' then raise exception 'too_far' using errcode = '22023'; end if;
  if p_ends_at - p_starts_at not between interval '1 hour' and interval '16 hours'
     or extract(epoch from p_starts_at)::bigint % 1800 <> 0 or extract(epoch from p_ends_at)::bigint % 1800 <> 0 then
    raise exception 'invalid_slot' using errcode = '22023';
  end if;

  -- 合并过的球馆换成保留的那家；隐藏的、不存在的去掉
  select array_agg(distinct coalesce(v.merged_into, v.id)) into venues
    from public.venues v where v.id = any (p_venue_ids) and not v.hidden_pending_review;
  if coalesce(cardinality(venues), 0) not between 1 and 3 then raise exception 'invalid_venues' using errcode = '22023'; end if;

  -- 防刷：同时最多 5 个在找的请求，每天最多发 20 个；同一时间不能重复约
  if (select count(*) from public.match_tickets where user_id = me and status in ('searching', 'offered', 'paused')) >= 5
     or (select count(*) from public.match_tickets where user_id = me and created_at > now() - interval '1 day') >= 20 then
    raise exception 'too_many_requests' using errcode = '54000';
  end if;
  if exists (select 1 from public.match_tickets where user_id = me and status in ('searching', 'offered', 'paused')
             and starts_at < p_ends_at and p_starts_at < ends_at)
     or public.has_game_between(me, p_starts_at, p_ends_at) then
    raise exception 'overlapping' using errcode = '23P01';
  end if;

  insert into public.match_tickets (user_id, mode, starts_at, ends_at, venue_ids, skill_tolerance, auto_accept, lock_at, last_minute,
                                    play_with, mixed)
    values (me, p_mode, p_starts_at, p_ends_at, venues, p_skill_tolerance, p_auto_accept,
            p_starts_at - case when hurried then interval '20 minutes' else interval '2 hours' end, hurried, p_play_with, p_mixed)
    returning id into new_ticket;
  perform public.match_ticket(new_ticket, now());
  return new_ticket;
end
$$;

create or replace function public.check_room_details(p_venue text, p_starts_at timestamptz, p_ends_at timestamptz)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if p_starts_at is null and p_ends_at is null then return; end if;
  if p_starts_at is null or p_ends_at is null or p_ends_at - p_starts_at not between interval '1 hour' and interval '8 hours' then
    raise exception 'invalid_slot' using errcode = '22023';
  end if;
  if p_starts_at <= now() then raise exception 'already_started' using errcode = '22023'; end if;
  if p_starts_at > now() + interval '30 days' then raise exception 'too_far' using errcode = '22023'; end if;
  if p_venue is not null and not exists (select 1 from public.venues where id = p_venue and merged_into is null and not hidden_pending_review) then
    raise exception 'invalid_venues' using errcode = '22023';
  end if;
end
$$;

create or replace function public.send_challenge(p_target uuid, p_venue text, p_starts_at timestamptz, p_ends_at timestamptz, p_message text,
                                      p_partner uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  availability text := public.challenge_availability(p_target);
  venue text;
  new_id uuid;
  params jsonb;
begin
  if availability = 'hidden' or not public.related(me, p_target) then raise exception 'not_allowed' using errcode = '42501'; end if;
  if availability <> 'available' then raise exception '%', availability using errcode = '22023'; end if;
  if p_starts_at < now() + interval '2 hours' or p_starts_at > now() + interval '30 days' then raise exception 'too_soon' using errcode = '22023'; end if;
  if coalesce(p_message, '') ~* '(https?:|www\.|@|\d{7,})' then raise exception 'no_contact_info' using errcode = '22023'; end if;
  select coalesce(merged_into, id) into venue from public.venues where id = p_venue and not hidden_pending_review;
  if venue is null then raise exception 'invalid_venues' using errcode = '22023'; end if;
  if public.has_game_between(me, p_starts_at, p_ends_at) then raise exception 'overlapping' using errcode = '23P01'; end if;
  if p_partner is not null and not public.valid_partner(me, p_partner, array[p_target], p_starts_at, p_ends_at) then
    raise exception 'invalid_partner' using errcode = '22023';
  end if;

  insert into public.challenges (challenger_id, target_id, challenger_partner_id, venue_id, starts_at, ends_at, message, expires_at)
    values (me, p_target, p_partner, venue, p_starts_at, p_ends_at, btrim(coalesce(p_message, '')),
            least(now() + interval '48 hours', p_starts_at - interval '1 hour'))
    returning id into new_id;
  params := public.slot(p_starts_at, venue) || jsonb_build_object(
    'name', (select nickname from public.profiles where id = me),
    'partner', (select nickname from public.profiles where id = p_partner),
    'target', (select nickname from public.profiles where id = p_target));
  if p_partner is null then
    perform public.notify(p_target, 'challenge', 'Singles challenge', '{name} challenged you: {when} · {court}.', '/app/games/', params);
  else
    perform public.notify(p_target, 'challenge', 'Doubles challenge',
      '{name} and {partner} challenged you: {when} · {court}. Pick a partner to accept.', '/app/games/', params);
    perform public.notify(p_partner, 'challenge', 'You’re someone’s doubles partner',
      '{name} picked you to play {target}: {when} · {court}. We’ll tell you if they accept.', '/app/games/', params);
  end if;
  return new_id;
end
$$;

create or replace function public.create_group(p_name text, p_venue text, p_summary text, p_level_min int, p_level_max int,
                                    p_policy public.join_policy, p_schedules jsonb, p_gender public.gender default null)
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
  if not public.valid_schedules(p_schedules) then raise exception 'invalid_schedule' using errcode = '22023'; end if;
  if btrim(p_name) ~* '(https?:|www\.|@|\d{5,})' or coalesce(p_summary, '') ~* '(https?:|www\.|\d{7,})' then
    raise exception 'no_contact_info' using errcode = '22023';
  end if;

  insert into public.play_groups (name, venue_id, owner_id, summary, level_min, level_max, join_policy, invite_code, gender)
    values (btrim(p_name), venue, me, btrim(coalesce(p_summary, '')), p_level_min, p_level_max, p_policy, public.new_invite_code(), p_gender)
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

-- 修改约球请求：先取消旧的再提交新的；新的报错时整个事务回滚，旧请求不受影响
create function public.replace_ticket(p_ticket uuid, p_mode public.game_mode, p_starts_at timestamptz, p_ends_at timestamptz,
                                      p_venue_ids text[], p_skill_tolerance int, p_auto_accept boolean,
                                      p_play_with public.gender default null, p_mixed boolean default false)
returns uuid language plpgsql security definer set search_path = '' as $$
begin
  perform public.cancel_ticket(p_ticket);
  return public.submit_ticket(p_mode, p_starts_at, p_ends_at, p_venue_ids, p_skill_tolerance, p_auto_accept, p_play_with, p_mixed);
end
$$;

-- 群主编辑球群。场次没变的保留；去掉或改了的，以后的场次取消（报了名的人收到通知），再按新的生成
create function public.update_group(p_group uuid, p_name text, p_summary text, p_level_min int, p_level_max int,
                                    p_policy public.join_policy, p_schedules jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  old record;
  session uuid;
begin
  if public.group_role_of(p_group, auth.uid()) is distinct from 'owner' then raise exception 'not_organizer' using errcode = '42501'; end if;
  if not public.valid_schedules(p_schedules) then raise exception 'invalid_schedule' using errcode = '22023'; end if;
  if btrim(p_name) ~* '(https?:|www\.|@|\d{5,})' or coalesce(p_summary, '') ~* '(https?:|www\.|\d{7,})' then
    raise exception 'no_contact_info' using errcode = '22023';
  end if;
  update public.play_groups set name = btrim(p_name), summary = btrim(coalesce(p_summary, '')),
         level_min = p_level_min, level_max = p_level_max, join_policy = p_policy
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

-- 群主解散球群：通知其他成员，删掉球群（场次、报名、成员一起删）
create function public.disband_group(p_group uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  g public.play_groups;
  member record;
begin
  select * into g from public.play_groups where id = p_group for update;
  if g.id is null then raise exception 'group_not_found' using errcode = 'P0002'; end if;
  if g.owner_id <> auth.uid() then raise exception 'not_organizer' using errcode = '42501'; end if;
  for member in select user_id from public.group_members where group_id = p_group and user_id <> g.owner_id and not pending loop
    perform public.notify(member.user_id, 'group', 'Group closed: {group}', 'The organizer closed {group}.', null,
      jsonb_build_object('group', g.name));
  end loop;
  delete from public.play_groups where id = p_group;
end
$$;

revoke execute on function public.valid_schedules(jsonb) from public, anon;
revoke execute on function public.replace_ticket(uuid, public.game_mode, timestamptz, timestamptz, text[], int, boolean, public.gender, boolean),
  public.update_group(uuid, text, text, int, int, public.join_policy, jsonb), public.disband_group(uuid) from public, anon;
grant execute on function public.replace_ticket(uuid, public.game_mode, timestamptz, timestamptz, text[], int, boolean, public.gender, boolean),
  public.update_group(uuid, text, text, int, int, public.join_policy, jsonb), public.disband_group(uuid) to authenticated;

insert into public.notification_texts (locale, english, translated)
select l.locale, t.english, t.translated
from (values
  ('zh-Hans', 'Group closed: {group}', '球群已解散：{group}'), ('zh-Hans', 'The organizer closed {group}.', '组织者解散了 {group}。'),
  ('zh-Hant', 'Group closed: {group}', '球群已解散：{group}'), ('zh-Hant', 'The organizer closed {group}.', '組織者解散了 {group}。'),
  ('ja', 'Group closed: {group}', 'グループが解散しました：{group}'), ('ja', 'The organizer closed {group}.', '主催者が {group} を解散しました。'),
  ('ko', 'Group closed: {group}', '모임이 해산됐어요: {group}'), ('ko', 'The organizer closed {group}.', '운영자가 {group}을(를) 해산했어요.'),
  ('hi', 'Group closed: {group}', 'ग्रुप बंद हुआ: {group}'), ('hi', 'The organizer closed {group}.', 'आयोजक ने {group} बंद कर दिया।'),
  ('id', 'Group closed: {group}', 'Grup dibubarkan: {group}'), ('id', 'The organizer closed {group}.', 'Penyelenggara membubarkan {group}.'),
  ('ms', 'Group closed: {group}', 'Kumpulan dibubarkan: {group}'), ('ms', 'The organizer closed {group}.', 'Penganjur membubarkan {group}.'),
  ('th', 'Group closed: {group}', 'ก๊วนถูกยุบแล้ว: {group}'), ('th', 'The organizer closed {group}.', 'ผู้จัดยุบ {group} แล้ว'),
  ('vi', 'Group closed: {group}', 'Nhóm đã giải tán: {group}'), ('vi', 'The organizer closed {group}.', 'Người tổ chức đã giải tán {group}.')
) as t(locale, english, translated)
join (select distinct locale from public.notification_texts) l on l.locale = t.locale;
