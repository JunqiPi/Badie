-- 访客报名：开关和链接、公开页不露隐私、报名和上限、候补在成员和访客之间递补、凭证取消、组织者移出、关掉、重置链接、旧版 App 的数据
begin;
create extension if not exists pgtap with schema extensions;
select plan(43);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000046' || lpad(n::text, 2, '0'))::uuid, 'gs' || n || '@test.local' from generate_series(1, 4) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000046' || lpad(n::text, 2, '0'))::uuid, 'Member' || n from generate_series(1, 4) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000046' || lpad(n::text, 2, '0'))::uuid
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
create function pg_temp.session() returns uuid language sql security definer as $$
  select id from public.group_sessions where group_id = pg_temp.id('group') order by starts_at limit 1
$$;
-- 像 guest-signup 函数那样报名（它用服务端密钥），记下凭证
create function pg_temp.guest(k text, ip text default '203.0.113.1', email text default null) returns text
language sql security definer as $$
  with r as (select public.guest_sign_up(pg_temp.code(), pg_temp.session(), k, email, 'zh-Hans', ip) as result),
       saved as (insert into tokens select k, result ->> 'token' from r)
  select result ->> 'status' from r
$$;
create function pg_temp.signup_id(k text) returns uuid language sql security definer as $$
  select id from public.session_signups where guest_name = k
$$;
create function pg_temp.status(k text) returns text language sql security definer as $$
  select case when waitlisted then 'waitlisted' else 'confirmed' end from public.session_signups where guest_name = k or user_id::text = k
$$;
create function pg_temp.emails() returns int language sql security definer as $$
  select count(*)::int from net.http_request_queue where url = 'http://functions.test/functions/v1/send-email'
$$;
-- 最近一封邮件
create function pg_temp.last_email() returns jsonb language sql security definer as $$
  select convert_from(body, 'utf8')::jsonb -> 0 from net.http_request_queue
  where url = 'http://functions.test/functions/v1/send-email' order by id desc limit 1
$$;
select vault.create_secret('http://functions.test', 'project_url');
select vault.create_secret('s3cret', 'push_secret');

-- 群主建群（明天一场，4 个名额），两个成员
select pg_temp.login(1);
insert into ids select 'group', public.create_group('Wed doubles', 'v-us-ca-21-badminton-club-21bc', '', 1, 9, 'open',
  jsonb_build_array(jsonb_build_object('weekday', extract(dow from (now() at time zone 'America/Los_Angeles') + interval '1 day'),
                                       'start', 1140, 'end', 1260, 'capacity', 4)));
select pg_temp.login(2); select public.join_group(pg_temp.id('group'));
select pg_temp.login(3); select public.join_group(pg_temp.id('group'));

-- 开关：只有组织者能开；默认关，没有链接
select pg_temp.login(2);
select throws_ok($$ select public.set_guest_signup(pg_temp.id('group'), true) $$, '42501', 'not_organizer', '成员不能打开访客报名');
select is(public.group_page(pg_temp.id('group')) -> 'guest_code', 'null'::jsonb, '成员看不到报名链接');
select pg_temp.login(1);
select is(public.group_page(pg_temp.id('group')) ->> 'guests_allowed', 'false', '默认关');
select lives_ok($$ select public.set_guest_signup(pg_temp.id('group'), true) $$, '群主打开访客报名');
select ok(char_length(public.group_page(pg_temp.id('group')) ->> 'guest_code') = 8, '打开后有一个 8 位的链接');
reset role;
select isnt(pg_temp.code(), (select invite_code::text from public.play_groups where id = pg_temp.id('group')), '链接和群号分开');

-- 公开页：不用登录；只有名字，没有 id、邮箱
select pg_temp.anon();
select is(public.guest_group_page('nope1234'), null, '链接不对打不开');
select is(public.guest_group_page(pg_temp.code()) ->> 'name', 'Wed doubles', '不用登录能打开报名页');
select is(public.guest_group_page(pg_temp.code()) ->> 'organizer', 'Member1', '显示组织者的名字');
select throws_ok($$ select public.guest_sign_up(pg_temp.code(), pg_temp.session(), 'Tina', null, 'en', '1.2.3.4') $$,
                 '42501', null, '网页不能绕过人机验证直接调报名');

-- 报名：两个成员先报，访客报上
select pg_temp.login(2); select public.sign_up_session(pg_temp.session());
reset role;
select is(pg_temp.guest('Tina', email := 'tina@example.com'), 'confirmed', '有名额就报上');
select is(pg_temp.emails(), 1, '留了邮箱：发一封带取消链接的确认邮件');
select ok(pg_temp.last_email() ->> 'text' like '%/g/' || pg_temp.code() || '/?cancel=' || pg_temp.token('Tina') || '%', '确认邮件里有取消链接');
select is(pg_temp.guest('Jenny'), 'confirmed', '第二个访客也报上');
select is((select count(*)::int from public.session_signups where guest_token_hash = pg_temp.token('Tina')), 0, '库里不存明文凭证');

select pg_temp.anon();
select is((select array_agg(k order by k) from jsonb_object_keys(public.guest_group_page(pg_temp.code()) -> 'sessions' -> 0 -> 'players' -> 0) k),
          array['guest', 'me', 'name', 'waitlisted'], '公开页的名单只有名字，没有 id、头像、邮箱');
select is(public.guest_group_page(pg_temp.code(), array[pg_temp.token('Jenny')]) -> 'sessions' -> 0 -> 'players' -> 2 ->> 'me', 'true',
          '凭这台设备的凭证认出自己');
select is((public.guest_group_page(pg_temp.code()) -> 'sessions' -> 0 ->> 'guest_spots')::int, 0, '4 个名额，访客最多一半');

-- 上限：访客满了不能再报；组织者可以改
reset role;
select throws_ok($$ select pg_temp.guest('Leo') $$, '54000', 'guest_spots_full', '访客名额满了');
select throws_ok($$ select public.guest_sign_up(pg_temp.code(), pg_temp.session(), 'x', null, 'en', '1.2.3.4') $$, '22023', 'invalid_guest_name', '名字 2–20 个字');
select throws_ok($$ select public.guest_sign_up(pg_temp.code(), pg_temp.session(), 'Call 6265551234', null, 'en', '1.2.3.4') $$, '22023', 'no_contact_info', '名字里不能留电话');
select throws_ok($$ select public.guest_sign_up(pg_temp.code(), pg_temp.session(), 'Leo', 'not-an-email', 'en', '1.2.3.4') $$, '22023', 'invalid_email', '邮箱格式要对');
select pg_temp.login(1);
select public.set_guest_signup(pg_temp.id('group'), true, 3);

-- 候补：成员 3 报满，访客 Leo 候补第 2 位之前先有成员 4 候补
select pg_temp.login(3); select public.sign_up_session(pg_temp.session());
select pg_temp.login(4); select public.join_group(pg_temp.id('group'));
select is(public.sign_up_session(pg_temp.session()), 'waitlisted', '满了，成员候补第 1 位');
reset role;
select is(public.guest_sign_up(pg_temp.code(), pg_temp.session(), 'Leo', 'leo@example.com', 'en', '203.0.113.9') ->> 'position', '2', '访客候补第 2 位');
update public.session_signups set guest_token_hash = public.guest_token_hash('leo-token') where guest_name = 'Leo';
insert into tokens values ('Leo', 'leo-token');

-- 访客取消：候补第一的成员递补
select pg_temp.anon();
select throws_ok($$ select public.guest_cancel('wrong') $$, 'P0002', 'signup_not_found', '凭证不对不能取消');
select lives_ok($$ select public.guest_cancel(pg_temp.token('Tina')) $$, '访客凭凭证取消');
reset role;
select is(pg_temp.status(pg_temp.u(4)::text), 'confirmed', '访客取消后，候补的成员递补');
-- 成员取消：候补的访客递补，发邮件
select pg_temp.login(2); select public.cancel_signup(pg_temp.session());
reset role;
select is(pg_temp.status('Leo'), 'confirmed', '成员取消后，候补的访客递补');
select is(pg_temp.last_email() ->> 'to', 'leo@example.com',
          '递补的访客收到邮件');

-- 组织者移出访客
select pg_temp.login(3);
select throws_ok($$ select public.remove_guest(pg_temp.signup_id('Jenny')) $$, '42501', 'not_organizer', '成员不能移出访客');
select pg_temp.login(1);
select lives_ok($$ select public.remove_guest(pg_temp.signup_id('Jenny')) $$, '组织者移出访客');
select is(pg_temp.signup_id('Jenny'), null, '移出后不在名单里');

-- 旧版 App：访客在 players 里，id、昵称、候补都在，人数照算
select pg_temp.login(3);
select is((select count(*)::int from jsonb_array_elements(public.group_page(pg_temp.id('group')) -> 'sessions' -> 0 -> 'players') p
           where p ->> 'guest' = 'true' and p ->> 'nickname' = 'Leo' and (p ->> 'id')::uuid is not null and p ? 'waitlisted'), 1,
          '旧版 App 解得开访客（id、nickname、waitlisted）');
select is((public.group_page(pg_temp.id('group')) -> 'sessions' -> 0 ->> 'confirmed')::int, 3, '报上的人数包括访客');

-- 每个 IP 每小时最多 10 次
reset role;
insert into public.guest_signup_ips (ip_hash) select public.guest_token_hash('198.51.100.7') from generate_series(1, 10);
select throws_ok($$ select pg_temp.guest('Amy', '198.51.100.7') $$, '54000', 'too_many_signups', '同一个 IP 一小时最多报 10 次');

-- 取消场次：留了邮箱的访客收到邮件
select pg_temp.login(1);
select lives_ok($$ select public.cancel_session(pg_temp.session()) $$, '组织者取消这一场');
reset role;
select is(pg_temp.last_email() ->> 'subject', 'Session cancelled: Wed doubles',
          '访客收到场次取消的邮件');

-- 重置链接：旧链接马上失效
select pg_temp.login(1);
insert into tokens values ('old link', pg_temp.code());
select lives_ok($$ select public.reset_guest_link(pg_temp.id('group')) $$, '组织者重置链接');
select pg_temp.anon();
select is(public.guest_group_page(pg_temp.token('old link')), null, '旧链接打不开');
select isnt(public.guest_group_page(pg_temp.code()), null, '新链接能打开');

-- 关掉：链接打不开、不能再报；已经报上的访客保留
select pg_temp.login(1);
select public.set_guest_signup(pg_temp.id('group'), false);
select pg_temp.anon();
select is(public.guest_group_page(pg_temp.code()), null, '关掉后链接打不开');
reset role;
select throws_ok($$ select pg_temp.guest('Kim') $$, 'P0002', 'guests_off', '关掉后不能报名');
select is(pg_temp.status('Leo'), 'confirmed', '已经报上的访客保留');

select * from finish();
rollback;
