-- 上架前的检查（模拟各种用户行为）发现的问题：
-- 1. 赛果：局数要两队都填、一致才算；“练球”和“平局”是两种说法；平局不上榜，老字段 games / wins 不含平局；比分换成我方视角
-- 2. 按天看人：连点、同时点两张卡不会重复约；我这个时间已有单打请求就直接用它去约；为邀请建的请求没约成自动取消；
--    别人约我、我没回不会被暂停；同一张卡只能约一次，双打每天最多邀请 20 次；性别没填刷不到混双；日期人数和卡片一致
-- 3. 管理员撤下的照片不能再换回来；拉黑了看不到对方的照片

-- 1. 赛果 -------------------------------------------------------------------------

create or replace function public.game_result(p_game uuid, p_now timestamptz default now())
returns table (status text, outcome public.result_outcome) language sql stable security definer set search_path = '' as $$
  with claims as (
    select r.outcome, r.team1_games, r.team2_games, gp.team from public.result_reports r
    join public.game_players gp on gp.game_id = r.game_id and gp.user_id = r.reporter_id
    where r.game_id = p_game and r.outcome is not null),
  summary as (select count(distinct outcome) as outcomes, count(distinct team) as teams, min(outcome::text) as outcome,
                     count(distinct (team1_games, team2_games)) filter (where team1_games is not null) as counts,
                     count(distinct (team1_games is null)) filter (where outcome = 'friendly') as friendly_kinds
              from claims)
  select case
      when s.outcomes > 1 or s.counts > 1 or s.friendly_kinds > 1 then 'disputed'
      when s.teams = 2 then 'verified'
      when exists (select 1 from public.game_players gp
                   left join public.result_reports r on r.game_id = gp.game_id and r.reporter_id = gp.user_id
                   where gp.game_id = p_game group by gp.team
                   having bool_and(r.reporter_id is not null and r.outcome is null)) then 'unsure'
      when p_now > (select ends_at from public.games where id = p_game) + interval '7 days' then 'expired'
      else 'awaiting' end,
    case when s.outcomes = 1 and s.counts <= 1 and s.friendly_kinds <= 1 and s.teams = 2 then s.outcome::public.result_outcome end
  from summary s
$$;


-- 局数：两队都填了、而且一致才用（只有一方填的，按 1 局算）
create or replace function public.game_rounds(p_game uuid)
returns table (team1 smallint, team2 smallint) language sql stable security definer set search_path = '' as $$
  select min(r.team1_games), min(r.team2_games) from public.result_reports r
  join public.game_players gp on gp.game_id = r.game_id and gp.user_id = r.reporter_id
  where r.game_id = p_game and r.team1_games is not null
  having count(distinct gp.team) = 2 and count(distinct (r.team1_games, r.team2_games)) = 1
$$;

alter table public.game_results add column draw boolean not null default false;

create or replace function public.refresh_game_results(p_game uuid)
returns void language sql security definer set search_path = '' as $$
  delete from public.game_results where game_id = p_game;
  insert into public.game_results (game_id, user_id, won, starts_at, venue_id, country, tz, opponents, gap, rounds_won, rounds_played, draw)
  select g.id, gp.user_id, gr.outcome = ('team' || gp.team)::public.result_outcome, g.starts_at, g.venue_id, v.country_code::text,
         coalesce(v.time_zone_id, 'UTC'),
         (select string_agg(o.user_id::text, '+' order by o.user_id) from public.game_players o where o.game_id = g.id and o.team <> gp.team),
         (select avg(public.open_rating(o.rating, op.gender)) from public.game_players o join public.profiles op on op.id = o.user_id
          where o.game_id = g.id and o.team <> gp.team)
           - (select avg(public.open_rating(m.rating, mp.gender)) from public.game_players m join public.profiles mp on mp.id = m.user_id
              where m.game_id = g.id and m.team = gp.team),
         coalesce(case gp.team when 1 then rounds.team1 else rounds.team2 end,
                  case when gr.outcome = ('team' || gp.team)::public.result_outcome then 1 else 0 end),
         coalesce(rounds.team1 + rounds.team2, 1),
         gr.outcome = 'friendly'
  from public.games g
  join public.venues v on v.id = g.venue_id
  join public.game_players gp on gp.game_id = g.id
  cross join public.game_result(p_game) gr
  left join public.game_rounds(p_game) rounds on true
  where g.id = p_game and gr.status = 'verified' and (gr.outcome <> 'friendly' or rounds.team1 is not null)
$$;

-- 周榜读这个：平局不上榜
create or replace function public.player_results(p_from timestamptz, p_to timestamptz)
returns table (game_id uuid, user_id uuid, won boolean, starts_at timestamptz, venue_id text, country text, tz text,
               opponents text, gap numeric)
language sql stable security definer set search_path = '' as $$
  select r.game_id, r.user_id, r.won, r.starts_at, r.venue_id, r.country, r.tz, r.opponents, r.gap
  from public.game_results r join public.games g on g.id = r.game_id and g.status = 'scheduled'
  where r.starts_at >= p_from and r.starts_at < p_to and not r.draw
$$;

create or replace function public.venue_board(p_venue text, p_offset int default 0, p_gender public.gender default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  with board as (select coalesce(p_gender, (select gender from public.profiles where id = auth.uid()), 'male') as gender),
  month as (select date_trunc('month', now()) - least(greatest(p_offset, 0), 1) * interval '1 month' as starts),
  results as (
    select r.*, row_number() over (partition by r.user_id, r.opponents order by r.starts_at) as per_opponent
    from public.game_results r join public.games g on g.id = r.game_id and g.status = 'scheduled'
    where r.venue_id = p_venue and not r.draw and r.starts_at >= (select starts from month) and r.starts_at < (select starts from month) + interval '1 month'),
  capped as (
    select r.*, row_number() over (partition by r.user_id, (r.starts_at at time zone r.tz)::date order by r.starts_at) as per_day
    from results r where r.per_opponent <= 4),
  opponents as (
    select x.user_id, count(distinct o) as opponents
    from capped x, unnest(string_to_array(x.opponents, '+')) o where x.per_day <= 3 group by x.user_id),
  scores as (
    select c.user_id, count(*) as games, count(*) filter (where c.won) as wins, o.opponents
    from capped c join opponents o using (user_id) where c.per_day <= 3 group by c.user_id, o.opponents),
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


-- 胜率：games / wins（老版本 App 用）不含平局；rounds / round_wins 含平局的局数；满 5 场公开按分出胜负的场数
create or replace function public.win_rate(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with counted as (
    select r.*, row_number() over (partition by r.opponents order by r.starts_at) as nth
    from public.game_results r join public.games g on g.id = r.game_id and g.status = 'scheduled'
    where r.user_id = p_user and r.starts_at >= date_trunc('month', now()) and r.starts_at < now() + interval '1 day')
  select jsonb_build_object(
    'games', count(*) filter (where not draw), 'wins', count(*) filter (where won),
    'draws', count(*) filter (where draw),
    'rounds', coalesce(sum(rounds_played), 0), 'round_wins', coalesce(sum(rounds_won), 0),
    'opponents', (select count(distinct o) from counted c, unnest(string_to_array(c.opponents, '+')) o where c.nth <= 3),
    'gap', coalesce(round(avg(gap), 2), 0),
    'public', count(*) filter (where not draw) >= 5)
  from counted where nth <= 3
$$;

create or replace function public.my_games()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(item order by starts_at desc), '[]') from (
    select g.starts_at, jsonb_build_object(
      'id', g.id, 'mode', g.mode, 'starts_at', g.starts_at, 'ends_at', g.ends_at, 'status', g.status,
      'venue', jsonb_build_object('id', v.id, 'name', v.name, 'city', v.city, 'street', v.street, 'tz', v.time_zone_id,
                                  'lat', v.lat, 'lon', v.lon, 'pricing', v.pricing, 'country', v.country_code),
      'host_id', public.game_host(g.id),
      'my_team', me.team, 'checked_in', me.checked_in_at is not null,
      'my_report', (select jsonb_build_object('outcome', r.outcome, 'score', r.score, 'team1_games', r.team1_games, 'team2_games', r.team2_games)
                    from public.result_reports r where r.game_id = g.id and r.reporter_id = auth.uid()),
      'result', (select to_jsonb(gr) from public.game_result(g.id) gr),
      -- 最近一次填的比分（双方都填了以后来的为准）
      'score', (select case when rp.team = me.team then r.score
                            else regexp_replace(r.score, '(\d+)\s*([:/-])\s*(\d+)', '\3\2\1', 'g') end
                from public.result_reports r
                join public.game_players rp on rp.game_id = r.game_id and rp.user_id = r.reporter_id
                where r.game_id = g.id and r.score is not null
                order by (r.reporter_id = auth.uid()) desc, r.updated_at desc limit 1),
      -- 双方确认以后才给局数
      'rounds', (select jsonb_build_object('team1', x.team1, 'team2', x.team2) from public.game_rounds(g.id) x
                 where (select r.status from public.game_result(g.id) r) = 'verified'),
      'review_until', g.ends_at + interval '48 hours',
      'players', (select jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', gp.rating, 'team', gp.team,
                                                      'me', gp.user_id = auth.uid(), 'checked_in', gp.checked_in_at is not null,
                                                      'paid', gp.paid_at is not null,
                                                      'reviewed', exists (select 1 from public.game_reviews r where r.game_id = g.id
                                                                          and r.reviewer_id = auth.uid() and r.reviewee_id = gp.user_id))
                                   order by gp.team, gp.rating desc)
                  from public.game_players gp join public.profiles p on p.id = gp.user_id where gp.game_id = g.id)
    ) as item
    from public.games g
    join public.game_players me on me.game_id = g.id and me.user_id = auth.uid()
    join public.venues v on v.id = g.venue_id
    where g.ends_at > now() - interval '60 days'
  ) items
$$;


do $$
begin
  perform public.refresh_game_results(id) from public.games where id in (select game_id from public.result_reports);
end
$$;

-- 2. 按天看人 -------------------------------------------------------------------------

-- 混双要一男一女：我没填性别就约不了
create or replace function public.can_invite(p_me uuid, t public.match_tickets)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles me, public.profiles them
    where me.id = p_me and them.id = t.user_id and them.show_searching and p_me <> t.user_id
      and not public.blocked_between(p_me, t.user_id) and not p_me = any (t.excluded_user_ids)
      and abs(round((public.open_rating(me.rating, me.gender) - public.open_rating(them.rating, them.gender)) * 3)) <= t.skill_tolerance * 3
      and (t.play_with is null or t.play_with = me.gender)
      and (not t.mixed or (me.gender is not null and them.gender is not null and me.gender <> them.gender)))
$$;
revoke execute on function public.can_invite(uuid, public.match_tickets) from public, anon, authenticated;

create or replace function public.day_candidates(p_from timestamptz, p_to timestamptz, p_lat double precision, p_lon double precision,
                                      p_radius_km double precision)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(c order by c ->> 'starts_at'), '[]') from (
    select jsonb_build_object(
             'ticket', t.id, 'mode', t.mode, 'mixed', t.mixed, 'play_with', t.play_with,
             'starts_at', t.starts_at, 'ends_at', t.ends_at,
             'user', jsonb_build_object('id', p.id, 'nickname', p.nickname, 'tag', p.tag, 'rating', p.rating, 'gender', p.gender,
                                        'recent_no_shows', public.recent_no_shows(p.id), 'avatar', p.avatar_path,
                                        'card_color', p.card_color, 'card_photo', p.card_photo_path),
             -- 每家球馆离我多远：右滑约的时候用最近的那家
             'venues', (select jsonb_agg(jsonb_build_object(
                                'id', v.id, 'name', v.name,
                                'km', round((extensions.st_distance(v.location, extensions.st_makepoint(p_lon, p_lat)::extensions.geography) / 1000)::numeric, 1))
                              order by extensions.st_distance(v.location, extensions.st_makepoint(p_lon, p_lat)::extensions.geography))
                        from public.venues v where v.id = any (t.venue_ids))) as c
    from public.match_tickets t join public.profiles p on p.id = t.user_id
    where auth.uid() is not null and p_to - p_from <= interval '2 days'
      and t.status = 'searching' and t.starts_at >= p_from and t.starts_at < p_to and t.lock_at > now() + interval '30 minutes'
      and public.can_invite(auth.uid(), t)
      and not exists (select 1 from public.candidate_skips s where s.viewer = auth.uid() and s.ticket_id = t.id)
      and exists (select 1 from public.venues v
                  where v.id = any (t.venue_ids)
                    and extensions.st_dwithin(v.location, extensions.st_makepoint(p_lon, p_lat)::extensions.geography,
                                              least(greatest(p_radius_km, 1), 100) * 1000))
    order by t.starts_at
    limit 50) x
$$;


-- 日期上的人数：和点进去看到的卡片用同一套条件
create or replace function public.pool_by_day(p_lat double precision, p_lon double precision, p_radius_km double precision, p_tz text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_object_agg(d.day, d.players), '{}') from (
    select (t.starts_at at time zone p_tz)::date::text as day, count(distinct t.user_id) as players
    from public.match_tickets t
    where t.status = 'searching' and t.lock_at > now() + interval '30 minutes' and t.starts_at < now() + interval '31 days'
      and public.can_invite(auth.uid(), t)
      and not exists (select 1 from public.candidate_skips s where s.viewer = auth.uid() and s.ticket_id = t.id)
      and exists (select 1 from public.venues v
                  where v.id = any (t.venue_ids)
                    and extensions.st_dwithin(v.location, extensions.st_makepoint(p_lon, p_lat)::extensions.geography,
                                              least(greatest(p_radius_km, 1), 100) * 1000))
    group by 1) d
  where auth.uid() is not null
$$;

create index if not exists candidate_skips_ticket_idx on public.candidate_skips (ticket_id);

-- 邀请来的提议记下是谁约的；只为邀请建的请求打个记号
alter table public.match_offers add column invited_by uuid references auth.users (id) on delete set null;
alter table public.match_tickets add column invite_only boolean not null default false;

-- 只为邀请建的请求：对方没接受（提议作废、退回去接着找）就直接取消，不变成我没设过的公开请求
create function public.cancel_unused_invite_ticket()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.invite_only and old.status = 'offered' and new.status in ('searching', 'paused') then
    new.status := 'cancelled';
    new.offer_id := null;
  end if;
  return new;
end
$$;
create trigger invite_only_tickets before update of status on public.match_tickets
  for each row execute function public.cancel_unused_invite_ticket();

create or replace function public.invite_ticket(p_ticket uuid, p_venue text, p_starts_at timestamptz)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  t public.match_tickets;
  slot_end timestamptz;
  hurried boolean;
  tz text;
  lock_time timestamptz;
  respond_by timestamptz;
  mine uuid;
  offer uuid;
begin
  if me is null or not exists (select 1 from public.profiles where id = me) then raise exception 'not_signed_in' using errcode = '42501'; end if;
  -- 同一个人的邀请排队处理：同时点两张卡不会都约上、时间撞在一起
  perform pg_advisory_xact_lock(hashtextextended('invite:' || me::text, 0));
  select * into t from public.match_tickets where id = p_ticket for update;
  if t.id is null or t.status <> 'searching' or t.mode <> 'singles' or t.lock_at <= now() + interval '30 minutes'
     or not public.can_invite(me, t)
     or exists (select 1 from public.candidate_skips s where s.viewer = me and s.ticket_id = t.id) then
    raise exception 'not_available' using errcode = 'P0002';
  end if;
  if not p_venue = any (t.venue_ids) or extract(epoch from p_starts_at)::bigint % 1800 <> 0 then
    raise exception 'invalid_slot' using errcode = '22023';
  end if;
  slot_end := least(t.ends_at, p_starts_at + interval '2 hours');
  if p_starts_at < greatest(t.starts_at, now() + interval '30 minutes') or slot_end - p_starts_at < interval '1 hour' then
    raise exception 'invalid_slot' using errcode = '22023';
  end if;
  -- 我这个时间正在找人的单打请求：直接用它去约（没约成会照常接着找）；别的撞车（等确认中的、暂停的、双打、已有球局）不行
  select id into mine from public.match_tickets
    where user_id = me and status = 'searching' and mode = 'singles' and starts_at < slot_end and p_starts_at < ends_at
    order by created_at limit 1;
  if exists (select 1 from public.match_tickets where user_id = me and status in ('searching', 'offered', 'paused')
             and starts_at < slot_end and p_starts_at < ends_at and id is distinct from mine)
     or public.has_game_between(me, p_starts_at, slot_end) then
    raise exception 'overlapping' using errcode = '23P01';
  end if;
  if (select count(*) from public.match_tickets where user_id = me and created_at > now() - interval '1 day') >= 20 then
    raise exception 'too_many_requests' using errcode = '54000';
  end if;

  hurried := p_starts_at < now() + interval '150 minutes';
  lock_time := p_starts_at - case when hurried then interval '20 minutes' else interval '2 hours' end;
  select coalesce(time_zone_id, 'UTC') into tz from public.venues where id = p_venue;
  respond_by := least(public.offer_respond_by(p_starts_at, now(), tz), lock_time);
  if respond_by < now() + interval '3 minutes' then raise exception 'too_soon' using errcode = '22023'; end if;

  if mine is null then
    -- 只为这次邀请建的请求：没约成就自动取消（见 invite_only_tickets 触发器），不会变成我没设过的公开请求
    insert into public.match_tickets (user_id, mode, starts_at, ends_at, venue_ids, skill_tolerance, auto_accept, lock_at, last_minute, status, invite_only)
      values (me, 'singles', p_starts_at, slot_end, array[p_venue], 8, false, lock_time, hurried, 'offered', true)
      returning id into mine;
  else
    update public.match_tickets set status = 'offered' where id = mine;
  end if;
  insert into public.match_offers (mode, starts_at, ends_at, venue_id, lock_at, invited_by)
    values ('singles', p_starts_at, slot_end, p_venue, lock_time, me) returning id into offer;
  insert into public.match_seats (offer_id, user_id, ticket_id, team, response, respond_by, responded_at)
    values (offer, me, mine, 1, 'accepted', respond_by, now()), (offer, t.user_id, t.id, 2, 'pending', respond_by, null);
  update public.match_tickets set offer_id = offer where id = mine;
  update public.match_tickets set status = 'offered', offer_id = offer where id = t.id;
  insert into public.candidate_skips (viewer, ticket_id) values (me, t.id) on conflict do nothing;

  perform public.notify(t.user_id, 'offer', '{name} wants to play', '{when} · {court}. Confirm by {by}.', '/app/play/',
    public.slot(p_starts_at, p_venue) || jsonb_build_object('name', (select nickname from public.profiles where id = me),
                                                              'by', jsonb_build_object('at', respond_by, 'tz', tz)));
  return offer;
end
$$;


create or replace function public.invite_doubles(p_ticket uuid, p_venue text, p_starts_at timestamptz)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  t public.match_tickets;
  slot_end timestamptz;
  mine int;
  theirs int;
  room uuid;
begin
  if me is null or not exists (select 1 from public.profiles where id = me) then raise exception 'not_signed_in' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended('invite:' || me::text, 0));
  select * into t from public.match_tickets where id = p_ticket for update;
  if t.id is null or t.status <> 'searching' or t.mode <> 'doubles' or t.lock_at <= now() + interval '30 minutes'
     or not public.can_invite(me, t)
     or exists (select 1 from public.candidate_skips s where s.viewer = me and s.ticket_id = t.id)
     -- 同一个人一天只约一次
     or exists (select 1 from public.room_invites i where i.invited_by = me and i.user_id = t.user_id and i.created_at > now() - interval '1 day') then
    raise exception 'not_available' using errcode = 'P0002';
  end if;
  if not p_venue = any (t.venue_ids) or extract(epoch from p_starts_at)::bigint % 1800 <> 0 then
    raise exception 'invalid_slot' using errcode = '22023';
  end if;
  slot_end := least(t.ends_at, p_starts_at + interval '2 hours');
  if p_starts_at < greatest(t.starts_at, now() + interval '30 minutes') or slot_end - p_starts_at < interval '1 hour' then
    raise exception 'invalid_slot' using errcode = '22023';
  end if;
  if (select count(*) from public.room_invites where invited_by = me and created_at > now() - interval '1 day') >= 20 then
    raise exception 'too_many_requests' using errcode = '54000';
  end if;
  mine := public.room_level(me, t.play_with, t.mixed);
  theirs := public.room_level(t.user_id, t.play_with, t.mixed);
  room := public.create_room('doubles', 'public', p_venue, p_starts_at, slot_end,
                             greatest(1, least(mine, theirs) - 1), least(9, greatest(mine, theirs) + 1),
                             '{}', '', t.play_with, t.mixed);
  insert into public.room_invites (room_id, user_id, invited_by) values (room, t.user_id, me) on conflict do nothing;
  perform public.notify(t.user_id, 'room', '{name} invited you to play', '{when} · {court}. Open Badie to join.',
    '/app/rooms/' || room || '/',
    jsonb_build_object('name', (select nickname from public.profiles where id = me)) || coalesce(public.slot(p_starts_at, p_venue), '{}'));
  -- 这张卡片约过了，不再出现
  insert into public.candidate_skips (viewer, ticket_id) values (me, p_ticket) on conflict do nothing;
  return room;
end
$$;


create or replace function public.process_matchmaking(p_now timestamptz default now())
returns void language plpgsql security definer set search_path = '' as $$
declare
  seat record;
  item record;
begin
  -- 没在期限内回复：本人的请求暂停（不再给不在线的人发提议，回来点一下就继续），这组作废
  for seat in update public.match_seats s set response = 'expired'
              from public.match_offers o
              where o.id = s.offer_id and o.status = 'open' and s.response = 'pending' and s.respond_by <= p_now
              returning s.user_id, s.ticket_id, o.starts_at, o.venue_id, o.invited_by loop
    if seat.invited_by is not null then
      update public.match_tickets set status = 'searching', offer_id = null where id = seat.ticket_id and status = 'offered';
      continue;
    end if;
    update public.match_tickets set status = 'paused', offer_id = null where id = seat.ticket_id and status = 'offered';
    perform public.notify(seat.user_id, 'missed', 'You missed a match',
      '{when} · {court}. Your request is paused. Open Badie to keep looking.', '/app/play/', public.slot(seat.starts_at, seat.venue_id));
  end loop;

  for item in select o.id from public.match_offers o
              where o.status = 'open'
                and (o.lock_at <= p_now or exists (select 1 from public.match_seats s where s.offer_id = o.id and s.response = 'expired')) loop
    perform public.fail_offer(item.id, p_now);
  end loop;

  -- 到锁定时间还没约成：结束，不计入任何记录（正在确认中的等提议有结果再说）
  for item in update public.match_tickets set status = 'expired'
              where status in ('searching', 'paused') and lock_at <= p_now
              returning user_id, starts_at, venue_ids[1] as venue_id, last_minute loop
    perform public.notify(item.user_id, 'expired', 'No game this time',
      case when item.last_minute then 'We couldn’t find players for {when} · {court}. Nothing counts against you.'
           else 'We couldn’t find players for {when} · {court}. Nothing counts against you. Still want to play? Try a last-minute search.' end,
      '/app/play/', public.slot(item.starts_at, item.venue_id));
  end loop;

  for item in select id from public.match_tickets where status = 'searching' order by priority desc, created_at loop
    perform public.match_ticket(item.id, p_now);
  end loop;
end
$$;


-- 3. 照片和资料卡 -------------------------------------------------------------------------

-- 管理员撤下的照片记下来，不能再设回去（别人把我的照片路径清掉 = 撤下；自己换掉、删掉不算）
create table public.removed_photos (
  path text primary key,
  removed_at timestamptz not null default now()
);
alter table public.removed_photos enable row level security;
revoke all on public.removed_photos from anon, authenticated;

create or replace function public.forget_removed_photos()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.removed_photos (path)
    select x from unnest(array[old.avatar_path, old.card_photo_path]) x
    where x is not null and x is distinct from new.avatar_path and x is distinct from new.card_photo_path
      and auth.uid() is distinct from new.id
  on conflict do nothing;
  return new;
end
$$;
create trigger profiles_removed_photos after update of avatar_path, card_photo_path on public.profiles
  for each row execute function public.forget_removed_photos();


create or replace function public.set_avatar(p_path text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if p_path is not null and (p_path !~ ('^' || me || '/[0-9a-f-]{36}\.jpg$')
                             or not exists (select 1 from storage.objects where bucket_id = 'avatars' and name = p_path)
                             or exists (select 1 from public.removed_photos where path = p_path)) then
    raise exception 'invalid_avatar' using errcode = '22023';
  end if;
  update public.profiles set avatar_path = p_path where id = me;
end
$$;


create or replace function public.set_card_photo(p_path text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if p_path is not null and (p_path !~ ('^' || me || '/[0-9a-f-]{36}\.jpg$')
                             or not exists (select 1 from storage.objects where bucket_id = 'avatars' and name = p_path)
                             or exists (select 1 from public.removed_photos where path = p_path)) then
    raise exception 'invalid_avatar' using errcode = '22023';
  end if;
  update public.profiles set card_photo_path = p_path where id = me;
end
$$;

create or replace function public.player_card(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select base || jsonb_build_object(
    'win_rate', case when p_user = auth.uid() or (w ->> 'public')::boolean then w end,
    'challenge', public.challenge_availability(p_user),
    'message', public.message_option(auth.uid(), p_user) - 'group_id',
    'verified', pr.verified_kind,
    'avatar', case when not public.blocked_between(auth.uid(), p_user) then pr.avatar_path end,
    'gender', pr.gender,
    'tag', pr.tag,
    'card_color', pr.card_color,
    'card_photo', case when not public.blocked_between(auth.uid(), p_user) then pr.card_photo_path end,
    'recent_no_shows', public.recent_no_shows(p_user),
    'suspended_until', public.suspended_until(p_user))
  from public.player_card_base(p_user) base, public.win_rate(p_user) w, public.profiles pr
  where base is not null and pr.id = p_user
$$;


-- 头像文件夹：以前是“最多 4 个文件”。管理员撤下的照片、没删成的旧文件会占着名额，满了以后再也传不了。
-- 改成一天最多传 10 个（旧文件下次上传时由 App 清理）
drop policy "players upload their own avatar" on storage.objects;
create or replace function public.my_avatar_uploads_today()
returns bigint language sql stable security definer set search_path = '' as $$
  select count(*) from storage.objects
  where bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text and created_at > now() - interval '1 day'
$$;
revoke execute on function public.my_avatar_uploads_today() from public, anon;
grant execute on function public.my_avatar_uploads_today() to authenticated;
create policy "players upload their own avatar" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text
              and public.my_avatar_uploads_today() < 10);
