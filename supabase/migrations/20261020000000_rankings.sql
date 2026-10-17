-- 胜率、排行榜与约战
-- 规则与 iOS 一致（Badie-iOS/docs/DESIGN.md §14，Models/Ranking.swift、Challenge.swift）：
-- - 只算双方确认过、分出胜负的比赛（友谊局、记不清、有分歧的不算）
-- - 月度胜率满 5 场才公开，并带上场数、对手数、对手平均强弱；同一对手每月最多计 3 场
-- - 场馆月榜比打了多少场（同一对手最多 4 场、每天最多 3 场），按水平段分开排，每段第一是“本月馆主”
-- - 全球周榜（UTC 周一重置）：输 10 赢 15，乘对手强度 0.5–1.5，同一对手第 2 场减半、第 3 场起不计，每周最多 15 场
-- - 上榜门槛：注册满 7 天、没关闭上榜、近 60 天没和 3 位以上不同对手有到期未解决的分歧
-- - 约战：谁能挑战我由我决定；48 小时内回应；拒绝和超时对发起人都显示“未成行”
-- 和 iOS 的差别：这一版只做单打约战

-- ---------------------------------------------------------------------------
-- 设置
-- ---------------------------------------------------------------------------

create type public.challenge_policy as enum ('everyone', 'similar', 'friends', 'nobody');

alter table public.profiles
  add column show_on_boards boolean not null default true,
  add column challenge_policy public.challenge_policy not null default 'similar';
grant update (show_on_boards, challenge_policy) on public.profiles to authenticated;

-- ---------------------------------------------------------------------------
-- 计分用的对局记录
-- ---------------------------------------------------------------------------

-- 时间段内每位球员的确认胜负：对手组合（同一组对手算一个）、对手平均比我方强多少级
create function public.player_results(p_from timestamptz, p_to timestamptz)
returns table (game_id uuid, user_id uuid, won boolean, starts_at timestamptz, venue_id text, country text, tz text,
               opponents text, gap numeric)
language sql stable security definer set search_path = '' as $$
  select g.id, gp.user_id, gr.outcome = ('team' || gp.team)::public.result_outcome, g.starts_at, g.venue_id, v.country_code::text,
         coalesce(v.time_zone_id, 'UTC'),
         (select string_agg(o.user_id::text, '+' order by o.user_id) from public.game_players o where o.game_id = g.id and o.team <> gp.team),
         (select avg(o.rating) from public.game_players o where o.game_id = g.id and o.team <> gp.team)
           - (select avg(m.rating) from public.game_players m where m.game_id = g.id and m.team = gp.team)
  from public.games g
  join public.venues v on v.id = g.venue_id
  join public.game_players gp on gp.game_id = g.id
  cross join lateral public.game_result(g.id) gr
  where g.status = 'scheduled' and g.starts_at >= p_from and g.starts_at < p_to
    and gr.status = 'verified' and gr.outcome <> 'friendly'
$$;

-- 能不能上榜：注册满 7 天、没关闭上榜、不是“故意拒认”（近 60 天和 ≥3 位不同对手有到期未解决的分歧）
create function public.board_eligible(p_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select p.show_on_boards and p.created_at <= now() - interval '7 days'
    and (select count(distinct o.user_id)
         from public.game_players gp join public.games g on g.id = gp.game_id
         join public.game_players o on o.game_id = g.id and o.team <> gp.team
         where gp.user_id = p_user and g.status = 'scheduled'
           and g.ends_at between now() - interval '60 days' and now() - interval '7 days'
           and (select count(distinct r.outcome) from public.result_reports r where r.game_id = g.id and r.outcome is not null) > 1) < 3
  from public.profiles p where p.id = p_user
$$;

-- 水平段：1–2、3–4、5–6、7+
create function public.level_band(p_rating numeric)
returns int language sql immutable set search_path = '' as $$
  select least((round(p_rating)::int + 1) / 2, 4)
$$;

-- ---------------------------------------------------------------------------
-- 月度胜率
-- ---------------------------------------------------------------------------

create function public.win_rate(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with counted as (
    select r.*, row_number() over (partition by r.opponents order by r.starts_at) as nth
    from public.player_results(date_trunc('month', now()), now() + interval '1 day') r
    where r.user_id = p_user)
  select jsonb_build_object(
    'games', count(*), 'wins', count(*) filter (where won),
    'opponents', (select count(distinct o) from counted c, unnest(string_to_array(c.opponents, '+')) o where c.nth <= 3),
    'gap', coalesce(round(avg(gap), 2), 0),
    'public', count(*) >= 5)
  from counted where nth <= 3
$$;

-- ---------------------------------------------------------------------------
-- 榜单
-- ---------------------------------------------------------------------------

-- 我看榜单时排除：拉黑关系、我举报过的人
create function public.hidden_from(p_viewer uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.blocked_between(p_viewer, p_user)
    or exists (select 1 from public.user_reports where reporter_id = p_viewer and reported_id = p_user)
$$;

-- 场馆月榜：按水平段分开，每段前 10 名，加上我的位置
create function public.venue_board(p_venue text)
returns jsonb language sql stable security definer set search_path = '' as $$
  with results as (
    select r.*, row_number() over (partition by r.user_id, r.opponents order by r.starts_at) as per_opponent
    from public.player_results(date_trunc('month', now()), now() + interval '1 day') r
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
    'bands', coalesce((select jsonb_agg(jsonb_build_object('band', b.band, 'entries', b.entries) order by b.band) from (
        select band, jsonb_agg(jsonb_build_object('id', user_id, 'nickname', nickname, 'rating', rating, 'rank', rank,
                                                  'games', games, 'wins', wins, 'me', user_id = auth.uid()) order by rank, lower(nickname)) as entries
        from ranked where rank <= 10 or user_id = auth.uid() group by band) b), '[]'))
  where auth.uid() is not null
$$;

-- 全球周榜：scope = 'global' / 'country'（本国）/ 'level'（我的水平段）。前 50 名，加上我的位置和进度
create function public.weekly_board(p_scope text default 'global')
returns jsonb language sql stable security definer set search_path = '' as $$
  with me as (select id, country_code::text as country, public.level_band(rating) as band from public.profiles where id = auth.uid()),
  week as (select date_trunc('week', now() at time zone 'UTC') at time zone 'UTC' as starts),
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

-- ---------------------------------------------------------------------------
-- 约战（单打）
-- ---------------------------------------------------------------------------

create type public.challenge_status as enum ('pending', 'accepted', 'declined', 'expired', 'withdrawn');

create table public.challenges (
  id uuid primary key default gen_random_uuid(),
  challenger_id uuid not null references auth.users (id) on delete cascade,
  target_id uuid not null references auth.users (id) on delete cascade,
  venue_id text not null references public.venues (id),
  starts_at timestamptz not null check (extract(epoch from starts_at)::bigint % 1800 = 0),
  ends_at timestamptz not null check (extract(epoch from ends_at)::bigint % 1800 = 0),
  message text not null default '' check (char_length(message) <= 60),
  status public.challenge_status not null default 'pending',
  -- 48 小时内回应，最晚开赛前 1 小时
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  game_id uuid references public.games (id),
  check (challenger_id <> target_id),
  check (ends_at - starts_at between interval '1 hour' and interval '3 hours')
);

create index challenges_target_idx on public.challenges (target_id, status);
create index challenges_challenger_idx on public.challenges (challenger_id, created_at);

alter table public.challenges enable row level security;
revoke all on public.challenges from anon, authenticated;
grant all on public.challenges to service_role;

-- 能不能挑战 TA：'available'，或者不能的原因；'hidden' = 不显示按钮
create function public.challenge_availability(p_target uuid)
returns text language sql stable security definer set search_path = '' as $$
  with me as (select * from public.profiles where id = auth.uid()), them as (select * from public.profiles where id = p_target)
  select case
    when (select id from me) is null or (select id from them) is null or p_target = auth.uid() then 'hidden'
    when (select challenge_policy from them) = 'nobody' or public.blocked_between(auth.uid(), p_target) then 'hidden'
    when (select country_code from me) is distinct from (select country_code from them) then 'hidden'
    when (select challenge_policy from them) = 'friends' and not public.are_friends(auth.uid(), p_target) then 'friends_only'
    when (select challenge_policy from them) = 'similar' and abs((select rating from me) - (select rating from them)) > 1.01 then 'level_out_of_range'
    when exists (select 1 from public.challenges where challenger_id = auth.uid() and target_id = p_target and status = 'pending' and expires_at > now())
      then 'already_pending'
    when exists (select 1 from public.challenges where challenger_id = auth.uid() and target_id = p_target
                 and status in ('declined', 'expired') and coalesce(responded_at, expires_at) > now() - interval '7 days') then 'cooldown'
    when (select count(*) from public.challenges where challenger_id = auth.uid() and status = 'pending' and expires_at > now()) >= 3 then 'too_many_outgoing'
    when (select count(*) from public.challenges where challenger_id = auth.uid() and created_at > now() - interval '1 day') >= 5 then 'daily_limit'
    when (select count(*) from public.challenges where target_id = p_target and status = 'pending' and expires_at > now()) >= 3 then 'target_busy'
    else 'available' end
$$;

create function public.send_challenge(p_target uuid, p_venue text, p_starts_at timestamptz, p_ends_at timestamptz, p_message text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  availability text := public.challenge_availability(p_target);
  venue text;
  new_id uuid;
begin
  if availability = 'hidden' or not public.related(me, p_target) then raise exception 'not_allowed' using errcode = '42501'; end if;
  if availability <> 'available' then raise exception '%', availability using errcode = '22023'; end if;
  if p_starts_at < now() + interval '2 hours' or p_starts_at > now() + interval '14 days' then raise exception 'too_soon' using errcode = '22023'; end if;
  if coalesce(p_message, '') ~* '(https?:|www\.|@|\d{7,})' then raise exception 'no_contact_info' using errcode = '22023'; end if;
  select coalesce(merged_into, id) into venue from public.venues where id = p_venue and not hidden_pending_review;
  if venue is null then raise exception 'invalid_venues' using errcode = '22023'; end if;
  if public.has_game_between(me, p_starts_at, p_ends_at) then raise exception 'overlapping' using errcode = '23P01'; end if;

  insert into public.challenges (challenger_id, target_id, venue_id, starts_at, ends_at, message, expires_at)
    values (me, p_target, venue, p_starts_at, p_ends_at, btrim(coalesce(p_message, '')),
            least(now() + interval '48 hours', p_starts_at - interval '1 hour'))
    returning id into new_id;
  perform public.notify(p_target, 'challenge', 'Singles challenge',
    (select nickname from public.profiles where id = me) || ' challenged you: ' || public.slot_text(p_starts_at, venue) || '.', '/app/games/');
  return new_id;
end
$$;

-- 接受：生成一场单打球局（照常签到、报赛果）。拒绝不通知对方，对方看到“未成行”
create function public.respond_challenge(p_challenge uuid, p_accept boolean)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  c public.challenges;
  new_game uuid;
begin
  select * into c from public.challenges where id = p_challenge and target_id = auth.uid() and status = 'pending' and expires_at > now() for update;
  if c.id is null then raise exception 'challenge_closed' using errcode = 'P0002'; end if;
  if not p_accept then
    update public.challenges set status = 'declined', responded_at = now() where id = p_challenge;
    return null;
  end if;
  if public.has_game_between(c.challenger_id, c.starts_at, c.ends_at) or public.has_game_between(c.target_id, c.starts_at, c.ends_at) then
    raise exception 'overlapping' using errcode = '23P01';
  end if;
  insert into public.games (mode, starts_at, ends_at, venue_id) values ('singles', c.starts_at, c.ends_at, c.venue_id) returning id into new_game;
  insert into public.game_players (game_id, user_id, team, rating)
    select new_game, p.id, case when p.id = c.challenger_id then 1 else 2 end, p.rating
    from public.profiles p where p.id in (c.challenger_id, c.target_id);
  update public.challenges set status = 'accepted', responded_at = now(), game_id = new_game where id = p_challenge;
  perform public.notify(c.challenger_id, 'matched', 'Challenge accepted',
    (select nickname from public.profiles where id = c.target_id) || ' is in: ' || public.slot_text(c.starts_at, c.venue_id) || '.',
    '/app/games/' || new_game || '/');
  return new_game;
end
$$;

create function public.withdraw_challenge(p_challenge uuid)
returns void language sql security definer set search_path = '' as $$
  update public.challenges set status = 'withdrawn', responded_at = now()
  where id = p_challenge and challenger_id = auth.uid() and status = 'pending'
$$;

-- 收到的（待回应）和发出的（最近 14 天）；拒绝和超时都显示成 'not_happening'
create function public.my_challenges()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'incoming', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'starts_at', c.starts_at, 'ends_at', c.ends_at, 'message', c.message, 'expires_at', c.expires_at,
        'venue', jsonb_build_object('name', v.name, 'tz', v.time_zone_id),
        'player', jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', p.rating)) order by c.starts_at)
      from public.challenges c join public.venues v on v.id = c.venue_id join public.profiles p on p.id = c.challenger_id
      where c.target_id = auth.uid() and c.status = 'pending' and c.expires_at > now()), '[]'),
    'outgoing', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'starts_at', c.starts_at, 'ends_at', c.ends_at, 'game_id', c.game_id,
        'status', case when c.status = 'pending' and c.expires_at <= now() then 'not_happening'
                       when c.status in ('declined', 'expired') then 'not_happening' else c.status::text end,
        'venue', jsonb_build_object('name', v.name, 'tz', v.time_zone_id),
        'player', jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', p.rating)) order by c.created_at desc)
      from public.challenges c join public.venues v on v.id = c.venue_id join public.profiles p on p.id = c.target_id
      where c.challenger_id = auth.uid() and c.status <> 'withdrawn' and c.created_at > now() - interval '14 days'), '[]'))
$$;

-- 到期没回应：过期（不通知任何人）
create function public.expire_challenges()
returns void language sql security definer set search_path = '' as $$
  update public.challenges set status = 'expired' where status = 'pending' and expires_at <= now()
$$;

-- ---------------------------------------------------------------------------
-- 资料页和战绩加上胜率、约战
-- ---------------------------------------------------------------------------

alter function public.player_card(uuid) rename to player_card_base;

create function public.player_card(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select base || jsonb_build_object(
    'win_rate', case when p_user = auth.uid() or (w ->> 'public')::boolean then w end,
    'challenge', public.challenge_availability(p_user))
  from public.player_card_base(p_user) base, public.win_rate(p_user) w
  where base is not null
$$;

create or replace function public.my_record()
returns jsonb language sql stable security definer set search_path = '' as $$
  select w || jsonb_build_object('losses', (w ->> 'games')::int - (w ->> 'wins')::int,
                                 'games_played', a.games_played, 'no_shows', a.no_shows, 'late_cancels', a.late_cancels)
  from public.win_rate(auth.uid()) w, public.attendance_record(auth.uid()) a
$$;

-- ---------------------------------------------------------------------------
-- 权限与定时任务
-- ---------------------------------------------------------------------------

revoke execute on function public.player_results(timestamptz, timestamptz), public.board_eligible(uuid), public.level_band(numeric),
  public.win_rate(uuid), public.hidden_from(uuid, uuid), public.challenge_availability(uuid), public.expire_challenges(),
  public.player_card_base(uuid)
  from public, anon, authenticated;

revoke execute on function public.venue_board(text), public.weekly_board(text), public.player_card(uuid),
  public.send_challenge(uuid, text, timestamptz, timestamptz, text), public.respond_challenge(uuid, boolean),
  public.withdraw_challenge(uuid), public.my_challenges()
  from public, anon;
grant execute on function public.venue_board(text), public.weekly_board(text), public.player_card(uuid),
  public.send_challenge(uuid, text, timestamptz, timestamptz, text), public.respond_challenge(uuid, boolean),
  public.withdraw_challenge(uuid), public.my_challenges()
  to authenticated;

select cron.schedule('expire-challenges', '*/5 * * * *', 'select public.expire_challenges()');
