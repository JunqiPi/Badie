-- 访客报名上线前补的：同名、注册后不占两个位子、只显示首字母、改时间保留报名、递补邮件的取消链接、
-- 移出访客发邮件、临时取消的记录、24 小时内少人通知组织者、结束的场次、清邮箱
begin;
create extension if not exists pgtap with schema extensions;
select plan(29);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000047' || lpad(n::text, 2, '0'))::uuid, 'gf' || n || '@test.local' from generate_series(1, 4) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000047' || lpad(n::text, 2, '0'))::uuid, 'Member' || n from generate_series(1, 4) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000047' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create function pg_temp.anon() returns void language sql as $$
  select set_config('role', 'anon', true), set_config('request.jwt.claims', '{"role": "anon"}', true);
$$;
create temp table ids (name text primary key, id uuid);
create temp table tokens (name text primary key, token text);
grant all on ids, tokens to authenticated, anon;
create function pg_temp.id(k text) returns uuid language sql as $$ select id from ids where name = k $$;
create function pg_temp.token(k text) returns text language sql as $$ select token from tokens where name = k $$;
create function pg_temp.code() returns text language sql security definer as $$
  select guest_code from public.play_groups where id = pg_temp.id('group')
$$;
-- 像 guest-signup 函数那样报名，凭证记在 k 下面
create function pg_temp.guest(k text, name text default null, email text default null) returns text
language sql security definer as $$
  with r as (select public.guest_sign_up(pg_temp.code(), pg_temp.id('session'), coalesce(name, k), email, 'en', '203.0.113.1') as result),
       saved as (insert into tokens select k, result ->> 'token' from r)
  select result ->> 'status' from r
$$;
create function pg_temp.signup_id(k text) returns uuid language sql security definer as $$
  select id from public.session_signups where guest_name = k
$$;
create function pg_temp.page_names() returns text[] language sql as $$
  select array_agg(p ->> 'name') from jsonb_array_elements(public.guest_group_page(pg_temp.code()) -> 'sessions') s,
         jsonb_array_elements(s -> 'players') p where s ->> 'id' = pg_temp.id('session')::text
$$;
create function pg_temp.notices(n int, title text) returns int language sql security definer as $$
  select count(*)::int from public.notifications where user_id = pg_temp.u(n) and notifications.title = notices.title
$$;
create function pg_temp.emails(subject text) returns int language sql security definer as $$
  select count(*)::int from net.http_request_queue
  where url = 'http://functions.test/functions/v1/send-email' and convert_from(body, 'utf8')::jsonb -> 0 ->> 'subject' = emails.subject
$$;
create function pg_temp.last_email() returns jsonb language sql security definer as $$
  select convert_from(body, 'utf8')::jsonb -> 0 from net.http_request_queue
  where url = 'http://functions.test/functions/v1/send-email' order by id desc limit 1
$$;
select vault.create_secret('http://functions.test', 'project_url');
select vault.create_secret('s3cret', 'push_secret');

-- 群主建群（明天一场，4 个名额，每场访客最多 3 个），三个成员
select pg_temp.login(1);
insert into ids select 'group', public.create_group('Wed doubles', 'v-us-ca-21-badminton-club-21bc', '', 1, 9, 'open',
  jsonb_build_array(jsonb_build_object('weekday', extract(dow from (now() at time zone 'America/Los_Angeles') + interval '1 day'),
                                       'start', 1140, 'end', 1260, 'capacity', 4)));
select public.set_guest_signup(pg_temp.id('group'), true, 3);
select pg_temp.login(2); select public.join_group(pg_temp.id('group'));
select pg_temp.login(3); select public.join_group(pg_temp.id('group'));
select pg_temp.login(4); select public.join_group(pg_temp.id('group'));
reset role;
insert into ids select 'session', id from public.group_sessions where group_id = pg_temp.id('group') order by starts_at limit 1;

-- 同名的访客：后报的写成 “Tony 2”
select pg_temp.guest('Kim');
select pg_temp.guest('Tony');
select pg_temp.guest('Tony again', 'Tony');
select isnt(pg_temp.signup_id('Tony 2'), null, '同一场第二个 Tony 记成 “Tony 2”');

-- 注册后在球群页报名，带上这台设备的访客凭证：那一行改成自己的，不占两个位子
select pg_temp.login(4);
select is(public.sign_up_session(pg_temp.id('session'), pg_temp.token('Kim')), 'confirmed', '带着访客凭证报名，沿用那一行的名额');
reset role;
select is(pg_temp.signup_id('Kim'), null, '访客那一行没了');
select is((select count(*)::int from public.session_signups where session_id = pg_temp.id('session')), 3, '还是 3 行，没多占一个位子');
select is((select guest_token_hash from public.session_signups where session_id = pg_temp.id('session') and user_id = pg_temp.u(4)), null,
          '改成成员的那一行不留访客凭证');

-- 只显示首字母：自己能改；公开页上是 “M.”
select pg_temp.login(3);
select lives_ok($$ update public.profiles set public_initials = true where id = auth.uid() $$, '自己能打开“只显示首字母”');
select public.sign_up_session(pg_temp.id('session'));
select pg_temp.anon();
select ok('M.' = any(pg_temp.page_names()) and not 'Member3' = any(pg_temp.page_names()), '公开页上只显示首字母');
select ok('Member4' = any(pg_temp.page_names()), '没打开的照常显示昵称');

-- 改时间（19:00 → 19:30）同时多一个名额：同一场改时间，报名都在，候补的补上，大家收到“场次有变”
reset role;
select pg_temp.guest('Leo', email := 'leo@example.com');
select pg_temp.login(2); select public.sign_up_session(pg_temp.id('session'));
reset role;
create temp table moved as select starts_at from public.group_sessions where id = pg_temp.id('session');
select pg_temp.login(1);
select lives_ok($$ select public.update_group(pg_temp.id('group'), 'Wed doubles', '', 1, 9, 'open',
  jsonb_build_array(jsonb_build_object('weekday', extract(dow from (now() at time zone 'America/Los_Angeles') + interval '1 day'),
                                       'start', 1170, 'end', 1290, 'capacity', 5))) $$, '群主改时间和名额');
reset role;
select is((select starts_at - (select starts_at from moved) from public.group_sessions where id = pg_temp.id('session')), interval '30 minutes',
          '还是同一场，晚了 30 分钟');
select is((select count(*)::int from public.session_signups where session_id = pg_temp.id('session')), 6, '报名都还在');
select is((select waitlisted from public.session_signups where guest_name = 'Leo'), false, '多了一个名额，候补第一的补上');
select is(pg_temp.notices(4, 'Session changed: Wed doubles'), 1, '报了名的成员收到“场次有变”');
select is(pg_temp.notices(4, 'Session cancelled: Wed doubles'), 0, '不再是“取消”');
select is(pg_temp.emails('Session changed: Wed doubles'), 1, '留了邮箱的访客也收到');

-- 递补的邮件带取消链接：新凭证能用，报名那台设备上的凭证也照样能用
insert into tokens select 'Leo mail', substring(pg_temp.last_email() ->> 'text' from '\?cancel=([A-Za-z0-9_-]+)');
select is(pg_temp.last_email() ->> 'subject', 'You’re in: Wed doubles', '递补的邮件');
select pg_temp.anon();
select ok((select bool_and((p ->> 'me')::boolean) from unnest(array[pg_temp.token('Leo mail'), pg_temp.token('Leo')]) t,
           jsonb_array_elements(public.guest_group_page(pg_temp.code(), array[t]) -> 'sessions' -> 0 -> 'players') p where p ->> 'name' = 'Leo'),
          '邮件里的新凭证和设备上的凭证都认得出自己');
select lives_ok($$ select public.guest_set_email(pg_temp.token('Leo mail'), 'leo@example.com') $$, '凭邮件里的凭证能改邮箱');

-- 组织者移出访客：发一封“你不在名单上了”
select pg_temp.login(1);
select public.remove_guest(pg_temp.signup_id('Leo'));
reset role;
select is(pg_temp.last_email() ->> 'subject', 'You’re off the list: Wed doubles', '被移出的访客收到邮件');

-- 开场前 1 小时：访客退出记临时取消，没有候补时通知组织者
update public.group_sessions set starts_at = now() + interval '1 hour', ends_at = now() + interval '3 hours' where id = pg_temp.id('session');
select pg_temp.anon();
select public.guest_cancel(pg_temp.token('Tony'));
reset role;
select is((select count(*)::int from public.session_late_cancels where session_id = pg_temp.id('session') and guest_name = 'Tony'), 1,
          '访客临时退出也有记录');
select is(pg_temp.notices(1, 'Spot open: Wed doubles'), 1, '24 小时内少了人、没人候补：组织者收到通知');
select ok((select body from public.notifications where user_id = pg_temp.u(1) and title = 'Spot open: Wed doubles') like '%4/5 signed up.',
          '通知里写现在几个人');
select pg_temp.login(2); select public.cancel_signup(pg_temp.id('session'));
reset role;
select is(pg_temp.notices(1, 'Spot open: Wed doubles'), 2, '成员临时退出也通知');

-- 组织者看得到谁临时退了，成员看不到
select pg_temp.login(1);
select is((select array_agg(p ->> 'nickname' || ':' || (p ->> 'guest') order by p ->> 'nickname')
           from jsonb_array_elements(public.group_page(pg_temp.id('group')) -> 'sessions' -> 0 -> 'late_cancels') p),
          array['Member2:false', 'Tony:true'], '组织者看到临时退出的人（访客标出来）');
select pg_temp.login(3);
select is(public.group_page(pg_temp.id('group')) -> 'sessions' -> 0 -> 'late_cancels', 'null'::jsonb, '成员看不到');

-- 开场还早（30 小时后）：退出不通知组织者
reset role;
update public.group_sessions set starts_at = now() + interval '30 hours', ends_at = now() + interval '32 hours' where id = pg_temp.id('session');
select pg_temp.login(4); select public.cancel_signup(pg_temp.id('session'));
reset role;
select is(pg_temp.notices(1, 'Spot open: Wed doubles'), 2, '开场还早，不通知');

-- 结束的场次：报名页上多留 1 天
update public.group_sessions set starts_at = now() - interval '3 hours', ends_at = now() - interval '1 hour' where id = pg_temp.id('session');
select pg_temp.anon();
select ok(pg_temp.page_names() is not null, '刚结束的场次还在报名页上');
reset role;
update public.group_sessions set starts_at = now() - interval '27 hours', ends_at = now() - interval '25 hours' where id = pg_temp.id('session');
select pg_temp.anon();
select is(pg_temp.page_names(), null, '结束一天后不显示');

-- 结束一天后清掉访客的邮箱
reset role;
update public.session_signups set guest_email = 'tony2@example.com' where guest_name = 'Tony 2';
select public.forget_guest_emails();
select is((select guest_email from public.session_signups where guest_name = 'Tony 2'), null, '结束一天后访客邮箱清掉');

select * from finish();
rollback;
