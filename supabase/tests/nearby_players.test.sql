-- 附近的人（大厅）：谁出现（球友也出现、没定级的不出现）、加球友状态、跳过 30 天、常用时间、推荐时间、新用户默认显示
begin;
create extension if not exists pgtap with schema extensions;
select plan(26);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000041' || lpad(n::text, 2, '0'))::uuid, 'np' || n || '@test.local' from generate_series(1, 20) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000041' || lpad(n::text, 2, '0'))::uuid, 'Near' || n from generate_series(1, 20) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000041' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
-- 在 21BC（弗里蒙特）20 公里内看到的人，按顺序
create function pg_temp.near(lat double precision default 37.514849, lon double precision default -121.986485) returns uuid[] language sql as $$
  select coalesce(array_agg((x -> 'user' ->> 'id')::uuid order by n), '{}')
  from jsonb_array_elements(public.nearby_players(lat, lon, 20)) with ordinality t(x, n)
$$;
create temp table r (k text primary key, v jsonb);
grant all on r to authenticated, anon;
-- 球馆当地后天是星期几（1 = 周日 … 7 = 周六）和日期
create function pg_temp.day2() returns date language sql as $$
  select (now() at time zone 'America/Los_Angeles')::date + 2
$$;
create function pg_temp.wd2() returns int language sql as $$
  select extract(dow from pg_temp.day2())::int + 1
$$;

-- 1 我；2 同馆（21BC）；3、8、10 常去 5 公里外的 Synergy；4 没打开显示；5 拉黑了我；6 已是球友（同馆）；7 在圣地亚哥；
-- 9 同馆但没定级；10 给我发过好友申请；11–20 没收藏球馆
update public.profiles set show_as_regular = (id <> pg_temp.u(4)), assessed_at = case when id <> pg_temp.u(9) then now() end
  where id in (select pg_temp.u(n) from generate_series(1, 20) n);
update public.profiles set preferred_mode = 'doubles' where id = pg_temp.u(2);
insert into public.favorite_venues (user_id, venue_id) values
  (pg_temp.u(1), 'v-us-ca-21-badminton-club-21bc'), (pg_temp.u(2), 'v-us-ca-21-badminton-club-21bc'),
  (pg_temp.u(3), 'v-us-ca-synergy-badminton-academy-fremont-missio'), (pg_temp.u(4), 'v-us-ca-21-badminton-club-21bc'),
  (pg_temp.u(5), 'v-us-ca-21-badminton-club-21bc'), (pg_temp.u(6), 'v-us-ca-21-badminton-club-21bc'),
  (pg_temp.u(7), 'v-us-ca-east-valley-community-center'), (pg_temp.u(8), 'v-us-ca-synergy-badminton-academy-fremont-missio'),
  (pg_temp.u(9), 'v-us-ca-21-badminton-club-21bc'), (pg_temp.u(10), 'v-us-ca-synergy-badminton-academy-fremont-missio');
insert into public.blocks (blocker, blocked) values (pg_temp.u(5), pg_temp.u(1));
insert into public.friendships (user_a, user_b) values (least(pg_temp.u(1), pg_temp.u(6)), greatest(pg_temp.u(1), pg_temp.u(6)));
insert into public.friend_requests (from_id, to_id) values (pg_temp.u(10), pg_temp.u(1));

-- 谁出现 -------------------------------------------------------------------------
select pg_temp.login(1);
select is(pg_temp.near(), array[pg_temp.u(2), pg_temp.u(6), pg_temp.u(3), pg_temp.u(8), pg_temp.u(10)],
          '开了显示、定过级、没拉黑、收藏的球馆在附近的人；球友也出现；同馆的在前');
insert into r select 'list', public.nearby_players(37.514849, -121.986485, 20);
select is((select (v -> 0 ->> 'shared_venues')::int from r where k = 'list'), 1, '共同球馆个数');
select is((select v -> 0 -> 'venues' -> 0 ->> 'id' from r where k = 'list'), 'v-us-ca-21-badminton-club-21bc', 'TA 在附近的球馆');
select is((select v -> 0 -> 'user' ->> 'preferred_mode' from r where k = 'list'), 'doubles', '带上喜欢的打法');
select is((select v -> 2 -> 'venues' -> 0 ->> 'km' from r where k = 'list')::numeric between 4 and 7, true, '距离按公里');
select is((select v -> 0 -> 'user' -> 'usual_times' from r where k = 'list'), '[]'::jsonb, '带上常用时间（没设是空的）');
select is((select array_agg(x ->> 'is_friend' order by n) from r, jsonb_array_elements(v) with ordinality t(x, n) where k = 'list'),
          array['false', 'true', 'false', 'false', 'false'], '是不是球友');
select is((select array_agg(coalesce(x ->> 'friend_request', '-') order by n) from r, jsonb_array_elements(v) with ordinality t(x, n) where k = 'list'),
          array['-', '-', '-', '-', 'received'], 'TA 申请过加我');

-- 加球友：不同馆的人也能申请（大厅里的人都能看资料）
select is(public.send_friend_request(pg_temp.u(3)), 'requested', '大厅里的人能申请加球友');
select ok(public.player_card(pg_temp.u(8)) is not null, '大厅里的人能看资料');
select is((select x ->> 'friend_request' from jsonb_array_elements(public.nearby_players(37.514849, -121.986485, 20)) x
           where x -> 'user' ->> 'id' = pg_temp.u(3)::text), 'sent', '我申请过显示 sent');
reset role;
update public.profiles set discoverable = false where id = pg_temp.u(12);
select pg_temp.login(1);
select throws_ok($$ select public.send_friend_request(pg_temp.u(12)) $$, '42501', 'not_allowed', '没收藏球馆的不在大厅里，不能随便申请');

-- 跳过 30 天
select public.skip_nearby(pg_temp.u(8));
select is(pg_temp.near(), array[pg_temp.u(2), pg_temp.u(6), pg_temp.u(3), pg_temp.u(10)], '跳过的人不再出现');
reset role;
update public.nearby_skips set created_at = now() - interval '31 days' where user_id = pg_temp.u(1);
select pg_temp.login(1);
select is(pg_temp.near(), array[pg_temp.u(2), pg_temp.u(6), pg_temp.u(3), pg_temp.u(8), pg_temp.u(10)], '30 天后又出现');

-- 定级以后出现
reset role;
update public.profiles set assessed_at = now() where id = pg_temp.u(9);
select pg_temp.login(1);
select ok(pg_temp.u(9) = any (pg_temp.near()), '定级以后出现在大厅里');

-- 常用时间 ---------------------------------------------------------------------------
select lives_ok(format($$ update public.profiles set usual_times = '[{"weekday": %s, "start": "14:00", "end": "18:00"}]' where id = %L $$,
                       pg_temp.wd2(), pg_temp.u(1)), '自己改常用时间');
select throws_ok($$ update public.profiles set usual_times = '[{"weekday": 8, "start": "14:00", "end": "18:00"}]' where id = pg_temp.u(1) $$,
                 '23514', null, '星期只能 1–7');
select throws_ok($$ update public.profiles set usual_times = '[{"weekday": 1, "start": "18:00", "end": "14:00"}]' where id = pg_temp.u(1) $$,
                 '23514', null, '结束要晚于开始');
select throws_ok($$ update public.profiles set usual_times = '[{"weekday": 1, "start": "9:00", "end": "14:00"}]' where id = pg_temp.u(1) $$,
                 '23514', null, '时间写成 HH:MM');
select throws_ok($$ update public.profiles set usual_times = (select jsonb_agg(jsonb_build_object('weekday', 1, 'start', '08:00', 'end', '09:00'))
                                                             from generate_series(1, 6)) where id = pg_temp.u(1) $$,
                 '23514', null, '最多 5 段');
select is((select x -> 'user' -> 'usual_times' -> 0 ->> 'start' from jsonb_array_elements(public.nearby_players(37.514849, -121.986485, 20)) x
           where x -> 'user' ->> 'id' = pg_temp.u(2)::text), null, '别人没设就没有');

-- 推荐时间：两人常用时间的重叠
select is(public.suggest_invite_window(pg_temp.u(2)), null, '没有重叠就是 null');
reset role;
update public.profiles set usual_times = jsonb_build_array(jsonb_build_object('weekday', pg_temp.wd2(), 'start', '15:00', 'end', '20:00'),
                                                           jsonb_build_object('weekday', pg_temp.wd2(), 'start', '06:00', 'end', '07:00'))
  where id = pg_temp.u(2);
select pg_temp.login(1);
insert into r select 'suggest', public.suggest_invite_window(pg_temp.u(2));
select is((select (v ->> 'window_start')::timestamptz from r where k = 'suggest'),
          (pg_temp.day2() + time '15:00') at time zone 'America/Los_Angeles', '从两人都有空的时候开始');
select is((select (v ->> 'window_end')::timestamptz from r where k = 'suggest'),
          (pg_temp.day2() + time '18:00') at time zone 'America/Los_Angeles', '到先结束的那个');
select is((select v ->> 'daypart' || ' ' || (v ->> 'venue_id') from r where k = 'suggest'), 'afternoon v-us-ca-21-badminton-club-21bc',
          '整段在下午，球馆是两人都常去的');

-- 新用户默认在附近的人里显示 ---------------------------------------------------------
reset role;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000004199', 'np99@test.local');
select pg_temp.login(99);
insert into public.profiles (id, nickname) values (auth.uid(), 'Newbie');
select is((select show_as_regular from public.profiles where id = auth.uid()), true, '新用户默认显示');

select * from finish();
rollback;
