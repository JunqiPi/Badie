-- 常在附近打的人：谁出现、跳过 30 天、想一起打（每天 10 个、互相想打直接成球友、同意 / 不了）、权限
begin;
create extension if not exists pgtap with schema extensions;
select plan(36);

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
create function pg_temp.kinds(n int, k text) returns int language sql security definer as $$
  select count(*)::int from public.notifications where user_id = pg_temp.u(n) and kind = k
$$;
create temp table r (k text primary key, v jsonb);
grant all on r to authenticated, anon;

-- 1 我；2 同馆（21BC）；3、8 常去 5 公里外的 Synergy；4 没打开常客显示；5 拉黑了我；6 已是球友；7 在圣地亚哥；9–20 没收藏球馆
update public.profiles set show_as_regular = (id <> pg_temp.u(4)) where id in (select pg_temp.u(n) from generate_series(1, 20) n);
update public.profiles set preferred_mode = 'doubles' where id = pg_temp.u(2);
insert into public.favorite_venues (user_id, venue_id) values
  (pg_temp.u(1), 'v-us-ca-21-badminton-club-21bc'), (pg_temp.u(2), 'v-us-ca-21-badminton-club-21bc'),
  (pg_temp.u(3), 'v-us-ca-synergy-badminton-academy-fremont-missio'), (pg_temp.u(4), 'v-us-ca-21-badminton-club-21bc'),
  (pg_temp.u(5), 'v-us-ca-21-badminton-club-21bc'), (pg_temp.u(6), 'v-us-ca-21-badminton-club-21bc'),
  (pg_temp.u(7), 'v-us-ca-east-valley-community-center'), (pg_temp.u(8), 'v-us-ca-synergy-badminton-academy-fremont-missio');
insert into public.blocks (blocker, blocked) values (pg_temp.u(5), pg_temp.u(1));
insert into public.friendships (user_a, user_b) values (least(pg_temp.u(1), pg_temp.u(6)), greatest(pg_temp.u(1), pg_temp.u(6)));

-- 谁出现 -------------------------------------------------------------------------
select pg_temp.login(1);
select is(pg_temp.near(), array[pg_temp.u(2), pg_temp.u(3), pg_temp.u(8)],
          '只出现开了常客显示、没拉黑、不是球友、收藏的球馆在附近的人；同馆的在前');
insert into r select 'list', public.nearby_players(37.514849, -121.986485, 20);
select is((select (v -> 0 ->> 'shared_venues')::int from r where k = 'list'), 1, '共同球馆个数');
select is((select v -> 0 -> 'venues' -> 0 ->> 'id' from r where k = 'list'), 'v-us-ca-21-badminton-club-21bc', 'TA 在附近的球馆');
select is((select v -> 0 -> 'user' ->> 'preferred_mode' from r where k = 'list'), 'doubles', '带上喜欢的打法');
select ok((select (v -> 1 -> 'user') ? 'preferred_mode' and v -> 1 -> 'user' -> 'preferred_mode' = 'null'::jsonb from r where k = 'list'),
          '没设打法是 null');
select is((select (v -> 1 -> 'venues' -> 0 ->> 'km')::numeric between 4 and 7 from r where k = 'list'), true, '距离按公里');

-- 跳过 30 天
select public.skip_nearby(pg_temp.u(8));
select is(pg_temp.near(), array[pg_temp.u(2), pg_temp.u(3)], '跳过的人不再出现');
reset role;
update public.nearby_skips set created_at = now() - interval '31 days' where user_id = pg_temp.u(1);
select pg_temp.login(1);
select is(pg_temp.near(), array[pg_temp.u(2), pg_temp.u(3), pg_temp.u(8)], '30 天后又出现');

-- 不能约的人
select throws_ok($$ select public.wish_to_play(pg_temp.u(4)) $$, 'P0002', 'not_available', '没开常客显示的不能约');
select throws_ok($$ select public.wish_to_play(pg_temp.u(5)) $$, 'P0002', 'not_available', '拉黑了的不能约');
select throws_ok($$ select public.wish_to_play(pg_temp.u(6)) $$, 'P0002', 'not_available', '已经是球友的不用约');
select throws_ok($$ select public.wish_to_play(pg_temp.u(1)) $$, 'P0002', 'not_available', '不能约自己');
select pg_temp.login(4);
select throws_ok($$ select public.wish_to_play(pg_temp.u(2)) $$, '22023', 'not_visible', '自己没开常客显示先要打开');

-- 想一起打：等对方回复 -------------------------------------------------------------
select pg_temp.login(1);
select is(public.wish_to_play(pg_temp.u(2)), '{"mutual": false, "remaining": 9, "suggestion": null}'::jsonb, '发出去，今天还能约 9 个');
select is(public.wish_to_play(pg_temp.u(2)), '{"mutual": false, "remaining": 9, "suggestion": null}'::jsonb, '再右滑一次什么都不变');
select is(pg_temp.near(), array[pg_temp.u(3), pg_temp.u(8)], '在等回复的人不再出现');
reset role;
select is(pg_temp.kinds(2, 'play_wish'), 1, '对方收到一条想一起打的通知');
select is((select title from public.notifications where user_id = pg_temp.u(2) and kind = 'play_wish'), 'Near1 wants to play with you',
          '通知写着谁想打');

select pg_temp.login(2);
insert into r select 'pending', public.pending_play_wishes();
select is((select jsonb_array_length(v) from r where k = 'pending'), 1, '收到的想一起打');
select is((select v -> 0 -> 'from' ->> 'id' from r where k = 'pending'), pg_temp.u(1)::text, '是谁');
select is((select v -> 0 ->> 'shared_venue' from r where k = 'pending'), '21 Badminton Club (21BC)', '也常去哪家');

-- 同意：成为球友、告诉对方、推荐共同球馆
select is(public.respond_play_wish(pg_temp.u(1), true) -> 'suggestion' ->> 'venue_id', 'v-us-ca-21-badminton-club-21bc', '同意后推荐两人都常去的球馆');
select is(public.pending_play_wishes(), '[]'::jsonb, '回复过就不在列表里');
reset role;
select ok(public.are_friends(pg_temp.u(1), pg_temp.u(2)), '同意后成为球友');
select is(pg_temp.kinds(1, 'play_wish_accepted'), 1, '对方收到同意的通知');

-- 互相想打：直接成为球友，两边都收到通知
select pg_temp.login(3);
select public.wish_to_play(pg_temp.u(1));
select pg_temp.login(1);
select is(public.wish_to_play(pg_temp.u(3)), '{"mutual": true, "remaining": 8, "suggestion": null}'::jsonb,
          '对方也想和我打：互相想打；没有共同球馆就不推荐');
reset role;
select ok(public.are_friends(pg_temp.u(1), pg_temp.u(3)) and pg_temp.kinds(3, 'play_wish_accepted') = 1
          and pg_temp.kinds(1, 'play_wish_accepted') = 2, '互相想打的成为球友，两边都收到通知');

-- 不了：不告诉对方，30 天内两边都不再出现
select pg_temp.login(8);
select public.wish_to_play(pg_temp.u(1));
select pg_temp.login(1);
select is(public.respond_play_wish(pg_temp.u(8), false), '{"suggestion": null}'::jsonb, '不了');
select is(pg_temp.kinds(8, 'play_wish_accepted'), 0, '拒绝不通知对方');
select is(pg_temp.near(), '{}'::uuid[], '拒绝过的人不再出现');
select pg_temp.login(8);
select ok(not pg_temp.u(1) = any (pg_temp.near(37.494296, -121.932259)), '被拒绝的一方也看不到对方');
select throws_ok($$ select public.wish_to_play(pg_temp.u(1)) $$, 'P0002', 'not_available', '30 天内不能再约');

-- 每天 10 个：已经发了 2 个（给 2 号、3 号），再发 8 个到上限
select pg_temp.login(1);
select is((select (array_agg((public.wish_to_play(pg_temp.u(n)) ->> 'remaining')::int order by n))[8] from generate_series(9, 16) n), 0,
          '第 10 个发完还剩 0 个');
select throws_ok($$ select public.wish_to_play(pg_temp.u(17)) $$, '54000', 'wish_limit', '24 小时最多 10 个');

-- 权限
select throws_ok($$ select * from public.play_wishes $$, '42501', null, '不能直接读想一起打的表');
set local role anon;
select throws_ok($$ select public.nearby_players(37.5, -122.0, 20) $$, '42501', null, '没登录不能看附近的人');

select * from finish();
rollback;
