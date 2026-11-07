-- 赛果按局：两边各赢几局，双方一致才算；局数不一样算有分歧；胜率按局算；平局也计入
begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000036' || lpad(n::text, 2, '0'))::uuid, 'rd' || n || '@test.local' from generate_series(1, 2) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000036' || lpad(n::text, 2, '0'))::uuid, 'Round' || n from generate_series(1, 2) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000036' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create temp table ids (name text primary key, id uuid);
grant all on ids to authenticated;
create function pg_temp.id(k text) returns uuid language sql as $$ select id from ids where name = k $$;
-- 半小时前开始的球局（月初的头半小时之外都在本月）
create function pg_temp.game(k text, hours int) returns void language sql as $$
  with g as (insert into public.games (mode, starts_at, ends_at, venue_id)
             values ('singles', now() - make_interval(mins => 30 + hours), now() + interval '1 hour', 'v-us-ca-21-badminton-club-21bc')
             returning id)
  insert into ids select k, id from g;
  insert into public.game_players (game_id, user_id, team, rating)
    select pg_temp.id(k), pg_temp.u(n), n, 3 from generate_series(1, 2) n;
$$;
select pg_temp.game('a', 1);
select pg_temp.game('b', 5);
select pg_temp.game('c', 9);

-- a：两人都报 3:2（1 号是 team1）
select pg_temp.login(1);
select throws_ok($$ select public.report_result(pg_temp.id('a'), null, null, 3, null) $$, '22023', 'invalid_games', '局数要两边都填');
select is(public.report_result(pg_temp.id('a'), 'team2', null, 3, 2), 'awaiting', '填了局数按局数定输赢');
select is((select outcome::text from public.result_reports where game_id = pg_temp.id('a') and reporter_id = pg_temp.u(1)), 'team1', '3:2 是 team1 赢');
select pg_temp.login(2);
select is(public.report_result(pg_temp.id('a'), 'team1', null, 3, 2), 'verified', '双方一致就确认');
reset role;
select is((select rounds_won || '/' || rounds_played from public.game_results where game_id = pg_temp.id('a') and user_id = pg_temp.u(2)), '2/5',
          '输的一方也记下赢的局数');

-- b：局数不一样算分歧
select pg_temp.login(1);
select public.report_result(pg_temp.id('b'), 'team1', null, 2, 0);
select pg_temp.login(2);
select is(public.report_result(pg_temp.id('b'), 'team1', null, 2, 1), 'disputed', '局数不一样就有分歧');

-- c：2:2 平局，也计入
select pg_temp.login(1);
select public.report_result(pg_temp.id('c'), null, null, 2, 2);
select pg_temp.login(2);
select is(public.report_result(pg_temp.id('c'), null, null, 2, 2), 'verified', '平局也能确认');
reset role;
select is((select won::text || ' ' || rounds_won || '/' || rounds_played from public.game_results
           where game_id = pg_temp.id('c') and user_id = pg_temp.u(1)), 'false 2/4', '平局不算赢，局数照算');

-- 1 号本月：3/5 + 2/4 = 5/9 局；按场是 2 场
select is((public.win_rate(pg_temp.u(1)) ->> 'round_wins') || '/' || (public.win_rate(pg_temp.u(1)) ->> 'rounds'), '5/9', '胜率按局算');
select is((public.win_rate(pg_temp.u(1)) ->> 'games')::int, 2, '按场的数也还在（给老版本）');

select * from finish();
rollback;
