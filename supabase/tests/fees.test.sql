-- 比分和 AA 付款：比分只能是数字和分隔符；自己标自己付没付，房间开的局房主可以替所有人标
begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000010' || lpad(n::text, 2, '0'))::uuid, 'f' || n || '@test.local' from generate_series(1, 5) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000010' || lpad(n::text, 2, '0'))::uuid, 'Fee' || n from generate_series(1, 5) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000010' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create temp table ids (name text primary key, id uuid);
grant all on ids to authenticated;
create function pg_temp.id(k text) returns uuid language sql as $$ select id from ids where name = k $$;
create function pg_temp.paid(n int) returns boolean language sql security definer as $$
  select paid_at is not null from public.game_players where game_id = pg_temp.id('game') and user_id = pg_temp.u(n)
$$;

-- 1–4 号一小时前打完一场双打，是 1 号的房间开出来的
with g as (insert into public.games (mode, starts_at, ends_at, venue_id)
           values ('doubles', now() - interval '3 hours', now() - interval '1 hour', 'v-us-ca-21-badminton-club-21bc') returning id)
insert into ids select 'game', id from g;
insert into public.game_players (game_id, user_id, team, rating)
  select pg_temp.id('game'), pg_temp.u(n), case when n in (1, 4) then 1 else 2 end, 3 from generate_series(1, 4) n;
insert into public.rooms (code, owner_id, mode, visibility, level_min, level_max, status, game_id)
  values ('FEE234', pg_temp.u(1), 'doubles', 'private', 1, 9, 'started', pg_temp.id('game'));

-- 比分
select pg_temp.login(2);
select throws_ok($$ select public.report_result(pg_temp.id('game'), 'team2', 'call 5551234') $$, '22023', 'invalid_score', '比分里不能有文字');
select is(public.report_result(pg_temp.id('game'), 'team2', ' 21:18 19:21 21:15 '), 'awaiting', '可以带比分报赛果');
select is(public.my_games() -> 0 -> 'my_report' ->> 'score', '21:18 19:21 21:15', '比分去掉首尾空格后保存');
select pg_temp.login(1);
select is(public.my_games() -> 0 ->> 'score', '21:18 19:21 21:15', '同场的人都看得到比分');
select is(public.my_games() -> 0 ->> 'host_id', pg_temp.u(1)::text, '房间开的局，房主是发起人');
select is(public.report_result(pg_temp.id('game'), null, '21:18'), 'awaiting', '可以改成记不清（另一位队友还没报）');
select is(public.my_games() -> 0 -> 'my_report' ->> 'score', null, '记不清的那份申报没有比分');

-- 付款
select pg_temp.login(3);
select throws_ok($$ select public.mark_paid(pg_temp.id('game'), pg_temp.u(4), true) $$, '42501', 'not_allowed', '不能替别人标（不是房主）');
select public.mark_paid(pg_temp.id('game'), pg_temp.u(3), true);
select pg_temp.login(1);
select public.mark_paid(pg_temp.id('game'), pg_temp.u(4), true);
select is(array[pg_temp.paid(3), pg_temp.paid(4), pg_temp.paid(2)], array[true, true, false], '自己标自己，房主替别人标');
select pg_temp.login(5);
select throws_ok($$ select public.mark_paid(pg_temp.id('game'), pg_temp.u(5), true) $$, '42501', 'not_allowed', '不在这局的人不能标');
select pg_temp.login(3);
select public.mark_paid(pg_temp.id('game'), pg_temp.u(3), false);
select is(pg_temp.paid(3), false, '可以改回没付');

select * from finish();
rollback;
