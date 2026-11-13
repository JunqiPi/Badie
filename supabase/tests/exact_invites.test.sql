-- 约 TA 定具体时间（p_duration）和约双打（p_mode）：定好的时间、旧版 App 照旧、双打答应后变成公开的双打局
begin;
create extension if not exists pgtap with schema extensions;
select plan(25);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000043' || lpad(n::text, 2, '0'))::uuid, 'ei' || n || '@test.local' from generate_series(1, 7) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000043' || lpad(n::text, 2, '0'))::uuid, 'Ex' || n from generate_series(1, 7) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000043' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
-- 球馆当地 n 天后的某个钟点
create function pg_temp.at(days int, hhmm text) returns timestamptz language sql as $$
  select (((now() at time zone 'America/Los_Angeles')::date + days) + hhmm::time) at time zone 'America/Los_Angeles'
$$;
create function pg_temp.last_title(n int) returns text language sql security definer as $$
  select title from public.notifications where user_id = pg_temp.u(n) order by id desc limit 1
$$;
create temp table r (k text primary key, v jsonb);
grant all on r to authenticated, anon;
create function pg_temp.room(k text) returns uuid language sql as $$ select (v ->> 'room_id')::uuid from r where r.k = room.k $$;
create function pg_temp.summary(k text) returns jsonb language sql security definer as $$ select public.room_summary(pg_temp.room(k)) $$;

-- 都开了显示、定过级、常去 21BC；1 是 Lv.4，5 是 Lv.5
update public.profiles set show_as_regular = true, assessed_at = now(), rating = case when id = pg_temp.u(5) then 5 else 4 end
  where id in (select pg_temp.u(n) from generate_series(1, 7) n);
insert into public.favorite_venues (user_id, venue_id) select pg_temp.u(n), 'v-us-ca-21-badminton-club-21bc' from generate_series(1, 7) n;

-- 定具体时间 -----------------------------------------------------------------------------------
select pg_temp.login(1);
insert into r select 'exact', public.invite_player(pg_temp.u(2), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(1, '19:00'), pg_temp.at(1, '21:30'),
                                                   null, 150);
select is((select (x ->> 'time_set') || ' ' || (x ->> 'duration_minutes') || ' ' || (x ->> 'mode') from pg_temp.summary('exact') x),
          'true 150 singles', '窗口正好 2.5 小时、打 2.5 小时：定好的时间');
select is((select (x ->> 'starts_at')::timestamptz || ' ' || (x ->> 'ends_at')::timestamptz from pg_temp.summary('exact') x),
          pg_temp.at(1, '19:00') || ' ' || pg_temp.at(1, '21:30'), '开始、结束就是选的时间');
insert into r select 'loose', public.invite_player(pg_temp.u(3), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(2, '19:00'), pg_temp.at(2, '22:00'),
                                                   null, 120);
select is((select (x ->> 'time_set') || ' ' || (x ->> 'duration_minutes') from pg_temp.summary('loose') x), 'false 120',
          '窗口比打的时间长：还是大概的时间');
select throws_ok($$ select public.invite_player(pg_temp.u(4), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(1, '10:00'), pg_temp.at(1, '12:00'), null, 45) $$,
                 'invalid_window', '打 45 分钟不行');
select throws_ok($$ select public.invite_player(pg_temp.u(4), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(1, '08:00'), pg_temp.at(1, '13:00'), null, 300) $$,
                 'invalid_window', '超过 4 小时不行');
select throws_ok($$ select public.invite_player(pg_temp.u(4), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(1, '10:00'), pg_temp.at(1, '11:00'), null, 120) $$,
                 'invalid_window', '打的时间比窗口长不行');
select throws_ok($$ select public.invite_player(pg_temp.u(4), 'v-us-ca-21-badminton-club-21bc', now() - interval '1 hour',
                                                to_timestamp(ceil(extract(epoch from now()) / 1800) * 1800) + interval '30 minutes', null, 90) $$,
                 'invalid_window', '定好的时间已经来不及');
-- 旧版 App：不传打多久，2 小时的窗口照旧是定好的时间
insert into r select 'old', public.invite_player(pg_temp.u(4), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(3, '10:00'), pg_temp.at(3, '12:00'));
select is((select (x ->> 'time_set') || ' ' || (x ->> 'duration_minutes') || ' ' || (x ->> 'mode') from pg_temp.summary('old') x),
          'true 120 singles', '旧版 App 照旧');

-- 单打说好：球局按选的时间 ---------------------------------------------------------------------------
select pg_temp.login(2);
insert into r select 'exact_yes', public.respond_invite(pg_temp.room('exact'), true);
reset role;
select is((select (g.ends_at - g.starts_at) || ' ' || g.time_set || ' ' || g.duration_minutes
           from public.games g where g.id = (select (v ->> 'game_id')::uuid from r where k = 'exact_yes')),
          '02:30:00 true 150', '成局：定好的 2.5 小时');

-- 双打 ---------------------------------------------------------------------------------------------
select pg_temp.login(1);
select throws_ok($$ select public.invite_player(pg_temp.u(5), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(1, '14:00'), pg_temp.at(1, '18:00'),
                                                'afternoon', 120, 'doubles') $$,
                 'invalid_window', '双打要定好时间');
insert into r select 'dbl', public.invite_player(pg_temp.u(5), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(4, '19:00'), pg_temp.at(4, '21:00'),
                                                 null, 120, 'doubles');
select is((select (x ->> 'mode') || ' ' || (x ->> 'visibility') || ' ' || (x ->> 'time_set') from pg_temp.summary('dbl') x),
          'doubles private true', '双打邀请：等回复时是私密的');
select is(pg_temp.last_title(5), 'Ex1 invited you to play doubles', '对方收到双打邀请');

-- 换个时间：不传项目就还是双打；双打不能换成大概的时间
select pg_temp.login(5);
select throws_ok($$ select public.counter_invite(pg_temp.room('dbl'), null, pg_temp.at(5, '14:00'), pg_temp.at(5, '18:00'), 'afternoon') $$,
                 'invalid_window', '双打换个时间也要定好');
select lives_ok($$ select public.counter_invite(pg_temp.room('dbl'), null, pg_temp.at(5, '10:00'), pg_temp.at(5, '11:30'), null, 90) $$,
                '换成 1.5 小时');
select is((select (x ->> 'mode') || ' ' || (x ->> 'duration_minutes') || ' ' || (x ->> 'time_set') from pg_temp.summary('dbl') x),
          'doubles 90 true', '还是双打，打 1.5 小时');

-- 说好：变成公开的双打局，两个人在里面，还差 2 人
select pg_temp.login(1);
insert into r select 'dbl_yes', public.respond_invite(pg_temp.room('dbl'), true);
select is((select v - 'room_id' from r where k = 'dbl_yes'), '{"status": "accepted", "game_id": null}', '答应双打：没有直接成局');
select is((select (x ->> 'status') || ' ' || (x ->> 'visibility') || ' ' || (x ->> 'going') || '/' || (x ->> 'capacity')
           from pg_temp.summary('dbl') x), 'open public 2/4', '公开的双打局，2/4');
select is((select x -> 'invite' from pg_temp.summary('dbl') x), 'null'::jsonb, '不再是一对一的邀请');
select is((select (x ->> 'level_min') || '-' || (x ->> 'level_max') from pg_temp.summary('dbl') x), '3-6', '水平范围：两个人上下各一级');
select is(pg_temp.last_title(5), 'Ex1 said yes to doubles', '告诉对方');
select ok(not exists (select 1 from jsonb_array_elements(public.nearby_invites()) x where (x ->> 'id') = pg_temp.room('dbl')::text),
          '不在邀请列表里');
select ok(pg_temp.u(5) in (select (x -> 'user' ->> 'id')::uuid from jsonb_array_elements(public.nearby_players(37.514849, -121.986485, 20)) x),
          '两个人之间没有还在等的邀请了');

-- 附近的人可以加入，人齐了房主开局
select pg_temp.login(6);
select is(public.join_room(pg_temp.room('dbl')), 'member', '别人加入');
select pg_temp.login(7);
select is(public.join_room(pg_temp.room('dbl')), 'member', '第 4 个人加入');
select pg_temp.login(1);
select isnt(public.start_room(pg_temp.room('dbl')), null, '房主开局');

select * from finish();
rollback;
