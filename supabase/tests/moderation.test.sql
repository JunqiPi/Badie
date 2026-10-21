-- 不当用语：名字不让存、自由文字换成 ***；整词匹配不误伤地名，后台同步不查；举报“不当内容”；管理员处理举报
begin;
create extension if not exists pgtap with schema extensions;
select plan(22);

-- 1 号普通用户，2 号骚扰别人，9 号管理员
create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000001' || lpad(n::text, 2, '0'))::uuid
$$;
insert into auth.users (id, email) select pg_temp.u(n), 'm' || n || '@test.local' from unnest(array[1, 2, 9]) n;
insert into public.profiles (id, nickname, rating, gender) select pg_temp.u(n), 'Mod' || n, 3, 'male' from unnest(array[1, 2, 9]) n;
insert into public.admin_users (user_id) values (pg_temp.u(9));
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
-- 以某个用户的身份直接写表（绕过 RLS，只为测触发器）
create function pg_temp.as_user(n int) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create function pg_temp.open_report() returns bigint language sql security definer as $$
  select min(id) from public.user_reports where resolved_at is null
$$;
create function pg_temp.rename(name text) returns void language sql as $$
  update public.profiles set nickname = name where id = pg_temp.u(1)
$$;

-- 昵称：有不当词不让存；整词匹配，Scunthorpe 这种不误伤；数字代替字母也算；中文按包含匹配，不误伤“奶茶”
select pg_temp.login(1);
select throws_ok($$ select pg_temp.rename('fuck off') $$, '22023', 'objectionable_content', '英文脏话不让当昵称');
select throws_ok($$ select pg_temp.rename('Sh1t') $$, '22023', 'objectionable_content', '数字代替字母也算');
select throws_ok($$ select pg_temp.rename('Blow-job') $$, '22023', 'objectionable_content', '词组中间加连字符也算');
select throws_ok($$ select pg_temp.rename('我是傻逼') $$, '22023', 'objectionable_content', '中文脏话不让当昵称');
select lives_ok($$ select pg_temp.rename('Scunthorpe') $$, '整词匹配：地名里含不当词的字母不算');
select lives_ok($$ select pg_temp.rename('奶茶爱好者') $$, '“奶茶”不误伤');
select lives_ok($$ select pg_temp.rename('Mixed-sex 4') $$, '“mixed-sex”这类正常说法不拦');

-- 球群名不让存，简介把不当词换成 ***
select throws_ok($$ select public.create_group('Bitch Club', 'v-us-ca-21-badminton-club-21bc', '', 1, 9, 'open',
                                              '[{"weekday": 3, "start": 1140, "end": 1260, "capacity": 8}]') $$,
                 '22023', 'objectionable_content', '球群名有不当词不让建');
select lives_ok($$ select public.create_group('Shuttle Club', 'v-us-ca-21-badminton-club-21bc', 'No bullshit, just games', 1, 9, 'open',
                                             '[{"weekday": 3, "start": 1140, "end": 1260, "capacity": 8}]') $$, '正常球群能建');
reset role;
select is((select summary from public.play_groups where name = 'Shuttle Club'), 'No ***, just games', '简介里的不当词换成 ***');

-- 消息：不拦，换成 ***（直接写表测触发器）
select pg_temp.as_user(2);
insert into public.messages (thread, sender_id, body)
  values ('dm:' || least(pg_temp.u(1), pg_temp.u(2)) || ':' || greatest(pg_temp.u(1), pg_temp.u(2)), pg_temp.u(2), 'you are a stupid b1tch, 傻逼');
select is((select body from public.messages where sender_id = pg_temp.u(2)), 'you are a stupid ***, ***', '消息里的不当词换成 ***');

-- 球馆名：玩家加的不让存，后台同步（没有登录用户）不查
select throws_ok($$ insert into public.venues (name, location, street, city, country_code, source)
                    values ('Shit Hall', 'POINT(0 0)', 's', 'c', 'US', 'player') $$,
                 '22023', 'objectionable_content', '玩家加的球馆名有不当词不让存');
select set_config('request.jwt.claims', '', true);
select lives_ok($$ insert into public.venues (name, location, street, city, country_code, source)
                   values ('Cockfosters Leisure Centre', 'POINT(0 0)', 's', 'c', 'GB', 'curated') $$, '后台同步的地名不查');

-- 举报“不当内容”
insert into public.user_reports (reporter_id, reported_id, reason, details) values (pg_temp.u(1), pg_temp.u(2), 'inappropriate', 'rude messages');
insert into public.user_reports (reporter_id, reported_id, reason) values (pg_temp.u(9), pg_temp.u(2), 'harassment');
select is((select count(*)::int from public.user_reports where reason = 'inappropriate' and reported_id = pg_temp.u(2)), 1, '可以举报不当内容');

-- 举报队列只有管理员能看，带上被举报人在举报人看得到的会话里发的消息
select pg_temp.login(1);
select throws_ok($$ select public.admin_report_queue() $$, '42501', 'admin_only', '普通用户看不了举报队列');
select pg_temp.login(9);
select is(jsonb_array_length(public.admin_report_queue()), 2, '管理员看得到两条举报');
select is(public.admin_report_queue() -> 0 -> 'messages' -> 0 ->> 'body', 'you are a stupid ***, ***', '附上发给举报人的消息');
select is((public.admin_report_queue() -> 0 ->> 'open_reports')::int, 2, '这个人有两条没处理的举报');

-- 改掉昵称：这个人的举报一起结案；封号：登录不了，记进审核日志
select public.admin_resolve_report(pg_temp.open_report(), 'reset_nickname');
reset role;
select is((select nickname from public.profiles where id = pg_temp.u(2)), 'Player 0000', '昵称改成 Player 加编号');
select is((select count(*)::int from public.user_reports where resolved_at is null), 0, '这个人的举报都结案了');
insert into public.user_reports (reporter_id, reported_id, reason) values (pg_temp.u(1), pg_temp.u(2), 'harassment');
select pg_temp.login(9);
select public.admin_resolve_report(pg_temp.open_report(), 'suspend', 'repeated harassment');
reset role;
select ok((select banned_until > now() + interval '50 years' from auth.users where id = pg_temp.u(2)), '封号后登录不了');
select is((select action from public.moderation_log where target_id = pg_temp.u(2)::text order by id desc limit 1), 'suspend', '记进审核日志');

select * from finish();
rollback;
