-- 项目：男单、女单、男双、女双、混双（加上不限）。
-- 男单 / 女单 / 男双 / 女双 = 单打或双打 + 只和自己同性别的人打（play_with / gender，只能是自己的性别）。
-- 混双：四个人两男两女，每边一男一女；男生和男生比、女生和女生比，所以等级不换算，各按各的。
-- 混双的约球只和混双的约球配；混双局男女各两个位子，满了的那边进候补。

alter table public.match_tickets add column mixed boolean not null default false,
  add constraint match_tickets_mixed_check check (not mixed or (mode = 'doubles' and play_with is null));
alter table public.rooms add column mixed boolean not null default false,
  add constraint rooms_mixed_check check (not mixed or (mode = 'doubles' and gender is null));

-- ---------------------------------------------------------------------------
-- 快速匹配
-- ---------------------------------------------------------------------------

create or replace function public.match_ticket(p_ticket uuid, p_now timestamptz)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  t public.match_tickets;
  my_rating numeric;
  my_gender public.gender;
  picked uuid[];
  slot_start timestamptz;
  slot_end timestamptz;
  venue text;
  tz text;
  hurried boolean;
  offer_lock timestamptz;
  respond_by timestamptz;
  new_offer uuid;
  seat record;
begin
  select * into t from public.match_tickets
    where id = p_ticket and status = 'searching' and lock_at > p_now for update skip locked;
  if t.id is null then return null; end if;
  -- 混双各按各的等级比；其余按换算后的等级
  select case when t.mixed then rating else public.open_rating(rating, gender) end, gender into my_rating, my_gender
    from public.profiles where id = t.user_id;

  -- 候选：同模式（混双只配混双）、时间重叠 ≥ 30 分钟、有共同球馆、水平差在双方的容忍范围内（1 级 = 3 档）、
  -- 性别合双方的要求、双方都没排除对方、那段时间没有别的球局。优先：被退回的 > 水平接近 > 先来的。
  -- 混双男女各留 6 个候选，免得前几名全是同一性别
  with eligible as (
    select c.id, c.user_id, c.starts_at, c.ends_at, c.venue_ids, c.priority, c.skill_tolerance, c.excluded_user_ids,
           c.play_with, p.gender, x.rating, abs(x.rating - my_rating) as gap, c.created_at,
           row_number() over (order by c.priority desc, abs(x.rating - my_rating), c.created_at) as n,
           row_number() over (partition by p.gender order by c.priority desc, abs(x.rating - my_rating), c.created_at) as n_gender
    from public.match_tickets c join public.profiles p on p.id = c.user_id
    cross join lateral (select case when t.mixed then p.rating else public.open_rating(p.rating, p.gender) end as rating) x
    where c.status = 'searching' and c.mode = t.mode and c.mixed = t.mixed and c.user_id <> t.user_id and c.lock_at > p_now
      and c.starts_at <= t.ends_at - interval '30 minutes' and c.ends_at >= t.starts_at + interval '30 minutes'
      and c.venue_ids && t.venue_ids
      and not c.user_id = any (t.excluded_user_ids) and not t.user_id = any (c.excluded_user_ids)
      and public.accepts(t.play_with, p.gender) and public.accepts(c.play_with, my_gender)
      and (not t.mixed or p.gender is not null)
      and abs(round((x.rating - my_rating) * 3)) <= least(t.skill_tolerance, c.skill_tolerance) * 3
      and not public.has_game_between(c.user_id, t.starts_at, t.ends_at)),
  candidates as (select * from eligible where case when t.mixed then n_gender <= 6 else n <= 8 end)
  select case
    when t.mode = 'singles' then (select array[t.id, c.id] from candidates c order by c.priority desc, c.gap, c.created_at limit 1)
    -- 双打：另外三人彼此也要满足上面的条件（含性别要求），并且有一家四个人都能去的球馆；混双要两男两女。
    -- 被退回的多、水平集中的优先
    else (select array[t.id, a.id, b.id, c.id]
          from candidates a join candidates b on b.id > a.id join candidates c on c.id > b.id
          where a.user_id <> b.user_id and a.user_id <> c.user_id and b.user_id <> c.user_id
            and least(t.ends_at, a.ends_at, b.ends_at, c.ends_at) - greatest(t.starts_at, a.starts_at, b.starts_at, c.starts_at) >= interval '30 minutes'
            and exists (select 1 from unnest(t.venue_ids) v where v = any (a.venue_ids) and v = any (b.venue_ids) and v = any (c.venue_ids))
            and not array[a.user_id, b.user_id, c.user_id] && (a.excluded_user_ids || b.excluded_user_ids || c.excluded_user_ids)
            and public.accepts(a.play_with, b.gender) and public.accepts(b.play_with, a.gender)
            and public.accepts(a.play_with, c.gender) and public.accepts(c.play_with, a.gender)
            and public.accepts(b.play_with, c.gender) and public.accepts(c.play_with, b.gender)
            and (not t.mixed or (select count(*) filter (where g = 'male') = 2 and count(*) filter (where g = 'female') = 2
                                 from unnest(array[my_gender, a.gender, b.gender, c.gender]) g))
            and round((greatest(a.rating, b.rating, c.rating, my_rating) - least(a.rating, b.rating, c.rating, my_rating)) * 3)
                <= least(t.skill_tolerance, a.skill_tolerance, b.skill_tolerance, c.skill_tolerance) * 3
          order by a.priority::int + b.priority::int + c.priority::int desc,
                   greatest(a.rating, b.rating, c.rating, my_rating) - least(a.rating, b.rating, c.rating, my_rating),
                   a.gap + b.gap + c.gap
          limit 1)
    end into picked;
  if picked is null then return null; end if;

  -- 锁住选中的请求；有人正被别的匹配占着就这轮放弃，下一轮再来
  if (select count(*) from (select 1 from public.match_tickets
                            where id = any (picked) and status = 'searching' for update skip locked) l) < cardinality(picked) then
    return null;
  end if;

  -- 时间：大家共同空闲的开头，最长 2 小时；球馆：按发起人的顺序，第一家大家都能去的
  select max(starts_at), least(min(ends_at), max(starts_at) + interval '2 hours'), bool_or(last_minute)
    into slot_start, slot_end, hurried
    from public.match_tickets where id = any (picked);
  select u.v into venue from unnest(t.venue_ids) with ordinality as u(v, n)
    where not exists (select 1 from public.match_tickets m where m.id = any (picked) and not u.v = any (m.venue_ids))
    order by u.n limit 1;
  select coalesce(time_zone_id, 'UTC') into tz from public.venues where id = venue;
  offer_lock := slot_start - case when hurried then interval '20 minutes' else interval '2 hours' end;
  respond_by := least(public.offer_respond_by(slot_start, p_now, tz), offer_lock);
  -- 来不及回复（普通局少于 10 分钟、临时局少于 3 分钟）就不发提议
  if respond_by - p_now < (case when hurried then interval '3 minutes' else interval '10 minutes' end) then return null; end if;

  insert into public.match_offers (mode, starts_at, ends_at, venue_id, lock_at)
    values (t.mode, slot_start, slot_end, venue, offer_lock) returning id into new_offer;

  -- 分队：按换算后的水平排第 1、4 的一队，第 2、3 的一队（单打就是各一队）。
  -- 混双：强的男生配弱一点的女生，另一队反过来。开了自动接受的直接算确认
  insert into public.match_seats (offer_id, user_id, ticket_id, team, response, respond_by, responded_at)
    select new_offer, m.user_id, m.id,
           case when t.mixed then case when (m.gender = 'male') = (m.rank_in_gender = 1) then 1 else 2 end
                when m.rank in (1, 4) then 1 else 2 end,
           case when m.auto_accept then 'accepted'::public.seat_response else 'pending' end,
           respond_by, case when m.auto_accept then p_now end
    from (select mt.*, p.gender,
                 row_number() over (order by public.open_rating(p.rating, p.gender) desc, mt.id) as rank,
                 row_number() over (partition by p.gender order by p.rating desc, mt.id) as rank_in_gender
          from public.match_tickets mt join public.profiles p on p.id = mt.user_id where mt.id = any (picked)) m;
  update public.match_tickets set status = 'offered', offer_id = new_offer, priority = false where id = any (picked);

  if public.finalize_offer(new_offer) is not null then return new_offer; end if;

  for seat in select user_id, response from public.match_seats where offer_id = new_offer loop
    if seat.response = 'accepted' then
      perform public.notify(seat.user_id, 'offer_auto', 'Match found, accepted for you',
        '{when} · {court}. Waiting for the others to confirm.', '/app/play/', public.slot(slot_start, venue));
    else
      perform public.notify(seat.user_id, 'offer', 'Match found, please confirm', '{when} · {court}. Confirm by {by}.', '/app/play/',
        public.slot(slot_start, venue) || jsonb_build_object('by', jsonb_build_object('at', respond_by, 'tz', tz)));
    end if;
  end loop;
  return new_offer;
end
$$;

-- 有多少人在找、其中条件都合适的（和匹配时的条件一样；混双只数混双）
create or replace function public.ticket_pool(p_ticket uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with t as (
    select mt.*, case when mt.mixed then p.rating else public.open_rating(p.rating, p.gender) end as rating, p.gender,
           coalesce((select v.time_zone_id from public.venues v where v.id = mt.venue_ids[1]), 'UTC') as tz
    from public.match_tickets mt join public.profiles p on p.id = mt.user_id
    where mt.id = p_ticket and mt.user_id = auth.uid()),
  nearby as (
    select c.user_id, c.starts_at, c.ends_at, c.venue_ids, c.skill_tolerance, c.excluded_user_ids, c.play_with, p.gender,
           case when t.mixed then p.rating else public.open_rating(p.rating, p.gender) end as rating
    from t, public.match_tickets c join public.profiles p on p.id = c.user_id
    where c.status = 'searching' and c.mode = t.mode and c.mixed = t.mixed and c.user_id <> t.user_id and c.lock_at > now()
      and (c.starts_at at time zone t.tz)::date = (t.starts_at at time zone t.tz)::date
      and not public.blocked_between(t.user_id, c.user_id)
      and exists (select 1 from public.venues a join public.venues b on extensions.st_dwithin(a.location, b.location, 30000)
                  where a.id = any (t.venue_ids) and b.id = any (c.venue_ids)))
  select jsonb_build_object(
    'available', (select count(distinct n.user_id) from nearby n),
    'compatible', (select count(distinct n.user_id) from nearby n
                   where n.starts_at <= t.ends_at - interval '30 minutes' and n.ends_at >= t.starts_at + interval '30 minutes'
                     and n.venue_ids && t.venue_ids
                     and not n.user_id = any (t.excluded_user_ids) and not t.user_id = any (n.excluded_user_ids)
                     and public.accepts(t.play_with, n.gender) and public.accepts(n.play_with, t.gender)
                     and abs(round((n.rating - t.rating) * 3)) <= least(t.skill_tolerance, n.skill_tolerance) * 3))
  from t
$$;

-- 发起时多一个“混双”；只和同性别的人打只能选自己的性别（参数变了，先删旧的）
drop function public.submit_ticket(public.game_mode, timestamptz, timestamptz, text[], int, boolean, public.gender);
create function public.submit_ticket(p_mode public.game_mode, p_starts_at timestamptz, p_ends_at timestamptz,
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
  if p_starts_at > now() + interval '14 days' then raise exception 'too_far' using errcode = '22023'; end if;
  if p_ends_at - p_starts_at not between interval '1 hour' and interval '8 hours'
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
revoke execute on function public.submit_ticket(public.game_mode, timestamptz, timestamptz, text[], int, boolean, public.gender, boolean) from public, anon;
grant execute on function public.submit_ticket(public.game_mode, timestamptz, timestamptz, text[], int, boolean, public.gender, boolean) to authenticated;

create or replace function public.my_matchmaking()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(item order by starts_at), '[]') from (
    select t.starts_at, jsonb_build_object(
      'id', t.id, 'mode', t.mode, 'starts_at', t.starts_at, 'ends_at', t.ends_at, 'status', t.status,
      'skill_tolerance', t.skill_tolerance, 'auto_accept', t.auto_accept, 'lock_at', t.lock_at, 'game_id', t.game_id,
      'last_minute', t.last_minute, 'play_with', t.play_with, 'mixed', t.mixed,
      'venues', (select jsonb_agg(jsonb_build_object('id', v.id, 'name', v.name, 'city', v.city, 'tz', v.time_zone_id))
                 from public.venues v where v.id = any (t.venue_ids)),
      'offer', (select jsonb_build_object(
          'id', o.id, 'starts_at', o.starts_at, 'ends_at', o.ends_at, 'respond_by', me.respond_by, 'my_response', me.response,
          'lock_at', o.lock_at,
          'venue', jsonb_build_object('id', v.id, 'name', v.name, 'city', v.city, 'street', v.street, 'tz', v.time_zone_id),
          'accepted', (select count(*) from public.match_seats s where s.offer_id = o.id and s.response = 'accepted'),
          'players', (select jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', p.rating, 'gender', p.gender, 'team', s.team,
                                                          'me', s.user_id = auth.uid()) order by s.team, p.rating desc)
                      from public.match_seats s join public.profiles p on p.id = s.user_id where s.offer_id = o.id))
        from public.match_offers o join public.venues v on v.id = o.venue_id
        join public.match_seats me on me.offer_id = o.id and me.user_id = auth.uid()
        where o.id = t.offer_id and o.status = 'open')
    ) as item
    from public.match_tickets t
    where t.user_id = auth.uid() and (t.status in ('searching', 'offered', 'paused') or t.lock_at > now() - interval '1 day')
  ) items
$$;

-- ---------------------------------------------------------------------------
-- 公开局：混双男女各两个位子
-- ---------------------------------------------------------------------------

-- 房间里（不算候补）这个性别已经有几个人
create function public.room_going(p_room uuid, p_gender public.gender)
returns int language sql stable security definer set search_path = '' as $$
  select count(*)::int from public.room_members m join public.profiles p on p.id = m.user_id
  where m.room_id = p_room and not m.waitlisted and p.gender is not distinct from p_gender
$$;
revoke execute on function public.room_going(uuid, public.gender) from public, anon, authenticated;

-- 在这个局里按哪把尺子算等级：混双、只限女生按自己的等级，其余按换算后的
create function public.room_level(p_user uuid, p_gender public.gender, p_mixed boolean)
returns int language sql stable security definer set search_path = '' as $$
  select case when p_mixed then (select round(rating)::int from public.profiles where id = p_user)
              else public.audience_level(p_user, p_gender) end
$$;
revoke execute on function public.room_level(uuid, public.gender, boolean) from public, anon, authenticated;

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
    'my_status', public.room_status_of(r.id, auth.uid()))
  from public.rooms r where r.id = p_room
$$;

-- 混双局只给填了性别的人看
create or replace function public.rooms_near(lat double precision, lng double precision, radius_km double precision default 30)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(public.room_summary(x.id) order by x.starts_at), '[]')
  from (select r.id, r.starts_at
        from public.rooms r join public.venues v on v.id = r.venue_id
        left join lateral (select gender from public.profiles where id = auth.uid()) me on true
        where r.visibility = 'public' and r.status = 'open' and r.starts_at > now()
          and extensions.st_dwithin(v.location, extensions.st_makepoint(rooms_near.lng, rooms_near.lat)::extensions.geography,
                                    least(radius_km, 100) * 1000)
          and not public.blocked_between(auth.uid(), r.owner_id)
          and public.accepts(r.gender, me.gender) and (not r.mixed or me.gender is not null)
        order by r.starts_at
        limit 50) x
  where auth.uid() is not null
$$;

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
  if (select count(*) from public.room_members m join public.rooms o on o.id = m.room_id where m.user_id = me and o.status = 'open') >= 10 then
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

-- 空出的位子按候补顺序补上；混双只补空出来的那边
create or replace function public.promote_room_waitlist(p_room uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  r public.rooms;
  next_up uuid;
begin
  select * into r from public.rooms where id = p_room and status = 'open';
  if r.id is null then return; end if;
  while (select count(*) from public.room_members where room_id = p_room and not waitlisted) < public.room_capacity(r.mode) loop
    select m.user_id into next_up from public.room_members m join public.profiles p on p.id = m.user_id
      where m.room_id = p_room and m.waitlisted and (not r.mixed or public.room_going(p_room, p.gender) < 2)
      order by m.joined_at limit 1;
    exit when next_up is null;
    update public.room_members set waitlisted = false where room_id = p_room and user_id = next_up;
    perform public.notify(next_up, 'room_promoted', 'You’re off the waitlist',
      'A spot opened up for {when} · {court}. If you can’t make it, cancel early.', '/app/rooms/' || p_room || '/',
      public.slot(r.starts_at, r.venue_id));
    next_up := null;
  end loop;
end
$$;

create or replace function public.start_room(p_room uuid)
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
  if (select count(*) from public.room_members where room_id = p_room and not waitlisted) <> public.room_capacity(r.mode)
     or (r.mixed and (public.room_going(p_room, 'male') <> 2 or public.room_going(p_room, 'female') <> 2)) then
    raise exception 'not_enough_players' using errcode = '22023';
  end if;
  if exists (select 1 from public.room_members m where m.room_id = p_room and not m.waitlisted
             and public.has_game_between(m.user_id, r.starts_at, r.ends_at)) then
    raise exception 'overlapping' using errcode = '23P01';
  end if;

  -- 分队：按换算后的水平第 1、4 一队；混双强的男生配弱一点的女生
  insert into public.games (mode, starts_at, ends_at, venue_id) values (r.mode, r.starts_at, r.ends_at, r.venue_id) returning id into new_game;
  insert into public.game_players (game_id, user_id, team, rating)
    select new_game, ranked.user_id,
           case when r.mode = 'singles' then ranked.n
                when r.mixed then case when (ranked.gender = 'male') = (ranked.n_gender = 1) then 1 else 2 end
                when ranked.n in (1, 4) then 1 else 2 end,
           ranked.rating
    from (select m.user_id, p.rating, p.gender,
                 row_number() over (order by public.open_rating(p.rating, p.gender) desc, m.joined_at)::smallint as n,
                 row_number() over (partition by p.gender order by p.rating desc, m.joined_at) as n_gender
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

drop function public.create_room(public.game_mode, public.room_visibility, text, timestamptz, timestamptz, int, int, text[], text, public.gender);
create function public.create_room(p_mode public.game_mode, p_visibility public.room_visibility, p_venue text,
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
  if (select count(*) from public.rooms where owner_id = me and status = 'open') >= 3 then
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
revoke execute on function public.create_room(public.game_mode, public.room_visibility, text, timestamptz, timestamptz, int, int, text[], text,
                                              public.gender, boolean) from public, anon;
grant execute on function public.create_room(public.game_mode, public.room_visibility, text, timestamptz, timestamptz, int, int, text[], text,
                                             public.gender, boolean) to authenticated;
