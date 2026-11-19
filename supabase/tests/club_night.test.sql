-- 当晚：排场（谁能用、开始、公平、晚到、重复按、撤销、减场地、换人、帮手、推送、看板）和收款
begin;
create extension if not exists pgtap with schema extensions;
select plan(71);

-- 14 个注册用户：1 是群主，2–13 是成员，14 不是成员
insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000047' || lpad(n::text, 2, '0'))::uuid, 'cn' || n || '@test.local' from generate_series(1, 14) n;
insert into public.profiles (id, nickname, rating)
  select ('00000000-0000-0000-0000-0000000047' || lpad(n::text, 2, '0'))::uuid, 'P' || n, 2 + n % 5 from generate_series(1, 14) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000047' || lpad(n::text, 2, '0'))::uuid
$$;
-- 只换身份（auth.uid()），不换数据库角色：测试里要直接查内部的表。函数对 authenticated / anon 开没开放由下面单独查
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'postgres', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create function pg_temp.anon() returns void language sql as $$
  select set_config('role', 'anon', true), set_config('request.jwt.claims', '{"role": "anon"}', true);
$$;
create temp table ids (name text primary key, id uuid);
grant all on ids to authenticated, anon;
create function pg_temp.id(k text) returns uuid language sql as $$ select id from ids where name = k $$;
create function pg_temp.signup(n int) returns uuid language sql security definer as $$
  select id from public.session_signups where session_id = pg_temp.id('night') and user_id = pg_temp.u(n)
$$;
-- 场上的那一场
create function pg_temp.game_on(c int) returns bigint language sql security definer as $$
  select id from public.night_games where session_id = pg_temp.id('night') and court = c and ended_at is null
$$;
-- 在场的人今晚场数最多和最少差几
create function pg_temp.spread(p_people uuid[] default null) returns int language sql security definer as $$
  select max(games) - min(games) from public.night_people(pg_temp.id('night'))
  where attendance = 'here' and (p_people is null or id = any(p_people))
$$;
-- 按场地顺序轮流打完 n 场
create function pg_temp.play(n int) returns void language plpgsql security definer as $$
begin
  for i in 0..n - 1 loop
    perform public.night_finish(pg_temp.game_on(i % (select courts from public.club_nights where session_id = pg_temp.id('night')) + 1));
  end loop;
end
$$;
create function pg_temp.board() returns text language sql security definer as $$
  select board_code from public.club_nights where session_id = pg_temp.id('night')
$$;
grant execute on all functions in schema pg_temp to authenticated, anon;

select vault.create_secret('http://functions.test', 'project_url');
select vault.create_secret('s3cret', 'push_secret');

-- 群主建群，2–13 加入；今晚这一场（已经开场半小时），一周前同一时间有一场填过每人 $12
select pg_temp.login(1);
insert into ids select 'group', public.create_group('Wed night', 'v-us-ca-21-badminton-club-21bc', '', 1, 9, 'open',
  jsonb_build_array(jsonb_build_object('weekday', 3, 'start', 1140, 'end', 1320, 'capacity', 20)));
select pg_temp.login(n), public.join_group(pg_temp.id('group')) from generate_series(2, 13) n;
reset role;
with x as (
  insert into public.group_sessions (group_id, schedule_id, starts_at, ends_at, capacity)
  select pg_temp.id('group'), s.id, now() - interval '30 minutes', now() + interval '150 minutes', 20
  from public.group_schedules s where s.group_id = pg_temp.id('group') returning id)
insert into ids select 'night', id from x;
insert into public.group_sessions (group_id, schedule_id, starts_at, ends_at, capacity, fee)
  select pg_temp.id('group'), s.id, now() - interval '7 days 30 minutes', now() - interval '7 days' + interval '150 minutes', 20, 12
  from public.group_schedules s where s.group_id = pg_temp.id('group');
-- 1–12 报上名
insert into public.session_signups (session_id, user_id, signed_up_at)
  select pg_temp.id('night'), pg_temp.u(n), now() - interval '1 day' + n * interval '1 minute' from generate_series(1, 12) n;
-- 2 号的手机能收推送
insert into public.push_devices (user_id, kind, token) values (pg_temp.u(2), 'apns', repeat('ab', 32));
update public.profiles set locale = 'zh-Hans' where id = pg_temp.u(2);

-- 谁能用
select pg_temp.login(5);
select is(public.night_state(pg_temp.id('night')), null, '成员打不开当晚页');
select throws_ok($$ select public.night_start(pg_temp.id('night')) $$, '42501', 'not_allowed', '成员不能开始排场');
select pg_temp.login(1);
select is(public.night_state(pg_temp.id('night')) ->> 'started', 'false', '组织者能打开，还没开始');
select is((select count(*)::int from jsonb_array_elements(public.night_state(pg_temp.id('night')) -> 'people')), 12, '名单就是报名的人');

-- 12 人、3 片场地双打，全到了
select lives_ok($$ select public.night_settings(pg_temp.id('night'), 3, true, false) $$, '设置 3 片场地');
select lives_ok($$ select public.night_mark(pg_temp.id('night'), null, 'here') $$, '全到了');
select is((select count(*)::int from public.night_games where session_id = pg_temp.id('night')), 0, '开始前不排人');
select lives_ok($$ select public.night_start(pg_temp.id('night')) $$, '开始排场');
select is((select count(*)::int from public.night_games where session_id = pg_temp.id('night') and ended_at is null), 3, '3 片场地都排上了人');
select is((select count(*)::int from public.live_pushes where user_id = pg_temp.u(2)), 1, '上场的注册球员收到一条推送');
select ok((select title from public.live_pushes where user_id = pg_temp.u(2)) ~ '^轮到你了：场地 [123]$', '推送按收件人的语言写场地号');
select ok((select body from public.live_pushes where user_id = pg_temp.u(2)) ~ '^和 P\d+ 一组，对 P\d+、P\d+。$', '推送写搭档和对手');
select is((select collapse from public.live_pushes where user_id = pg_temp.u(2)), 'night:' || pg_temp.id('night'), '同一晚的推送互相替换');

-- 公平：轮流打完 30 场，每人场数最多差 1
select pg_temp.play(30);
select cmp_ok(pg_temp.spread(), '<=', 1, '打完 30 场，每人今晚场数最多差 1');

-- 13、14 号 9 点才到（14 号是现场加的访客）：从在场最少的场数算起，不会一来就连打
reset role;
insert into public.session_signups (session_id, user_id) values (pg_temp.id('night'), pg_temp.u(13));
select pg_temp.login(1);
select lives_ok($$ select public.night_mark(pg_temp.id('night'), array[pg_temp.signup(13)], 'here') $$, '13 号到了');
insert into ids select 'walkin', public.night_add(pg_temp.id('night'), 'Tony');
select is(public.night_add(pg_temp.id('night'), 'Tony'), pg_temp.id('walkin'), '连点两次只加一个人');
select is((select eff from public.night_people(pg_temp.id('night')) where id = pg_temp.id('walkin')),
          (select min(eff) from public.night_people(pg_temp.id('night')) where attendance = 'here' and id <> pg_temp.id('walkin')),
          '晚到的人从在场最少的场数算起');
create temp table mark as select max(id) as id from public.night_games;
grant select on mark to authenticated;
select pg_temp.play(14);
-- 14 个人时有得挑：这 14 场里同一对搭档最多 2 次
select cmp_ok((select max(c)::int from (select count(*) as c from public.night_games g, lateral (values (g.players[1:2]), (g.players[3:4])) t(pair)
                                   where g.session_id = pg_temp.id('night') and g.id > (select id from mark)
                                   group by (select array_agg(x order by x) from unnest(t.pair) x)) z), '<=', 2,
              '14 个人时，同一对搭档最多 2 次');
select cmp_ok((select max(eff) - min(eff) from public.night_people(pg_temp.id('night')) where attendance = 'here'), '<=', 1,
              '晚到以后再打 14 场，大家（按算上补的场数）还是最多差 1');

-- 同一片场地按两次：第二次报错，不会多空出一片
select public.night_finish(pg_temp.game_on(1)) from (select 1) x;
select throws_ok(format('select public.night_finish(%s)', (select max(id) from public.night_games where session_id = pg_temp.id('night') and ended_at is not null and court = 1)),
                 'P0002', 'court_changed', '已经打完的再按一次报 court_changed');
select is((select count(*)::int from public.night_games where session_id = pg_temp.id('night') and ended_at is null), 3, '还是 3 片场地在打');

-- 撤销：刚才那场接着打，刚排上的撤掉
select lives_ok($$ select public.night_undo(pg_temp.id('night')) $$, '10 秒内能撤销');
select is((select ended_at from public.night_games where id = (select max(id) from public.night_games where session_id = pg_temp.id('night') and court = 1)),
          null, '撤销后那一场接着打');
select is((select count(*)::int from public.night_games where session_id = pg_temp.id('night') and ended_at is null), 3, '撤销后还是 3 片场地');
select throws_ok($$ select public.night_undo(pg_temp.id('night')) $$, 'P0002', 'nothing_to_undo', '只能撤最后一步');

-- 减到 2 片：场地 3 正在打的打完再收
select lives_ok($$ select public.night_settings(pg_temp.id('night'), 2, true, false) $$, '场地减到 2 片');
select is((select count(*)::int from public.night_games where session_id = pg_temp.id('night') and ended_at is null), 3, '场地 3 正在打的接着打');
select public.night_finish(pg_temp.game_on(3));
select is(pg_temp.game_on(3), null, '场地 3 打完不再排人');

-- 换人：场上的人换成等着的人；手动放到下一场
select lives_ok(format('select public.night_swap(%s, %L, %L)', pg_temp.game_on(1),
                       (select players[1] from public.night_games where id = pg_temp.game_on(1)),
                       (select id from public.night_people(pg_temp.id('night')) where attendance = 'here' and on_court is null limit 1)),
                '换人');
select lives_ok($$ select public.night_bump(pg_temp.signup(3), true) $$, '手动放到下一场');
select ok(pg_temp.signup(3) = any(array(select jsonb_array_elements_text(public.night_state(pg_temp.id('night')) -> 'next' -> 0)::uuid))
          or exists (select 1 from public.night_games where session_id = pg_temp.id('night') and ended_at is null and pg_temp.signup(3) = any(players)),
          '放到下一场的人排在接下来的第一组');

-- 休息和走了的人不再排
select public.night_mark(pg_temp.id('night'), array[pg_temp.signup(4)], 'left');
update mark set id = (select max(id) from public.night_games);
select pg_temp.play(6);
select ok(not exists (select 1 from public.night_games where session_id = pg_temp.id('night') and id > (select id from mark)
                      and pg_temp.signup(4) = any(players)), '走了的人不再上场');

-- 帮手：只能是到场的注册用户，最多 3 个；能排场，不能收款
select throws_ok(format('select public.night_helpers(%L, array[%L]::uuid[])', pg_temp.id('night'), pg_temp.u(14)), '22023', 'not_attending',
                 '没来的人不能当帮手');
select lives_ok(format('select public.night_helpers(%L, array[%L]::uuid[])', pg_temp.id('night'), pg_temp.u(5)), '5 号当帮手');
select is((select count(*)::int from public.notifications where user_id = pg_temp.u(5) and title = 'P1 asked you to help tonight'), 1, '帮手收到通知');
select pg_temp.login(5);
select is(public.night_state(pg_temp.id('night')) ->> 'role', 'helper', '帮手能打开当晚页');
select lives_ok(format('select public.night_finish(%s)', pg_temp.game_on(2)), '帮手能按打完了');
select throws_ok($$ select public.night_pay(pg_temp.id('night')) $$, '42501', 'not_organizer', '帮手不能收款');
select throws_ok(format('select public.night_helpers(%L, %L::uuid[])', pg_temp.id('night'), '{}'), '42501', 'not_organizer', '帮手不能再加帮手');

-- 看板：不登录能看，只有名字
select pg_temp.anon();
select is(public.live_board(pg_temp.board()) ->> 'kind', 'night', '不登录能看看板');
select is((select count(*)::int from jsonb_array_elements(public.live_board(pg_temp.board()) -> 'people') p
           where p ?| array['user_id', 'avatar', 'rating', 'email', 'paid']), 0, '看板上没有用户 id、头像、等级、邮箱和付款');
select is(public.live_board('nope1234'), null, '码不对打不开');
reset role;
select ok(has_function_privilege('anon', 'public.live_board(text, text[])', 'execute')
          and not has_function_privilege('anon', 'public.night_state(uuid)', 'execute')
          and not has_function_privilege('authenticated', 'public.night_pick(uuid, uuid[])', 'execute')
          and has_function_privilege('authenticated', 'public.night_finish(bigint, text)', 'execute'), '看板对外开放，排人的内部函数不开放');

-- 收款：每人多少钱默认上周的数；到场的人要付，没来的和收钱的人自己不用付
select pg_temp.login(1);
select is((public.night_pay(pg_temp.id('night')) ->> 'amount')::numeric, 12::numeric, '每人多少钱默认上周的数');
select lives_ok($$ select public.set_session_fee(pg_temp.id('night'), 15) $$, '改成每人 $15');
select is((select count(*)::int from jsonb_array_elements(public.night_pay(pg_temp.id('night')) -> 'people') p where (p ->> 'owes')::boolean),
          13, '标了到场的 13 人要付（群主自己不用）');
select lives_ok($$ select public.set_payment_handles('@kevin-w', '$kevinw', 'paypal.me/kevinw', 'kevin@test.local') $$, '填收款方式');
select is(public.my_payment_handles() ->> 'venmo', 'kevin-w', 'Venmo 去掉 @');
select throws_ok($$ select public.set_payment_handles('ab', null, null, null) $$, '22023', 'invalid_venmo', 'Venmo 用户名不对报错');

-- 付钱的人：球群页上看到付给谁、多少钱、收款方式（含 Zelle）；“我付了”算已付，标成自己标的
select pg_temp.login(2);
select is((select (s -> 'pay' ->> 'amount')::numeric from jsonb_array_elements(public.group_tonight(pg_temp.id('group'))) s
           where (s ->> 'id')::uuid = pg_temp.id('night')), 15::numeric, '球群页上写着每人 $15');
select is((select s -> 'pay' -> 'handles' ->> 'zelle' from jsonb_array_elements(public.group_tonight(pg_temp.id('group'))) s
           where (s ->> 'id')::uuid = pg_temp.id('night')), 'kevin@test.local', '注册用户能看到 Zelle');
select lives_ok($$ select public.i_paid(pg_temp.id('night')) $$, '点我付了');
select pg_temp.login(1);
select is((select p ->> 'paid_self' from jsonb_array_elements(public.night_pay(pg_temp.id('night')) -> 'people') p
           where (p ->> 'id')::uuid = pg_temp.signup(2)), 'true', '组织者那边写着自己标的');
-- 访客留了邮箱：提醒没付的，注册用户收通知，访客收邮件（带付款链接）
reset role;
update public.session_signups set guest_email = 'tony@test.local', guest_locale = 'zh-Hans' where id = pg_temp.id('walkin');
select pg_temp.login(1);
select is(public.remind_unpaid(pg_temp.id('night')), 12, '提醒了 11 个注册用户和 1 个访客');
select is((select count(*)::int from public.notifications where user_id = pg_temp.u(3) and title = 'Court fee: Wed night'), 1, '没付的注册用户收到通知');
select is((select count(*)::int from public.notifications where user_id = pg_temp.u(2) and title = 'Court fee: Wed night'), 0, '付了的不提醒');
select throws_ok($$ select public.remind_unpaid(pg_temp.id('night')) $$, '54000', 'reminded_recently', '12 小时内只能提醒一次');

-- 访客用提醒邮件里的链接付款：看不到 Zelle，“我付了”算已付
create temp table pay as select substring(convert_from(body, 'utf8') from 'badie.rsvp/pay/([A-Za-z0-9_-]+)/') as token
  from net.http_request_queue where url = 'http://functions.test/functions/v1/send-email' order by id desc limit 1;
grant select on pay to anon;
select ok((select token from pay) is not null, '提醒邮件里有付款链接');
select pg_temp.anon();
select is((select (e ->> 'amount')::numeric from jsonb_array_elements(public.guest_payment(array[(select token from pay)])) e), 15::numeric,
          '访客打开链接看到每人 $15');
select is((select e -> 'handles' ? 'zelle' from jsonb_array_elements(public.guest_payment(array[(select token from pay)])) e), false,
          '访客看不到 Zelle');
select lives_ok($$ select public.guest_i_paid((select token from pay)) $$, '访客点我付了');
reset role;
select is((select paid_self from public.session_signups where id = pg_temp.id('walkin')), true, '访客标的也写自己标的');
select pg_temp.login(1);
select lives_ok($$ select public.mark_signup_paid(pg_temp.id('walkin'), false) $$, '组织者能改回没付');

-- 球员的“今晚”卡和球群页的按钮
select pg_temp.login(1);
select is((select (s ->> 'can_run')::boolean from jsonb_array_elements(public.group_tonight(pg_temp.id('group'))) s
           where (s ->> 'id')::uuid = pg_temp.id('night')), true, '组织者在球群页看到排场');
select pg_temp.login(6);
select is((select (s ->> 'can_run')::boolean from jsonb_array_elements(public.group_tonight(pg_temp.id('group'))) s
           where (s ->> 'id')::uuid = pg_temp.id('night')), false, '成员看不到排场');
select ok((select s ->> 'board' from jsonb_array_elements(public.group_tonight(pg_temp.id('group'))) s
           where (s ->> 'id')::uuid = pg_temp.id('night')) is not null, '成员能看排场的看板');
select ok((select e ->> 'status' from jsonb_array_elements(public.my_tonight()) e where e ->> 'kind' = 'night') in ('court', 'next', 'waiting'),
          '今晚卡写着我在场上、下一场或者等候中');

-- 用今晚的名单开一场比赛：排场先停，场上的打完以后场地给比赛
select pg_temp.login(1);
insert into ids select 'match', public.create_match('Tonight', null, 2, 'singles', 21, 1, true,
  (select jsonb_agg(jsonb_build_object('signup_id', pg_temp.signup(n))) from generate_series(5, 8) n), null, null, null, false, pg_temp.id('night'));
select is((select count(*)::int from public.match_games where match_id = pg_temp.id('match') and status = 'playing'), 0, '排场的场地还在打，比赛先等');
select public.night_finish(pg_temp.game_on(1));
select is(pg_temp.game_on(1), null, '比赛时排场不再排人');
select is((select count(*)::int from public.match_games where match_id = pg_temp.id('match') and status = 'playing' and court = 1), 1,
          '空出来的场地上了比赛');
select is(public.night_state(pg_temp.id('night')) ->> 'match_live', 'true', '当晚页知道在打比赛');

select * from finish();
rollback;
