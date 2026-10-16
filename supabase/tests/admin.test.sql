-- 管理员与球馆审核测试
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local'),
  ('00000000-0000-0000-0000-0000000000b1', 'u1@test.local'),
  ('00000000-0000-0000-0000-0000000000b2', 'u2@test.local');
insert into public.admin_users (user_id, role) values ('00000000-0000-0000-0000-0000000000a1', 'owner');

create function pg_temp.login(uid text) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
$$;

-- 普通用户加两家球馆，其中一家被两人举报
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select public.add_venue('Sunset Badminton Club', 37.70, -122.45, '10 Sunset Blvd', 'San Francisco', 'CA', '', 'US');
select public.add_venue('Mission Badminton Hall', 37.75, -122.42, '20 Mission St', 'San Francisco', 'CA', '', 'US');
select public.report_venue((select id from public.venues where name = 'Sunset Badminton Club'), 'closed');
select pg_temp.login('00000000-0000-0000-0000-0000000000b2');
select public.report_venue((select id from public.venues where name = 'Sunset Badminton Club'), 'not_badminton');
select public.confirm_venue((select id from public.venues where name = 'Mission Badminton Hall'));

-- 普通用户不能用管理功能
select ok(not public.is_admin(), '普通用户不是管理员');
select throws_ok($$ select * from public.admin_venue_queue() $$, '42501', null, '普通用户读不到审核队列');
select throws_ok($$ select public.admin_resolve_venue((select id from public.venues limit 1), 'verify') $$,
                 '42501', null, '普通用户不能审核');
select is((select count(*)::int from public.admin_users), 0, '普通用户读不到管理员名单');
select is((select count(*)::int from public.moderation_log), 0, '普通用户读不到审核日志');

-- 管理员
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select ok(public.is_admin(), '管理员身份');
select is((select count(*)::int from public.admin_venue_queue()), 1, '队列里只有被举报的那家');
select is((select reporters from public.admin_venue_queue()), 2, '显示举报人数');
select is((select count(*)::int from public.venues where name = 'Sunset Badminton Club'), 1, '管理员能看到被隐藏的球馆');

select is((select (public.admin_resolve_venue((select id from public.venues where name = 'Sunset Badminton Club'), 'keep', '实地看过还在')).hidden_pending_review),
          false, '判定无误后恢复显示');
select is((select count(*)::int from public.admin_venue_queue()), 0, '处理后移出队列');
select is((select action from public.moderation_log order by id desc limit 1), 'keep', '操作写入审核日志');

-- 合并：确认人和收藏转到保留的球馆
select public.admin_merge_venue((select id from public.venues where name = 'Mission Badminton Hall'),
                                (select id from public.venues where name = 'Sunset Badminton Club'), '重复');
select ok((select 'Mission Badminton Hall' = any (aliases) from public.venues where name = 'Sunset Badminton Club'),
          '被合并的名称记为别名');
select is((select count(*)::int from public.venue_confirmations
           where venue_id = (select id from public.venues where name = 'Sunset Badminton Club')), 2,
          '确认人合并（同一人只算一次）');

select * from finish();
rollback;
