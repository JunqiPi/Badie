-- 比赛（1.0.7 走查后改）：
-- 1. 赛制和参赛方式分开选。赛制：循环 round_robin / 小组赛 + 淘汰赛 groups / 瑞士轮 swiss / 单淘汰 knockout；
--    参赛方式：单打 singles / 双打固定搭档 fixed / 双打轮换搭档 rotating（只配循环，按个人排名）
-- 2. 循环、瑞士轮、轮换搭档自己定打几轮：循环可以超过一遍（第二遍换边），瑞士轮最多打到每两人都碰过
-- 3. 淘汰赛任意人数：按种子排签位（1 号和最后一号在两头），不够 2 的幂的给前几号种子轮空；小组赛 2–8 组；可选打三四名
-- 4. 比分只收合规的完整比分（去掉“比分不对也保存”）；中途退赛单独记（谁退赛、前面打完的局、没打完那局的比分）
-- 5. 比赛结束后，注册球员打过的每一场计入个人胜率（和约球的赛果一起算本月胜率；不进每周排行）

-- ---------------------------------------------------------------------------
-- 表
-- ---------------------------------------------------------------------------

alter table public.matches drop constraint matches_format_check;
alter table public.matches drop constraint matches_pools_check;
alter table public.matches add column play text;
alter table public.matches add column third_place boolean not null default false;
update public.matches
  set play = case format when 'rotating' then 'rotating' when 'fixed' then 'fixed'
                         when 'groups' then case when doubles then 'fixed' else 'singles' end else 'singles' end,
      format = case format when 'groups' then 'groups' else 'round_robin' end;
alter table public.matches alter column play set not null;
alter table public.matches add constraint matches_play_check check (play in ('singles', 'fixed', 'rotating'));
alter table public.matches add constraint matches_format_check check (format in ('round_robin', 'groups', 'swiss', 'knockout'));
alter table public.matches add constraint matches_rotating_check check (play <> 'rotating' or format = 'round_robin');
alter table public.matches add constraint matches_pools_check check (pools between 2 and 8);

-- 淘汰赛：stage = 'ko'，ko_size 是这一轮的签位数（2 = 决赛、4 = 半决赛、8 = 四分之一决赛…），slot 是第几个签位对（从 1 起）。
-- 第 slot 场的胜者进下一轮的第 (slot + 1) / 2 场。轮空也是一行（bye，状态 skipped，side_b 是空的），客户端不显示成一场。
-- 三四名决赛 stage = 'third'。retired：中途退赛的一边（比分里是退赛前打的）
alter table public.match_games drop constraint match_games_stage_check;
alter table public.match_games add column ko_size smallint;
alter table public.match_games add column slot smallint;
alter table public.match_games add column bye boolean not null default false;
alter table public.match_games add column retired smallint check (retired in (1, 2));
update public.match_games
  set ko_size = case stage when 'semi' then 4 else 2 end, slot = case stage when 'semi' then seq else 1 end, stage = 'ko'
  where stage in ('semi', 'final');
alter table public.match_games add constraint match_games_stage_check check (stage in ('pool', 'ko', 'third'));
create unique index match_games_ko_slot_idx on public.match_games (match_id, ko_size, slot) where stage = 'ko';

-- 比赛里打的每一场，按注册球员存一行（比赛结束时算；结束后改了比分重算）。胜率读它和约球的 game_results
create table public.match_results (
  game_id bigint not null references public.match_games (id) on delete cascade,
  match_id uuid not null references public.matches (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  won boolean not null,
  starts_at timestamptz not null,
  opponents text not null,          -- 对方的人（注册的用户 id，访客用参赛的 id），按 id 排序用 + 连起来
  gap numeric,                      -- 对方平均水平减我方平均水平（只算注册的人）
  rounds_won int not null,
  rounds_played int not null,
  primary key (game_id, user_id)
);
create index match_results_user_idx on public.match_results (user_id, starts_at);
create index match_results_match_idx on public.match_results (match_id);
alter table public.match_results enable row level security;
revoke all on public.match_results from anon, authenticated;
grant all on public.match_results to service_role;

-- ---------------------------------------------------------------------------
-- 比分
-- ---------------------------------------------------------------------------

drop function public.loose_winner(int[]);

-- 一局打完了没有：先到分；要领先 2 分时到分后拉开 2 分，或者打到封顶（21 → 30、15 → 21、11 → 15）
create function public.game_done(p_hi int, p_lo int, p_points int, p_win_by_two boolean)
returns boolean language sql immutable set search_path = '' as $$
  select p_lo >= 0 and p_hi > p_lo and case
    when not p_win_by_two then p_hi = p_points
    else (p_hi = p_points and p_lo <= p_points - 2)
      or (p_hi > p_points and p_hi <= case p_points when 21 then 30 when 15 then 21 else 15 end
          and (p_hi - p_lo = 2 or (p_hi = case p_points when 21 then 30 when 15 then 21 else 15 end and p_lo = p_hi - 1))) end
$$;

-- 中途退赛时记的比分：前面打完的局都合规、还没人赢够；最后可以带上没打完那一局（打得到的比分，也还不算打完）。可以是空的
create function public.retire_scores_ok(p_scores int[], p_points int, p_best_of int, p_win_by_two boolean)
returns boolean language plpgsql immutable set search_path = '' as $$
declare
  cap int := case when not p_win_by_two then p_points when p_points = 21 then 30 when p_points = 15 then 21 else 15 end;
  need int := p_best_of / 2 + 1;
  wins int[] := array[0, 0];
  n int := coalesce(cardinality(p_scores), 0) / 2;
  hi int;
  lo int;
begin
  if coalesce(cardinality(p_scores), 0) % 2 = 1 or n > p_best_of then return false; end if;
  for i in 1..n loop
    if wins[1] = need or wins[2] = need then return false; end if;
    if p_scores[2 * i - 1] is null or p_scores[2 * i] is null then return false; end if;
    hi := greatest(p_scores[2 * i - 1], p_scores[2 * i]);
    lo := least(p_scores[2 * i - 1], p_scores[2 * i]);
    if lo < 0 then return false; end if;
    if public.game_done(hi, lo, p_points, p_win_by_two) then
      if p_scores[2 * i - 1] > p_scores[2 * i] then wins[1] := wins[1] + 1; else wins[2] := wins[2] + 1; end if;
    -- 没打完的那局：还没到分，或者在加分阶段（两边都到了分减 1，最多差 1 分）
    elsif i < n or not (hi < p_points or (p_win_by_two and lo >= p_points - 1 and hi - lo <= 1 and hi < cap)) then
      return false;
    end if;
  end loop;
  return wins[1] < need and wins[2] < need;
end
$$;

revoke execute on function public.game_done(int, int, int, boolean), public.retire_scores_ok(int[], int, int, boolean)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 计划和预计
-- ---------------------------------------------------------------------------

drop function public.match_preview(text, int, int, int, int, boolean, int, int, int);
drop function public.match_plan(text, int, boolean, int);

-- entries：参赛单位（人或队）的个数；full_rounds：循环打满一遍的轮数（分组时是一组的）；
-- default_rounds / max_rounds：能选几轮；per_round：每轮几场；qualifiers：进淘汰赛的个数；bracket：签位数（2 的幂）
create function public.match_plan(p_format text, p_play text, p_players int, p_pools int default null, p_advance int default null)
returns table (entries int, full_rounds int, default_rounds int, max_rounds int, per_round int, qualifiers int, bracket int)
language plpgsql immutable set search_path = '' as $$
declare
  size int;
  pools int := coalesce(p_pools, 2);
begin
  entries := case when p_play = 'fixed' then p_players / 2 else p_players end;
  per_round := case when p_play = 'rotating' then p_players / 4 else entries / 2 end;
  qualifiers := 0;
  bracket := 0;
  if p_play = 'rotating' then
    full_rounds := p_players + p_players % 2 - 1;
    default_rounds := least(full_rounds, 30);
    max_rounds := 30;
  elsif p_format = 'round_robin' then
    full_rounds := entries + entries % 2 - 1;
    default_rounds := full_rounds;
    max_rounds := least(2 * full_rounds, 60);
  elsif p_format = 'swiss' then
    full_rounds := entries + entries % 2 - 1;
    -- 默认打到第一名能分出来：log2(人数) 向上取整
    default_rounds := 1;
    while (2 ^ default_rounds)::int < entries loop default_rounds := default_rounds + 1; end loop;
    default_rounds := least(default_rounds, full_rounds);
    max_rounds := full_rounds;
  elsif p_format = 'groups' then
    size := (entries + pools - 1) / pools;
    full_rounds := size + size % 2 - 1;
    default_rounds := full_rounds;
    max_rounds := full_rounds;
    qualifiers := least(pools * coalesce(p_advance, 1), entries);
  else
    full_rounds := 0;
    default_rounds := 0;
    max_rounds := 0;
    qualifiers := entries;
  end if;
  if qualifiers >= 2 then
    bracket := 2;
    while bracket < qualifiers loop bracket := bracket * 2; end loop;
  end if;
  return next;
end
$$;

-- 预计：rounds（小组赛 / 循环 / 瑞士轮的轮数加上淘汰赛的轮数）、games、minutes（每轮按场地数分几批，每批 21 分 15 分钟、
-- 15 分 10 分钟、11 分 7 分钟，三局两胜乘 2.5），以及能选几轮
create function public.match_preview(p_format text, p_play text, p_players int, p_courts int, p_points int, p_best_of int,
                                     p_pools int default null, p_advance int default null, p_rounds int default null,
                                     p_third_place boolean default false)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  plan record;
  courts int := greatest(coalesce(p_courts, 1), 1);
  rounds int;
  games int;
  batches int;
  ko_rounds int := 0;
  s int;
  n int;
begin
  select * into plan from public.match_plan(p_format, p_play, p_players, p_pools, p_advance);
  rounds := case when p_format in ('groups', 'knockout') then plan.full_rounds
                 else least(greatest(coalesce(p_rounds, plan.default_rounds), 1), plan.max_rounds) end;
  games := rounds * plan.per_round;
  batches := rounds * ceil(plan.per_round::numeric / courts)::int;
  if plan.bracket >= 2 then
    s := plan.bracket;
    while s >= 2 loop
      -- 第一轮只有不轮空的那几场
      n := case when s = plan.bracket then plan.qualifiers - s / 2 else s / 2 end;
      if s = 2 and coalesce(p_third_place, false) and plan.qualifiers >= 4 then n := n + 1; end if;
      games := games + n;
      batches := batches + ceil(n::numeric / courts)::int;
      ko_rounds := ko_rounds + 1;
      s := s / 2;
    end loop;
  end if;
  return jsonb_build_object(
    'entries', plan.entries, 'full_rounds', plan.full_rounds, 'default_rounds', plan.default_rounds, 'max_rounds', plan.max_rounds,
    'pool_rounds', rounds, 'ko_rounds', ko_rounds, 'rounds', rounds + ko_rounds, 'games', games, 'bracket', plan.bracket,
    'qualifiers', plan.qualifiers,
    'minutes', ceil(batches * case p_points when 21 then 15 when 15 then 10 else 7 end * case when p_best_of = 3 then 2.5 else 1 end));
end
$$;

-- ---------------------------------------------------------------------------
-- 排名单位、积分榜
-- ---------------------------------------------------------------------------

-- 排名的单位：双打固定搭档是一队（key t<队号>），其余是一个人（key 是 id）
create or replace function public.match_entries(p_match uuid)
returns table (key text, name text, members uuid[], pool smallint, seed int, withdrawn boolean, rating numeric)
language sql stable security definer set search_path = '' as $$
  select x.key, string_agg(x.name, ' · ' order by x.seq), array_agg(x.id order by x.seq), min(x.pool), min(x.seq),
         bool_or(x.withdrawn_at is not null), avg(coalesce(x.rating, 3))
  from (select mp.*, case when m.doubles then 't' || mp.team else mp.id::text end as key
        from public.match_players mp join public.matches m on m.id = mp.match_id where mp.match_id = p_match) x
  group by x.key
$$;

-- 积分榜：按胜率，再看净胜分、总得分；两人（两队）还分不开看他们之间的胜负，三人以上写并列。
-- p_all = false 只算小组赛（出线用），true 连淘汰赛一起算。分组的每组单独排。瑞士轮的轮空算赢一场
create or replace function public.match_standings(p_match uuid, p_all boolean default false)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  swiss boolean := (select format = 'swiss' from public.matches where id = p_match);
  rows jsonb[];
  r jsonb;
  result jsonb := '[]'::jsonb;
  i int := 1;
  j int;
  pos int := 0;
  a_wins int;
  b_wins int;
begin
  select array_agg(to_jsonb(t) order by coalesce(t.pool, 0), t.rate desc nulls last, t.diff desc, t.pf desc, t.seed) into rows from (
    with counted as (
      select * from public.match_games g
      where g.match_id = p_match and (p_all or g.stage = 'pool') and (g.status = 'done' or (swiss and g.bye))
    ), sides as (
      select g.id, 1 as side, g.side_a as members, g.winner, public.side_points(g.scores, 1) as pf, public.side_points(g.scores, 2) as pa
      from counted g
      union all
      select g.id, 2, g.side_b, g.winner, public.side_points(g.scores, 2), public.side_points(g.scores, 1)
      from counted g where not g.bye
    )
    select e.key, e.name, e.members, e.pool, e.seed, e.withdrawn, count(s.id)::int as played,
           (count(s.id) filter (where s.winner = s.side))::int as wins, (count(s.id) filter (where s.winner <> s.side))::int as losses,
           coalesce(sum(s.pf), 0)::int as pf, coalesce(sum(s.pa), 0)::int as pa, coalesce(sum(s.pf - s.pa), 0)::int as diff,
           (count(s.id) filter (where s.winner = s.side))::numeric / nullif(count(s.id), 0) as rate
    from public.match_entries(p_match) e left join sides s on s.members @> e.members
    group by e.key, e.name, e.members, e.pool, e.seed, e.withdrawn
  ) t;
  while i <= coalesce(cardinality(rows), 0) loop
    if i = 1 or (rows[i] ->> 'pool') is distinct from (rows[i - 1] ->> 'pool') then pos := 0; end if;
    j := i;
    while j < cardinality(rows) and (rows[j + 1] ->> 'pool') is not distinct from (rows[i] ->> 'pool')
          and (rows[j + 1] ->> 'rate') is not distinct from (rows[i] ->> 'rate')
          and rows[j + 1] ->> 'diff' = rows[i] ->> 'diff' and rows[j + 1] ->> 'pf' = rows[i] ->> 'pf' loop
      j := j + 1;
    end loop;
    if j = i + 1 then
      select count(*) filter (where (g.side_a @> x.a and g.side_b @> x.b and g.winner = 1) or (g.side_b @> x.a and g.side_a @> x.b and g.winner = 2)),
             count(*) filter (where (g.side_a @> x.b and g.side_b @> x.a and g.winner = 1) or (g.side_b @> x.b and g.side_a @> x.a and g.winner = 2))
        into a_wins, b_wins
        from public.match_games g,
             lateral (select array(select jsonb_array_elements_text(rows[i] -> 'members')::uuid) as a,
                             array(select jsonb_array_elements_text(rows[j] -> 'members')::uuid) as b) x
        where g.match_id = p_match and g.status = 'done' and not g.bye and (p_all or g.stage = 'pool');
      if b_wins > a_wins then r := rows[i]; rows[i] := rows[j]; rows[j] := r; end if;
      if a_wins <> b_wins then
        result := result || (rows[i] || jsonb_build_object('rank', pos + 1, 'tied', false))
                   || (rows[j] || jsonb_build_object('rank', pos + 2, 'tied', false));
        pos := pos + 2;
        i := j + 1;
        continue;
      end if;
    end if;
    for k in i..j loop
      result := result || (rows[k] || jsonb_build_object('rank', pos + 1, 'tied', j > i));
    end loop;
    pos := pos + j - i + 1;
    i := j + 1;
  end loop;
  return result;
end
$$;

-- 最终排名。循环、瑞士轮就是积分榜。有淘汰赛时：冠军、决赛输的、三四名（打了的话），其余按在第几轮被淘汰并列
-- （半决赛输的并列第 3，四分之一决赛输的并列第 5…）；提前结束时还没输的排在同一轮输了的前面；没进淘汰赛的排在后面，按小组赛成绩
create or replace function public.match_ranking(p_match uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  m public.matches;
  table_all jsonb;
begin
  select * into m from public.matches where id = p_match;
  table_all := public.match_standings(p_match, true);
  if m.format not in ('groups', 'knockout') or not exists (select 1 from public.match_games where match_id = p_match and stage = 'ko') then
    return table_all;
  end if;
  return (
    with ent as (
      select t.e, t.ord, array(select jsonb_array_elements_text(t.e -> 'members')::uuid) as members
      from jsonb_array_elements(table_all) with ordinality t(e, ord)
    ), ko as (
      select ent.*,
             (select min(g.ko_size) from public.match_games g
              where g.match_id = p_match and g.stage = 'ko' and (g.side_a || g.side_b) @> ent.members) as reached,
             (select min(g.ko_size) from public.match_games g
              where g.match_id = p_match and g.stage = 'ko' and g.status = 'done' and not g.bye
                and (case when g.winner = 1 then g.side_b else g.side_a end) @> ent.members) as lost_at,
             (select case when (case when g.winner = 1 then g.side_a else g.side_b end) @> ent.members then 3.0 else 3.5 end
              from public.match_games g where g.match_id = p_match and g.stage = 'third' and g.status = 'done'
                and (g.side_a || g.side_b) @> ent.members) as third,
             exists (select 1 from public.match_games g where g.match_id = p_match and g.stage = 'ko' and g.ko_size = 2
                     and g.status = 'done' and (case when g.winner = 1 then g.side_a else g.side_b end) @> ent.members) as champion
      from ent
    ), keyed as (
      select ko.e, ko.ord,
             case when ko.third is not null then ko.third
                  when ko.lost_at is not null then ko.lost_at::numeric
                  when ko.champion then 1
                  when ko.reached is not null then ko.reached / 2.0 + 0.5
                  else 1000 + rank() over (partition by ko.reached is null
                                           order by (ko.e ->> 'rate')::numeric desc nulls last, (ko.e ->> 'diff')::int desc,
                                                    (ko.e ->> 'pf')::int desc) end as k
      from ko
    )
    select jsonb_agg(x.e || jsonb_build_object('rank', x.rank, 'tied', x.tied) order by x.rank, x.ord)
    from (select a.e, a.ord, (select count(*) from keyed b where b.k < a.k) + 1 as rank,
                 (select count(*) from keyed b where b.k = a.k) > 1 as tied
          from keyed a) x);
end
$$;

-- ---------------------------------------------------------------------------
-- 排对阵
-- ---------------------------------------------------------------------------

-- 循环（单打、双打固定搭档）和小组赛：圆桌法。循环可以超过一遍（第二遍换边）；小组赛每组打满一遍。单数时每轮一个人（一队）轮空
create or replace function public.match_schedule_rr(p_match uuid)
returns void language sql security definer set search_path = '' as $$
  with mt as (
    select * from public.matches where id = p_match
  ), e as (
    select x.*, (row_number() over (partition by coalesce(x.pool, 0) order by x.seed) - 1)::int as idx
    from public.match_entries(p_match) x
  ), pools as (
    select coalesce(pool, 0) as pool, (count(*) + count(*) % 2)::int as m from e group by coalesce(pool, 0)
  )
  insert into public.match_games (match_id, round, seq, pool, side_a, side_b)
  select p_match, r + 1, row_number() over (partition by r order by ps.pool, pr.a), nullif(ps.pool, 0),
         case when (r / (ps.m - 1)) % 2 = 0 then a.members else b.members end,
         case when (r / (ps.m - 1)) % 2 = 0 then b.members else a.members end
  from pools ps
  cross join mt
  cross join lateral generate_series(0, case when mt.format = 'groups' then ps.m - 2 else mt.rounds - 1 end) r
  cross join lateral public.round_robin_pairs(ps.m, r % (ps.m - 1)) pr
  join e a on coalesce(a.pool, 0) = ps.pool and a.idx = pr.a
  join e b on coalesce(b.pool, 0) = ps.pool and b.idx = pr.b
$$;

-- 瑞士轮的一轮：第 1 轮按水平上半区打下半区；之后按积分榜从上往下，和最近的、还没碰过的配（实在都碰过了就碰第二次）。
-- 单数时，没轮空过的人里排最后的轮空（算赢一场）
create function public.match_swiss_round(p_match uuid, p_round int)
returns void language plpgsql security definer set search_path = '' as $$
declare
  order_keys text[];
  members jsonb;
  bye_key text;
  half int;
  a text;
  b text;
  k int := 0;
begin
  select jsonb_object_agg(key, to_jsonb(e.members)) into members from public.match_entries(p_match) e where not e.withdrawn;
  if p_round = 1 then
    select array_agg(key order by rating desc, seed) into order_keys from public.match_entries(p_match) where not withdrawn;
  else
    select array_agg(x.e ->> 'key' order by x.ord) into order_keys
      from jsonb_array_elements(public.match_standings(p_match, true)) with ordinality x(e, ord)
      where not (x.e ->> 'withdrawn')::boolean;
  end if;
  if coalesce(cardinality(order_keys), 0) < 2 then return; end if;
  if cardinality(order_keys) % 2 = 1 then
    select u.key into bye_key from unnest(order_keys) with ordinality u(key, i)
      where not exists (select 1 from public.match_games g where g.match_id = p_match and g.bye
                        and g.side_a @> array(select jsonb_array_elements_text(members -> u.key)::uuid))
      order by u.i desc limit 1;
    bye_key := coalesce(bye_key, order_keys[cardinality(order_keys)]);
    order_keys := array_remove(order_keys, bye_key);
    insert into public.match_games (match_id, round, seq, side_a, side_b, status, winner, bye)
      values (p_match, p_round, cardinality(order_keys) / 2 + 1, array(select jsonb_array_elements_text(members -> bye_key)::uuid),
              '{}', 'skipped', 1, true);
  end if;
  if p_round = 1 then
    half := cardinality(order_keys) / 2;
    for i in 1..half loop
      insert into public.match_games (match_id, round, seq, side_a, side_b)
        values (p_match, p_round, i, array(select jsonb_array_elements_text(members -> order_keys[i])::uuid),
                array(select jsonb_array_elements_text(members -> order_keys[i + half])::uuid));
    end loop;
    return;
  end if;
  while cardinality(order_keys) > 0 loop
    a := order_keys[1];
    select u.key into b from unnest(order_keys[2:]) with ordinality u(key, i)
      where not exists (
        select 1 from public.match_games g
        where g.match_id = p_match and g.status <> 'cancelled' and not g.bye
          and ((g.side_a @> array(select jsonb_array_elements_text(members -> a)::uuid)
                and g.side_b @> array(select jsonb_array_elements_text(members -> u.key)::uuid))
            or (g.side_b @> array(select jsonb_array_elements_text(members -> a)::uuid)
                and g.side_a @> array(select jsonb_array_elements_text(members -> u.key)::uuid))))
      order by u.i limit 1;
    b := coalesce(b, order_keys[2]);
    k := k + 1;
    insert into public.match_games (match_id, round, seq, side_a, side_b)
      values (p_match, p_round, k, array(select jsonb_array_elements_text(members -> a)::uuid),
              array(select jsonb_array_elements_text(members -> b)::uuid));
    order_keys := array_remove(array_remove(order_keys, a), b);
  end loop;
end
$$;

-- 签位顺序：第 i 个签位放几号种子。2 → 1,2；4 → 1,4,2,3；8 → 1,8,4,5,2,7,3,6（1 号和 2 号只会在决赛碰）
create function public.bracket_order(p_size int)
returns int[] language plpgsql immutable set search_path = '' as $$
declare
  o int[] := array[1];
  n int := 1;
  nxt int[];
  x int;
begin
  while n < p_size loop
    n := n * 2;
    nxt := '{}';
    foreach x in array o loop nxt := nxt || array[x, n + 1 - x]; end loop;
    o := nxt;
  end loop;
  return o;
end
$$;

-- 淘汰赛第一轮：p_seeds 按种子顺序（match_entries 的一行，jsonb）。签位不够的给前几号种子轮空；
-- 小组赛出线的，第一轮同组的尽量错开（和别的签位换下面那个）
create function public.match_bracket(p_match uuid, p_seeds jsonb[], p_round int)
returns void language plpgsql security definer set search_path = '' as $$
declare
  q int := coalesce(cardinality(p_seeds), 0);
  size int := 2;
  ord int[];
  pos jsonb[] := '{}'::jsonb[];
  t jsonb;
  x jsonb;
  y jsonb;
begin
  if q < 2 then return; end if;
  while size < q loop size := size * 2; end loop;
  ord := public.bracket_order(size);
  for i in 1..size loop
    pos := pos || case when ord[i] <= q then p_seeds[ord[i]] else 'null'::jsonb end;
  end loop;
  for k in 1..size / 2 loop
    x := pos[2 * k - 1];
    y := pos[2 * k];
    continue when jsonb_typeof(x) <> 'object' or jsonb_typeof(y) <> 'object' or (x ->> 'pool') is null
                  or (x ->> 'pool') <> (y ->> 'pool');
    for j in 1..size / 2 loop
      continue when j = k or jsonb_typeof(pos[2 * j]) <> 'object';
      if (pos[2 * j] ->> 'pool') <> (x ->> 'pool')
         and (jsonb_typeof(pos[2 * j - 1]) <> 'object' or (pos[2 * j - 1] ->> 'pool') <> (y ->> 'pool')) then
        t := pos[2 * j];
        pos[2 * j] := y;
        pos[2 * k] := t;
        exit;
      end if;
    end loop;
  end loop;
  for k in 1..size / 2 loop
    x := pos[2 * k - 1];
    y := pos[2 * k];
    if jsonb_typeof(x) = 'object' and jsonb_typeof(y) = 'object' then
      insert into public.match_games (match_id, round, seq, stage, ko_size, slot, side_a, side_b)
        values (p_match, p_round, k, 'ko', size, k, array(select jsonb_array_elements_text(x -> 'members')::uuid),
                array(select jsonb_array_elements_text(y -> 'members')::uuid));
    else
      insert into public.match_games (match_id, round, seq, stage, ko_size, slot, side_a, side_b, status, winner, bye)
        values (p_match, p_round, k, 'ko', size, k,
                array(select jsonb_array_elements_text((case when jsonb_typeof(x) = 'object' then x else y end) -> 'members')::uuid),
                '{}', 'skipped', 1, true);
    end if;
  end loop;
end
$$;

-- 小组赛打完后的淘汰赛：每组前 advance 名出线（退赛的不算），按名次、再按成绩排种子。
-- 出线卡在并列上时标出来，组织者可以改（p_seeds：按种子顺序的 key）
create or replace function public.match_knockout(p_match uuid, p_seeds text[] default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  m public.matches;
  table_pool jsonb := public.match_standings(p_match);
  seeds jsonb[];
  round_no int := (select coalesce(max(round), 0) + 1 from public.match_games where match_id = p_match and stage = 'pool');
  cut_tie boolean := false;
begin
  select * into m from public.matches where id = p_match;
  with placed as (
    select e, row_number() over (partition by e ->> 'pool' order by ord) as place
    from jsonb_array_elements(table_pool) with ordinality x(e, ord)
    where not (e ->> 'withdrawn')::boolean
  )
  select array_agg(e order by place, (e ->> 'rate')::numeric desc nulls last, (e ->> 'diff')::int desc, (e ->> 'pf')::int desc)
    into seeds from placed where place <= m.advance;
  if p_seeds is not null then
    seeds := array(select e from unnest(p_seeds) with ordinality s(key, i) join jsonb_array_elements(table_pool) e on e ->> 'key' = s.key
                   order by s.i);
    if cardinality(seeds) <> cardinality(p_seeds) or cardinality(seeds) not between 2 and 16 then
      raise exception 'invalid_qualifiers' using errcode = '22023';
    end if;
  else
    cut_tie := exists (
      select 1 from jsonb_array_elements(table_pool) x join jsonb_array_elements(table_pool) y
        on x ->> 'pool' = y ->> 'pool' and x ->> 'rank' = y ->> 'rank' and x ->> 'key' <> y ->> 'key'
      where x ->> 'key' = any(array(select s ->> 'key' from unnest(seeds) s))
        and not y ->> 'key' = any(array(select s ->> 'key' from unnest(seeds) s)) and not (y ->> 'withdrawn')::boolean);
  end if;
  if coalesce(cardinality(seeds), 0) < 2 then return; end if;
  update public.matches set tie_at_cut = cut_tie where id = p_match;
  perform public.match_bracket(p_match, seeds, round_no);
end
$$;

-- 淘汰赛往下排：一个签位对的两场都有结果（或者轮空）就排下一轮那一场；还没开始的下一场跟着改过的比分换人。
-- 两场半决赛都打完、选了三四名的，排三四名决赛。退赛的人排进来的场次直接算对方赢
create function public.match_ko_next(p_match uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  m public.matches;
  s int;
  f1 public.match_games;
  f2 public.match_games;
  nxt public.match_games;
  w1 uuid[];
  w2 uuid[];
begin
  select * into m from public.matches where id = p_match;
  loop
  for s in select distinct ko_size from public.match_games where match_id = p_match and stage = 'ko' and ko_size > 2 order by ko_size desc loop
    for k in 1..s / 4 loop
      select * into f1 from public.match_games where match_id = p_match and stage = 'ko' and ko_size = s and slot = 2 * k - 1;
      select * into f2 from public.match_games where match_id = p_match and stage = 'ko' and ko_size = s and slot = 2 * k;
      continue when f1.id is null or f2.id is null
                    or not ((f1.status = 'done' or f1.bye) and (f2.status = 'done' or f2.bye));
      w1 := case when f1.winner = 1 then f1.side_a else f1.side_b end;
      w2 := case when f2.winner = 1 then f2.side_a else f2.side_b end;
      select * into nxt from public.match_games where match_id = p_match and stage = 'ko' and ko_size = s / 2 and slot = k;
      if nxt.id is null then
        insert into public.match_games (match_id, round, seq, stage, ko_size, slot, side_a, side_b)
          values (p_match, greatest(f1.round, f2.round) + 1, k, 'ko', s / 2, k, w1, w2);
      elsif nxt.status = 'queued' and (nxt.side_a <> w1 or nxt.side_b <> w2) then
        update public.match_games set side_a = w1, side_b = w2, version = version + 1 where id = nxt.id;
      end if;
    end loop;
  end loop;
  if m.third_place then
    select * into f1 from public.match_games where match_id = p_match and stage = 'ko' and ko_size = 4 and slot = 1;
    select * into f2 from public.match_games where match_id = p_match and stage = 'ko' and ko_size = 4 and slot = 2;
    if f1.status = 'done' and f2.status = 'done' and not f1.bye and not f2.bye then
      w1 := case when f1.winner = 1 then f1.side_b else f1.side_a end;
      w2 := case when f2.winner = 1 then f2.side_b else f2.side_a end;
      select * into nxt from public.match_games where match_id = p_match and stage = 'third';
      if nxt.id is null then
        insert into public.match_games (match_id, round, seq, stage, side_a, side_b)
          values (p_match, greatest(f1.round, f2.round) + 1, 2, 'third', w1, w2);
      elsif nxt.status = 'queued' and (nxt.side_a <> w1 or nxt.side_b <> w2) then
        update public.match_games set side_a = w1, side_b = w2, version = version + 1 where id = nxt.id;
      end if;
    end if;
  end if;
  -- 退赛的人排进了下一场：算对方赢，再往下排
  update public.match_games g
    set status = 'done', walkover = true, court = null, version = version + 1,
        winner = case when exists (select 1 from public.match_players p where p.id = any(g.side_a) and p.withdrawn_at is not null) then 2 else 1 end
    where g.match_id = p_match and g.stage in ('ko', 'third') and g.status in ('queued', 'playing')
      and exists (select 1 from public.match_players p where p.id = any(g.side_a || g.side_b) and p.withdrawn_at is not null);
  exit when not found;
  end loop;
end
$$;

-- 每次比分、退赛之后：小组赛打完排淘汰赛；淘汰赛往下排；瑞士轮一轮打完排下一轮；空场地排上人；都打完了就结束
create or replace function public.match_progress(p_match uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  m public.matches;
  last_round int;
begin
  select * into m from public.matches where id = p_match;
  if m.status <> 'live' then return; end if;
  if m.format = 'groups' and not exists (select 1 from public.match_games where match_id = p_match and status in ('queued', 'playing'))
     and not exists (select 1 from public.match_games where match_id = p_match and stage <> 'pool') then
    perform public.match_knockout(p_match);
  end if;
  if m.format in ('groups', 'knockout') then
    perform public.match_ko_next(p_match);
  end if;
  if m.format = 'swiss' and not exists (select 1 from public.match_games where match_id = p_match and status in ('queued', 'playing')) then
    select coalesce(max(round), 0) into last_round from public.match_games where match_id = p_match;
    if last_round < m.rounds then perform public.match_swiss_round(p_match, last_round + 1); end if;
  end if;
  perform public.match_fill(p_match);
  if not exists (select 1 from public.match_games where match_id = p_match and status in ('queued', 'playing')) then
    perform public.match_close(p_match);
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 个人胜率
-- ---------------------------------------------------------------------------

-- 一场比赛的结果按注册球员存起来：结束了才存；退赛没打的（walkover）、轮空不算；中途退赛的算输，没打完那局不算局数
create function public.refresh_match_results(p_match uuid)
returns void language sql security definer set search_path = '' as $$
  delete from public.match_results where match_id = p_match;
  insert into public.match_results (game_id, match_id, user_id, won, starts_at, opponents, gap, rounds_won, rounds_played)
  select g.id, g.match_id, mp.user_id, g.winner = s.side, coalesce(g.started_at, m.created_at),
         coalesce((select string_agg(coalesce(o.user_id, o.id)::text, '+' order by coalesce(o.user_id, o.id)::text)
                   from public.match_players o where o.id = any(s.theirs)), ''),
         (select avg(public.open_rating(op.rating, op.gender)) from public.match_players o join public.profiles op on op.id = o.user_id
          where o.id = any(s.theirs))
           - (select avg(public.open_rating(pp.rating, pp.gender)) from public.match_players o join public.profiles pp on pp.id = o.user_id
              where o.id = any(s.mine)),
         coalesce((select count(*) from generate_series(1, cardinality(g.scores) / 2) i
                   where public.game_done(greatest(g.scores[2 * i - 1], g.scores[2 * i]), least(g.scores[2 * i - 1], g.scores[2 * i]),
                                          m.points, m.win_by_two)
                     and g.scores[2 * i - s.side % 2] > g.scores[2 * i - 1 + s.side % 2]), 0),
         coalesce((select count(*) from generate_series(1, cardinality(g.scores) / 2) i
                   where public.game_done(greatest(g.scores[2 * i - 1], g.scores[2 * i]), least(g.scores[2 * i - 1], g.scores[2 * i]),
                                          m.points, m.win_by_two)), 0)
  from public.matches m
  join public.match_games g on g.match_id = m.id
  cross join lateral (values (1, g.side_a, g.side_b), (2, g.side_b, g.side_a)) s(side, mine, theirs)
  join public.match_players mp on mp.id = any(s.mine) and mp.user_id is not null
  where m.id = p_match and m.status = 'done' and g.status = 'done' and not g.walkover and not g.bye and g.winner is not null
$$;

-- 胜率：约球（确认过的赛果）加上比赛里打的，本月、同一组对手最多算 3 场；满 5 场公开
create or replace function public.win_rate(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with results as (
    select r.won, r.draw, r.starts_at, r.opponents, r.gap, r.rounds_won, r.rounds_played
    from public.game_results r join public.games g on g.id = r.game_id and g.status = 'scheduled'
    where r.user_id = p_user and r.starts_at >= date_trunc('month', now()) and r.starts_at < now() + interval '1 day'
    union all
    select x.won, false, x.starts_at, x.opponents, x.gap, x.rounds_won, x.rounds_played
    from public.match_results x
    where x.user_id = p_user and x.starts_at >= date_trunc('month', now()) and x.starts_at < now() + interval '1 day'
  ), counted as (
    select r.*, row_number() over (partition by r.opponents order by r.starts_at) as nth from results r
  )
  select jsonb_build_object(
    'games', count(*) filter (where not draw), 'wins', count(*) filter (where won),
    'draws', count(*) filter (where draw),
    'rounds', coalesce(sum(rounds_played), 0), 'round_wins', coalesce(sum(rounds_won), 0),
    'opponents', (select count(distinct o) from counted c, unnest(string_to_array(c.opponents, '+')) o where c.nth <= 3),
    'gap', coalesce(round(avg(gap), 2), 0),
    'public', count(*) filter (where not draw) >= 5)
  from counted where nth <= 3
$$;

-- 比赛结束：没打的写“没打”，存个人胜率，每个参赛的注册用户收到自己的名次
create or replace function public.match_close(p_match uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  m public.matches;
  e jsonb;
  player uuid;
begin
  update public.matches set status = 'done', ended_at = now() where id = p_match and status = 'live' returning * into m;
  if m.id is null then return; end if;
  update public.match_games set status = 'skipped', court = null where match_id = p_match and status in ('queued', 'playing');
  perform public.refresh_match_results(p_match);
  for e in select * from jsonb_array_elements(public.match_ranking(p_match)) loop
    for player in select mp.user_id from public.match_players mp
                  where mp.id in (select jsonb_array_elements_text(e -> 'members')::uuid) and mp.user_id is not null and mp.withdrawn_at is null loop
      perform public.notify(player, 'match', 'Match over: you placed #{rank}', 'Open it to see the final standings.',
        '/app/matches/' || p_match || '/', jsonb_build_object('rank', e ->> 'rank', 'match', m.name));
    end loop;
  end loop;
end
$$;

revoke execute on function public.match_swiss_round(uuid, int), public.bracket_order(int), public.match_bracket(uuid, jsonb[], int),
  public.match_ko_next(uuid), public.refresh_match_results(uuid) from public, anon, authenticated;
grant execute on function public.match_preview(text, text, int, int, int, int, int, int, int, boolean) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 比赛页
-- ---------------------------------------------------------------------------

create or replace function public.match_view(p_match uuid, p_full boolean)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'kind', 'match', 'id', m.id, 'name', m.name, 'format', m.format, 'play', m.play, 'doubles', m.doubles, 'points', m.points,
    'best_of', m.best_of, 'win_by_two', m.win_by_two, 'courts', m.courts, 'rounds', m.rounds, 'pools', m.pools, 'advance', m.advance,
    'third_place', m.third_place, 'status', m.status,
    'created_at', m.created_at, 'ended_at', m.ended_at, 'board_code', m.board_code, 'session_id', m.session_id,
    'venue', (select v.name from public.venues v where v.id = m.venue_id), 'tie_at_cut', m.tie_at_cut,
    'round', coalesce((select min(round) from public.match_games where match_id = m.id and status in ('queued', 'playing')),
                      (select max(round) from public.match_games where match_id = m.id)),
    'players', (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id', p.id, 'name', p.name, 'team', p.team, 'pool', p.pool,
                                                             'withdrawn', p.withdrawn_at is not null,
                                                             'user_id', case when p_full then p.user_id end)) order by p.seq), '[]')
                from public.match_players p where p.match_id = m.id),
    'games', (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                'id', g.id, 'round', g.round, 'stage', g.stage, 'pool', g.pool, 'ko_size', g.ko_size, 'slot', g.slot,
                'bye', nullif(g.bye, false), 'a', g.side_a, 'b', g.side_b, 'court', g.court,
                'status', g.status, 'scores', g.scores, 'winner', g.winner, 'walkover', nullif(g.walkover, false), 'retired', g.retired,
                'version', case when p_full then g.version end,
                'scored_by', (select nickname from public.profiles where id = g.scored_by),
                'edited_by', (select nickname from public.profiles where id = g.edited_by),
                'flagged', case when p_full and g.flagged then true end)) order by g.round, g.seq), '[]')
              from public.match_games g where g.match_id = m.id),
    'standings', public.match_standings(m.id),
    'ranking', case when m.status = 'done' then public.match_ranking(m.id) end)
  from public.matches m where m.id = p_match
$$;

-- ---------------------------------------------------------------------------
-- 建一场
-- ---------------------------------------------------------------------------

drop function public.create_match(text, text, int, text, int, int, boolean, jsonb, int, int, int, boolean, uuid, uuid[]);

-- p_format：round_robin / groups / swiss / knockout；p_play：singles / fixed / rotating（只配 round_robin）。
-- p_rounds：循环、瑞士轮、轮换搭档打几轮（不给用默认）；p_pools / p_advance：分几组、每组前几名出线；p_third_place：打三四名。
-- p_players：[{user_id} | {signup_id}（从“当晚”开的）| {name}（访客），固定搭档可以带 team]，按顺序是种子。
-- 没给搭档的按实力配（最强配最弱）；分组按实力蛇形分；淘汰赛、瑞士轮按水平排种子。开始后参赛的注册用户收到通知
create function public.create_match(p_name text, p_venue text, p_courts int, p_format text, p_play text, p_points int, p_best_of int,
                                    p_win_by_two boolean, p_players jsonb, p_rounds int default null, p_pools int default null,
                                    p_advance int default null, p_third_place boolean default false, p_session uuid default null,
                                    p_helpers uuid[] default '{}')
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  clean_name text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  teams boolean := p_play = 'fixed';
  n int := coalesce(jsonb_array_length(case when jsonb_typeof(p_players) = 'array' then p_players end), 0);
  e int;
  plan record;
  new_match uuid;
  item jsonb;
  k int := 0;
  v_user uuid;
  v_signup uuid;
  v_name text;
  v_rating numeric;
  player record;
begin
  if me is null then raise exception 'not_allowed' using errcode = '42501'; end if;
  if char_length(clean_name) not between 1 and 40 then raise exception 'invalid_match_name' using errcode = '22023'; end if;
  if public.has_offensive(clean_name) then raise exception 'objectionable_content' using errcode = '22023'; end if;
  if p_format is null or p_format not in ('round_robin', 'groups', 'swiss', 'knockout')
     or p_play is null or p_play not in ('singles', 'fixed', 'rotating') or (p_play = 'rotating' and p_format <> 'round_robin')
     or p_points is null or p_points not in (11, 15, 21) or p_best_of is null or p_best_of not in (1, 3)
     or p_courts is null or p_courts not between 1 and 12
     or (p_format = 'groups' and (p_pools is null or p_pools not between 2 and 8 or coalesce(p_advance, 1) not in (1, 2))) then
    raise exception 'invalid_match' using errcode = '22023';
  end if;
  e := case when teams then n / 2 else n end;
  if n not between 2 and 64 or (teams and n % 2 = 1) or (p_play in ('fixed', 'rotating') and n < 4)
     or (p_format = 'swiss' and e < 3)
     or (p_format = 'groups' and (e / p_pools < coalesce(p_advance, 1) + 1 or p_pools * coalesce(p_advance, 1) > 16)) then
    raise exception 'invalid_player_count' using errcode = '22023';
  end if;
  select * into plan from public.match_plan(p_format, p_play, n, p_pools, p_advance);
  if p_format in ('round_robin', 'swiss') and p_rounds is not null and p_rounds not between 1 and plan.max_rounds then
    raise exception 'invalid_rounds' using errcode = '22023';
  end if;
  if p_venue is not null and not exists (select 1 from public.venues where id = p_venue) then
    raise exception 'venue_not_found' using errcode = 'P0002';
  end if;
  if p_session is not null then
    perform public.night_guard(p_session);
    if exists (select 1 from public.club_nights c join public.matches m on m.id = c.match_id where c.session_id = p_session and m.status = 'live') then
      raise exception 'match_running' using errcode = '22023';
    end if;
  end if;

  insert into public.matches (owner_id, session_id, name, venue_id, courts, format, play, doubles, points, best_of, win_by_two, rounds,
                              pools, advance, third_place)
    values (me, p_session, clean_name, p_venue, p_courts, p_format, p_play, teams, p_points, p_best_of, coalesce(p_win_by_two, true),
            greatest(case when p_format in ('round_robin', 'swiss') then coalesce(p_rounds, plan.default_rounds) else plan.full_rounds end, 1),
            case when p_format = 'groups' then p_pools end, case when p_format = 'groups' then coalesce(p_advance, 1) end,
            p_format in ('groups', 'knockout') and coalesce(p_third_place, false))
    returning id into new_match;

  for item in select * from jsonb_array_elements(p_players) loop
    k := k + 1;
    v_user := null; v_signup := null; v_rating := null;
    if item ? 'signup_id' and p_session is not null then
      select p.id, p.user_id, p.name, p.rating into v_signup, v_user, v_name, v_rating
        from public.night_people(p_session) p where p.id = (item ->> 'signup_id')::uuid;
      if v_signup is null then raise exception 'player_not_found' using errcode = 'P0002'; end if;
    elsif item ? 'user_id' then
      select p.id, p.nickname, p.rating into v_user, v_name, v_rating from public.profiles p where p.id = (item ->> 'user_id')::uuid;
      if v_user is null or public.blocked_between(me, v_user)
         or not (v_user = me or public.related(me, v_user)
                 or exists (select 1 from public.session_signups where session_id = p_session and user_id = v_user)) then
        raise exception 'player_not_found' using errcode = 'P0002';
      end if;
    else
      v_name := public.clean_player_name(item ->> 'name');
    end if;
    if v_user is not null and exists (select 1 from public.match_players where match_id = new_match and user_id = v_user) then
      raise exception 'duplicate_player' using errcode = '22023';
    end if;
    if exists (select 1 from public.match_players where match_id = new_match and lower(name) = lower(v_name)) then
      v_name := left(v_name, 20) || ' ' || (select count(*) + 1 from public.match_players where match_id = new_match and lower(name) like lower(v_name) || '%');
    end if;
    insert into public.match_players (match_id, user_id, signup_id, name, rating, seq, team)
      values (new_match, v_user, v_signup, left(v_name, 24), v_rating, k, case when teams then (item ->> 'team')::smallint end);
  end loop;

  if teams then
    if exists (select 1 from public.match_players where match_id = new_match and team is null) then
      update public.match_players mp set team = case when x.rk < n / 2 then x.rk + 1 else n - x.rk end
        from (select id, (row_number() over (order by coalesce(rating, 3) desc, seq) - 1)::int as rk
              from public.match_players where match_id = new_match) x
        where mp.id = x.id;
    elsif exists (select 1 from public.match_players where match_id = new_match group by team having count(*) <> 2) then
      raise exception 'invalid_teams' using errcode = '22023';
    end if;
  end if;
  if p_format = 'groups' then
    update public.match_players mp set pool = case when (e.i / p_pools) % 2 = 0 then e.i % p_pools + 1 else p_pools - e.i % p_pools end
      from (select members, (row_number() over (order by rating desc, seed) - 1)::int as i from public.match_entries(new_match)) e
      where mp.id = any(e.members);
  end if;

  if p_play = 'rotating' then
    perform public.match_schedule_rotating(new_match, 1);
  elsif p_format in ('round_robin', 'groups') then
    perform public.match_schedule_rr(new_match);
  elsif p_format = 'swiss' then
    perform public.match_swiss_round(new_match, 1);
  else
    perform public.match_bracket(new_match,
      array(select to_jsonb(x) from public.match_entries(new_match) x order by x.rating desc, x.seed), 1);
  end if;

  if cardinality(coalesce(p_helpers, '{}')) > 0 then perform public.match_helpers(new_match, p_helpers); end if;
  if p_session is not null then
    insert into public.club_nights (session_id, match_id) values (p_session, new_match)
      on conflict (session_id) do update set match_id = excluded.match_id;
  end if;

  for player in
    select mp.user_id, min(g.round) as first_round from public.match_players mp
    left join public.match_games g on g.match_id = new_match and mp.id = any(g.side_a || g.side_b)
    where mp.match_id = new_match and mp.user_id is not null and mp.user_id <> me group by mp.user_id
  loop
    perform public.notify(player.user_id, 'match', 'Match started: {match}', 'Your first game is in round {round}.',
      '/app/matches/' || new_match || '/', jsonb_build_object('match', clean_name, 'round', coalesce(player.first_round, 1)));
  end loop;
  perform public.match_progress(new_match);
  return new_match;
end
$$;

-- ---------------------------------------------------------------------------
-- 输比分、退赛
-- ---------------------------------------------------------------------------

drop function public.match_score(bigint, int[], int, boolean);

-- 记一场的结果（match_score、match_retire 共用）：淘汰赛改了胜负、下一场已经开始了的不能改；
-- 小组赛改了胜负、淘汰赛还没开始的，淘汰赛重新排；然后往下排、记撤销、结束了的重算个人胜率
create function public.match_apply(p_game bigint, p_scores int[], p_winner smallint, p_retired smallint)
returns void language plpgsql security definer set search_path = '' as $$
declare
  g public.match_games;
  m public.matches;
  last_id bigint;
  playing bigint[];
begin
  select * into g from public.match_games where id = p_game;
  select * into m from public.matches where id = g.match_id;
  if g.status = 'done' and g.winner is distinct from p_winner then
    if g.stage = 'ko' and exists (
         select 1 from public.match_games x where x.match_id = m.id and x.status <> 'queued'
           and ((x.stage = 'ko' and x.ko_size = g.ko_size / 2 and x.slot = (g.slot + 1) / 2) or (x.stage = 'third' and g.ko_size = 4))) then
      raise exception 'knockout_started' using errcode = '22023';
    end if;
    if g.stage = 'pool' and m.format = 'groups' and exists (select 1 from public.match_games where match_id = m.id and stage <> 'pool') then
      if exists (select 1 from public.match_games where match_id = m.id and stage <> 'pool' and status <> 'queued' and not bye) then
        raise exception 'knockout_started' using errcode = '22023';
      end if;
      delete from public.match_games where match_id = m.id and stage <> 'pool';
    end if;
  end if;
  select coalesce(max(id), 0) into last_id from public.match_games where match_id = m.id;
  select coalesce(array_agg(id), '{}') into playing from public.match_games where match_id = m.id and status = 'playing';
  update public.match_games
    set scores = case when cardinality(p_scores) > 0 then p_scores::smallint[] end, winner = p_winner, retired = p_retired,
        status = 'done', walkover = false, version = version + 1,
        scored_by = coalesce(scored_by, auth.uid()), edited_by = case when g.status = 'done' then auth.uid() end,
        flagged = flagged and public.match_role(m.id) not in ('organizer', 'helper')
    where id = p_game;
  perform public.match_progress(m.id);
  update public.matches
    set undo = jsonb_build_object('game', to_jsonb(g), 'created', (select coalesce(jsonb_agg(id), '[]') from public.match_games where match_id = m.id and id > last_id),
                                  'started', (select coalesce(jsonb_agg(id), '[]') from public.match_games
                                              where match_id = m.id and status = 'playing' and id <> all(playing)),
                                  'closed', m.status = 'live' and status = 'done'),
        undo_until = now() + interval '10 seconds'
    where id = m.id;
  if m.status = 'done' then perform public.refresh_match_results(m.id); end if;
end
$$;

-- 输比分：每一局都要合规，三局两胜要有人赢满两局（不合规的一律不收）。
-- 组织者和帮手随时能输、能改（带上看到的版本，两个人同时改后到的报 score_changed）；
-- 这一场的注册球员只能在打的时候输一次，先存的算，已经有比分了报 score_taken
create function public.match_score(p_game bigint, p_scores int[], p_version int)
returns void language plpgsql security definer set search_path = '' as $$
declare
  g public.match_games;
  m public.matches;
  role text;
  win smallint;
begin
  select * into g from public.match_games where id = p_game;
  if g.id is null or g.bye then raise exception 'game_not_found' using errcode = 'P0002'; end if;
  select * into m from public.matches where id = g.match_id for update;
  select * into g from public.match_games where id = p_game;
  role := public.match_role(m.id);
  if role in ('organizer', 'helper') then
    if g.version is distinct from p_version then raise exception 'score_changed' using errcode = '40001'; end if;
    if g.status in ('cancelled', 'skipped') then raise exception 'game_cancelled' using errcode = '22023'; end if;
  elsif exists (select 1 from public.match_players where match_id = m.id and user_id = auth.uid() and withdrawn_at is null
                and id = any(g.side_a || g.side_b)) then
    if g.status = 'done' then raise exception 'score_taken' using errcode = '40001'; end if;
    if g.status <> 'playing' then raise exception 'not_allowed' using errcode = '42501'; end if;
  else
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  if p_scores is null or cardinality(p_scores) not between 2 and 2 * m.best_of
     or exists (select 1 from unnest(p_scores) x where x is null or x not between 0 and 99) then
    raise exception 'score_invalid' using errcode = '22023';
  end if;
  win := public.score_winner(p_scores, m.points, m.best_of, m.win_by_two);
  if win is null then raise exception 'score_invalid' using errcode = '22023'; end if;
  perform public.match_apply(p_game, p_scores, win, null);
end
$$;

-- 中途退赛（组织者、帮手）：p_side 是退赛的一边（1 / 2），算对方赢；p_scores 是退赛前打完的局，最后可以带上没打完那局的比分
create function public.match_retire(p_game bigint, p_side int, p_scores int[], p_version int)
returns void language plpgsql security definer set search_path = '' as $$
declare
  g public.match_games;
  m public.matches;
begin
  select * into g from public.match_games where id = p_game;
  if g.id is null or g.bye then raise exception 'game_not_found' using errcode = 'P0002'; end if;
  perform public.match_guard(g.match_id);
  select * into m from public.matches where id = g.match_id for update;
  select * into g from public.match_games where id = p_game;
  if g.version is distinct from p_version then raise exception 'score_changed' using errcode = '40001'; end if;
  if g.status in ('cancelled', 'skipped') then raise exception 'game_cancelled' using errcode = '22023'; end if;
  if p_side is null or p_side not in (1, 2) or exists (select 1 from unnest(p_scores) x where x is null or x not between 0 and 99)
     or not public.retire_scores_ok(coalesce(p_scores, '{}'), m.points, m.best_of, m.win_by_two) then
    raise exception 'score_invalid' using errcode = '22023';
  end if;
  perform public.match_apply(p_game, coalesce(p_scores, '{}'), (3 - p_side)::smallint, p_side::smallint);
end
$$;

-- 撤销最后一次输比分（10 秒内）：比分回到原来的样子，因为它排上的场次、淘汰赛、下一轮、结束都撤掉
create or replace function public.match_undo(p_match uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  m public.matches;
  prev public.match_games;
begin
  perform public.match_guard(p_match);
  select * into m from public.matches where id = p_match for update;
  if m.undo is null or m.undo_until < now() then raise exception 'nothing_to_undo' using errcode = 'P0002'; end if;
  prev := jsonb_populate_record(null::public.match_games, m.undo -> 'game');
  update public.match_games set status = 'queued', court = null, started_at = null
    where match_id = p_match and status = 'playing' and id in (select jsonb_array_elements_text(m.undo -> 'started')::bigint);
  delete from public.match_games
    where match_id = p_match and id in (select jsonb_array_elements_text(m.undo -> 'created')::bigint)
      and (status = 'queued' or bye);
  update public.match_games
    set scores = prev.scores, winner = prev.winner, retired = prev.retired, status = prev.status, walkover = prev.walkover,
        court = prev.court, started_at = prev.started_at, scored_by = prev.scored_by, edited_by = prev.edited_by, flagged = prev.flagged,
        version = version + 1
    where id = prev.id;
  update public.matches set undo = null, undo_until = null,
         status = case when (m.undo ->> 'closed')::boolean then 'live' else status end,
         ended_at = case when (m.undo ->> 'closed')::boolean then null else ended_at end
    where id = p_match;
  perform public.refresh_match_results(p_match);
  perform public.match_progress(p_match);
end
$$;

-- 退赛（受伤或走了）：p_game 给了就这一场算对方赢；没打的场次默认取消，p_forfeit 算对方赢（淘汰赛总是算对方赢，好往下排）。
-- 固定搭档整队退出；轮换搭档这一轮取消，后面的轮次重排；瑞士轮后面的轮次不再排他
create or replace function public.match_withdraw(p_player uuid, p_game bigint default null, p_forfeit boolean default false)
returns void language plpgsql security definer set search_path = '' as $$
declare
  m public.matches;
  members uuid[];
  current_round int;
begin
  select m2.* into m from public.matches m2 join public.match_players p on p.match_id = m2.id where p.id = p_player;
  if m.id is null then raise exception 'player_not_found' using errcode = 'P0002'; end if;
  perform public.match_guard(m.id);
  perform 1 from public.matches where id = m.id for update;
  select array_agg(p.id) into members from public.match_players p join public.match_players me on me.id = p_player
    where p.match_id = m.id and (p.id = p_player or (m.doubles and p.team = me.team));
  update public.match_players set withdrawn_at = coalesce(withdrawn_at, now()) where id = any(members);
  if p_game is not null then
    update public.match_games set status = 'done', walkover = true, scores = null, retired = null,
                                  winner = case when side_a && members then 2 else 1 end, version = version + 1
      where id = p_game and match_id = m.id and (side_a || side_b) && members and status in ('queued', 'playing');
  end if;
  if m.play = 'rotating' then
    select max(round) into current_round from public.match_games where match_id = m.id and status in ('playing', 'done');
    update public.match_games set status = 'cancelled', court = null
      where match_id = m.id and status in ('queued', 'playing') and (side_a || side_b) && members and round <= coalesce(current_round, 0);
    perform public.match_schedule_rotating(m.id, coalesce(current_round, 0) + 1);
  else
    update public.match_games
      set status = case when p_forfeit or stage <> 'pool' then 'done' else 'cancelled' end,
          walkover = coalesce(p_forfeit, false) or stage <> 'pool', court = null,
          winner = case when p_forfeit or stage <> 'pool' then case when side_a && members then 2 else 1 end end, version = version + 1
      where match_id = m.id and status in ('queued', 'playing') and (side_a || side_b) && members;
  end if;
  perform public.match_progress(m.id);
end
$$;

-- 中途加人：只有双打轮换搭档能加，从下一轮开始排
create or replace function public.match_add_player(p_match uuid, p_user uuid default null, p_name text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  m public.matches;
  v_name text;
  v_rating numeric;
  added uuid;
  current_round int;
begin
  perform public.match_guard(p_match);
  select * into m from public.matches where id = p_match for update;
  if m.play <> 'rotating' or m.status <> 'live' then raise exception 'cannot_add_player' using errcode = '22023'; end if;
  if p_user is not null then
    select nickname, rating into v_name, v_rating from public.profiles where id = p_user;
    if v_name is null or public.blocked_between(auth.uid(), p_user)
       or not (public.related(auth.uid(), p_user)
               or exists (select 1 from public.session_signups where session_id = m.session_id and user_id = p_user)) then
      raise exception 'player_not_found' using errcode = 'P0002';
    end if;
    if exists (select 1 from public.match_players where match_id = p_match and user_id = p_user) then
      raise exception 'duplicate_player' using errcode = '22023';
    end if;
  else
    v_name := public.clean_player_name(p_name);
  end if;
  if exists (select 1 from public.match_players where match_id = p_match and lower(name) = lower(v_name)) then
    v_name := left(v_name, 20) || ' ' || (select count(*) + 1 from public.match_players where match_id = p_match and lower(name) like lower(v_name) || '%');
  end if;
  if (select count(*) from public.match_players where match_id = p_match) >= 64 then
    raise exception 'invalid_player_count' using errcode = '22023';
  end if;
  insert into public.match_players (match_id, user_id, name, rating, seq)
    values (p_match, p_user, left(v_name, 24), v_rating, (select max(seq) + 1 from public.match_players where match_id = p_match))
    returning id into added;
  select max(round) into current_round from public.match_games where match_id = p_match and status in ('playing', 'done');
  perform public.match_schedule_rotating(p_match, coalesce(current_round, 0) + 1);
  if p_user is not null then
    perform public.notify(p_user, 'match', 'Match started: {match}', 'Your first game is in round {round}.', '/app/matches/' || p_match || '/',
      jsonb_build_object('match', m.name, 'round', coalesce((select min(round) from public.match_games where match_id = p_match
                                                             and added = any(side_a || side_b)), current_round + 1)));
  end if;
  perform public.match_fill(p_match);
  return added;
end
$$;

-- 出线卡在并列上时，组织者点选谁出线（p_keys 按种子顺序）；淘汰赛还没开始才能改
create or replace function public.match_qualify(p_match uuid, p_keys text[])
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.match_guard(p_match, true);
  perform 1 from public.matches where id = p_match and format = 'groups' and status = 'live' for update;
  if not found or exists (select 1 from public.match_games where match_id = p_match and stage <> 'pool' and status <> 'queued' and not bye) then
    raise exception 'knockout_started' using errcode = '22023';
  end if;
  delete from public.match_games where match_id = p_match and stage <> 'pool';
  perform public.match_knockout(p_match, p_keys);
  perform public.match_progress(p_match);
end
$$;

-- 我的 → 比赛：建的、帮忙的、参加过的，新的在前（最近 50 场）
create or replace function public.my_matches()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', m.id, 'name', m.name, 'format', m.format, 'play', m.play, 'status', m.status, 'created_at', m.created_at, 'ended_at', m.ended_at,
      'players', (select count(*) from public.match_players p where p.match_id = m.id),
      'rank', case when m.status = 'done' then (
        select (e ->> 'rank')::int from jsonb_array_elements(public.match_ranking(m.id)) e
        where exists (select 1 from public.match_players p where p.match_id = m.id and p.user_id = auth.uid()
                      and (e -> 'members') ? p.id::text)) end)
    order by m.created_at desc), '[]')
  from (select * from public.matches m
        where m.owner_id = auth.uid() or auth.uid() = any(m.helpers)
           or exists (select 1 from public.match_players p where p.match_id = m.id and p.user_id = auth.uid())
        order by m.created_at desc limit 50) m
$$;

revoke execute on function public.match_apply(bigint, int[], smallint, smallint) from public, anon, authenticated;
revoke execute on function
  public.create_match(text, text, int, text, text, int, int, boolean, jsonb, int, int, int, boolean, uuid, uuid[]),
  public.match_score(bigint, int[], int), public.match_retire(bigint, int, int[], int) from public, anon;
grant execute on function
  public.create_match(text, text, int, text, text, int, int, boolean, jsonb, int, int, int, boolean, uuid, uuid[]),
  public.match_score(bigint, int[], int), public.match_retire(bigint, int, int[], int) to authenticated;

-- 已经结束的比赛补上个人胜率
do $$
begin
  perform public.refresh_match_results(id) from public.matches where status = 'done';
end
$$;
