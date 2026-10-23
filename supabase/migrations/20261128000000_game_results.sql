-- 榜单和胜率读预先算好的赛果：结果确认（双方报的一致）时算一次存起来，看榜时按时间读。
-- 以前每次看榜、看资料卡都要把全站这段时间的每场每人重算一遍（每人还有好几个子查询），人越多越慢。

create table public.game_results (
  game_id uuid not null references public.games (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  won boolean not null,
  starts_at timestamptz not null,
  venue_id text not null,
  country text,
  tz text not null,
  -- 对方的人（按 id 排序、用 + 连起来）：同一对手封顶时用
  opponents text not null,
  -- 对方平均水平减我方平均水平（男女换算后）
  gap numeric,
  primary key (game_id, user_id)
);
create index game_results_starts_idx on public.game_results (starts_at);
create index game_results_user_idx on public.game_results (user_id, starts_at);
create index game_results_venue_idx on public.game_results (venue_id, starts_at);
alter table public.game_results enable row level security;
revoke all on public.game_results from anon, authenticated;
grant all on public.game_results to service_role;

-- 一场球的赛果：只存确认过、不是友谊局的
create function public.refresh_game_results(p_game uuid)
returns void language sql security definer set search_path = '' as $$
  delete from public.game_results where game_id = p_game;
  insert into public.game_results (game_id, user_id, won, starts_at, venue_id, country, tz, opponents, gap)
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
  cross join public.game_result(p_game) gr
  where g.id = p_game and gr.status = 'verified' and gr.outcome <> 'friendly'
$$;

-- 报结果、改结果，或者球局改了时间、球馆：重算这一场（games 的行用 id，result_reports 的行用 game_id）
create function public.on_result_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  changed jsonb := to_jsonb(coalesce(new, old));
begin
  perform public.refresh_game_results(coalesce(changed ->> 'game_id', changed ->> 'id')::uuid);
  return null;
end
$$;

create trigger result_reports_results after insert or update or delete on public.result_reports
  for each row execute function public.on_result_change();
create trigger games_results after update of starts_at, venue_id on public.games
  for each row execute function public.on_result_change();

do $$
begin
  perform public.refresh_game_results(id) from public.games where id in (select game_id from public.result_reports);
end
$$;

-- 读存好的赛果（取消的球局不算）
create or replace function public.player_results(p_from timestamptz, p_to timestamptz)
returns table (game_id uuid, user_id uuid, won boolean, starts_at timestamptz, venue_id text, country text, tz text,
               opponents text, gap numeric)
language sql stable security definer set search_path = '' as $$
  select r.game_id, r.user_id, r.won, r.starts_at, r.venue_id, r.country, r.tz, r.opponents, r.gap
  from public.game_results r join public.games g on g.id = r.game_id and g.status = 'scheduled'
  where r.starts_at >= p_from and r.starts_at < p_to
$$;

-- 胜率只读这个人的
create or replace function public.win_rate(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with counted as (
    select r.*, row_number() over (partition by r.opponents order by r.starts_at) as nth
    from public.game_results r join public.games g on g.id = r.game_id and g.status = 'scheduled'
    where r.user_id = p_user and r.starts_at >= date_trunc('month', now()) and r.starts_at < now() + interval '1 day')
  select jsonb_build_object(
    'games', count(*), 'wins', count(*) filter (where won),
    'opponents', (select count(distinct o) from counted c, unnest(string_to_array(c.opponents, '+')) o where c.nth <= 3),
    'gap', coalesce(round(avg(gap), 2), 0),
    'public', count(*) >= 5)
  from counted where nth <= 3
$$;

-- 周榜、球馆月榜：对手数一次算好再连回来（以前每人扫一遍全部结果）；月榜只读这家球馆的
create or replace function public.weekly_board(p_scope text default 'global', p_offset int default 0, p_gender public.gender default null)
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
  opponents as (
    select x.user_id, count(distinct o) as opponents from counted x, unnest(string_to_array(x.opponents, '+')) o group by x.user_id),
  scores as (
    select c.user_id,
           round(sum((case when c.won then 15 else 10 end) * least(1.5, greatest(0.5, 1 + coalesce(c.gap, 0) * 0.5))
                     * case c.meeting when 1 then 1 when 2 then 0.5 else 0 end))::int as points,
           count(*) as games, count(*) filter (where c.won) as wins,
           o.opponents
    from counted c join opponents o using (user_id) group by c.user_id, o.opponents),
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

create or replace function public.venue_board(p_venue text, p_offset int default 0, p_gender public.gender default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  with board as (select coalesce(p_gender, (select gender from public.profiles where id = auth.uid()), 'male') as gender),
  month as (select date_trunc('month', now()) - least(greatest(p_offset, 0), 1) * interval '1 month' as starts),
  results as (
    select r.*, row_number() over (partition by r.user_id, r.opponents order by r.starts_at) as per_opponent
    from public.game_results r join public.games g on g.id = r.game_id and g.status = 'scheduled'
    where r.venue_id = p_venue and r.starts_at >= (select starts from month) and r.starts_at < (select starts from month) + interval '1 month'),
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

revoke execute on function public.refresh_game_results(uuid), public.on_result_change() from public, anon, authenticated;
