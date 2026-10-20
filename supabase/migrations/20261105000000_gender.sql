-- 男女：羽毛球男女差距很大，等级按性别各自算（女生的 4 级是女子 4 级）。
-- 男女同场时换算到同一把尺子：女子等级 − 1.5 ≈ 男子等级（男子三级能单打赢女子四级）。
-- 性别只用来定级和匹配（注册时说明），资料里必选男 / 女，可以改。
-- 约球可以选只和男生 / 只和女生打；公开局、球群可以设成只限男生 / 女生；排行榜男女分开。

create type public.gender as enum ('male', 'female');
alter table public.profiles add column gender public.gender;
grant insert (gender), update (gender) on public.profiles to authenticated;

-- 换算到同一把尺子上的等级（男子等级）；没填性别的按男子算
create function public.open_rating(p_rating numeric, p_gender public.gender)
returns numeric language sql immutable set search_path = '' as $$
  select p_rating - case when p_gender = 'female' then 1.5 else 0 end
$$;

-- 对方的性别合不合我的要求（不限 = null）
create function public.accepts(p_wanted public.gender, p_gender public.gender)
returns boolean language sql immutable set search_path = '' as $$
  select p_wanted is null or p_wanted = p_gender
$$;

-- 公开局、球群的等级范围按参加的人算：女生局按女子等级，其余按男子等级（女生的等级换算后比）
create function public.audience_level(p_user uuid, p_audience public.gender)
returns int language sql stable security definer set search_path = '' as $$
  select round(case when p_audience = 'female' then rating else public.open_rating(rating, gender) end)::int
  from public.profiles where id = p_user
$$;
revoke execute on function public.audience_level(uuid, public.gender) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 快速匹配：可以只和男生 / 女生打（null = 不限）。双方的要求都要满足，水平按换算后的等级比
-- ---------------------------------------------------------------------------

alter table public.match_tickets add column play_with public.gender;

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
  select public.open_rating(rating, gender), gender into my_rating, my_gender from public.profiles where id = t.user_id;

  -- 候选：同模式、时间重叠 ≥ 30 分钟、有共同球馆、水平差在双方的容忍范围内（1 级 = 3 档，按换算后的等级）、
  -- 性别合双方的要求、双方都没排除对方、那段时间没有别的球局。优先：被退回的 > 水平接近 > 先来的
  with candidates as (
    select c.id, c.user_id, c.starts_at, c.ends_at, c.venue_ids, c.priority, c.skill_tolerance, c.excluded_user_ids,
           c.play_with, p.gender, x.rating, abs(x.rating - my_rating) as gap, c.created_at
    from public.match_tickets c join public.profiles p on p.id = c.user_id
    cross join lateral (select public.open_rating(p.rating, p.gender) as rating) x
    where c.status = 'searching' and c.mode = t.mode and c.user_id <> t.user_id and c.lock_at > p_now
      and c.starts_at <= t.ends_at - interval '30 minutes' and c.ends_at >= t.starts_at + interval '30 minutes'
      and c.venue_ids && t.venue_ids
      and not c.user_id = any (t.excluded_user_ids) and not t.user_id = any (c.excluded_user_ids)
      and public.accepts(t.play_with, p.gender) and public.accepts(c.play_with, my_gender)
      and abs(round((x.rating - my_rating) * 3)) <= least(t.skill_tolerance, c.skill_tolerance) * 3
      and not public.has_game_between(c.user_id, t.starts_at, t.ends_at)
    order by c.priority desc, gap, c.created_at
    limit 8)
  select case
    when t.mode = 'singles' then (select array[t.id, c.id] from candidates c order by c.priority desc, c.gap, c.created_at limit 1)
    -- 双打：另外三人彼此也要满足上面的条件（含性别要求），并且有一家四个人都能去的球馆；被退回的多、水平集中的优先
    else (select array[t.id, a.id, b.id, c.id]
          from candidates a join candidates b on b.id > a.id join candidates c on c.id > b.id
          where a.user_id <> b.user_id and a.user_id <> c.user_id and b.user_id <> c.user_id
            and least(t.ends_at, a.ends_at, b.ends_at, c.ends_at) - greatest(t.starts_at, a.starts_at, b.starts_at, c.starts_at) >= interval '30 minutes'
            and exists (select 1 from unnest(t.venue_ids) v where v = any (a.venue_ids) and v = any (b.venue_ids) and v = any (c.venue_ids))
            and not array[a.user_id, b.user_id, c.user_id] && (a.excluded_user_ids || b.excluded_user_ids || c.excluded_user_ids)
            and public.accepts(a.play_with, b.gender) and public.accepts(b.play_with, a.gender)
            and public.accepts(a.play_with, c.gender) and public.accepts(c.play_with, a.gender)
            and public.accepts(b.play_with, c.gender) and public.accepts(c.play_with, b.gender)
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

  -- 分队：按换算后的水平排第 1、4 的一队，第 2、3 的一队（单打就是各一队）；开了自动接受的直接算确认
  insert into public.match_seats (offer_id, user_id, ticket_id, team, response, respond_by, responded_at)
    select new_offer, m.user_id, m.id, case when m.rank in (1, 4) then 1 else 2 end,
           case when m.auto_accept then 'accepted'::public.seat_response else 'pending' end,
           respond_by, case when m.auto_accept then p_now end
    from (select mt.*, row_number() over (order by public.open_rating(p.rating, p.gender) desc, mt.id) as rank
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

-- 有多少人在找、其中条件都合适的（和匹配时的条件一样，含性别要求）
create or replace function public.ticket_pool(p_ticket uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with t as (
    select mt.*, public.open_rating(p.rating, p.gender) as rating, p.gender, coalesce((select v.time_zone_id from public.venues v where v.id = mt.venue_ids[1]), 'UTC') as tz
    from public.match_tickets mt join public.profiles p on p.id = mt.user_id
    where mt.id = p_ticket and mt.user_id = auth.uid()),
  nearby as (
    select c.user_id, c.starts_at, c.ends_at, c.venue_ids, c.skill_tolerance, c.excluded_user_ids, c.play_with, p.gender,
           public.open_rating(p.rating, p.gender) as rating
    from t, public.match_tickets c join public.profiles p on p.id = c.user_id
    where c.status = 'searching' and c.mode = t.mode and c.user_id <> t.user_id and c.lock_at > now()
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

-- 发起时多一个“和谁打”（参数变了，先删旧的）
drop function public.submit_ticket(public.game_mode, timestamptz, timestamptz, text[], int, boolean);
create function public.submit_ticket(p_mode public.game_mode, p_starts_at timestamptz, p_ends_at timestamptz,
                                     p_venue_ids text[], p_skill_tolerance int, p_auto_accept boolean,
                                     p_play_with public.gender default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  venues text[];
  hurried boolean := p_starts_at < now() + interval '150 minutes';
  new_ticket uuid;
begin
  if me is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if not exists (select 1 from public.profiles where id = me) then raise exception 'no_profile' using errcode = 'P0002'; end if;
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

  insert into public.match_tickets (user_id, mode, starts_at, ends_at, venue_ids, skill_tolerance, auto_accept, lock_at, last_minute, play_with)
    values (me, p_mode, p_starts_at, p_ends_at, venues, p_skill_tolerance, p_auto_accept,
            p_starts_at - case when hurried then interval '20 minutes' else interval '2 hours' end, hurried, p_play_with)
    returning id into new_ticket;
  perform public.match_ticket(new_ticket, now());
  return new_ticket;
end
$$;
revoke execute on function public.submit_ticket(public.game_mode, timestamptz, timestamptz, text[], int, boolean, public.gender) from public, anon;
grant execute on function public.submit_ticket(public.game_mode, timestamptz, timestamptz, text[], int, boolean, public.gender) to authenticated;

create or replace function public.my_matchmaking()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(item order by starts_at), '[]') from (
    select t.starts_at, jsonb_build_object(
      'id', t.id, 'mode', t.mode, 'starts_at', t.starts_at, 'ends_at', t.ends_at, 'status', t.status,
      'skill_tolerance', t.skill_tolerance, 'auto_accept', t.auto_accept, 'lock_at', t.lock_at, 'game_id', t.game_id,
      'last_minute', t.last_minute, 'play_with', t.play_with,
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
-- 公开局、球群：可以只限男生 / 女生（null = 不限）。限定了的局只有对应性别能看到、能加入
-- ---------------------------------------------------------------------------

alter table public.rooms add column gender public.gender;
alter table public.play_groups add column gender public.gender;

create or replace function public.room_summary(p_room uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', r.id, 'mode', r.mode, 'visibility', r.visibility, 'status', r.status, 'closed_reason', r.closed_reason,
    'game_id', r.game_id, 'starts_at', r.starts_at, 'ends_at', r.ends_at, 'level_min', r.level_min, 'level_max', r.level_max,
    'tags', r.tags, 'note', r.note, 'gender', r.gender, 'capacity', public.room_capacity(r.mode), 'last_activity_at', r.last_activity_at,
    'going', (select count(*) from public.room_members m where m.room_id = r.id and not m.waitlisted),
    'waitlist', (select count(*) from public.room_members m where m.room_id = r.id and m.waitlisted),
    'owner', (select jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', p.rating) from public.profiles p where p.id = r.owner_id),
    'venue', (select jsonb_build_object('id', v.id, 'name', v.name, 'city', v.city, 'street', v.street, 'tz', v.time_zone_id,
                                        'lat', v.lat, 'lon', v.lon, 'pricing', v.pricing, 'country', v.country_code)
              from public.venues v where v.id = r.venue_id),
    'my_status', public.room_status_of(r.id, auth.uid()))
  from public.rooms r where r.id = p_room
$$;

create or replace function public.rooms_near(lat double precision, lng double precision, radius_km double precision default 30)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(public.room_summary(x.id) order by x.starts_at), '[]')
  from (select r.id, r.starts_at
        from public.rooms r join public.venues v on v.id = r.venue_id
        where r.visibility = 'public' and r.status = 'open' and r.starts_at > now()
          and extensions.st_dwithin(v.location, extensions.st_makepoint(rooms_near.lng, rooms_near.lat)::extensions.geography,
                                    least(radius_km, 100) * 1000)
          and not public.blocked_between(auth.uid(), r.owner_id)
          and public.accepts(r.gender, (select gender from public.profiles where id = auth.uid()))
        order by r.starts_at
        limit 50) x
  where auth.uid() is not null
$$;

create or replace function public.join_room_internal(p_room uuid, p_via_code boolean)
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

  level := public.audience_level(me, r.gender);
  if level is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if not public.accepts(r.gender, (select gender from public.profiles where id = me)) then
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
    from (select m.user_id, p.rating, row_number() over (order by public.open_rating(p.rating, p.gender) desc, m.joined_at)::smallint as n
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

drop function public.create_room(public.game_mode, public.room_visibility, text, timestamptz, timestamptz, int, int, text[], text);
create function public.create_room(p_mode public.game_mode, p_visibility public.room_visibility, p_venue text,
                                   p_starts_at timestamptz, p_ends_at timestamptz, p_level_min int, p_level_max int,
                                   p_tags text[] default '{}', p_note text default '', p_gender public.gender default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  level int;
  new_room uuid;
begin
  level := public.audience_level(me, p_gender);
  if level is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if not public.accepts(p_gender, (select gender from public.profiles where id = me)) then
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
  insert into public.rooms (code, owner_id, mode, visibility, venue_id, starts_at, ends_at, level_min, level_max, tags, note, gender)
    values (public.new_invite_code(), me, p_mode, p_visibility, p_venue, p_starts_at, p_ends_at,
            least(p_level_min, level), greatest(p_level_max, level),
            coalesce((select array_agg(distinct t) from unnest(p_tags) t), '{}'), btrim(coalesce(p_note, '')), p_gender)
    returning id into new_room;
  insert into public.room_members (room_id, user_id) values (new_room, me);
  return new_room;
end
$$;
revoke execute on function public.create_room(public.game_mode, public.room_visibility, text, timestamptz, timestamptz, int, int, text[], text, public.gender)
  from public, anon;
grant execute on function public.create_room(public.game_mode, public.room_visibility, text, timestamptz, timestamptz, int, int, text[], text, public.gender)
  to authenticated;

create or replace function public.group_summary(p_group uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', g.id, 'name', g.name, 'summary', g.summary, 'level_min', g.level_min, 'level_max', g.level_max, 'join_policy', g.join_policy, 'gender', g.gender,
    'venue', jsonb_build_object('id', v.id, 'name', v.name, 'city', v.city, 'tz', v.time_zone_id),
    'schedules', (select jsonb_agg(jsonb_build_object('weekday', s.weekday, 'start', s.start_minutes, 'end', s.end_minutes,
                                                      'capacity', s.capacity, 'fee', s.fee_note) order by s.weekday, s.start_minutes)
                  from public.group_schedules s where s.group_id = g.id),
    'activity', public.group_activity(g.id),
    'my_role', public.group_role_of(g.id, auth.uid()))
  from public.play_groups g join public.venues v on v.id = g.venue_id
  where g.id = p_group
$$;

create or replace function public.groups_near(lat double precision, lng double precision, radius_km double precision default 30)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(item order by (item -> 'activity' ->> 'sessions')::int desc, item ->> 'name'), '[]')
  from (select public.group_summary(g.id) as item
        from public.play_groups g join public.venues v on v.id = g.venue_id
        where extensions.st_dwithin(v.location, extensions.st_makepoint(groups_near.lng, groups_near.lat)::extensions.geography,
                                    least(radius_km, 100) * 1000)
          and not public.blocked_between(auth.uid(), g.owner_id)
          and public.accepts(g.gender, (select gender from public.profiles where id = auth.uid()))
        limit 50) x
  where auth.uid() is not null
$$;

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
  if level is null or level not between g.level_min and g.level_max then raise exception 'level_out_of_range' using errcode = '22023'; end if;
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

drop function public.create_group(text, text, text, int, int, public.join_policy, jsonb);
create function public.create_group(p_name text, p_venue text, p_summary text, p_level_min int, p_level_max int,
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
  if jsonb_typeof(p_schedules) is distinct from 'array' or jsonb_array_length(p_schedules) not between 1 and 3 then
    raise exception 'invalid_schedule' using errcode = '22023';
  end if;
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
  -- 防刷（放在写入之后，先报具体的输入错误）：每人最多当 5 个群的群主，每天最多建 2 个
  if (select count(*) from public.play_groups where owner_id = me) > 5
     or (select count(*) from public.play_groups where owner_id = me and created_at > now() - interval '1 day') > 2 then
    raise exception 'too_many_groups' using errcode = '54000';
  end if;
  perform public.ensure_sessions(new_group);
  return new_group;
end
$$;
revoke execute on function public.create_group(text, text, text, int, int, public.join_policy, jsonb, public.gender) from public, anon;
grant execute on function public.create_group(text, text, text, int, int, public.join_policy, jsonb, public.gender) to authenticated;

-- ---------------------------------------------------------------------------
-- 约战的“水平相近”、战绩里的对手强弱按换算后的等级比；排行榜男女分开排
-- ---------------------------------------------------------------------------

create or replace function public.challenge_availability(p_target uuid)
returns text language sql stable security definer set search_path = '' as $$
  with me as (select * from public.profiles where id = auth.uid()), them as (select * from public.profiles where id = p_target)
  select case
    when (select id from me) is null or (select id from them) is null or p_target = auth.uid() then 'hidden'
    when (select challenge_policy from them) = 'nobody' or public.blocked_between(auth.uid(), p_target) then 'hidden'
    when (select country_code from me) is distinct from (select country_code from them) then 'hidden'
    when (select challenge_policy from them) = 'friends' and not public.are_friends(auth.uid(), p_target) then 'friends_only'
    when (select challenge_policy from them) = 'similar'
         and abs((select public.open_rating(rating, gender) from me) - (select public.open_rating(rating, gender) from them)) > 1.01
      then 'level_out_of_range'
    when exists (select 1 from public.challenges where challenger_id = auth.uid() and target_id = p_target and status = 'pending' and expires_at > now())
      then 'already_pending'
    when exists (select 1 from public.challenges where challenger_id = auth.uid() and target_id = p_target
                 and status in ('declined', 'expired') and coalesce(responded_at, expires_at) > now() - interval '7 days') then 'cooldown'
    when (select count(*) from public.challenges where challenger_id = auth.uid() and status = 'pending' and expires_at > now()) >= 3 then 'too_many_outgoing'
    when (select count(*) from public.challenges where challenger_id = auth.uid() and created_at > now() - interval '1 day') >= 5 then 'daily_limit'
    when (select count(*) from public.challenges where target_id = p_target and status = 'pending' and expires_at > now()) >= 3 then 'target_busy'
    else 'available' end
$$;

create or replace function public.player_results(p_from timestamptz, p_to timestamptz)
returns table (game_id uuid, user_id uuid, won boolean, starts_at timestamptz, venue_id text, country text, tz text,
               opponents text, gap numeric)
language sql stable security definer set search_path = '' as $$
  select g.id, gp.user_id, gr.outcome = ('team' || gp.team)::public.result_outcome, g.starts_at, g.venue_id, v.country_code::text,
         coalesce(v.time_zone_id, 'UTC'),
         (select string_agg(o.user_id::text, '+' order by o.user_id) from public.game_players o where o.game_id = g.id and o.team <> gp.team),
         (select avg(public.open_rating(o.rating, op.gender)) from public.game_players o join public.profiles op on op.id = o.user_id
          where o.game_id = g.id and o.team <> gp.team)
           - (select avg(public.open_rating(m.rating, mp.gender)) from public.game_players m join public.profiles mp on mp.id = m.user_id
              where m.game_id = g.id and m.team = gp.team)
  from public.games g
  join public.venues v on v.id = g.venue_id
  join public.game_players gp on gp.game_id = g.id
  cross join lateral public.game_result(g.id) gr
  where g.status = 'scheduled' and g.starts_at >= p_from and g.starts_at < p_to
    and gr.status = 'verified' and gr.outcome <> 'friendly'
$$;

drop function public.venue_board(text, int);
create function public.venue_board(p_venue text, p_offset int default 0, p_gender public.gender default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  with board as (select coalesce(p_gender, (select gender from public.profiles where id = auth.uid()), 'male') as gender),
  month as (select date_trunc('month', now()) - least(greatest(p_offset, 0), 1) * interval '1 month' as starts),
  results as (
    select r.*, row_number() over (partition by r.user_id, r.opponents order by r.starts_at) as per_opponent
    from public.player_results((select starts from month), (select starts from month) + interval '1 month') r
    where r.venue_id = p_venue),
  capped as (
    select r.*, row_number() over (partition by r.user_id, (r.starts_at at time zone r.tz)::date order by r.starts_at) as per_day
    from results r where r.per_opponent <= 4),
  scores as (
    select c.user_id, count(*) as games, count(*) filter (where c.won) as wins,
           (select count(distinct o) from capped x, unnest(string_to_array(x.opponents, '+')) o where x.user_id = c.user_id and x.per_day <= 3) as opponents
    from capped c where c.per_day <= 3 group by c.user_id),
  ranked as (
    select s.*, p.nickname, p.rating, public.level_band(p.rating) as band,
           rank() over (partition by public.level_band(p.rating) order by s.games desc, s.wins desc) as rank
    from scores s join public.profiles p on p.id = s.user_id
    where s.games >= 3 and s.opponents >= 2 and public.board_eligible(s.user_id)
      and coalesce(p.gender, 'male') = (select gender from board)
      and (s.user_id = auth.uid() or not public.hidden_from(auth.uid(), s.user_id)))
  select jsonb_build_object(
    'venue', (select jsonb_build_object('id', v.id, 'name', v.name, 'city', v.city) from public.venues v where v.id = p_venue),
    'month_starts', (select starts from month), 'gender', (select gender from board),
    'bands', coalesce((select jsonb_agg(jsonb_build_object('band', b.band, 'entries', b.entries) order by b.band) from (
        select band, jsonb_agg(jsonb_build_object('id', user_id, 'nickname', nickname, 'rating', rating, 'rank', rank,
                                                  'games', games, 'wins', wins, 'me', user_id = auth.uid()) order by rank, lower(nickname)) as entries
        from ranked where rank <= 10 or user_id = auth.uid() group by band) b), '[]'))
  where auth.uid() is not null
$$;

drop function public.weekly_board(text, int);
create function public.weekly_board(p_scope text default 'global', p_offset int default 0, p_gender public.gender default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  with me as (select id, country_code::text as country, public.level_band(rating) as band, gender from public.profiles where id = auth.uid()),
  board as (select coalesce(p_gender, (select gender from me), 'male') as gender),
  week as (select (date_trunc('week', now() at time zone 'UTC') at time zone 'UTC') - least(greatest(p_offset, 0), 1) * interval '7 days' as starts),
  results as (
    select r.*, row_number() over (partition by r.user_id order by r.starts_at) as nth
    from public.player_results((select starts from week), (select starts from week) + interval '7 days') r
    where p_scope <> 'country' or r.country = (select country from me)),
  counted as (
    select r.*, row_number() over (partition by r.user_id, r.opponents order by r.starts_at) as meeting
    from results r where r.nth <= 15),
  scores as (
    select c.user_id,
           round(sum((case when c.won then 15 else 10 end) * least(1.5, greatest(0.5, 1 + coalesce(c.gap, 0) * 0.5))
                     * case c.meeting when 1 then 1 when 2 then 0.5 else 0 end))::int as points,
           count(*) as games, count(*) filter (where c.won) as wins,
           (select count(distinct o) from counted x, unnest(string_to_array(x.opponents, '+')) o where x.user_id = c.user_id) as opponents
    from counted c group by c.user_id),
  ranked as (
    select s.*, p.nickname, p.rating, rank() over (order by s.points desc, s.wins desc) as rank
    from scores s join public.profiles p on p.id = s.user_id
    where s.games >= 3 and s.opponents >= 2 and public.board_eligible(s.user_id)
      and coalesce(p.gender, 'male') = (select gender from board)
      and (p_scope <> 'level' or public.level_band(p.rating) = (select band from me))
      and (s.user_id = auth.uid() or not public.hidden_from(auth.uid(), s.user_id)))
  select jsonb_build_object(
    'week_starts', (select starts from week), 'gender', (select gender from board),
    'entries', coalesce((select jsonb_agg(jsonb_build_object('id', user_id, 'nickname', nickname, 'rating', rating, 'rank', rank,
                                                             'points', points, 'games', games, 'wins', wins, 'me', user_id = auth.uid())
                                          order by rank, lower(nickname))
                         from ranked where rank <= 50), '[]'),
    'me', (select jsonb_build_object('rank', r.rank, 'points', r.points) from ranked r where r.user_id = auth.uid()),
    'progress', (select jsonb_build_object('games', s.games, 'opponents', s.opponents, 'points', s.points) from scores s where s.user_id = auth.uid()),
    'eligible', public.board_eligible(auth.uid()))
  where auth.uid() is not null
$$;
revoke execute on function public.venue_board(text, int, public.gender), public.weekly_board(text, int, public.gender) from public, anon;
grant execute on function public.venue_board(text, int, public.gender), public.weekly_board(text, int, public.gender) to authenticated;

-- 资料页显示性别（女生局、男女换算都要看得到）
create or replace function public.player_card(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select base || jsonb_build_object(
    'win_rate', case when p_user = auth.uid() or (w ->> 'public')::boolean then w end,
    'challenge', public.challenge_availability(p_user),
    'message', public.message_option(auth.uid(), p_user) - 'group_id',
    'verified', pr.verified_kind,
    'avatar', pr.avatar_path,
    'gender', pr.gender)
  from public.player_card_base(p_user) base, public.win_rate(p_user) w, public.profiles pr
  where base is not null and pr.id = p_user
$$;

-- 举报多一个原因：性别填得不对（防止有人冒充进女生局）
alter table public.user_reports drop constraint user_reports_reason_check,
  add constraint user_reports_reason_check check (reason in ('harassment', 'scam', 'unsafe', 'fake', 'wrong_gender', 'other'));
