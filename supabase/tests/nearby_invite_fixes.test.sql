-- 附近的人 v2 的修正：常用时间 1–8 小时、最多 5 段；推荐时间只给能约的人；说好时要来得及；不能约球的人拦下；
-- 受邀的人在不了 / 过期以后还能打开房间页；没定时间的球局先定时间才能报赛果、签到自动定时间、签到或报过赛果的不自动取消
begin;
create extension if not exists pgtap with schema extensions;
select plan(24);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000043' || lpad(n::text, 2, '0'))::uuid, 'nf' || n || '@test.local' from generate_series(1, 9) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000043' || lpad(n::text, 2, '0'))::uuid, 'Fix' || n from generate_series(1, 9) n;

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
-- 球馆当地后天是星期几（1 = 周日 … 7 = 周六）
create function pg_temp.wd2() returns int language sql as $$
  select extract(dow from (now() at time zone 'America/Los_Angeles')::date + 2)::int + 1
$$;
-- 现在往前取整到半点
create function pg_temp.half() returns timestamptz language sql as $$
  select to_timestamp(floor(extract(epoch from now()) / 1800) * 1800)
$$;
create function pg_temp.kinds(n int, k text) returns int language sql security definer as $$
  select count(*)::int from public.notifications where user_id = pg_temp.u(n) and kind = k
$$;
create temp table r (k text primary key, v jsonb);
grant all on r to authenticated, anon;
create function pg_temp.room(k text) returns uuid language sql as $$ select (v ->> 'room_id')::uuid from r where r.k = room.k $$;
create function pg_temp.game(k text) returns uuid language sql as $$ select (v ->> 'game_id')::uuid from r where r.k = game.k $$;

-- 都开了显示、定过级、常去 21BC；8 没开显示
update public.profiles set show_as_regular = (id <> pg_temp.u(8)), assessed_at = now()
  where id in (select pg_temp.u(n) from generate_series(1, 9) n);
insert into public.favorite_venues (user_id, venue_id) select pg_temp.u(n), 'v-us-ca-21-badminton-club-21bc' from generate_series(1, 9) n;

-- 常用时间：每段 1–8 小时，最多 5 段 ------------------------------------------------------
select pg_temp.login(1);
select lives_ok($$ update public.profiles set usual_times = (select jsonb_agg(jsonb_build_object('weekday', n, 'start', '08:00', 'end', '09:00'))
                                                             from generate_series(1, 5) n) where id = pg_temp.u(1) $$, '5 段可以');
select throws_ok($$ update public.profiles set usual_times = (select jsonb_agg(jsonb_build_object('weekday', n, 'start', '08:00', 'end', '09:00'))
                                                              from generate_series(1, 6) n) where id = pg_temp.u(1) $$,
                 '23514', null, '最多 5 段');
select throws_ok($$ update public.profiles set usual_times = '[{"weekday": 1, "start": "08:00", "end": "08:30"}]' where id = pg_temp.u(1) $$,
                 '23514', null, '至少 1 小时');
select throws_ok($$ update public.profiles set usual_times = '[{"weekday": 1, "start": "08:00", "end": "17:00"}]' where id = pg_temp.u(1) $$,
                 '23514', null, '最多 8 小时');
select lives_ok($$ update public.profiles set usual_times = '[{"weekday": 1, "start": "16:00", "end": "24:00"}]' where id = pg_temp.u(1) $$,
                '正好 8 小时、到 24:00 可以');

-- 推荐时间：只给能约的人 ------------------------------------------------------------------
reset role;
update public.profiles set usual_times = jsonb_build_array(jsonb_build_object('weekday', pg_temp.wd2(), 'start', '14:00', 'end', '18:00'))
  where id in (pg_temp.u(1), pg_temp.u(2), pg_temp.u(8));
select pg_temp.login(1);
select isnt(public.suggest_invite_window(pg_temp.u(2)), null, '能约的人有推荐时间');
select is(public.suggest_invite_window(pg_temp.u(8)), null, '不在大厅里的人没有推荐时间');

-- 发邀请 ---------------------------------------------------------------------------------
insert into r select 'r' || n, public.invite_player(pg_temp.u(n), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(1, '14:00'), pg_temp.at(1, '18:00'), 'afternoon')
  from unnest(array[2, 3, 4, 5, 6, 9]) n;

-- 说好时要来得及：窗口里没有“现在 + 30 分钟”以后能开始的时间 ---------------------------------
reset role;
update public.rooms set window_start = now() - interval '1 hour', starts_at = now() - interval '1 hour',
                        window_end = now() + interval '2 hours 10 minutes', ends_at = now() + interval '2 hours 10 minutes', daypart = null
  where id = pg_temp.room('r2');
select pg_temp.login(2);
select throws_ok(format('select public.respond_invite(%L, true)', pg_temp.room('r2')), '22023', 'too_late', '来不及了不能说好');
select is(public.respond_invite(pg_temp.room('r2'), false) ->> 'status', 'declined', '还能说不了');

-- 不了以后受邀的人还能打开房间页 ----------------------------------------------------------
select is(public.room_page(pg_temp.room('r2')) ->> 'status', 'closed', '受邀的人说了不了还能打开房间页');
select pg_temp.login(1);
select is(public.room_page(pg_temp.room('r2')) -> 'invite' ->> 'declined_by', pg_temp.u(2)::text, '房间里写着谁说的不了');
select pg_temp.login(7);
select is(public.room_page(pg_temp.room('r2')), null, '别人还是看不到');

-- 不能约球的人：说好、换个时间都拦下，不了照样能说 --------------------------------------------
select pg_temp.login(4);
insert into r select 'acc4', public.respond_invite(pg_temp.room('r4'), true);
reset role;
insert into public.strikes (user_id, game_id, level, starts_at) values (pg_temp.u(1), pg_temp.game('acc4'), 2, now());
select pg_temp.login(3);
select throws_ok(format('select public.respond_invite(%L, true)', pg_temp.room('r3')), '42501', 'suspended', '发邀请的人不能约球时不能成局');
select throws_ok(format('select public.counter_invite(%L, null, %L, %L)', pg_temp.room('r3'), pg_temp.at(2, '18:00'), pg_temp.at(2, '20:00')),
                 '42501', 'suspended', '对方不能约球时不能换个时间');
select lives_ok(format('select public.respond_invite(%L, false)', pg_temp.room('r3')), '不了照样能说');
reset role;
delete from public.strikes where user_id = pg_temp.u(1);

-- 没定时间的球局：先定时间才能报赛果；签到就按现在定下时间 -----------------------------------
update public.games set window_start = pg_temp.half() - interval '1 hour', starts_at = pg_temp.half() - interval '1 hour',
                        window_end = pg_temp.half() + interval '4 hours', ends_at = pg_temp.half() + interval '4 hours', daypart = null
  where id = pg_temp.game('acc4');
select pg_temp.login(4);
select throws_ok(format('select public.report_result(%L, %L)', pg_temp.game('acc4'), 'team1'), '22023', 'time_not_set', '没定时间不能报赛果');
select lives_ok(format('select public.check_in(%L)', pg_temp.game('acc4')), '窗口里能签到');
reset role;
select is((select time_set || ' ' || starts_at || ' ' || ends_at from public.games where id = pg_temp.game('acc4')),
          'true ' || pg_temp.half() || ' ' || (pg_temp.half() + interval '2 hours'), '签到就按现在这个半点定下时间');
select is((select time_set from public.rooms where game_id = pg_temp.game('acc4')), true, '房间也一样');
select is(pg_temp.kinds(1, 'game_time_set'), 1, '对方收到定时间的通知');
select pg_temp.login(4);
select lives_ok(format('select public.report_result(%L, %L)', pg_temp.game('acc4'), 'team1'), '定了时间就能报赛果');

-- 没定时间的球局：有人签到或报过赛果的到点不取消 ----------------------------------------------
select pg_temp.login(5);
insert into r select 'acc5', public.respond_invite(pg_temp.room('r5'), true);
select pg_temp.login(6);
insert into r select 'acc6', public.respond_invite(pg_temp.room('r6'), true);
reset role;
update public.games set starts_at = now() - interval '3 hours', window_start = now() - interval '3 hours',
                        ends_at = now() + interval '1 hour', window_end = now() + interval '1 hour'
  where id in (pg_temp.game('acc5'), pg_temp.game('acc6'));
update public.game_players set checked_in_at = now() where game_id = pg_temp.game('acc5') and user_id = pg_temp.u(5);
insert into public.result_reports (game_id, reporter_id, outcome) values (pg_temp.game('acc6'), pg_temp.u(6), 'team1');
-- 没回复的邀请也到点
update public.rooms set window_end = now() + interval '1 hour' where id = pg_temp.room('r9');
select public.expire_rooms();
select is((select status::text from public.games where id = pg_temp.game('acc5')), 'scheduled', '有人签到的不自动取消');
select is((select status::text from public.games where id = pg_temp.game('acc6')), 'scheduled', '报过赛果的不自动取消');

-- 过期以后受邀的人也能打开房间页
select pg_temp.login(9);
select is(public.room_page(pg_temp.room('r9')) ->> 'closed_reason', 'expired', '过期以后受邀的人还能打开房间页');

select * from finish();
rollback;
