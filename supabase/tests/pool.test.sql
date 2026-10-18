-- 有多少人在找：只给人数；不算自己、屏蔽关系和太远的；“条件都合适”和匹配时的条件一样
begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000012' || lpad(n::text, 2, '0'))::uuid, 'p' || n || '@test.local' from generate_series(1, 6) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000012' || lpad(n::text, 2, '0'))::uuid, 'Pool' || chr(64 + n) from generate_series(1, 6) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000012' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
-- 后天（洛杉矶）h 点开始、2 小时
create function pg_temp.at(h int) returns timestamptz language sql as $$
  select (date_trunc('day', now() at time zone 'America/Los_Angeles') + interval '2 days' + h * interval '1 hour') at time zone 'America/Los_Angeles'
$$;
-- n 号的请求 id
create function pg_temp.t(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000012' || lpad((n + 50)::text, 2, '0'))::uuid
$$;
create function pg_temp.ticket(n int, mode public.game_mode, h int, venue text) returns uuid language sql as $$
  insert into public.match_tickets (id, user_id, mode, starts_at, ends_at, venue_ids, skill_tolerance, lock_at)
    values (pg_temp.t(n), pg_temp.u(n), mode, pg_temp.at(h), pg_temp.at(h + 2), array[venue], 1, pg_temp.at(h) - interval '2 hours')
  returning id
$$;

-- 1 号：后天 18–20 点在 Fremont。2 号条件都合适；3 号同一天上午在附近的 Milpitas；4 号打双打；
-- 5 号被 1 号屏蔽；6 号在 45 公里外
select pg_temp.ticket(1, 'singles', 18, 'v-us-ca-21-badminton-club-21bc');
select pg_temp.ticket(2, 'singles', 18, 'v-us-ca-21-badminton-club-21bc');
select pg_temp.ticket(3, 'singles', 10, 'v-us-ca-bay-badminton-center-milpitas');
select pg_temp.ticket(4, 'doubles', 18, 'v-us-ca-21-badminton-club-21bc');
select pg_temp.ticket(5, 'singles', 18, 'v-us-ca-21-badminton-club-21bc');
select pg_temp.ticket(6, 'singles', 18, 'v-us-ca-bay-badminton-center-south-san-francisco');
insert into public.blocks (blocker, blocked) values (pg_temp.u(1), pg_temp.u(5));

select pg_temp.login(1);
select is(public.ticket_pool(pg_temp.t(1)),
          '{"available": 2, "compatible": 1}', '同一天附近找单打的 2 人，其中 1 人条件都合适');
select is(public.pool_by_day(37.5148, -121.9865, 25, 'America/Los_Angeles'),
          jsonb_build_object((pg_temp.at(18) at time zone 'America/Los_Angeles')::date::text, 3), '按天数人：不分单双打，不算屏蔽的和太远的');

reset role;
update public.match_tickets set excluded_user_ids = array[pg_temp.u(1)] where user_id = pg_temp.u(2);
select pg_temp.login(1);
select is(public.ticket_pool(pg_temp.t(1)) ->> 'compatible', '0', '排除了我的人不算合适');

select pg_temp.login(2);
select is(public.ticket_pool(pg_temp.t(1)), null, '别人的请求查不到');
select is(public.pool_by_day(37.5148, -121.9865, 25, 'America/Los_Angeles') ->> (pg_temp.at(18) at time zone 'America/Los_Angeles')::date::text,
          '4', '2 号看：不算自己，屏蔽只在 1 号和 5 号之间');

set local role anon;
select throws_ok($$ select public.pool_by_day(37.5, -122, 25, 'UTC') $$, '42501', null, '没登录不能查');

select * from finish();
rollback;
