-- 上周 / 上月榜单（和 iOS 的“本周 / 上周”“本月 / 上月”切换一致）：
-- p_offset = 0 是本期，1 是上一期；只开放这两个
drop function public.venue_board(text);
drop function public.weekly_board(text);

-- 场馆月榜：按水平段分开，每段前 10 名，加上我的位置
create function public.venue_board(p_venue text, p_offset int default 0)
returns jsonb language sql stable security definer set search_path = '' as $$
  with month as (select date_trunc('month', now()) - least(greatest(p_offset, 0), 1) * interval '1 month' as starts),
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
      and (s.user_id = auth.uid() or not public.hidden_from(auth.uid(), s.user_id)))
  select jsonb_build_object(
    'venue', (select jsonb_build_object('id', v.id, 'name', v.name, 'city', v.city) from public.venues v where v.id = p_venue),
    'month_starts', (select starts from month),
    'bands', coalesce((select jsonb_agg(jsonb_build_object('band', b.band, 'entries', b.entries) order by b.band) from (
        select band, jsonb_agg(jsonb_build_object('id', user_id, 'nickname', nickname, 'rating', rating, 'rank', rank,
                                                  'games', games, 'wins', wins, 'me', user_id = auth.uid()) order by rank, lower(nickname)) as entries
        from ranked where rank <= 10 or user_id = auth.uid() group by band) b), '[]'))
  where auth.uid() is not null
$$;

-- 全球周榜：scope = 'global' / 'country'（本国）/ 'level'（我的水平段）。前 50 名，加上我的位置和进度
create function public.weekly_board(p_scope text default 'global', p_offset int default 0)
returns jsonb language sql stable security definer set search_path = '' as $$
  with me as (select id, country_code::text as country, public.level_band(rating) as band from public.profiles where id = auth.uid()),
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
      and (p_scope <> 'level' or public.level_band(p.rating) = (select band from me))
      and (s.user_id = auth.uid() or not public.hidden_from(auth.uid(), s.user_id)))
  select jsonb_build_object(
    'week_starts', (select starts from week),
    'entries', coalesce((select jsonb_agg(jsonb_build_object('id', user_id, 'nickname', nickname, 'rating', rating, 'rank', rank,
                                                             'points', points, 'games', games, 'wins', wins, 'me', user_id = auth.uid())
                                          order by rank, lower(nickname))
                         from ranked where rank <= 50), '[]'),
    'me', (select jsonb_build_object('rank', r.rank, 'points', r.points) from ranked r where r.user_id = auth.uid()),
    'progress', (select jsonb_build_object('games', s.games, 'opponents', s.opponents, 'points', s.points) from scores s where s.user_id = auth.uid()),
    'eligible', public.board_eligible(auth.uid()))
  where auth.uid() is not null
$$;

revoke execute on function public.venue_board(text, int), public.weekly_board(text, int) from public, anon;
grant execute on function public.venue_board(text, int), public.weekly_board(text, int) to authenticated;
