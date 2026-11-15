-- 让注册的人都能出现在发现页（2026-11-15 用户定的）
-- - 跳过定级问卷的人按 3 级算（rating 默认就是 3），和定过级的人一样进附近的人、能被约
-- - 双打邀请答应后变成的公开局不限水平（约球默认不限等级）
-- - 没有常去球馆的人：按最近发过的约球请求、开过或加入的房间、打过的球局、加入的球群补一家常去球馆
--   （都没有的，客户端下次拿到定位时自动收藏最近的一家）

-- ---------------------------------------------------------------------------
-- 跳过问卷的按 3 级算：有资料就算有等级
-- ---------------------------------------------------------------------------

create or replace function public.has_level(p_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles p where p.id = p_user)
$$;

-- 附近的人：不再要求定过级
create or replace function public.nearby_players(p_lat double precision, p_lon double precision, p_radius_km double precision)
returns jsonb language sql stable security definer set search_path = '' as $$
  with here as (
    select extensions.st_makepoint(p_lon, p_lat)::extensions.geography as g,
           (least(greatest(p_radius_km, 1), 100) * 1000)::double precision as m),
  me as (
    select p.id, public.open_rating(p.rating, p.gender) as level from public.profiles p where p.id = auth.uid()),
  near as materialized (
    select f.user_id, v.id, v.name, extensions.st_distance(v.location, h.g) as dist
    from here h
    join public.venues v on extensions.st_dwithin(v.location, h.g, h.m)
    join public.favorite_venues f on f.venue_id = v.id
    where f.user_id <> auth.uid()),
  closest as (
    select n.user_id, min(n.dist) as nearest from near n group by n.user_id),
  picked as (
    select p.id,
           (select count(*) from public.favorite_venues a join public.favorite_venues b on b.venue_id = a.venue_id and b.user_id = p.id
            where a.user_id = me.id)::int as shared,
           abs(public.open_rating(p.rating, p.gender) - me.level) as gap,
           c.nearest
    from me
    cross join closest c
    join public.profiles p on p.id = c.user_id
    where p.show_as_regular
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
-- 双打邀请答应后：公开局不限水平
-- ---------------------------------------------------------------------------

create or replace function public.respond_invite(p_room uuid, p_accept boolean)
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

  -- 不了：谁都能说（包括不能约球的人）
  if not p_accept then
    perform public.decline_invite(p_room, me);
    return jsonb_build_object('status', 'declined', 'game_id', null);
  end if;

  if r.window_end - make_interval(mins => r.duration_minutes) <= now() then
    raise exception 'invite_expired' using errcode = 'P0002';
  end if;
  -- 窗口里还要有一个“现在 + 30 分钟”以后能开始的时间
  if public.first_window_start(r.window_start, r.window_end, r.duration_minutes, r.daypart,
                               (select coalesce(v.time_zone_id, 'UTC') from public.venues v where v.id = r.venue_id),
                               now() + interval '30 minutes') is null then
    raise exception 'too_late' using errcode = '22023';
  end if;
  -- 两个人都要能约球（发邀请以后才被暂停的也拦下）
  if public.suspended_until(r.owner_id) is not null or public.suspended_until(r.invitee_id) is not null then
    raise exception 'suspended' using errcode = '42501';
  end if;
  if r.time_set and public.has_game_between(me, r.starts_at, r.ends_at) then
    raise exception 'overlapping' using errcode = '23P01';
  end if;
  if r.time_set and public.has_game_between(other, r.starts_at, r.ends_at) then
    raise exception 'not_available' using errcode = 'P0002';
  end if;

  insert into public.room_members (room_id, user_id) values (p_room, r.invitee_id) on conflict do nothing;
  delete from public.room_invites where room_id = p_room;

  -- 双打：变成普通的公开局，不限水平，附近的人可以加入，人齐了房主开局
  if r.mode = 'doubles' then
    update public.rooms
      set invitee_id = null, awaiting_id = null, visibility = 'public', last_activity_at = now(),
          level_min = 1, level_max = 9
      where id = p_room;
    perform public.notify(other, 'room', '{name} said yes to doubles', '{when} · {court}. 2 more players can join.',
      '/app/rooms/' || p_room || '/',
      jsonb_build_object('name', (select nickname from public.profiles where id = me)) || public.slot(r.starts_at, r.venue_id));
    return jsonb_build_object('status', 'accepted', 'game_id', null, 'room_id', p_room);
  end if;

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
  return jsonb_build_object('status', 'accepted', 'game_id', new_game, 'room_id', p_room);
end
$$;

-- ---------------------------------------------------------------------------
-- 补常去球馆：没有常去球馆的人，按最近用过的球馆补一家（合并过的换成保留的那家，待审核的不要）
-- ---------------------------------------------------------------------------

insert into public.favorite_venues (user_id, venue_id)
select distinct on (x.user_id) x.user_id, coalesce(v.merged_into, v.id)
from (
  select t.user_id, t.venue_ids[1] as venue_id, t.created_at as at from public.match_tickets t
  union all
  select m.user_id, r.venue_id, m.joined_at from public.room_members m join public.rooms r on r.id = m.room_id where r.venue_id is not null
  union all
  select gp.user_id, g.venue_id, g.starts_at from public.game_players gp join public.games g on g.id = gp.game_id
  union all
  select gm.user_id, pg.venue_id, gm.joined_at from public.group_members gm join public.play_groups pg on pg.id = gm.group_id where not gm.pending
) x
join public.venues v on v.id = x.venue_id
join public.profiles p on p.id = x.user_id
where not v.hidden_pending_review
  and not exists (select 1 from public.favorite_venues f where f.user_id = x.user_id)
order by x.user_id, x.at desc
on conflict do nothing;
