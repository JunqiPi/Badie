-- 球馆页的人：最近 30 天在这打过的、常客。只列附近的人里能看到的，不列自己、拉黑和举报过的
begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000044' || lpad(n::text, 2, '0'))::uuid, 'vp' || n || '@test.local' from generate_series(1, 8) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000044' || lpad(n::text, 2, '0'))::uuid, 'Vp' || n from generate_series(1, 8) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000044' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create function pg_temp.ids(list jsonb) returns uuid[] language sql as $$
  select coalesce(array_agg((x ->> 'id')::uuid order by n), '{}') from jsonb_array_elements(list) with ordinality t(x, n)
$$;

-- 1 是我；5 没开显示；6 被我拉黑；7 被我举报过；8 没定级；其余开了显示、定过级
update public.profiles set show_as_regular = (id <> pg_temp.u(5)), assessed_at = case when id <> pg_temp.u(8) then now() end
  where id in (select pg_temp.u(n) from generate_series(1, 8) n);
update public.profiles set show_as_regular = true where id = pg_temp.u(8);
-- 2、3、5、6、7、8 常去 21BC；4 只常去别家
insert into public.favorite_venues (user_id, venue_id)
  select pg_temp.u(n), 'v-us-ca-21-badminton-club-21bc' from unnest(array[1, 2, 3, 5, 6, 7, 8]) n;
insert into public.favorite_venues (user_id, venue_id)
  select pg_temp.u(4), id from public.venues where id <> 'v-us-ca-21-badminton-club-21bc' order by id limit 1;
insert into public.blocks (blocker, blocked) values (pg_temp.u(1), pg_temp.u(6));
insert into public.user_reports (reporter_id, reported_id, reason) values (pg_temp.u(1), pg_temp.u(7), 'other');

-- 球局：3 天前 1、4 打过；10 天前 2、3 打过；40 天前 7 打过（太早）；明天 5、6（还没打）；3 取消过的不算这一场
insert into public.games (id, mode, starts_at, ends_at, venue_id) values
  ('00000000-0000-0000-0000-00000000440a', 'singles', now() - interval '3 days', now() - interval '3 days' + interval '2 hours', 'v-us-ca-21-badminton-club-21bc'),
  ('00000000-0000-0000-0000-00000000440b', 'singles', now() - interval '10 days', now() - interval '10 days' + interval '2 hours', 'v-us-ca-21-badminton-club-21bc'),
  ('00000000-0000-0000-0000-00000000440c', 'singles', now() - interval '40 days', now() - interval '40 days' + interval '2 hours', 'v-us-ca-21-badminton-club-21bc'),
  ('00000000-0000-0000-0000-00000000440d', 'singles', now() + interval '1 day', now() + interval '1 day 2 hours', 'v-us-ca-21-badminton-club-21bc');
insert into public.game_players (game_id, user_id, team, rating) values
  ('00000000-0000-0000-0000-00000000440a', pg_temp.u(1), 1, 4), ('00000000-0000-0000-0000-00000000440a', pg_temp.u(4), 2, 4),
  ('00000000-0000-0000-0000-00000000440b', pg_temp.u(2), 1, 4), ('00000000-0000-0000-0000-00000000440b', pg_temp.u(3), 2, 4),
  ('00000000-0000-0000-0000-00000000440c', pg_temp.u(7), 1, 4), ('00000000-0000-0000-0000-00000000440c', pg_temp.u(2), 2, 4),
  ('00000000-0000-0000-0000-00000000440d', pg_temp.u(5), 1, 4), ('00000000-0000-0000-0000-00000000440d', pg_temp.u(6), 2, 4);

select pg_temp.login(1);
select is(pg_temp.ids(public.venue_people('v-us-ca-21-badminton-club-21bc') -> 'recent'), array[pg_temp.u(4), pg_temp.u(2), pg_temp.u(3)],
          '最近打过：近的在前，不列自己、还没打的、30 天前的');
select is(pg_temp.ids(public.venue_people('v-us-ca-21-badminton-club-21bc') -> 'regulars'), array[pg_temp.u(2), pg_temp.u(3)],
          '常客：不列自己、没开显示、拉黑、举报过、没定级的');
select is((public.venue_people('v-us-ca-21-badminton-club-21bc') -> 'recent' -> 1) ?& array['nickname', 'tag', 'rating', 'avatar', 'card_color',
          'card_photo', 'preferred_mode', 'usual_times', 'recent_no_shows'], true, '和附近的人一样的资料');

-- 取消了的不算
reset role;
update public.game_players set cancelled_at = now() - interval '11 days' where user_id = pg_temp.u(3) and game_id = '00000000-0000-0000-0000-00000000440b';
select pg_temp.login(1);
select is(pg_temp.ids(public.venue_people('v-us-ca-21-badminton-club-21bc') -> 'recent'), array[pg_temp.u(4), pg_temp.u(2)], '取消了的不算');

-- 拉黑是双向的：6 也看不到我
select pg_temp.login(6);
select ok(not pg_temp.u(1) = any(pg_temp.ids(public.venue_people('v-us-ca-21-badminton-club-21bc') -> 'regulars')), '被拉黑的人也看不到我');
select is(pg_temp.ids(public.venue_people('v-does-not-exist') -> 'recent'), '{}'::uuid[], '没有这家：空的');

-- 最多 20 位
reset role;
insert into auth.users (id, email) select gen_random_uuid(), 'vpx' || n || '@test.local' from generate_series(1, 25) n;
insert into public.profiles (id, nickname, show_as_regular, assessed_at)
  select id, 'Vx' || row_number() over (order by id), true, now() from auth.users where email like 'vpx%@test.local';
insert into public.favorite_venues (user_id, venue_id) select id, 'v-us-ca-21-badminton-club-21bc' from auth.users where email like 'vpx%@test.local';
select pg_temp.login(1);
select is(jsonb_array_length(public.venue_people('v-us-ca-21-badminton-club-21bc') -> 'regulars'), 20, '最多 20 位');

-- 没登录不能用
select set_config('role', 'anon', true), set_config('request.jwt.claims', '{"role": "anon"}', true);
select throws_ok($$ select public.venue_people('v-us-ca-21-badminton-club-21bc') $$, '42501', null, '没登录不能用');
reset role;
select is(has_function_privilege('authenticated', 'public.venue_people(text)', 'execute'), true, '登录的人能用');

select * from finish();
rollback;
