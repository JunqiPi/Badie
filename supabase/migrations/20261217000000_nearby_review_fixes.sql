-- 1.0.5 提交前复查的修正
-- - 等级：换算后的等级不低于 1、不高于 9。女生在不限性别的局里要减 1.5，rating 不到 2 的会算出 0 或负数：
--   两位 1 级女生约双打答应时报错，她们也开不了不限性别的局、加不进别人的公开局
-- - 同一时间约了几个人：一个成局以后，我提出的、和这场重叠的其他邀请自动撤回并告诉对方
--   （以前还开着，对方点“好”只看到“这个时间你已经有球局了”）
-- - 没定时间的球局：一个人签到就把时间定成现在，另一个人没答应过这个时间，这样的局不记爽约
-- - 附近的人、球馆页的人：结果不变，人多了不再变慢

-- ---------------------------------------------------------------------------
-- 等级限制在 1–9
-- ---------------------------------------------------------------------------

create or replace function public.audience_level(p_user uuid, p_audience public.gender)
returns int language sql stable security definer set search_path = '' as $$
  select greatest(1, least(9, round(case when p_audience = 'female' then rating else public.open_rating(rating, gender) end)))::int
  from public.profiles where id = p_user
$$;

-- ---------------------------------------------------------------------------
-- 成局（或定了时间）以后，重叠的邀请自动撤回
-- ---------------------------------------------------------------------------

-- 多了附近的人的邀请：时间是我提的、定好了具体时间、和这场重叠、还在等对方回复的，撤回并告诉对方。
-- 等我回复的不动（我去点“好”会被告知这个时间已经有球局）
create or replace function public.withdraw_invites_for(p_user uuid, p_game uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  g public.games;
  o record;
  seat record;
  inv record;
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

  -- 这场本身的那份（对方就在这场里）除外；别人正在操作的那份跳过，不等它
  for inv in select r.id, r.starts_at, r.venue_id, r.awaiting_id from public.rooms r
             where r.status = 'open' and r.invitee_id is not null and r.time_set
               and p_user in (r.owner_id, r.invitee_id) and r.awaiting_id <> p_user
               and r.starts_at < g.ends_at and g.starts_at < r.ends_at
               and not exists (select 1 from public.game_players gp where gp.game_id = p_game and gp.user_id = r.awaiting_id)
             for update of r skip locked
  loop
    update public.rooms set status = 'closed', closed_reason = 'owner_closed', awaiting_id = null, last_activity_at = now()
      where id = inv.id;
    delete from public.room_invites where room_id = inv.id;
    perform public.notify(inv.awaiting_id, 'invite_declined', 'Invite withdrawn', '{name} already has a game at {when}.',
      '/app/play/', public.slot(inv.starts_at, inv.venue_id) || jsonb_build_object('name', (select nickname from public.profiles where id = p_user)));
  end loop;
end
$$;

-- 回复邀请：对方那个时间已经有球局（撤回没赶上的少数情况）时说“TA 约不了”，不再说成是我有球局
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

  -- 双打：变成普通的公开局，水平范围是两个人的上下各一级，附近的人可以加入，人齐了房主开局
  if r.mode = 'doubles' then
    update public.rooms
      set invitee_id = null, awaiting_id = null, visibility = 'public', last_activity_at = now(),
          level_min = greatest(1, least(public.room_level(r.owner_id, null, false), public.room_level(r.invitee_id, null, false)) - 1),
          level_max = least(9, greatest(public.room_level(r.owner_id, null, false), public.room_level(r.invitee_id, null, false)) + 1)
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
-- 签到定下的时间：不记爽约
-- ---------------------------------------------------------------------------

alter table public.games add column time_by_check_in boolean not null default false;

-- 和原来一样，只是没定时间的球局被签到定下时间时记一笔（time_by_check_in）
create or replace function public.check_in(p_game uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  game public.games;
  new_start timestamptz;
  new_end timestamptz;
  player record;
begin
  update public.game_players gp set checked_in_at = coalesce(gp.checked_in_at, now())
    from public.games g
    where g.id = gp.game_id and gp.game_id = p_game and gp.user_id = me and g.status = 'scheduled'
      and now() between g.starts_at - interval '30 minutes' and g.ends_at;
  if not found then raise exception 'cannot_check_in' using errcode = 'P0002'; end if;

  -- 和定时间（set_game_time）同时发生时，等它做完再看
  select * into game from public.games where id = p_game for update;
  if game.time_set then return; end if;
  new_start := least(greatest(to_timestamp(floor(extract(epoch from now()) / 1800) * 1800), game.window_start),
                     game.window_end - make_interval(mins => game.duration_minutes));
  new_end := new_start + make_interval(mins => game.duration_minutes);
  update public.games set starts_at = new_start, ends_at = new_end, time_set = true, time_by_check_in = true where id = p_game;
  update public.rooms set starts_at = new_start, ends_at = new_end, time_set = true where game_id = p_game;
  for player in select user_id from public.game_players where game_id = p_game loop
    perform public.withdraw_invites_for(player.user_id, p_game);
    continue when player.user_id = me;
    perform public.notify(player.user_id, 'game_time_set', '{name} set the time', '{when} · {court}', '/app/games/' || p_game || '/',
      jsonb_build_object('name', (select nickname from public.profiles where id = me)) || public.slot(new_start, game.venue_id));
  end loop;
end
$$;

-- 这局他算不算爽约：没签到、没取消，同场多数人说他没来。时间是被签到临时定下的不算（他没答应过这个时间）
create or replace function public.judged_no_show(p_game uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select gp.checked_in_at is null and gp.cancelled_at is null and not g.time_by_check_in
       and (select count(*) from public.game_reviews r
            join public.game_players rp on rp.game_id = r.game_id and rp.user_id = r.reviewer_id and rp.cancelled_at is null
            where r.game_id = p_game and r.reviewee_id = p_user and r.attendance = 'no_show') * 2
         > (select count(*) from public.game_players o where o.game_id = p_game and o.user_id <> p_user and o.cancelled_at is null)
    from public.game_players gp join public.games g on g.id = gp.game_id
    where gp.game_id = p_game and gp.user_id = p_user), false)
$$;

-- ---------------------------------------------------------------------------
-- 附近的人、球馆页的人：结果不变，换个算法
-- ---------------------------------------------------------------------------

create index favorite_venues_venue_idx on public.favorite_venues (venue_id);

-- 每个人最近的球馆先算好一次（以前每个候选人都要把附近的收藏扫一遍，人数翻倍耗时翻四倍）
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

-- 先找这家球馆的人，再看能不能显示（以前每次都把所有用户过一遍）
create or replace function public.venue_people(p_venue text)
returns jsonb language sql stable security definer set search_path = '' as $$
  with here as (
    -- 合并过的球馆：原来那家的球局也算
    select v.id from public.venues v where v.id = p_venue or v.merged_into = p_venue),
  played as (
    select gp.user_id as id, max(g.ends_at) as last_played
    from public.games g join public.game_players gp on gp.game_id = g.id
    where g.venue_id in (select id from here) and g.status = 'scheduled' and g.time_set
      and g.ends_at between now() - interval '30 days' and now() and gp.cancelled_at is null
    group by gp.user_id),
  favorited as (
    select f.user_id as id, min(f.created_at) as since
    from public.favorite_venues f where f.venue_id in (select id from here)
    group by f.user_id),
  recent as (
    select x.id, x.last_played from played x join public.profiles p on p.id = x.id
    where p.id <> auth.uid() and p.show_as_regular and public.has_level(p.id)
      and exists (select 1 from public.favorite_venues f where f.user_id = p.id)
      and not public.hidden_from(auth.uid(), p.id) and not public.hidden_from(p.id, auth.uid())
    order by x.last_played desc, x.id
    limit 20),
  regulars as (
    select x.id, x.since from favorited x join public.profiles p on p.id = x.id
    where p.id <> auth.uid() and p.show_as_regular and public.has_level(p.id)
      and not public.hidden_from(auth.uid(), p.id) and not public.hidden_from(p.id, auth.uid())
    order by x.since, x.id
    limit 20)
  select jsonb_build_object(
    'recent', coalesce((select jsonb_agg(public.nearby_user(x.id) order by x.last_played desc, x.id) from recent x), '[]'),
    'regulars', coalesce((select jsonb_agg(public.nearby_user(x.id) order by x.since, x.id) from regulars x), '[]'))
  where auth.uid() is not null
$$;

-- ---------------------------------------------------------------------------
-- 通知译文
-- ---------------------------------------------------------------------------

insert into public.notification_texts (locale, english, translated)
select l.locale, t.english, t.translated
from (values
  ('zh-Hans', '{name} already has a game at {when}.', '{name} 已经约到 {when} 的球了。'),
  ('zh-Hant', '{name} already has a game at {when}.', '{name} 已經約到 {when} 的球了。'),
  ('ja', '{name} already has a game at {when}.', '{name} さんは {when} にすでに試合が決まりました。'),
  ('ko', '{name} already has a game at {when}.', '{name}님은 {when}에 이미 게임이 잡혔어요.'),
  ('hi', '{name} already has a game at {when}.', '{name} का {when} पर पहले से गेम तय हो गया।'),
  ('id', '{name} already has a game at {when}.', '{name} sudah dapat permainan pada {when}.'),
  ('ms', '{name} already has a game at {when}.', '{name} sudah ada permainan pada {when}.'),
  ('th', '{name} already has a game at {when}.', '{name} ได้เกมตอน {when} แล้ว'),
  ('vi', '{name} already has a game at {when}.', '{name} đã có trận lúc {when}.')
) as t(locale, english, translated)
join (select distinct locale from public.notification_texts) l on l.locale = t.locale;
