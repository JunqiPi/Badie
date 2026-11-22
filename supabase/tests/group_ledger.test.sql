-- 球群的价格和收款记录：价格写在每周场次上、改价格只影响以后的场次、免费不用付、收款记录、一次标已付、我还没付的
begin;
create extension if not exists pgtap with schema extensions;
select plan(34);

-- 1 是群主，2–4 是成员，5 不是成员
insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000048' || lpad(n::text, 2, '0'))::uuid, 'gl' || n || '@test.local' from generate_series(1, 5) n;
insert into public.profiles (id, nickname, rating)
  select ('00000000-0000-0000-0000-0000000048' || lpad(n::text, 2, '0'))::uuid, 'L' || n, 4 from generate_series(1, 5) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000048' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'postgres', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create temp table ids (name text primary key, id uuid);
create function pg_temp.id(k text) returns uuid language sql as $$ select id from ids where name = k $$;
create function pg_temp.slot(p_price jsonb) returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object('weekday', 3, 'start', 1140, 'end', 1320, 'capacity', 12) || coalesce(p_price, '{}'))
$$;
-- 以前开过的一场：days 天前，报名的人 2–4 和一个访客 Tony
create function pg_temp.past(k text, days int, fee numeric) returns void language plpgsql as $$
begin
  insert into ids select k, gen_random_uuid();
  insert into public.group_sessions (id, group_id, schedule_id, starts_at, ends_at, capacity, fee)
    select pg_temp.id(k), pg_temp.id('group'), s.id, now() - make_interval(days => days), now() - make_interval(days => days) + interval '3 hours', 12, fee
    from public.group_schedules s where s.group_id = pg_temp.id('group');
  insert into public.session_signups (session_id, user_id) select pg_temp.id(k), pg_temp.u(n) from generate_series(2, 4) n;
  insert into public.session_signups (session_id, guest_name, guest_token_hash) values (pg_temp.id(k), 'Tony', md5(k));
end
$$;
create function pg_temp.signup(k text, n int) returns uuid language sql as $$
  select id from public.session_signups where session_id = pg_temp.id(k) and user_id = pg_temp.u(n)
$$;

-- 价格写在每周场次上
select pg_temp.login(1);
select throws_ok($$ select public.create_group('Bad price', 'v-us-ca-21-badminton-club-21bc', '', 1, 9, 'open', pg_temp.slot('{"price": -1}')) $$,
                 '22023', 'invalid_schedule', '价格不能是负数');
select throws_ok($$ select public.create_group('Bad price', 'v-us-ca-21-badminton-club-21bc', '', 1, 9, 'open', pg_temp.slot('{"price": "12"}')) $$,
                 '22023', 'invalid_schedule', '价格要是数字');
select throws_ok($$ select public.create_group('Bad price', 'v-us-ca-21-badminton-club-21bc', '', 1, 9, 'open', pg_temp.slot('{"price": 1001}')) $$,
                 '22023', 'invalid_schedule', '价格最多 1000');
insert into ids select 'group', public.create_group('Wed night', 'v-us-ca-21-badminton-club-21bc', '', 1, 9, 'open', pg_temp.slot('{"price": 12.5}'));
select is((public.group_page(pg_temp.id('group')) -> 'schedules' -> 0 ->> 'price')::numeric, 12.5, '球群信息里有每场的价格');
select is((public.group_page(pg_temp.id('group')) -> 'sessions' -> 0 ->> 'price')::numeric, 12.5, '以后的场次写着每人 $12.5');
insert into ids select 'free', public.create_group('Free night', 'v-us-ca-21-badminton-club-21bc', '', 1, 9, 'open', pg_temp.slot('{"price": 0}'));
select is((public.group_page(pg_temp.id('free')) -> 'sessions' -> 0 ->> 'price')::numeric, 0::numeric, '免费的群写着 0');
insert into ids select 'old', public.create_group('Old app', 'v-us-ca-21-badminton-club-21bc', '', 1, 9, 'open', pg_temp.slot(null));
select is(public.group_page(pg_temp.id('old')) -> 'sessions' -> 0 ->> 'price', null, '旧版 App 建的群没有价格');
select pg_temp.login(n), public.join_group(pg_temp.id('group')) from generate_series(2, 4) n;

-- 以前开过的两场：7 天前 $12（那时候的价格），40 天前没写金额
reset role;
select pg_temp.past('week', 7, 12);
select pg_temp.past('long', 40, null);
update public.group_sessions set fee = 12, fee_by = pg_temp.u(1)
  where group_id = pg_temp.id('group') and starts_at > now() + interval '8 days';
insert into ids select 'manual', id from public.group_sessions where group_id = pg_temp.id('group') and fee_by is not null;

-- 改价格：还没开始的跟着改，开过的、组织者单独改过的不动；旧版 App 不带 "price" 就沿用
select pg_temp.login(1);
select lives_ok($$ select public.update_group(pg_temp.id('group'), 'Wed night', '', 1, 9, 'open', pg_temp.slot('{"price": 15}')) $$, '改成每人 $15');
select public.set_guest_signup(pg_temp.id('group'), true, null);
select is((public.guest_group_page((select guest_code from public.play_groups where id = pg_temp.id('group'))) -> 'sessions' -> 0 ->> 'price')::numeric,
          15::numeric, '访客报名页上写着每人 $15');
select is((select fee from public.group_sessions where group_id = pg_temp.id('group') and starts_at > now() and fee_by is null
           order by starts_at limit 1), 15::numeric, '以后的场次改成 $15');
select is((select fee from public.group_sessions where id = pg_temp.id('week')), 12::numeric, '开过的那一场还是 $12');
select is((select fee from public.group_sessions where id = pg_temp.id('manual')), 12::numeric, '组织者单独改过的那一场不动');
select is((select public.session_fee(pg_temp.id('long'))), null, '写价格以前没金额的场次不补金额');
select lives_ok($$ select public.update_group(pg_temp.id('group'), 'Wed night', 'Summary', 1, 9, 'open', pg_temp.slot(null)) $$, '旧版 App 编辑');
select is((select price from public.group_schedules where group_id = pg_temp.id('group')), 15::numeric, '旧版 App 编辑不丢价格');

-- 收款记录：开过的场次，新的在前
select is(jsonb_array_length(public.group_ledger(pg_temp.id('group')) -> 'sessions'), 2, '收款记录里有开过的两场');
select is(public.group_ledger(pg_temp.id('group')) -> 'sessions' -> 0 ->> 'id', pg_temp.id('week')::text, '新的在前');
select is(public.group_ledger(pg_temp.id('group')) -> 'sessions' -> 0 ->> 'owes', '4', '那一场 4 个人要付（3 个成员和访客）');
select is(jsonb_array_length(public.group_ledger(pg_temp.id('group'), (now() - interval '10 days')) -> 'sessions'), 1, '往前翻一页');
select is(public.group_ledger(pg_temp.id('group'), now() - interval '10 days') -> 'owed', 'null'::jsonb, '往前翻的页没有“谁还欠着”');

-- 40 天前那一场补上 $10：2 号欠两场 $22，访客 Tony 按名字合起来也是两场
select lives_ok($$ select public.set_session_fee(pg_temp.id('long'), 10) $$, '40 天前的场次也能改金额');
select is((select (o ->> 'amount')::numeric from jsonb_array_elements(public.group_ledger(pg_temp.id('group')) -> 'owed') o
           where o ->> 'id' = pg_temp.u(2)::text), 22::numeric, '2 号欠两场共 $22');
select is((select (o ->> 'sessions')::int from jsonb_array_elements(public.group_ledger(pg_temp.id('group')) -> 'owed') o
           where (o ->> 'guest')::boolean and o ->> 'name' = 'Tony'), 2, '访客按名字合起来');

-- 我还没付的（成员 3）
select pg_temp.login(3);
select is(jsonb_array_length(public.my_dues(pg_temp.id('group'))), 2, '3 号看到自己两场没付');
select is((select sum((d ->> 'amount')::numeric) from jsonb_array_elements(public.my_dues()) d), 22::numeric, '所有球群加起来 $22');
select throws_ok($$ select public.group_ledger(pg_temp.id('group')) $$, '42501', 'not_organizer', '成员看不到收款记录');
select throws_ok($$ select public.mark_signups_paid(array[pg_temp.signup('week', 3)], true) $$, '42501', 'not_organizer', '成员不能标别人已付');
select lives_ok($$ select public.i_paid(pg_temp.id('week')) $$, '3 号点我付了');
select is(jsonb_array_length(public.my_dues(pg_temp.id('group'))), 1, '还剩一场');

-- 组织者一次标两场已付
select pg_temp.login(1);
select is(public.mark_signups_paid(array[pg_temp.signup('week', 2), pg_temp.signup('long', 2)], true), 2, '2 号两场一次标成已付');
select is((select count(*)::int from jsonb_array_elements(public.group_ledger_rows(pg_temp.id('group'))) r where (r ->> 'paid_at') is not null), 3,
          '导出的表格里 3 行已付（2 号两场、3 号自己标的一场）');
select is((select count(*)::int from jsonb_array_elements(public.group_ledger(pg_temp.id('group')) -> 'owed') o
           where o ->> 'id' = pg_temp.u(2)::text), 0, '2 号不欠了');

-- 免费的场次谁都不用付
reset role;
update public.group_sessions set fee = 0 where id = pg_temp.id('week');
select pg_temp.login(4);
select is((select count(*)::int from jsonb_array_elements(public.my_dues()) d where (d ->> 'session_id')::uuid = pg_temp.id('week')), 0,
          '免费的那一场不用付');

reset role;
select ok(not has_function_privilege('anon', 'public.group_ledger(uuid, timestamptz, int)', 'execute')
          and not has_function_privilege('anon', 'public.my_dues(uuid)', 'execute')
          and has_function_privilege('authenticated', 'public.mark_signups_paid(uuid[], boolean)', 'execute')
          and not has_function_privilege('authenticated', 'public.schedule_prices(jsonb, uuid)', 'execute'), '权限');

select * from finish();
rollback;
