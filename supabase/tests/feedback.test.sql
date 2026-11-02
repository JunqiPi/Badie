-- 反馈：登录用户提交，管理员收到通知、看列表、回复；回复作为通知发给用户
begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000032' || lpad(n::text, 2, '0'))::uuid, 'fb' || n || '@test.local' from generate_series(1, 2) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000032' || lpad(n::text, 2, '0'))::uuid, 'Feedback' || n from generate_series(1, 2) n;
insert into public.admin_users (user_id, role) values ('00000000-0000-0000-0000-000000003202', 'owner');

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000032' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create function pg_temp.notes(n int, k text) returns int language sql security definer as $$
  select count(*)::int from public.notifications where user_id = pg_temp.u(n) and kind = k
$$;

select pg_temp.login(1);
select throws_ok($$ select public.submit_feedback('idea', '  hi  ') $$, '22023', 'invalid_feedback', '太短不收');
select throws_ok($$ select * from public.feedback $$, '42501', null, '不能直接读反馈表');
select isnt(public.submit_feedback('bug', 'Map is blank on the courts page.', '{"app": "1.0 (20261102.0440)", "os": "iOS 26.1", "email": "x@y.z"}'),
            null, '可以提交');
select throws_ok($$ select public.admin_feedback() $$, '42501', 'admin_only', '普通用户看不到列表');
select is(pg_temp.notes(2, 'feedback'), 1, '管理员收到通知');

select pg_temp.login(2);
select is(jsonb_array_length(public.admin_feedback()), 1, '管理员看到待处理的反馈');
select is(public.admin_feedback() -> 0 -> 'context', '{"app": "1.0 (20261102.0440)", "os": "iOS 26.1"}'::jsonb, '只留版本、系统等字段');
select public.admin_reply_feedback((public.admin_feedback() -> 0 ->> 'id')::bigint, 'Thanks, fixed in the next update.');
select is(jsonb_array_length(public.admin_feedback()), 0, '回复后不在待处理里');
select is(jsonb_array_length(public.admin_feedback('done')), 1, '在已处理里');
select is(pg_temp.notes(1, 'feedback_reply'), 1, '用户收到回复通知');

select * from finish();
rollback;
