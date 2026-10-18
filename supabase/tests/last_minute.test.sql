-- 临时局：开赛前 2.5 小时内也能约，确认期限短、开赛前 20 分钟锁定；普通请求到点没约成时提示可以转临时局
begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000008' || lpad(n::text, 2, '0'))::uuid, 'l' || n || '@test.local' from generate_series(1, 4) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000008' || lpad(n::text, 2, '0'))::uuid, 'Late' || n from generate_series(1, 4) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000008' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create function pg_temp.ticket(n int) returns public.match_tickets language sql security definer as $$
  select * from public.match_tickets where user_id = pg_temp.u(n) order by created_at desc limit 1
$$;
create function pg_temp.last_body(n int) returns text language sql security definer as $$
  select body from public.notifications where user_id = pg_temp.u(n) order by id desc limit 1
$$;
-- 1 小时到 1.5 小时后的半点
create function pg_temp.soon() returns timestamptz language sql as $$
  select to_timestamp(ceil(extract(epoch from now()) / 1800) * 1800) + interval '1 hour'
$$;

-- 1、2 号都临时约同一场单打：马上配上
select pg_temp.login(1);
select lives_ok($$ select public.submit_ticket('singles', pg_temp.soon(), pg_temp.soon() + interval '2 hours', '{v-us-ca-21-badminton-club-21bc}', 1, false) $$,
                '开赛前 2.5 小时内可以发起');
select ok((pg_temp.ticket(1)).last_minute, '记为临时局');
select is((pg_temp.ticket(1)).lock_at, pg_temp.soon() - interval '20 minutes', '开赛前 20 分钟锁定');
select ok((public.my_matchmaking() -> 0 ->> 'last_minute')::boolean, '客户端看得到是临时局');
select pg_temp.login(2);
select public.submit_ticket('singles', pg_temp.soon(), pg_temp.soon() + interval '2 hours', '{v-us-ca-21-badminton-club-21bc}', 1, false);
reset role;
select is((pg_temp.ticket(2)).status::text, 'offered', '此刻也在找的人马上配上');
select is((select lock_at from public.match_offers where id = (pg_temp.ticket(2)).offer_id), pg_temp.soon() - interval '20 minutes',
          '提议也在开赛前 20 分钟锁定');
select is((select respond_by from public.match_seats where user_id = pg_temp.u(2)), now() + interval '10 minutes', '10 分钟内确认');

-- 临时局到点没约成：结束，不再提示转临时局
select pg_temp.login(3);
select public.submit_ticket('doubles', pg_temp.soon(), pg_temp.soon() + interval '2 hours', '{v-us-ca-21-badminton-club-21bc}', 1, false);
-- 普通请求到点没约成：提示可以转临时局
select pg_temp.login(4);
select public.submit_ticket('singles', pg_temp.soon() + interval '1 day', pg_temp.soon() + interval '1 day 2 hours',
                            '{v-us-ca-albert-d-salgado-recreation-center}', 1, false);
reset role;
select public.process_matchmaking(pg_temp.soon() + interval '1 day' - interval '119 minutes');
select is((pg_temp.ticket(3)).status::text, 'expired', '临时局开赛前 20 分钟没约成：结束');
select unalike(pg_temp.last_body(3), '%last-minute%', '临时局结束时不再提示转临时局');
select alike(pg_temp.last_body(4), '%Try a last-minute search.', '普通请求结束时提示可以转临时局');

select * from finish();
rollback;
