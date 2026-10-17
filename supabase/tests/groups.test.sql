-- 球群规则测试：建群、加入 / 审批、报名 / 候补 / 递补、临时取消、取消场次、群聊（与 iOS 的规则一致）
begin;
create extension if not exists pgtap with schema extensions;
select plan(35);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000003' || lpad(n::text, 2, '0'))::uuid, 'g' || n || '@test.local' from generate_series(1, 9) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000003' || lpad(n::text, 2, '0'))::uuid, 'Group' || n from generate_series(1, 9) n;
update public.profiles set rating = 7 where id = '00000000-0000-0000-0000-000000000309';

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000003' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create function pg_temp.notes(n int, k text) returns int language sql security definer as $$
  select count(*)::int from public.notifications where user_id = pg_temp.u(n) and kind = k
$$;
-- 明天（球馆当地）是星期几，19:00–21:00，4 个名额
create function pg_temp.schedule(capacity int default 4) returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object(
    'weekday', extract(dow from (now() at time zone 'America/Los_Angeles') + interval '1 day'),
    'start', 1140, 'end', 1260, 'capacity', capacity, 'fee', '$12 each'))
$$;
create temp table ids (name text primary key, id uuid);
grant all on ids to authenticated;
create function pg_temp.id(k text) returns uuid language sql as $$ select id from ids where name = k $$;
create function pg_temp.code(k text) returns text language sql security definer as $$ select invite_code from public.play_groups where id = pg_temp.id(k) $$;
-- 这个群明天那一场
create function pg_temp.tomorrow(k text) returns uuid language sql security definer as $$
  select id from public.group_sessions where group_id = pg_temp.id(k) order by starts_at limit 1
$$;

-- 建群
select pg_temp.login(1);
insert into ids select 'open', public.create_group('Thursday doubles', 'v-us-ca-21-badminton-club-21bc', 'Friendly rotation', 2, 5, 'open', pg_temp.schedule());
insert into ids select 'approval', public.create_group('Weekend advanced', 'v-us-ca-21-badminton-club-21bc', '', 2, 6, 'approval', pg_temp.schedule(8));
select ok(pg_temp.id('open') is not null, '可以建群');
select is((public.group_page(pg_temp.id('open')) ->> 'my_role'), 'owner', '建群的人是群主');
select ok(jsonb_array_length(public.group_page(pg_temp.id('open')) -> 'sessions') >= 2, '自动生成未来 14 天的场次');
select is(public.group_page(pg_temp.id('open')) -> 'sessions' -> 0 ->> 'capacity', '4', '名额来自固定场次');
select throws_ok($$ select public.create_group('Bad', 'v-us-ca-21-badminton-club-21bc', '', 2, 5, 'open', pg_temp.schedule(2)) $$,
                 '23514', null, '名额至少 4 个');
select throws_ok($$ select public.create_group('Bad', 'v-us-ca-21-badminton-club-21bc', '', 2, 5, 'open',
                                              pg_temp.schedule() || pg_temp.schedule() || pg_temp.schedule() || pg_temp.schedule()) $$,
                 '22023', null, '最多 3 个固定场次');
select throws_ok($$ select public.create_group('wechat 5551234', 'v-us-ca-21-badminton-club-21bc', '', 2, 5, 'open', pg_temp.schedule()) $$,
                 '22023', null, '群名不能留联系方式');
select throws_ok($$ select * from public.play_groups $$, '42501', null, '球群表不能直接读');

-- 加入
select pg_temp.login(2);
select is(public.join_group(pg_temp.id('open')), 'member', '直接加入');
select is(public.find_group(lower(pg_temp.code('open'))), pg_temp.id('open'), '凭群号找到球群（不分大小写）');
select pg_temp.login(9);
select throws_ok($$ select public.join_group(pg_temp.id('open')) $$, '22023', null, '水平不在范围内不能加入');
select pg_temp.login(6);
select is(public.group_page(pg_temp.id('open')) -> 'invite_code', 'null'::jsonb, '非成员看不到群号');
select is(public.group_page(pg_temp.id('open')) -> 'members', 'null'::jsonb, '非成员看不到成员名单');
select is(public.group_page(pg_temp.id('open')) -> 'activity' ->> 'sessions', '0', '对外只显示活跃度');

-- 需要同意的群
select pg_temp.login(3);
select is(public.join_group(pg_temp.id('approval')), 'pending', '需要同意：先待审批');
select is(pg_temp.notes(1, 'group'), 1, '组织者收到申请');
select pg_temp.login(1);
select is(jsonb_array_length(public.group_page(pg_temp.id('approval')) -> 'pending'), 1, '组织者看到申请');
select lives_ok($$ select public.respond_join_request(pg_temp.id('approval'), pg_temp.u(3), true) $$, '组织者同意');
select pg_temp.login(3);
select is(public.group_page(pg_temp.id('approval')) ->> 'my_role', 'member', '同意后成为成员');

-- 报名：4 个名额，第 5 个人候补；有人退出自动递补
select pg_temp.login(3);
select public.join_group(pg_temp.id('open'));
select pg_temp.login(4);
select public.join_group(pg_temp.id('open'));
select pg_temp.login(5);
select public.join_group(pg_temp.id('open'));
select pg_temp.login(6);
select throws_ok($$ select public.sign_up_session(pg_temp.tomorrow('open')) $$, '42501', null, '非成员不能报名');
select pg_temp.login(1); select public.sign_up_session(pg_temp.tomorrow('open'));
select pg_temp.login(2); select public.sign_up_session(pg_temp.tomorrow('open'));
select pg_temp.login(3); select public.sign_up_session(pg_temp.tomorrow('open'));
select pg_temp.login(4); select public.sign_up_session(pg_temp.tomorrow('open'));
select pg_temp.login(5);
select is(public.sign_up_session(pg_temp.tomorrow('open')), 'waitlisted', '满了进候补');
select is(public.group_page(pg_temp.id('open')) -> 'sessions' -> 0 ->> 'my_status', 'waitlisted:1', '候补第 1 位');
select pg_temp.login(2);
select lives_ok($$ select public.cancel_signup(pg_temp.tomorrow('open')) $$, '可以取消报名');
select pg_temp.login(5);
select is(public.group_page(pg_temp.id('open')) -> 'sessions' -> 0 ->> 'my_status', 'confirmed', '候补自动递补');
select is(pg_temp.notes(5, 'group'), 1, '递补的人收到通知');

-- 开场前 2 小时内退出 = 临时取消
reset role;
update public.group_sessions set starts_at = now() + interval '1 hour', ends_at = now() + interval '3 hours' where id = pg_temp.tomorrow('open');
select pg_temp.login(3);
select public.cancel_signup(pg_temp.tomorrow('open'));
reset role;
select is((select late_cancels from public.attendance_record(pg_temp.u(3)))::int, 1, '临时取消计入履约记录');

-- 群聊、交集
select pg_temp.login(2);
select lives_ok($$ select public.send_message('group', pg_temp.id('open'), 'See you Thursday') $$, '成员可以在群里聊天');
select isnt(public.player_card(pg_temp.u(4)), null, '同群的人可以互看资料');
select pg_temp.login(6);
select throws_ok($$ select public.send_message('group', pg_temp.id('open'), 'hi') $$, '42501', null, '非成员不能发');

-- 取消场次、退群
select pg_temp.login(2);
select throws_ok($$ select public.cancel_session(pg_temp.tomorrow('open')) $$, '42501', null, '只有组织者能取消场次');
select pg_temp.login(1);
select lives_ok($$ select public.cancel_session(pg_temp.tomorrow('open')) $$, '组织者可以取消场次');
select is(pg_temp.notes(4, 'group'), 1, '报了名的人收到取消通知');
select throws_ok($$ select public.leave_group(pg_temp.id('open')) $$, '22023', null, '群主不能退群');
select pg_temp.login(4);
select lives_ok($$ select public.leave_group(pg_temp.id('open')) $$, '成员可以退群');

-- 附近的球群
select pg_temp.login(7);
select ok((select jsonb_array_length(public.groups_near(lat, lon, 5)) >= 2 from public.venues where id = 'v-us-ca-21-badminton-club-21bc'),
          '能按位置找到球群');

select * from finish();
rollback;
