-- 朋友试用后的改动：30 天、任何时间（16 小时）、修改约球请求、球群场次校验、编辑和解散球群
begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000033' || lpad(n::text, 2, '0'))::uuid, 'ff' || n || '@test.local' from generate_series(1, 3) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000033' || lpad(n::text, 2, '0'))::uuid, 'Friend' || n from generate_series(1, 3) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000033' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
-- d 天后的 h 点（整点）
create function pg_temp.at(d int, h int) returns timestamptz language sql as $$
  select date_trunc('day', now()) + make_interval(days => d, hours => h)
$$;
create function pg_temp.ticket(d int, h1 int, h2 int) returns uuid language sql as $$
  select public.submit_ticket('singles', pg_temp.at(d, h1), pg_temp.at(d, h2), '{v-us-ca-21-badminton-club-21bc}', 1, false)
$$;
-- 明天（球馆当地）星期几 a 点到 b 点
create function pg_temp.schedule(a int, b int) returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object('weekday', extract(dow from (now() at time zone 'America/Los_Angeles') + interval '1 day'),
                                              'start', a * 60, 'end', b * 60, 'capacity', 4, 'fee', ''))
$$;
create function pg_temp.status(t uuid) returns text language sql security definer as $$
  select status::text from public.match_tickets where id = t
$$;
create temp table ids (k text primary key, id uuid);
grant all on ids to authenticated;
create function pg_temp.id(key text) returns uuid language sql as $$ select id from ids where k = key $$;
create function pg_temp.future_sessions(g uuid) returns int language sql security definer as $$
  select count(*)::int from public.group_sessions where group_id = g and starts_at > now() and cancelled_at is null
$$;

-- 约球：20 天后可以，31 天后不行；任何时间（7 点到 23 点）可以
select pg_temp.login(1);
select isnt(pg_temp.ticket(20, 18, 20), null, '可以约 20 天后');
select throws_ok($$ select pg_temp.ticket(31, 18, 20) $$, '22023', 'too_far', '最多 30 天');
insert into ids select 't', pg_temp.ticket(5, 7, 23);
select isnt(pg_temp.id('t'), null, '任何时间：一天 16 小时');

-- 修改请求：新的不合格时旧的不变；合格就换成新的
select throws_ok($$ select public.replace_ticket(pg_temp.id('t'), 'singles', pg_temp.at(40, 18), pg_temp.at(40, 20),
                                                 '{v-us-ca-21-badminton-club-21bc}', 1, false) $$, '22023', 'too_far', '新时间不合格');
select is(pg_temp.status(pg_temp.id('t')), 'searching', '旧请求还在');
insert into ids select 't2', public.replace_ticket(pg_temp.id('t'), 'singles', pg_temp.at(6, 18), pg_temp.at(6, 20),
                                                     '{v-us-ca-21-badminton-club-21bc}', 1, false);
select is(pg_temp.status(pg_temp.id('t')), 'cancelled', '改完旧请求取消');
select is(pg_temp.status(pg_temp.id('t2')), 'searching', '新请求在找人');

-- 球群：跨过午夜（结束早于开始）的场次给出能看懂的错误
select throws_ok($$ select public.create_group('Late night', 'v-us-ca-21-badminton-club-21bc', '', 2, 5, 'open', pg_temp.schedule(22, 1)) $$,
                 '22023', 'invalid_schedule', '结束早于开始');
select lives_ok($$ select public.create_group('All day', 'v-us-ca-21-badminton-club-21bc', '', 2, 5, 'open', pg_temp.schedule(9, 21)) $$,
                '一场可以 12 小时');
insert into ids select 'g', public.create_group('Weeknights', 'v-us-ca-21-badminton-club-21bc', '', 2, 5, 'open', pg_temp.schedule(19, 21));
select is(pg_temp.future_sessions(pg_temp.id('g')), 2, '生成未来两周的场次');

-- 成员不能编辑、不能解散
select pg_temp.login(2);
select public.join_group(pg_temp.id('g'));
select throws_ok($$ select public.update_group(pg_temp.id('g'), 'Weeknights', '', 2, 5, 'open', pg_temp.schedule(19, 21)) $$,
                 '42501', 'not_organizer', '成员不能编辑');
select throws_ok($$ select public.disband_group(pg_temp.id('g')) $$, '42501', 'not_organizer', '成员不能解散');

-- 群主改时间：旧场次取消，按新时间生成；名字一起改
select pg_temp.login(1);
select lives_ok($$ select public.update_group(pg_temp.id('g'), 'Weeknight doubles', 'Bring shoes', 2, 6, 'open',
                                             pg_temp.schedule(20, 22) || pg_temp.schedule(18, 20)) $$, '群主可以编辑');
reset role;
select is((select name from public.play_groups where id = pg_temp.id('g')), 'Weeknight doubles', '名字改了');
select is(pg_temp.future_sessions(pg_temp.id('g')), 4, '旧场次取消，两个新时间各两场');

-- 解散：成员收到通知，球群没了
select pg_temp.login(1);
select public.disband_group(pg_temp.id('g'));
reset role;
select is((select count(*)::int from public.play_groups where id = pg_temp.id('g')), 0, '球群已删除');
select is((select count(*)::int from public.notifications where user_id = pg_temp.u(2) and kind = 'group' and title like '%Weeknight doubles%'), 1,
          '成员收到解散通知');

select * from finish();
rollback;
