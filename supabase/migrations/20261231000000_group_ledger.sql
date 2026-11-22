-- 球群的价格和收款记录（需求见 Badie-iOS/docs/CLUB_NIGHT.md 的“价格和收款记录”）
-- 1. 每周场次有价格（每人每场，0 = 免费，空 = 没写）。报名前就看得到；生成场次时记到这一场上，改价格只影响还没开始的场次
-- 2. 免费的场次谁都不用付
-- 3. 组织者的收款记录：开过的每一场收齐了没有，谁还欠着几场、多少钱，可以一次标成已付；收款不再限 30 天
-- 4. 球员的“我还没付的”：60 天内、填了金额的场次
-- 旧版 App 不传 "price"：建群就是没写；编辑时沿用同一个星期几原来的价格

alter table public.group_schedules add column price numeric(7, 2) check (price >= 0 and price <= 1000);

-- 某一场可以是 0（这一场免费）
alter table public.group_sessions drop constraint group_sessions_fee_check;
alter table public.group_sessions add constraint group_sessions_fee_check check (fee >= 0 and fee <= 1000);

-- 每周场次多 "price"：数字 0–1000 或 null
create or replace function public.valid_schedules(p jsonb, p_coached boolean)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(jsonb_typeof(p) = 'array' and jsonb_array_length(p) between 1 and 7
    and not exists (
      select 1 from jsonb_array_elements(p) s
      cross join lateral (select coalesce((s ->> 'weekday')::int, -1) as d, coalesce((s ->> 'start')::int, -1) as a,
                                 coalesce((s ->> 'end')::int, -1) as b, coalesce((s ->> 'capacity')::int, -1) as c) x
      where x.d not between 0 and 6 or x.a not between 0 and 1410 or x.a % 30 <> 0 or x.b not between 30 and 1440 or x.b % 30 <> 0
         or x.b - x.a not between 60 and 720 or x.c not between (case when p_coached then 1 else 4 end) and 40
         or char_length(coalesce(s ->> 'fee', '')) > 120
         or coalesce(jsonb_typeof(s -> 'price'), 'null') not in ('number', 'null')
         or (jsonb_typeof(s -> 'price') = 'number' and (s ->> 'price')::numeric not between 0 and 1000)), false)
$$;

-- 编辑时没带 "price"（旧版 App）：沿用同一个星期几原来那一项的价格（同一开始时间的优先）。价格保留两位小数
create function public.schedule_prices(p_items jsonb, p_group uuid)
returns jsonb language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(n || jsonb_build_object('price',
           case when n ? 'price' then round((n ->> 'price')::numeric, 2)
                else (select s.price from public.group_schedules s
                      where p_group is not null and s.group_id = p_group and s.weekday = (n ->> 'weekday')::int
                      order by s.start_minutes = (n ->> 'start')::int desc, s.start_minutes limit 1) end)
         order by x.ord), '[]')
  from jsonb_array_elements(p_items) with ordinality as x (n, ord)
$$;
revoke execute on function public.schedule_prices(jsonb, uuid) from public, anon, authenticated;

-- 生成场次：把每周场次的价格记到这一场上
create or replace function public.ensure_sessions(p_group uuid)
returns void language sql security definer set search_path = '' as $$
  insert into public.group_sessions (group_id, schedule_id, starts_at, ends_at, capacity, venue_id, fee)
    select s.group_id, s.id,
           (d + make_interval(mins => s.start_minutes)) at time zone tz.name,
           (d + make_interval(mins => s.end_minutes)) at time zone tz.name, s.capacity, v.id, s.price
    from public.group_schedules s
    join public.play_groups g on g.id = s.group_id
    join public.venues v on v.id = coalesce(s.venue_id, g.venue_id)
    cross join lateral (select coalesce(v.time_zone_id, 'UTC') as name) tz
    cross join lateral generate_series(date_trunc('day', now() at time zone tz.name), date_trunc('day', now() at time zone tz.name) + interval '13 days', interval '1 day') d
    where s.group_id = p_group and extract(dow from d) = s.weekday
      and (d + make_interval(mins => s.start_minutes)) at time zone tz.name > now()
  on conflict (schedule_id, starts_at) do nothing
$$;

-- 改了价格：还没开始、组织者没单独改过金额的场次跟着改
create function public.schedule_price_changed()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.group_sessions set fee = new.price
    where schedule_id = new.id and starts_at > now() and fee_by is null and fee is distinct from new.price;
  return null;
end
$$;
revoke execute on function public.schedule_price_changed() from public, anon, authenticated;
create trigger group_schedules_price_changed after update of price on public.group_schedules
  for each row when (old.price is distinct from new.price) execute function public.schedule_price_changed();

-- 每人多少钱：这一场的；没有时，每周场次没写价格的才用同一个每周场次上一次填的（写了价格以后，以前没金额的场次不补）
create or replace function public.session_fee(p_session uuid)
returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce(gs.fee, case when sc.price is null then
           (select p.fee from public.group_sessions p where p.schedule_id = gs.schedule_id and p.starts_at < gs.starts_at
                                                      and p.fee is not null order by p.starts_at desc limit 1) end)
  from public.group_sessions gs join public.group_schedules sc on sc.id = gs.schedule_id
  where gs.id = p_session
$$;

-- 这一场谁要付：同上一版，免费（0）的场次谁都不用付
create or replace function public.session_payers(p_session uuid)
returns table (id uuid, owes boolean) language sql stable security definer set search_path = '' as $$
  select su.id,
         su.user_id is distinct from public.session_payee(p_session)
         and coalesce(f.fee, 1) > 0
         and coalesce(su.owes, case when bool_or(su.attendance is not null) over () then su.attendance is not null else not su.waitlisted end)
  from public.session_signups su cross join (select public.session_fee(p_session) as fee) f
  where su.session_id = p_session
$$;

-- 收款：组织者从开场前 1 小时起都能改（以前只到结束后 30 天）
create or replace function public.pay_guard(p_session uuid)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_organizer((select group_id from public.group_sessions where id = p_session), auth.uid()) then
    raise exception 'not_organizer' using errcode = '42501';
  end if;
  if not exists (select 1 from public.group_sessions where id = p_session and cancelled_at is null
                 and now() >= starts_at - interval '1 hour') then
    raise exception 'night_closed' using errcode = 'P0002';
  end if;
end
$$;

-- 这一场每人多少钱：0 = 这一场免费，空 = 不填
create or replace function public.set_session_fee(p_session uuid, p_amount numeric)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.pay_guard(p_session);
  if p_amount is not null and (p_amount < 0 or p_amount > 1000) then raise exception 'invalid_amount' using errcode = '22023'; end if;
  update public.group_sessions set fee = round(p_amount, 2), fee_by = auth.uid() where id = p_session;
end
$$;

-- 建群：每周场次带 "price"
create or replace function public.create_group(p_name text, p_venue text, p_summary text, p_level_min int, p_level_max int,
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
  items := public.schedule_prices(public.normalize_group_schedules(p_schedules, courts, null, null), null);
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
  insert into public.group_schedules (group_id, weekday, start_minutes, end_minutes, capacity, fee_note, venue_id, price)
    select new_group, (s ->> 'weekday')::smallint, (s ->> 'start')::smallint, (s ->> 'end')::smallint, (s ->> 'capacity')::smallint,
           nullif(btrim(s ->> 'fee'), ''), s ->> 'venue', (s ->> 'price')::numeric
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

-- 改球群：每周场次带 "price"（改了价格的那一项也改在原来那一行上，还没开始的场次跟着改）。其余同上一版
create or replace function public.update_group(p_group uuid, p_name text, p_summary text, p_level_min int, p_level_max int,
                                               p_policy public.join_policy, p_schedules jsonb, p_coached boolean default null,
                                               p_venues text[] default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  old record;
  doomed uuid;
  session record;
  item jsonb;
  is_coached boolean;
  before text[];
  courts text[];
  items jsonb;
  court text;
  tz text;
  new_start timestamptz;
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
  items := public.schedule_prices(public.normalize_group_schedules(p_schedules, courts, before, p_group), p_group);

  update public.play_groups set name = btrim(p_name), summary = btrim(coalesce(p_summary, '')),
         level_min = p_level_min, level_max = p_level_max, join_policy = p_policy, coached = is_coached, venue_id = courts[1]
    where id = p_group;

  for old in select s.* from public.group_schedules s where s.group_id = p_group and not exists (
               select 1 from jsonb_array_elements(items) n
               where (n ->> 'weekday')::int = s.weekday and (n ->> 'start')::int = s.start_minutes and (n ->> 'end')::int = s.end_minutes
                 and (n ->> 'capacity')::int = s.capacity and nullif(btrim(n ->> 'fee'), '') is not distinct from s.fee_note
                 and (n ->> 'venue') is not distinct from s.venue_id
                 and (n ->> 'price')::numeric is not distinct from s.price)
             order by s.weekday, s.start_minutes loop
    -- 同一个星期几、还没有对应的那一项新的
    select n into item from jsonb_array_elements(items) n
      where (n ->> 'weekday')::int = old.weekday and not exists (
              select 1 from public.group_schedules s
              where s.group_id = p_group and s.weekday = (n ->> 'weekday')::int and s.start_minutes = (n ->> 'start')::int
                and s.end_minutes = (n ->> 'end')::int and s.capacity = (n ->> 'capacity')::int
                and s.fee_note is not distinct from nullif(btrim(n ->> 'fee'), '') and s.venue_id is not distinct from (n ->> 'venue')
                and s.price is not distinct from (n ->> 'price')::numeric)
      order by (n ->> 'start')::int limit 1;
    if item is null then
      for doomed in select id from public.group_sessions where schedule_id = old.id and cancelled_at is null and starts_at > now() loop
        perform public.cancel_session(doomed);
      end loop;
      delete from public.group_schedules where id = old.id;
      continue;
    end if;

    update public.group_schedules
      set start_minutes = (item ->> 'start')::smallint, end_minutes = (item ->> 'end')::smallint, capacity = (item ->> 'capacity')::smallint,
          fee_note = nullif(btrim(item ->> 'fee'), ''), venue_id = item ->> 'venue', price = (item ->> 'price')::numeric
      where id = old.id;
    court := coalesce(item ->> 'venue', courts[1]);
    tz := (select coalesce(v.time_zone_id, 'UTC') from public.venues v where v.id = court);
    for session in select gs.id, gs.starts_at, gs.venue_id, gs.capacity, gs.cancelled_at, coalesce(v.time_zone_id, 'UTC') as old_tz,
                          (gs.starts_at at time zone coalesce(v.time_zone_id, 'UTC'))::date as day
                   from public.group_sessions gs left join public.venues v on v.id = gs.venue_id
                   where gs.schedule_id = old.id and gs.starts_at > now() loop
      new_start := (session.day + make_interval(mins => (item ->> 'start')::int)) at time zone tz;
      -- 改到了今天已经过去的时间：这一场取消
      if new_start <= now() then
        if session.cancelled_at is null then perform public.cancel_session(session.id); end if;
        continue;
      end if;
      update public.group_sessions
        set starts_at = new_start, ends_at = (session.day + make_interval(mins => (item ->> 'end')::int)) at time zone tz,
            capacity = (item ->> 'capacity')::int, venue_id = court
        where id = session.id;
      continue when session.cancelled_at is not null;
      if new_start <> session.starts_at or court is distinct from session.venue_id then
        perform public.notify(su.user_id, 'group', 'Session changed: {group}', '{old} is now {when} · {court}. You’re still on the list.',
                              '/app/groups/' || p_group || '/',
                              public.slot(new_start, court) || jsonb_build_object('group', btrim(p_name),
                                                                                  'old', jsonb_build_object('at', session.starts_at, 'tz', session.old_tz)))
          from public.session_signups su where su.session_id = session.id and su.user_id <> auth.uid();
        perform public.send_guest_emails((
          select jsonb_agg(public.guest_email(su.id, 'Session changed: {group}',
                                              '{old} is now {when} · {court}. You’re still on the list. If you can’t make it, cancel here:',
                                              'https://badie.rsvp/g/' || g.guest_code || '/?cancel=' || public.new_guest_mail_token(su.id),
                                              jsonb_build_object('old', jsonb_build_object('at', session.starts_at, 'tz', session.old_tz))))
          from public.session_signups su join public.play_groups g on g.id = p_group
          where su.session_id = session.id and su.guest_email is not null));
      end if;
      -- 名额多了：候补的按顺序补上
      perform public.promote_waitlist(session.id) from generate_series(1, (item ->> 'capacity')::int - session.capacity);
    end loop;
  end loop;

  insert into public.group_schedules (group_id, weekday, start_minutes, end_minutes, capacity, fee_note, venue_id, price)
    select p_group, (n ->> 'weekday')::smallint, (n ->> 'start')::smallint, (n ->> 'end')::smallint, (n ->> 'capacity')::smallint,
           nullif(btrim(n ->> 'fee'), ''), n ->> 'venue', (n ->> 'price')::numeric
    from jsonb_array_elements(items) n
    where not exists (select 1 from public.group_schedules s
                      where s.group_id = p_group and s.weekday = (n ->> 'weekday')::int and s.start_minutes = (n ->> 'start')::int
                        and s.end_minutes = (n ->> 'end')::int and s.capacity = (n ->> 'capacity')::int
                        and s.fee_note is not distinct from nullif(btrim(n ->> 'fee'), '')
                        and s.venue_id is not distinct from (n ->> 'venue')
                        and s.price is not distinct from (n ->> 'price')::numeric);
  perform public.ensure_sessions(p_group);
end
$$;

-- 球群信息：每周场次多 "price"
create or replace function public.group_summary(p_group uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', g.id, 'name', g.name, 'summary', g.summary, 'level_min', g.level_min, 'level_max', g.level_max, 'join_policy', g.join_policy, 'gender', g.gender,
    'coached', g.coached,
    'venue', jsonb_build_object('id', v.id, 'name', v.name, 'city', v.city, 'tz', v.time_zone_id),
    'venues', (select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'city', c.city, 'tz', c.time_zone_id) order by gv.position)
               from public.group_venues gv join public.venues c on c.id = gv.venue_id where gv.group_id = g.id),
    'schedules', (select jsonb_agg(jsonb_build_object('weekday', s.weekday, 'start', s.start_minutes, 'end', s.end_minutes,
                                                      'capacity', s.capacity, 'fee', s.fee_note, 'venue', s.venue_id,
                                                      'price', s.price) order by s.weekday, s.start_minutes)
                  from public.group_schedules s where s.group_id = g.id),
    'activity', public.group_activity(g.id),
    'my_role', public.group_role_of(g.id, auth.uid()))
  from public.play_groups g join public.venues v on v.id = g.venue_id
  where g.id = p_group
$$;

-- 球群页：每一场多 "price"（这一场每人多少钱，0 = 免费，null = 没写）。其余同上一版
create or replace function public.group_page(p_group uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  role text := public.group_role_of(p_group, me);
  member boolean := role in ('owner', 'organizer', 'member');
  organizer boolean := role in ('owner', 'organizer');
begin
  if me is null or not exists (select 1 from public.play_groups g where g.id = p_group and not public.blocked_between(me, g.owner_id)) then
    return null;
  end if;
  perform public.ensure_sessions(p_group);
  return public.group_summary(p_group) || jsonb_build_object(
    'invite_code', case when member then (select invite_code from public.play_groups where id = p_group) end,
    'sessions', coalesce((select jsonb_agg(jsonb_build_object(
        'id', s.id, 'starts_at', s.starts_at, 'ends_at', s.ends_at, 'capacity', s.capacity, 'cancelled', s.cancelled_at is not null,
        'venue', coalesce(s.venue_id, g.venue_id), 'price', public.session_fee(s.id),
        'confirmed', (select count(*) from public.session_signups su where su.session_id = s.id and not su.waitlisted),
        'waitlist', (select count(*) from public.session_signups su where su.session_id = s.id and su.waitlisted),
        'my_status', (select case when not su.waitlisted then 'confirmed'
                                  else 'waitlisted:' || (select count(*) from public.session_signups w
                                                         where w.session_id = s.id and w.waitlisted and w.signed_up_at <= su.signed_up_at) end
                      from public.session_signups su where su.session_id = s.id and su.user_id = me),
        'players', case when member then (select jsonb_agg(jsonb_build_object('id', coalesce(su.user_id, su.id), 'nickname', coalesce(p.nickname, su.guest_name),
                                                                              'waitlisted', su.waitlisted, 'guest', su.user_id is null,
                                                                              'signed_up_at', su.signed_up_at)
                                                           order by su.waitlisted, su.signed_up_at)
                                          from public.session_signups su left join public.profiles p on p.id = su.user_id
                                          where su.session_id = s.id and (su.user_id is null or p.id is not null)) end,
        'late_cancels', case when organizer then (select jsonb_agg(jsonb_build_object('nickname', coalesce(p.nickname, lc.guest_name),
                                                                                      'guest', lc.user_id is null)
                                                                   order by lc.cancelled_at)
                                                  from public.session_late_cancels lc left join public.profiles p on p.id = lc.user_id
                                                  where lc.session_id = s.id and (lc.user_id is null or p.id is not null)
                                                    and not exists (select 1 from public.session_signups su
                                                                    where su.session_id = s.id and su.user_id = lc.user_id)) end)
        order by s.starts_at)
      from public.group_sessions s join public.play_groups g on g.id = s.group_id
      where s.group_id = p_group and s.ends_at > now() and s.starts_at < now() + interval '14 days'), '[]'),
    'members', case when member then (select jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', p.rating, 'role', m.role)
                                                       order by m.role, lower(p.nickname))
                                      from public.group_members m join public.profiles p on p.id = m.user_id
                                      where m.group_id = p_group and not m.pending) end,
    'pending', case when organizer then (
        select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', p.rating) order by m.joined_at), '[]')
        from public.group_members m join public.profiles p on p.id = m.user_id where m.group_id = p_group and m.pending) end,
    'guests_allowed', case when organizer then (select guests_allowed from public.play_groups where id = p_group) end,
    'guest_limit', case when organizer then (select guest_limit from public.play_groups where id = p_group) end,
    'guest_code', case when organizer then (select guest_code from public.play_groups where id = p_group) end);
end
$$;

-- ---------------------------------------------------------------------------
-- 收款记录（组织者）
-- ---------------------------------------------------------------------------

-- 开过的场次（新的在前，一页 p_limit 场，p_before 往前翻）：每人多少钱、收钱的人、要付几人、付了几人。
-- 第一页还有 "owed"：谁还欠着。只算写了金额（大于 0）的场次，注册用户按人、访客按名字合起来，"signups" 是那几行报名
create function public.group_ledger(p_group uuid, p_before timestamptz default null, p_limit int default 20)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_organizer(p_group, auth.uid()) then raise exception 'not_organizer' using errcode = '42501'; end if;
  return jsonb_build_object(
    'sessions', (select coalesce(jsonb_agg(x.item order by x.starts_at desc), '[]') from (
        select gs.starts_at, jsonb_build_object(
            'id', gs.id, 'starts_at', gs.starts_at, 'ends_at', gs.ends_at, 'venue', v.name, 'tz', v.time_zone_id,
            'amount', public.session_fee(gs.id),
            'payee', (select nickname from public.profiles where id = public.session_payee(gs.id)),
            'owes', (select count(*) from public.session_payers(gs.id) py where py.owes),
            'paid', (select count(*) from public.session_payers(gs.id) py join public.session_signups su on su.id = py.id
                     where py.owes and su.paid_at is not null)) as item
        from public.group_sessions gs join public.play_groups g on g.id = gs.group_id
        join public.venues v on v.id = coalesce(gs.venue_id, g.venue_id)
        where gs.group_id = p_group and gs.cancelled_at is null and gs.starts_at <= now()
          and (p_before is null or gs.starts_at < p_before)
          and exists (select 1 from public.session_signups su where su.session_id = gs.id)
        order by gs.starts_at desc limit least(greatest(coalesce(p_limit, 20), 1), 100)) x),
    'owed', case when p_before is null then (
        select coalesce(jsonb_agg(jsonb_build_object('id', k.user_id, 'name', k.name, 'guest', k.user_id is null,
                                                     'sessions', k.n, 'amount', k.total, 'signups', k.ids)
                                  order by k.total desc, lower(k.name)), '[]')
        from (select su.user_id, min(coalesce(p.nickname, su.guest_name)) as name, count(*) as n, sum(f.fee) as total,
                     jsonb_agg(su.id order by gs.starts_at) as ids
              from public.group_sessions gs
              cross join lateral (select public.session_fee(gs.id) as fee) f
              cross join lateral public.session_payers(gs.id) py
              join public.session_signups su on su.id = py.id
              left join public.profiles p on p.id = su.user_id
              where gs.group_id = p_group and gs.cancelled_at is null and gs.starts_at <= now() and f.fee > 0
                and py.owes and su.paid_at is null and (su.user_id is null or p.id is not null)
              group by su.user_id, case when su.user_id is null then lower(btrim(su.guest_name)) end) k) end);
end
$$;

-- 导出成表格：最近 500 场，每人一行（日期、名字、是不是访客、每人多少钱、要不要付、什么时候付的、是不是自己标的）
create function public.group_ledger_rows(p_group uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_organizer(p_group, auth.uid()) then raise exception 'not_organizer' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
              'starts_at', gs.starts_at, 'tz', v.time_zone_id, 'venue', v.name, 'name', coalesce(p.nickname, su.guest_name),
              'guest', su.user_id is null, 'amount', f.fee, 'owes', py.owes, 'paid_at', su.paid_at, 'paid_self', su.paid_self)
            order by gs.starts_at desc, lower(coalesce(p.nickname, su.guest_name))), '[]')
          from (select * from public.group_sessions where group_id = p_group and cancelled_at is null and starts_at <= now()
                order by starts_at desc limit 500) gs
          join public.play_groups g on g.id = gs.group_id
          join public.venues v on v.id = coalesce(gs.venue_id, g.venue_id)
          cross join lateral (select public.session_fee(gs.id) as fee) f
          cross join lateral public.session_payers(gs.id) py
          join public.session_signups su on su.id = py.id
          left join public.profiles p on p.id = su.user_id
          where (py.owes or su.paid_at is not null) and (su.user_id is null or p.id is not null));
end
$$;

-- 一次标几行已付 / 改回没付（收款记录里“都付了”）。都要是自己当组织者的球群、开场前 1 小时以后的场次。返回改了几行
create function public.mark_signups_paid(p_signups uuid[], p_paid boolean)
returns int language plpgsql security definer set search_path = '' as $$
declare
  changed int;
begin
  if cardinality(p_signups) > 200 or exists (
       select 1 from unnest(p_signups) x (id)
       left join public.session_signups su on su.id = x.id
       left join public.group_sessions gs on gs.id = su.session_id
       where gs.id is null or gs.cancelled_at is not null or now() < gs.starts_at - interval '1 hour'
          or not public.is_organizer(gs.group_id, auth.uid())) then
    raise exception 'not_organizer' using errcode = '42501';
  end if;
  update public.session_signups set paid_at = case when p_paid then coalesce(paid_at, now()) end, paid_self = false
    where id = any(p_signups) and (paid_at is null) = p_paid;
  get diagnostics changed = row_count;
  return changed;
end
$$;

-- 我还没付的：开过的、写了金额（大于 0）的场次，60 天内，我要付、还没付。p_group 空 = 所有球群
create function public.my_dues(p_group uuid default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'session_id', gs.id, 'group_id', g.id, 'group', g.name, 'starts_at', gs.starts_at, 'ends_at', gs.ends_at, 'tz', v.time_zone_id,
      'amount', f.fee, 'to', pr.nickname, 'to_id', pr.id, 'handles', coalesce(public.payee_handles(pr.id, true), '{}'))
    order by gs.starts_at), '[]')
  from public.session_signups su
  join public.group_sessions gs on gs.id = su.session_id
  join public.play_groups g on g.id = gs.group_id
  join public.venues v on v.id = coalesce(gs.venue_id, g.venue_id)
  cross join lateral (select public.session_fee(gs.id) as fee) f
  join public.profiles pr on pr.id = public.session_payee(gs.id)
  where su.user_id = auth.uid() and su.paid_at is null and (p_group is null or gs.group_id = p_group)
    and gs.cancelled_at is null and gs.starts_at <= now() and gs.starts_at > now() - interval '60 days' and f.fee > 0
    and (select py.owes from public.session_payers(gs.id) py where py.id = su.id)
$$;

revoke execute on function public.group_ledger(uuid, timestamptz, int), public.group_ledger_rows(uuid),
  public.mark_signups_paid(uuid[], boolean), public.my_dues(uuid) from public, anon;
grant execute on function public.group_ledger(uuid, timestamptz, int), public.group_ledger_rows(uuid),
  public.mark_signups_paid(uuid[], boolean), public.my_dues(uuid) to authenticated;
