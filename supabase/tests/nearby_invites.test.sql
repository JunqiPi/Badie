-- 附近的人右滑发邀请：发邀请（时间窗口、每天 10 个）、换个时间、好、不了 + 冷却、定时间、没定时间自动取消（不记临时取消）、
-- 旧的房间入口挡住、权限
begin;
create extension if not exists pgtap with schema extensions;
select plan(73);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000042' || lpad(n::text, 2, '0'))::uuid, 'ni' || n || '@test.local' from generate_series(1, 16) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000042' || lpad(n::text, 2, '0'))::uuid, 'Inv' || n from generate_series(1, 16) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000042' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
-- 球馆当地 n 天后的某个钟点
create function pg_temp.at(days int, hhmm text) returns timestamptz language sql as $$
  select (((now() at time zone 'America/Los_Angeles')::date + days) + hhmm::time) at time zone 'America/Los_Angeles'
$$;
create function pg_temp.near() returns uuid[] language sql as $$
  select coalesce(array_agg((x -> 'user' ->> 'id')::uuid order by n), '{}')
  from jsonb_array_elements(public.nearby_players(37.514849, -121.986485, 20)) with ordinality t(x, n)
$$;
create function pg_temp.kinds(n int, k text) returns int language sql security definer as $$
  select count(*)::int from public.notifications where user_id = pg_temp.u(n) and kind = k
$$;
create function pg_temp.last_note(n int) returns text language sql security definer as $$
  select title || ' / ' || body from public.notifications where user_id = pg_temp.u(n) order by id desc limit 1
$$;
create temp table r (k text primary key, v jsonb);
grant all on r to authenticated, anon;
create function pg_temp.room(k text) returns uuid language sql as $$ select (v ->> 'room_id')::uuid from r where r.k = room.k $$;
create function pg_temp.invited(n int) returns jsonb language sql as $$
  select x from jsonb_array_elements(public.nearby_invites()) x where x -> 'invite' -> 'to' ->> 'id' = pg_temp.u(n)::text
$$;

-- 1–15 都开了显示、定过级、常去 21BC；13 没开显示；14 没定级；15 是 2 的球友；16 没收藏球馆
update public.profiles set show_as_regular = (id <> pg_temp.u(13)), assessed_at = case when id <> pg_temp.u(14) then now() end
  where id in (select pg_temp.u(n) from generate_series(1, 16) n);
update public.profiles set locale = 'zh-Hans' where id = pg_temp.u(4);
insert into public.favorite_venues (user_id, venue_id) select pg_temp.u(n), 'v-us-ca-21-badminton-club-21bc' from generate_series(1, 15) n;
insert into public.friendships (user_a, user_b) values (least(pg_temp.u(2), pg_temp.u(15)), greatest(pg_temp.u(2), pg_temp.u(15)));

-- 发邀请 ---------------------------------------------------------------------------
select pg_temp.login(1);
insert into r select 'r2', public.invite_player(pg_temp.u(2), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(1, '14:00'), pg_temp.at(1, '18:00'), 'afternoon');
select is((select (v ->> 'remaining')::int from r where k = 'r2'), 9, '发出去，今天还能约 9 个');
insert into r select 'mine', pg_temp.invited(2);
select is((select v ->> 'time_set' from r where k = 'mine'), 'false', '没定具体时间');
select is((select (v ->> 'window_start')::timestamptz from r where k = 'mine'), pg_temp.at(1, '14:00'), '窗口开始');
select is((select (v ->> 'starts_at')::timestamptz || ' ' || (v ->> 'ends_at')::timestamptz from r where k = 'mine'),
          pg_temp.at(1, '14:00') || ' ' || pg_temp.at(1, '18:00'), 'starts_at / ends_at 先填窗口');
select is((select v ->> 'daypart' || ' ' || (v ->> 'duration_minutes') || ' ' || (v ->> 'mode') || ' ' || (v ->> 'visibility') from r where k = 'mine'),
          'afternoon 120 singles private', '下午、打 2 小时、单打私密局');
select is((select v -> 'invite' ->> 'awaiting_me' from r where k = 'mine'), 'false', '发出去以后等对方回复');
select is((select (v -> 'invite' ->> 'answer_by')::timestamptz from r where k = 'mine'), pg_temp.at(1, '16:00'), '最晚回复：窗口结束前 2 小时');
select throws_ok($$ select public.invite_player(pg_temp.u(2), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(2, '14:00'), pg_temp.at(2, '18:00')) $$,
                 '23505', 'already_invited', '同一个人还没回复不能再约');
select ok(not pg_temp.u(2) = any (pg_temp.near()), '有还没回复的邀请，大厅里不再出现');

reset role;
select is(pg_temp.kinds(2, 'room'), 1, '对方收到邀请通知');
select ok(pg_temp.last_note(2) ~ '^Inv1 invited you to play / .* 2:00 PM–6:00 PM · 21 Badminton Club \(21BC\)\. Open Badie to join\.$',
          '通知里写时间窗口');

select pg_temp.login(2);
insert into r select 'theirs', x from jsonb_array_elements(public.my_rooms()) x where x -> 'invite' is not null;
select is((select v ->> 'my_status' || ' ' || (v -> 'invite' ->> 'awaiting_me') || ' ' || (v -> 'invite' -> 'from' ->> 'nickname') from r where k = 'theirs'),
          'invited true Inv1', '收到的人在我的房间里看到：被邀请、轮到我、谁约的');
select ok(not pg_temp.u(1) = any (pg_temp.near()), '收到的人的大厅里也不出现对方');
select ok((public.player_card(pg_temp.u(1)) ->> 'usual_times') is not null, '资料带上常用时间');

-- 不能约的
select pg_temp.login(1);
select throws_ok($$ select public.invite_player(pg_temp.u(14), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(1, '14:00'), pg_temp.at(1, '18:00')) $$,
                 'P0002', 'not_available', '没定级的不能约');
select throws_ok($$ select public.invite_player(pg_temp.u(13), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(1, '14:00'), pg_temp.at(1, '18:00')) $$,
                 'P0002', 'not_available', '没开显示的不能约');
select throws_ok($$ select public.invite_player(pg_temp.u(1), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(1, '14:00'), pg_temp.at(1, '18:00')) $$,
                 'P0002', 'not_available', '不能约自己');
select throws_ok($$ select public.invite_player(pg_temp.u(3), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(1, '14:15'), pg_temp.at(1, '18:00')) $$,
                 '22023', 'invalid_window', '要对齐半点');
select throws_ok($$ select public.invite_player(pg_temp.u(3), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(1, '14:00'), pg_temp.at(1, '15:00')) $$,
                 '22023', 'invalid_window', '窗口要能打满 2 小时');
select throws_ok($$ select public.invite_player(pg_temp.u(3), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(1, '08:00'), pg_temp.at(1, '13:00'), 'evening') $$,
                 '22023', 'invalid_window', '时段要在窗口里');
select throws_ok($$ select public.invite_player(pg_temp.u(3), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(1, '08:00'), pg_temp.at(9, '08:00')) $$,
                 '22023', 'invalid_window', '最多跨 7 天');
select throws_ok($$ select public.invite_player(pg_temp.u(3), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(32, '14:00'), pg_temp.at(32, '18:00')) $$,
                 '22023', 'too_far', '30 天内');
select throws_ok($$ select public.invite_player(pg_temp.u(3), 'no-such-venue', pg_temp.at(1, '14:00'), pg_temp.at(1, '18:00')) $$,
                 '22023', 'invalid_venues', '球馆要存在');
select pg_temp.login(13);
select throws_ok($$ select public.invite_player(pg_temp.u(3), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(1, '14:00'), pg_temp.at(1, '18:00')) $$,
                 '22023', 'not_visible', '自己没开显示先要打开');
select pg_temp.login(2);
select ok((public.invite_player(pg_temp.u(15), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(3, '08:00'), pg_temp.at(4, '22:00')) ->> 'room_id') is not null,
          '球友也能约；窗口可以跨天');

-- 每天 10 个：3–11 再约 9 个，第 11 个不行
select pg_temp.login(1);
insert into r select 'r' || n, public.invite_player(pg_temp.u(n), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(1, '14:00'), pg_temp.at(1, '18:00'), 'any')
  from generate_series(3, 11) n;
select is((select (v ->> 'remaining')::int from r where k = 'r11'), 0, '第 10 个以后还能约 0 个');
select throws_ok($$ select public.invite_player(pg_temp.u(12), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(1, '14:00'), pg_temp.at(1, '18:00')) $$,
                 '54000', 'invite_limit', '24 小时最多 10 个');
select lives_ok($$ select public.create_room('singles', 'private', null, null, null, 1, 9) $$, '发出去的邀请不占“最多 3 个房间”');
reset role;
select ok(pg_temp.last_note(4) ~ '^Inv1 邀请你打球 / \d+月\d+日 周. 14:00–18:00 · 21 Badminton Club \(21BC\)。', '中文通知的时间窗口');

-- 换个时间 ---------------------------------------------------------------------------
select pg_temp.login(1);
select throws_ok(format('select public.respond_invite(%L, true)', pg_temp.room('r2')), '22023', 'not_your_turn', '发邀请的人不能替对方答应');
select pg_temp.login(2);
select lives_ok(format('select public.counter_invite(%L, null, %L, %L)', pg_temp.room('r2'), pg_temp.at(2, '18:00'), pg_temp.at(2, '20:00')),
                '换个时间：正好 2 小时就是定好的时间');
select throws_ok(format('select public.respond_invite(%L, true)', pg_temp.room('r2')), '22023', 'not_your_turn', '换完以后轮到对方');
select pg_temp.login(1);
insert into r select 'mine2', pg_temp.invited(2);
select is((select v ->> 'time_set' || ' ' || (v -> 'invite' ->> 'awaiting_me') || ' ' || (v -> 'invite' ->> 'rounds') from r where k = 'mine2'),
          'true true 1', '定好的时间，轮到发邀请的人回复');
reset role;
select is(pg_temp.kinds(1, 'invite_counter'), 1, '发邀请的人收到“想换个时间”');
select ok(pg_temp.last_note(1) ~ '^Inv2 suggested another time / .* 6:00 PM · 21 Badminton Club \(21BC\)\. Open Badie to answer\.$', '通知里写新时间');

-- 好：成局 -------------------------------------------------------------------------
select pg_temp.login(1);
insert into r select 'acc2', public.respond_invite(pg_temp.room('r2'), true);
select is((select v ->> 'status' from r where k = 'acc2'), 'accepted', '答应了就成局');
select is((select (x ->> 'starts_at')::timestamptz || ' ' || (x ->> 'time_set') || ' ' || (x ->> 'mode')
           from jsonb_array_elements(public.my_games()) x where x ->> 'id' = (select v ->> 'game_id' from r where k = 'acc2')),
          pg_temp.at(2, '18:00') || ' true singles', '球局是定好的时间');
reset role;
select is(pg_temp.kinds(2, 'matched'), 1, '对方收到成局通知');
select is((select status::text from public.rooms where id = pg_temp.room('r2')), 'started', '房间开局了');
select pg_temp.login(2);
select is(public.open_thread('game', (select (v ->> 'game_id')::uuid from r where k = 'acc2')) ->> 'access', 'open', '有群聊');

-- 好：没定时间的成局，再定时间 ------------------------------------------------------
select pg_temp.login(3);
insert into r select 'acc3', public.respond_invite(pg_temp.room('r3'), true);
insert into r select 'g3', x from jsonb_array_elements(public.my_games()) x where x ->> 'id' = (select v ->> 'game_id' from r where k = 'acc3');
select is((select v ->> 'time_set' || ' ' || (v ->> 'window_start')::timestamptz || ' ' || (v ->> 'set_time_by')::timestamptz from r where k = 'g3'),
          'false ' || pg_temp.at(1, '14:00') || ' ' || pg_temp.at(1, '16:00'), '没定时间：带窗口和最晚定时间');
reset role;
select ok(pg_temp.last_note(1) ~ 'Set the exact time when you’re ready\.$', '告诉对方具体几点再定');
select ok(not public.has_game_between(pg_temp.u(3), pg_temp.at(1, '14:00'), pg_temp.at(1, '18:00')), '没定时间的球局不占时间');
select pg_temp.login(3);
select throws_ok(format('select public.set_game_time(%L, %L)', (select v ->> 'game_id' from r where k = 'acc3'), pg_temp.at(1, '17:00')),
                 '22023', 'invalid_slot', '要在窗口里打满 2 小时');
select throws_ok(format('select public.set_game_time(%L, %L)', (select v ->> 'game_id' from r where k = 'acc3'), pg_temp.at(1, '14:10')),
                 '22023', 'invalid_slot', '要对齐半点');
select pg_temp.login(4);
select throws_ok(format('select public.set_game_time(%L, %L)', (select v ->> 'game_id' from r where k = 'acc3'), pg_temp.at(1, '15:00')),
                 'P0002', 'not_available', '别人不能定');
select pg_temp.login(1);
select lives_ok(format('select public.set_game_time(%L, %L)', (select v ->> 'game_id' from r where k = 'acc3'), pg_temp.at(1, '15:30')),
                '任一方定时间');
select throws_ok(format('select public.set_game_time(%L, %L)', (select v ->> 'game_id' from r where k = 'acc3'), pg_temp.at(1, '14:00')),
                 '22023', 'time_already_set', '定了就不能再定');
reset role;
select is((select starts_at || ' ' || ends_at || ' ' || time_set from public.games where id = (select (v ->> 'game_id')::uuid from r where k = 'acc3')),
          pg_temp.at(1, '15:30') || ' ' || pg_temp.at(1, '17:30') || ' true', '定了时间就是普通球局');
select is(pg_temp.kinds(3, 'game_time_set'), 1, '对方收到定时间的通知');
select ok(public.has_game_between(pg_temp.u(3), pg_temp.at(1, '17:00'), pg_temp.at(1, '18:00')), '定了时间就占时间');

-- 没定时间：到点自动取消，谁都不记临时取消 ------------------------------------------------
select pg_temp.login(5);
insert into r select 'acc5', public.respond_invite(pg_temp.room('r5'), true);
reset role;
update public.games set starts_at = now() - interval '3 hours', window_start = now() - interval '3 hours',
                        ends_at = now() + interval '1 hour', window_end = now() + interval '1 hour'
  where id = (select (v ->> 'game_id')::uuid from r where k = 'acc5');
select public.expire_rooms();
select is((select status::text from public.games where id = (select (v ->> 'game_id')::uuid from r where k = 'acc5')), 'cancelled',
          '窗口结束前 2 小时还没定就取消');
select is((select count(*)::int from public.game_players where game_id = (select (v ->> 'game_id')::uuid from r where k = 'acc5')
           and (late_cancel or cancelled_at is not null)), 0, '谁都不算取消');
select is((select late_cancels from public.attendance_record(pg_temp.u(5))) + (select late_cancels from public.attendance_record(pg_temp.u(1))), 0::bigint,
          '履约记录里没有临时取消');
select ok(pg_temp.last_note(5) ~ '^Game cancelled / No time was set for .*, so it was cancelled\.$', '两个人都收到取消通知');

-- 没定时间、窗口已经开始：自己取消也不算临时取消
select pg_temp.login(6);
insert into r select 'acc6', public.respond_invite(pg_temp.room('r6'), true);
reset role;
update public.games set starts_at = now() - interval '1 hour', window_start = now() - interval '1 hour',
                        ends_at = now() + interval '5 hours', window_end = now() + interval '5 hours'
  where id = (select (v ->> 'game_id')::uuid from r where k = 'acc6');
select pg_temp.login(6);
select lives_ok(format('select public.cancel_game(%L)', (select v ->> 'game_id' from r where k = 'acc6')), '窗口开始后还能取消没定时间的球局');
reset role;
select is((select late_cancel from public.game_players where game_id = (select (v ->> 'game_id')::uuid from r where k = 'acc6') and user_id = pg_temp.u(6)),
          false, '不记临时取消');

-- 不了 + 30 天冷却 -----------------------------------------------------------------
select pg_temp.login(7);
select is(public.respond_invite(pg_temp.room('r7'), false), '{"status": "declined", "game_id": null}'::jsonb, '不了');
reset role;
select ok(pg_temp.last_note(1) ~ '^Inv7 can’t make it this time / ', '发邀请的人收到“这次来不了”');
select pg_temp.login(7);
select ok(not pg_temp.u(1) = any (pg_temp.near()), '30 天内拒绝的人不出现（拒绝的一方）');
select pg_temp.login(1);
select ok(not pg_temp.u(7) = any (pg_temp.near()), '30 天内拒绝的人不出现（被拒绝的一方）');
select pg_temp.login(7);
select throws_ok($$ select public.invite_player(pg_temp.u(1), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(1, '14:00'), pg_temp.at(1, '18:00')) $$,
                 'P0002', 'not_available', '冷却期里不能约');
reset role;
update public.rooms set last_activity_at = now() - interval '31 days' where id = pg_temp.room('r7');
select pg_temp.login(1);
select ok(pg_temp.u(7) = any (pg_temp.near()), '30 天后又出现');

-- 被邀请的人退出 = 不了；旧的入口挡住 -------------------------------------------------
select pg_temp.login(8);
select public.leave_room(pg_temp.room('r8'));
reset role;
select is((select closed_reason from public.rooms where id = pg_temp.room('r8')), 'declined', '被邀请的人退出等于不了');
select pg_temp.login(12);
select throws_ok(format('select public.join_room(%L)', pg_temp.room('r9')), 'P0002', 'room_not_found', '别人不能“加入”一对一的邀请');
reset role;
insert into r select 'code9', to_jsonb(code::text) from public.rooms where id = pg_temp.room('r9');
select pg_temp.login(12);
select throws_ok(format('select public.join_room_code(%L)', (select v #>> '{}' from r where k = 'code9')), 'P0002', 'room_not_found',
                 '凭房间码也进不来');
select pg_temp.login(1);
select throws_ok(format('select public.update_room(%L, %L, %L, %L)', pg_temp.room('r9'), 'v-us-ca-21-badminton-club-21bc',
                        pg_temp.at(2, '10:00'), pg_temp.at(2, '12:00')), 'P0002', 'not_available', '不能用改房间改邀请');
select pg_temp.login(9);
select is(public.join_room(pg_temp.room('r9')), 'member', '旧版 App：受邀的人点“加入”等于答应');
reset role;
select is((select status::text from public.rooms where id = pg_temp.room('r9')), 'started', '成局了');

-- 没人回复：到点悄悄关闭
reset role;
update public.rooms set window_end = now() + interval '1 hour' where id = pg_temp.room('r10');
select public.expire_rooms();
select is((select status::text || ' ' || closed_reason from public.rooms where id = pg_temp.room('r10')), 'closed expired', '没人回复到点关闭');

-- 权限 -----------------------------------------------------------------------------
select pg_temp.login(1);
select throws_ok($$ select public.decline_invite(pg_temp.room('r11'), pg_temp.u(1)) $$, '42501', null, '内部函数不能直接调');
select throws_ok($$ select * from public.rooms $$, '42501', null, '房间表不能直接读');
set local role anon;
select throws_ok($$ select public.invite_player(pg_temp.u(2), 'v-us-ca-21-badminton-club-21bc', now(), now()) $$, '42501', null, '没登录不能约');

select * from finish();
rollback;
