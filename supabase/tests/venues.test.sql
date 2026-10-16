-- 球馆库规则测试（与 iOS VenueTests 的规则一致）
begin;
create extension if not exists pgtap with schema extensions;
select plan(24);

-- 测试用户
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'a@test.local'),
  ('00000000-0000-0000-0000-00000000000b', 'b@test.local'),
  ('00000000-0000-0000-0000-00000000000c', 'c@test.local'),
  ('00000000-0000-0000-0000-00000000000d', 'd@test.local');

create function pg_temp.login(uid text) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
$$;
create function pg_temp.logout() returns void language sql as $$
  select set_config('role', 'anon', true), set_config('request.jwt.claims', '{"role":"anon"}', true);
$$;

-- 名称相似度
select ok(public.venue_names_similar('Bay Badminton Center', 'Bay Badminton Centre'), '英文拼写差异算相近');
select ok(public.venue_names_similar('朝阳体育中心羽毛球馆', '朝阳体育中心'), '去掉通用词后互相包含算相近');
select ok(not public.venue_names_similar('Synergy Badminton', 'Bay Badminton Center'), '不同名字不相近');

-- 未登录不能添加
select pg_temp.logout();
select throws_ok($$ select public.add_venue('Test Hall', 37.3, -121.9, '1 Main St', 'San Jose', 'CA', '95110', 'US') $$,
                 '42501', null, '未登录不能调用 add_venue');

-- 添加球馆
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select lives_ok($$ select public.add_venue('Bay Badminton Center', 37.3000, -121.9000, '1 Main St', 'San Jose', 'CA', '95110', 'us',
                                          apple_place_id => 'I123') $$, '登录后可以添加');
select is((select status::text from public.venues where apple_place_id = 'I123'), 'unconfirmed', '新球馆是待确认');
select is((select id from public.venues where apple_place_id = 'I123'), 'v-ap-I123', 'Place ID 决定球馆 ID');
select is((select country_code::text from public.venues where apple_place_id = 'I123'), 'US', '国家代码转大写');
select is((select count(*)::int from public.venue_confirmations where venue_id = 'v-ap-I123'), 1, '添加者自动算一次确认');

-- 查重
select is((select (public.add_venue('Another Name', 37.31, -121.91, '9 Other St', 'San Jose', 'CA', '95110', 'US',
                                    apple_place_id => 'I123')).id), 'v-ap-I123', 'Place ID 相同直接返回已有球馆');
select throws_ok($$ select public.add_venue('Bay Badminton Centre', 37.3005, -121.9000, '1 Main St', 'San Jose', 'CA', '95110', 'US') $$,
                 '23505', null, '200 米内名称相近：拒绝');
select lives_ok($$ select public.add_venue('Downtown Fitness', 37.3001, -121.9000, '1 Main St', 'San Jose', 'CA', '95110', 'US') $$,
                '同一栋楼但名字不同：允许');
select alike((select review_flag from public.venues where name = 'Downtown Fitness'), '%Bay Badminton Center%', '同一栋楼标记人工复核');
select throws_ok($$ select public.add_venue('X', 37.5, -122.0, '1 Main St', 'San Jose', 'CA', '95110', 'US') $$,
                 '22023', null, '名称太短被拒');
select throws_ok($$ select public.add_venue('No Street Hall', 37.5, -122.0, '', 'San Jose', 'CA', '95110', 'US') $$,
                 '22023', null, '地址不完整被拒');
select throws_ok($$ select public.add_venue('Imported Hall', 37.5, -122.0, '1 St', 'San Jose', 'CA', '', 'US', source => 'open_data') $$,
                 '42501', null, '客户端不能冒充开放数据来源');

-- 每天最多 3 家（已加 2 家）
select lives_ok($$ select public.add_venue('Third Hall', 37.6, -122.1, '3 St', 'San Jose', 'CA', '', 'US') $$, '第 3 家可以');
select throws_ok($$ select public.add_venue('Fourth Hall', 37.7, -122.2, '4 St', 'San Jose', 'CA', '', 'US') $$,
                 '54000', null, '第 4 家被限流');

-- 客户端不能直接写表
select throws_ok($$ insert into public.venues (name, location, street, city, country_code, source)
                    values ('Direct', 'POINT(0 0)', 's', 'c', 'US', 'player') $$,
                 '42501', null, '不能绕过函数直接插入');

-- 附近查询
select is((select count(*)::int from public.venues_near(37.3, -121.9, 1)), 2, '1 公里内 2 家');
select is((select (venue).name from public.venues_near(37.3, -121.9, 1) limit 1), 'Bay Badminton Center', '按距离排序');

-- 3 位不同球友确认后升级
select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select public.confirm_venue('v-ap-I123');
select pg_temp.login('00000000-0000-0000-0000-00000000000c');
select is((select (public.confirm_venue('v-ap-I123')).status::text), 'confirmed', '3 人确认后变球友确认');

-- 2 位不同球友举报待确认的球馆：隐藏，添加者仍可见
select public.report_venue((select id from public.venues where name = 'Third Hall'), 'closed');
select pg_temp.login('00000000-0000-0000-0000-00000000000d');
select public.report_venue((select id from public.venues where name = 'Third Hall'), 'wrong_location');
select is((select count(*)::int from public.venues where name = 'Third Hall'), 0, '被 2 人举报后对他人隐藏');
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select is((select count(*)::int from public.venues where name = 'Third Hall'), 1, '添加者本人仍能看到');

select * from finish();
rollback;
