-- 一个球群几个球馆：建群最多 5 个、场次选球馆、场次记下球馆、附近按任何一个球馆找、删球馆回到主球馆、换主球馆、旧版 App 建群和编辑照常
begin;
create extension if not exists pgtap with schema extensions;
select plan(34);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000012' || lpad(n::text, 2, '0'))::uuid, 'gv' || n || '@test.local' from generate_series(1, 3) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000012' || lpad(n::text, 2, '0'))::uuid, 'Courts' || n from generate_series(1, 3) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000012' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
-- 明天（球馆当地）是星期几；start 开始，两小时
create function pg_temp.slot(start int, venue text default null) returns jsonb language sql as $$
  select jsonb_build_object('weekday', extract(dow from (now() at time zone 'America/Los_Angeles') + interval '1 day'),
                            'start', start, 'end', start + 120, 'capacity', 8)
         || case when venue is null then '{}'::jsonb else jsonb_build_object('venue', venue) end
$$;
create temp table ids (name text primary key, id uuid);
grant all on ids to authenticated;
create function pg_temp.id(k text) returns uuid language sql as $$ select id from ids where name = k $$;
-- 这个群明天 start 开始的那一场
create function pg_temp.session(k text, start int) returns uuid language sql security definer as $$
  select s.id from public.group_sessions s
  where s.group_id = pg_temp.id(k) and s.cancelled_at is null
    and extract(hour from s.starts_at at time zone 'America/Los_Angeles') * 60 = start
  order by s.starts_at limit 1
$$;
create function pg_temp.session_venue(k text, start int) returns text language sql as $$
  select x ->> 'venue' from jsonb_array_elements(public.group_page(pg_temp.id(k)) -> 'sessions') x
  where x ->> 'id' = pg_temp.session(k, start)::text
$$;

-- 三个球馆：弗里蒙特两家（主球馆 21BC），还有一家在 100 公里外的蒙特雷
select pg_temp.login(1);
insert into ids select 'multi', public.create_group('Three courts', null, '', 1, 9, 'open',
  jsonb_build_array(pg_temp.slot(1080), pg_temp.slot(1200, 'v-us-ca-happy-birdie-badminton-fremont')), null, false,
  array['v-us-ca-21-badminton-club-21bc', 'v-us-ca-happy-birdie-badminton-fremont', 'v-us-ca-monterey-sports-center']);
select ok(pg_temp.id('multi') is not null, '可以建 3 个球馆的群');
select is((select array_agg(x ->> 'id') from jsonb_array_elements(public.group_page(pg_temp.id('multi')) -> 'venues') x),
          array['v-us-ca-21-badminton-club-21bc', 'v-us-ca-happy-birdie-badminton-fremont', 'v-us-ca-monterey-sports-center'],
          'venues 按顺序，第一个是主球馆');
select is(public.group_page(pg_temp.id('multi')) -> 'venue' ->> 'id', 'v-us-ca-21-badminton-club-21bc', 'venue 还是主球馆');
select is(public.group_page(pg_temp.id('multi')) -> 'venues' -> 1 ->> 'name', 'Happy Birdie Badminton - Fremont', 'venues 带名字');
select is((select jsonb_agg(x -> 'venue' order by (x ->> 'start')::int) from jsonb_array_elements(public.group_page(pg_temp.id('multi')) -> 'schedules') x),
          '[null, "v-us-ca-happy-birdie-badminton-fremont"]'::jsonb, '每周场次带球馆，主球馆是 null');
select is(pg_temp.session_venue('multi', 1080), 'v-us-ca-21-badminton-club-21bc', '没选球馆的场次在主球馆');
select is(pg_temp.session_venue('multi', 1200), 'v-us-ca-happy-birdie-badminton-fremont', '场次在选的球馆');

-- 附近：任何一个球馆在范围内都算，带到最近那个球馆的距离
select pg_temp.login(2);
select ok((select bool_or(x ->> 'id' = pg_temp.id('multi')::text) from public.venues v,
           jsonb_array_elements(public.groups_near(v.lat, v.lon, 5)) x where v.id = 'v-us-ca-monterey-sports-center'),
          '在蒙特雷也能找到（不是主球馆）');
select ok((select (x ->> 'distance_m')::int < 100 from public.venues v,
           jsonb_array_elements(public.groups_near(v.lat, v.lon, 5)) x where v.id = 'v-us-ca-monterey-sports-center' and x ->> 'id' = pg_temp.id('multi')::text),
          'distance_m 是到最近的球馆');

-- 报名第二个球馆那一场，取消时通知里写那个球馆
select public.join_group(pg_temp.id('multi'));
select public.sign_up_session(pg_temp.session('multi', 1200));
select is((public.my_groups() -> 'sessions' -> 0 ->> 'venue'), 'Happy Birdie Badminton - Fremont', '我报名的场次写实际的球馆');

-- 不合格的球馆
select pg_temp.login(1);
select throws_ok($$ select public.create_group('Six courts', null, '', 1, 9, 'open', jsonb_build_array(pg_temp.slot(1080)), null, false,
                   (select array_agg(id order by id) from (select id from public.venues where city = 'Fremont' and not hidden_pending_review limit 6) x)) $$,
                 '22023', 'invalid_venues', '最多 5 个球馆');
select throws_ok($$ select public.create_group('Twice', null, '', 1, 9, 'open', jsonb_build_array(pg_temp.slot(1080)), null, false,
                   array['v-us-ca-21-badminton-club-21bc', 'v-us-ca-21-badminton-club-21bc']) $$,
                 '22023', 'invalid_venues', '球馆不能重复');
select throws_ok($$ select public.create_group('Nowhere', null, '', 1, 9, 'open', jsonb_build_array(pg_temp.slot(1080)), null, false,
                   array['v-us-ca-21-badminton-club-21bc', 'v-nope']) $$,
                 '22023', 'invalid_venues', '球馆要存在');
select throws_ok($$ select public.create_group('Empty', null, '', 1, 9, 'open', jsonb_build_array(pg_temp.slot(1080)), null, false, '{}') $$,
                 '22023', 'invalid_venues', '至少 1 个球馆');
select throws_ok($$ select public.create_group('Elsewhere', null, '', 1, 9, 'open',
                   jsonb_build_array(pg_temp.slot(1080, 'v-us-ca-monterey-sports-center')), null, false, array['v-us-ca-21-badminton-club-21bc']) $$,
                 '22023', 'invalid_schedule', '场次的球馆要是这个群的');

-- 旧版 App：只传 p_venue
insert into ids select 'old', public.create_group('Old style', 'v-us-ca-happy-birdie-badminton-fremont', '', 1, 9, 'open', jsonb_build_array(pg_temp.slot(1080)));
select is(jsonb_array_length(public.group_page(pg_temp.id('old')) -> 'venues'), 1, '旧版建群：一个球馆');
select is(public.group_page(pg_temp.id('old')) -> 'venues' -> 0 ->> 'id', 'v-us-ca-happy-birdie-badminton-fremont', '就是 p_venue');
select is(pg_temp.session_venue('old', 1080), 'v-us-ca-happy-birdie-badminton-fremont', '旧版建的群场次也有球馆');
select ok((select count(*) >= 1 and bool_and((a ->> 'distance_m')::int <= (b ->> 'distance_m')::int)
           from public.venues v, jsonb_array_elements(public.groups_near(v.lat, v.lon, 30)) with ordinality a (a, i)
           join jsonb_array_elements(public.groups_near(v.lat, v.lon, 30)) with ordinality b (b, j) on j = i + 1
           where v.id = 'v-us-osm-w839432575'), '近的在前');

-- 旧版 App 编辑：不传 p_venues，场次不带 "venue"，原来在第二个球馆的场次不动
select lives_ok($$ select public.update_group(pg_temp.id('multi'), 'Three courts', 'Renamed', 1, 9, 'open',
                   jsonb_build_array(pg_temp.slot(1080), pg_temp.slot(1200))) $$, '旧版 App 编辑');
select is(pg_temp.session_venue('multi', 1200), 'v-us-ca-happy-birdie-badminton-fremont', '旧版编辑后场次还在原来的球馆');
reset role;
select is((select count(*)::int from public.session_signups where session_id = pg_temp.session('multi', 1200)), 1, '旧版编辑后报名还在');

-- 删掉第二个球馆：那里的场次回到主球馆，报名不丢
select pg_temp.login(1);
select lives_ok($$ select public.update_group(pg_temp.id('multi'), 'Three courts', '', 1, 9, 'open',
                   jsonb_build_array(pg_temp.slot(1080), pg_temp.slot(1200, 'v-us-ca-happy-birdie-badminton-fremont')), null,
                   array['v-us-ca-21-badminton-club-21bc', 'v-us-ca-monterey-sports-center']) $$, '可以删球馆');
select is(jsonb_array_length(public.group_page(pg_temp.id('multi')) -> 'venues'), 2, '剩两个球馆');
select is((select jsonb_agg(x -> 'venue') from jsonb_array_elements(public.group_page(pg_temp.id('multi')) -> 'schedules') x),
          '[null, null]'::jsonb, '删掉的球馆上的每周场次回到主球馆');
select is(pg_temp.session_venue('multi', 1200), 'v-us-ca-21-badminton-club-21bc', '已经生成的场次也回到主球馆');
reset role;
select is((select count(*)::int from public.session_signups where session_id = pg_temp.session('multi', 1200)), 1, '报名还在');

-- 换主球馆：原来在主球馆的场次还在原来的球馆
select pg_temp.login(1);
select lives_ok($$ select public.update_group(pg_temp.id('multi'), 'Three courts', '', 1, 9, 'open',
                   jsonb_build_array(pg_temp.slot(1080, 'v-us-ca-21-badminton-club-21bc'), pg_temp.slot(1200, 'v-us-ca-21-badminton-club-21bc')), null,
                   array['v-us-ca-monterey-sports-center', 'v-us-ca-21-badminton-club-21bc']) $$, '可以换主球馆');
reset role;
select is((select venue_id from public.play_groups where id = pg_temp.id('multi')), 'v-us-ca-monterey-sports-center', 'play_groups.venue_id 跟着主球馆');
select is((select count(*)::int from public.group_sessions where group_id = pg_temp.id('multi') and cancelled_at is not null), 0,
          '换主球馆不取消场次');
select pg_temp.login(1);
select is(pg_temp.session_venue('multi', 1080), 'v-us-ca-21-badminton-club-21bc', '场次还在原来的球馆');
select is((select jsonb_agg(x -> 'venue') from jsonb_array_elements(public.group_page(pg_temp.id('multi')) -> 'schedules') x),
          '["v-us-ca-21-badminton-club-21bc", "v-us-ca-21-badminton-club-21bc"]'::jsonb, '每周场次记下原来的球馆');

-- 场次换到另一个球馆：原来的取消（报了名的人收到通知），按新球馆生成
select lives_ok($$ select public.update_group(pg_temp.id('multi'), 'Three courts', '', 1, 9, 'open',
                   jsonb_build_array(pg_temp.slot(1080, 'v-us-ca-21-badminton-club-21bc'), pg_temp.slot(1200, 'v-us-ca-monterey-sports-center'))) $$,
                '场次可以换球馆');
reset role;
select is((select count(*)::int from public.notifications where user_id = pg_temp.u(2) and kind = 'group' and body like '%21 Badminton Club%'), 1,
          '报了名的人收到取消通知，写的是原来的球馆');

select * from finish();
rollback;
