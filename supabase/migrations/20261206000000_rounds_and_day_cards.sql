-- 1. 赛果按局记：一场常常打好几局，两边各赢了几局（team1_games : team2_games），一致才算数；胜率按局算
-- 2. 按天看人：右滑双打也直接约（替我开一个公开的双打局并邀请 TA）；卡片上的球馆按离我远近排

-- 1. 赛果按局 ------------------------------------------------------------------

alter table public.result_reports
  add column team1_games smallint check (team1_games between 0 and 30),
  add column team2_games smallint check (team2_games between 0 and 30),
  add constraint result_reports_games_check check ((team1_games is null) = (team2_games is null)
                                                    and (team1_games is null or team1_games + team2_games between 1 and 30));

alter table public.game_results
  add column rounds_won smallint not null default 0,
  add column rounds_played smallint not null default 0;
update public.game_results set rounds_won = case when won then 1 else 0 end, rounds_played = 1;

-- 双方报的局数不一样也算有分歧（只填了谁赢、没填局数的不比）
create or replace function public.game_result(p_game uuid, p_now timestamptz default now())
returns table (status text, outcome public.result_outcome) language sql stable security definer set search_path = '' as $$
  with claims as (
    select r.outcome, r.team1_games, r.team2_games, gp.team from public.result_reports r
    join public.game_players gp on gp.game_id = r.game_id and gp.user_id = r.reporter_id
    where r.game_id = p_game and r.outcome is not null),
  summary as (select count(distinct outcome) as outcomes, count(distinct team) as teams, min(outcome::text) as outcome,
                     count(distinct (team1_games, team2_games)) filter (where team1_games is not null) as counts
              from claims)
  select case
      when s.outcomes > 1 or s.counts > 1 then 'disputed'
      when s.teams = 2 then 'verified'
      when exists (select 1 from public.game_players gp
                   left join public.result_reports r on r.game_id = gp.game_id and r.reporter_id = gp.user_id
                   where gp.game_id = p_game group by gp.team
                   having bool_and(r.reporter_id is not null and r.outcome is null)) then 'unsure'
      when p_now > (select ends_at from public.games where id = p_game) + interval '7 days' then 'expired'
      else 'awaiting' end,
    case when s.outcomes = 1 and s.counts <= 1 and s.teams = 2 then s.outcome::public.result_outcome end
  from summary s
$$;

-- 确认过的局数（双方一致时取任意一份）
create function public.game_rounds(p_game uuid)
returns table (team1 smallint, team2 smallint) language sql stable security definer set search_path = '' as $$
  select r.team1_games, r.team2_games from public.result_reports r
  where r.game_id = p_game and r.team1_games is not null order by r.updated_at desc limit 1
$$;
revoke execute on function public.game_rounds(uuid) from public, anon, authenticated;

-- 报赛果：填了局数就按局数定输赢（一样多 = 平局，记成 friendly 但局数照样计入胜率）
drop function public.report_result(uuid, public.result_outcome, text);
create function public.report_result(p_game uuid, p_outcome public.result_outcome, p_score text default null,
                                     p_team1_games int default null, p_team2_games int default null)
returns text language plpgsql security definer set search_path = '' as $$
declare
  score text := nullif(btrim(coalesce(p_score, '')), '');
  outcome public.result_outcome := p_outcome;
begin
  if not exists (select 1 from public.games g join public.game_players gp on gp.game_id = g.id and gp.user_id = auth.uid()
                 where g.id = p_game and g.status = 'scheduled' and now() between g.starts_at and g.ends_at + interval '7 days') then
    raise exception 'cannot_report' using errcode = 'P0002';
  end if;
  if score is not null and (char_length(score) > 40 or score !~ '^[0-9 :,/-]+$') then
    raise exception 'invalid_score' using errcode = '22023';
  end if;
  if (p_team1_games is null) <> (p_team2_games is null)
     or (p_team1_games is not null and (least(p_team1_games, p_team2_games) < 0 or p_team1_games + p_team2_games not between 1 and 30)) then
    raise exception 'invalid_games' using errcode = '22023';
  end if;
  if p_team1_games is not null then
    outcome := case when p_team1_games > p_team2_games then 'team1' when p_team2_games > p_team1_games then 'team2' else 'friendly' end;
  end if;
  perform 1 from public.games where id = p_game for update;
  if (select r.status from public.game_result(p_game) r) = 'verified' then raise exception 'result_locked' using errcode = '22023'; end if;
  insert into public.result_reports (game_id, reporter_id, outcome, score, team1_games, team2_games)
    values (p_game, auth.uid(), outcome, case when outcome is null then null else score end,
            case when outcome is not null then p_team1_games end, case when outcome is not null then p_team2_games end)
    on conflict (game_id, reporter_id) do update
      set outcome = excluded.outcome, score = excluded.score, team1_games = excluded.team1_games, team2_games = excluded.team2_games,
          updated_at = now();
  return (select r.status from public.game_result(p_game) r);
end
$$;
revoke execute on function public.report_result(uuid, public.result_outcome, text, int, int) from public, anon;
grant execute on function public.report_result(uuid, public.result_outcome, text, int, int) to authenticated;

-- 存好的赛果：带上每人赢的局数和打的局数；平局（局数一样多）也存，不算赢
create or replace function public.refresh_game_results(p_game uuid)
returns void language sql security definer set search_path = '' as $$
  delete from public.game_results where game_id = p_game;
  insert into public.game_results (game_id, user_id, won, starts_at, venue_id, country, tz, opponents, gap, rounds_won, rounds_played)
  select g.id, gp.user_id, gr.outcome = ('team' || gp.team)::public.result_outcome, g.starts_at, g.venue_id, v.country_code::text,
         coalesce(v.time_zone_id, 'UTC'),
         (select string_agg(o.user_id::text, '+' order by o.user_id) from public.game_players o where o.game_id = g.id and o.team <> gp.team),
         (select avg(public.open_rating(o.rating, op.gender)) from public.game_players o join public.profiles op on op.id = o.user_id
          where o.game_id = g.id and o.team <> gp.team)
           - (select avg(public.open_rating(m.rating, mp.gender)) from public.game_players m join public.profiles mp on mp.id = m.user_id
              where m.game_id = g.id and m.team = gp.team),
         coalesce(case gp.team when 1 then rounds.team1 else rounds.team2 end,
                  case when gr.outcome = ('team' || gp.team)::public.result_outcome then 1 else 0 end),
         coalesce(rounds.team1 + rounds.team2, 1)
  from public.games g
  join public.venues v on v.id = g.venue_id
  join public.game_players gp on gp.game_id = g.id
  cross join public.game_result(p_game) gr
  left join public.game_rounds(p_game) rounds on true
  where g.id = p_game and gr.status = 'verified' and (gr.outcome <> 'friendly' or rounds.team1 is not null)
$$;

-- 胜率：多给按局算的 rounds / round_wins（老版本 App 还读 games / wins）
create or replace function public.win_rate(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with counted as (
    select r.*, row_number() over (partition by r.opponents order by r.starts_at) as nth
    from public.game_results r join public.games g on g.id = r.game_id and g.status = 'scheduled'
    where r.user_id = p_user and r.starts_at >= date_trunc('month', now()) and r.starts_at < now() + interval '1 day')
  select jsonb_build_object(
    'games', count(*), 'wins', count(*) filter (where won),
    'rounds', coalesce(sum(rounds_played), 0), 'round_wins', coalesce(sum(rounds_won), 0),
    'opponents', (select count(distinct o) from counted c, unnest(string_to_array(c.opponents, '+')) o where c.nth <= 3),
    'gap', coalesce(round(avg(gap), 2), 0),
    'public', count(*) >= 5)
  from counted where nth <= 3
$$;

-- 我的球局：我报的局数、确认过的局数
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
      'score', (select r.score from public.result_reports r where r.game_id = g.id and r.score is not null
                order by r.updated_at desc limit 1),
      'rounds', (select jsonb_build_object('team1', x.team1, 'team2', x.team2) from public.game_rounds(g.id) x),
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

-- 2. 按天看人 ------------------------------------------------------------------

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
      and t.status = 'searching' and t.starts_at < p_to and t.ends_at > p_from and t.lock_at > now() + interval '30 minutes'
      and public.can_invite(auth.uid(), t)
      and not exists (select 1 from public.candidate_skips s where s.viewer = auth.uid() and s.ticket_id = t.id)
      and exists (select 1 from public.venues v
                  where v.id = any (t.venue_ids)
                    and extensions.st_dwithin(v.location, extensions.st_makepoint(p_lon, p_lat)::extensions.geography,
                                              least(greatest(p_radius_km, 1), 100) * 1000))
    order by t.starts_at
    limit 50) x
$$;


-- 右滑约双打：替我开一个公开的双打局（TA 的时间、我选的球馆），邀请 TA；附近的人可以加入补齐
create function public.invite_doubles(p_ticket uuid, p_venue text, p_starts_at timestamptz)
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
  select * into t from public.match_tickets where id = p_ticket;
  if t.id is null or t.status <> 'searching' or t.mode <> 'doubles' or not public.can_invite(me, t) then
    raise exception 'not_available' using errcode = 'P0002';
  end if;
  if not p_venue = any (t.venue_ids) or extract(epoch from p_starts_at)::bigint % 1800 <> 0 then
    raise exception 'invalid_slot' using errcode = '22023';
  end if;
  slot_end := least(t.ends_at, p_starts_at + interval '2 hours');
  if p_starts_at < greatest(t.starts_at, now() + interval '30 minutes') or slot_end - p_starts_at < interval '1 hour' then
    raise exception 'invalid_slot' using errcode = '22023';
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
revoke execute on function public.invite_doubles(uuid, text, timestamptz) from public, anon;
grant execute on function public.invite_doubles(uuid, text, timestamptz) to authenticated;
