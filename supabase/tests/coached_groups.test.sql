-- 教练带课的球群：1–40 人、收费备注 120 字、水平范围只作提示、旧版 App 编辑不丢标记、统计只有管理员能查
begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000009' || lpad(n::text, 2, '0'))::uuid, 'coach' || n || '@test.local' from generate_series(1, 4) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000009' || lpad(n::text, 2, '0'))::uuid, 'Coach' || n from generate_series(1, 4) n;
-- 3 号水平远高于群的范围；4 号是老用户（一周前注册）
update public.profiles set rating = 8 where id = '00000000-0000-0000-0000-000000000903';
update public.profiles set created_at = now() - interval '7 days' where id = '00000000-0000-0000-0000-000000000904';

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000009' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create function pg_temp.schedule(capacity int, fee text default '$40 a lesson') returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object(
    'weekday', extract(dow from (now() at time zone 'America/Los_Angeles') + interval '1 day'),
    'start', 1140, 'end', 1200, 'capacity', capacity, 'fee', fee))
$$;
create temp table ids (name text primary key, id uuid);
grant all on ids to authenticated;
create function pg_temp.id(k text) returns uuid language sql as $$ select id from ids where name = k $$;

-- 建群
select pg_temp.login(1);
insert into ids select 'lesson', public.create_group('Private lessons', 'v-us-ca-21-badminton-club-21bc', 'Footwork and basics', 1, 3, 'open',
                                                     pg_temp.schedule(1), null, true);
select ok(pg_temp.id('lesson') is not null, '教练带课的群可以只开 1 个名额');
select is(public.group_page(pg_temp.id('lesson')) ->> 'coached', 'true', '球群页带上教练带课的标记');
select is(public.group_page(pg_temp.id('lesson')) -> 'sessions' -> 0 ->> 'capacity', '1', '场次的名额是 1');
select throws_ok($$ select public.create_group('Bad', 'v-us-ca-21-badminton-club-21bc', '', 1, 3, 'open', pg_temp.schedule(0), null, true) $$,
                 '22023', 'invalid_schedule', '名额不能是 0');
select throws_ok($$ select public.create_group('Bad', 'v-us-ca-21-badminton-club-21bc', '', 1, 3, 'open', pg_temp.schedule(2)) $$,
                 '22023', 'invalid_schedule', '普通群还是至少 4 个名额');
insert into ids select 'plain', public.create_group('Friday doubles', 'v-us-ca-21-badminton-club-21bc', '', 1, 3, 'open', pg_temp.schedule(4));
select is(public.group_page(pg_temp.id('plain')) ->> 'coached', 'false', '不传就是普通群');

-- 收费备注 120 字
select lives_ok($$ select public.update_group(pg_temp.id('lesson'), 'Private lessons', 'Footwork and basics', 1, 3, 'open',
                                             pg_temp.schedule(1, repeat('a', 120))) $$, '收费备注可以写 120 字');
select throws_ok($$ select public.update_group(pg_temp.id('lesson'), 'Private lessons', '', 1, 3, 'open', pg_temp.schedule(1, repeat('a', 121))) $$,
                 '22023', 'invalid_schedule', '超过 120 字不行');

-- 旧版 App 编辑时不传 p_coached：标记不变
select is(public.group_page(pg_temp.id('lesson')) ->> 'coached', 'true', '不传 p_coached，标记保持原样');
select throws_ok($$ select public.update_group(pg_temp.id('lesson'), 'Private lessons', '', 1, 3, 'open', pg_temp.schedule(1), false) $$,
                 '22023', 'invalid_schedule', '取消标记时名额要回到 4 个以上');
select lives_ok($$ select public.update_group(pg_temp.id('plain'), 'Friday doubles', '', 1, 3, 'open', pg_temp.schedule(2), true) $$,
                '普通群可以改成教练带课');

-- 水平范围只作提示
select pg_temp.login(3);
select is(public.join_group(pg_temp.id('lesson')), 'member', '水平不在范围内也能加入教练带课的群');
select pg_temp.login(1);
insert into ids select 'strict', public.create_group('Beginners only', 'v-us-ca-21-badminton-club-21bc', '', 1, 3, 'open', pg_temp.schedule(4));
select pg_temp.login(3);
select throws_ok($$ select public.join_group(pg_temp.id('strict')) $$, '22023', 'level_out_of_range', '普通群还是按水平范围');

-- 统计：App 里调不到；管理员能看到学员数、新用户、其中约过球的
select throws_ok($$ select * from public.coached_group_stats() $$, '42501', null, '登录用户不能查统计');
select pg_temp.login(4);
select public.join_group(pg_temp.id('lesson'));
reset role;
insert into public.match_tickets (user_id, mode, starts_at, ends_at, venue_ids, skill_tolerance, lock_at)
  select pg_temp.u(3), 'singles', date_trunc('hour', now()) + interval '2 days', date_trunc('hour', now()) + interval '2 days 2 hours',
         array['v-us-ca-21-badminton-club-21bc'], 1, now() + interval '1 day';
select is((select students from public.coached_group_stats() where group_name = 'Private lessons'), 2::bigint, '学员数不算教练');
select is((select new_users from public.coached_group_stats() where group_name = 'Private lessons'), 1::bigint, '加群前 24 小时内注册的才算新用户');
select is((select new_users_who_played from public.coached_group_stats() where group_name = 'Private lessons'), 1::bigint, '新用户里发过约球请求的');

select * from finish();
rollback;
