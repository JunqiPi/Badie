-- 1.0.5 提交前复查的修正：等级不低于 1、重叠的邀请自动撤回、签到定下的时间不记爽约
begin;
create extension if not exists pgtap with schema extensions;
select plan(24);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000045' || lpad(n::text, 2, '0'))::uuid, 'rf' || n || '@test.local' from generate_series(1, 12) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000045' || lpad(n::text, 2, '0'))::uuid, 'Rf' || n from generate_series(1, 12) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000045' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
-- 球馆当地 n 天后的某个钟点
create function pg_temp.at(days int, hhmm text) returns timestamptz language sql as $$
  select (((now() at time zone 'America/Los_Angeles')::date + days) + hhmm::time) at time zone 'America/Los_Angeles'
$$;
create function pg_temp.half() returns timestamptz language sql as $$
  select to_timestamp(floor(extract(epoch from now()) / 1800) * 1800)
$$;
create function pg_temp.last(n int) returns text language sql security definer as $$
  select title || ' / ' || body from public.notifications where user_id = pg_temp.u(n) order by id desc limit 1
$$;
create temp table r (k text primary key, v jsonb);
grant all on r to authenticated, anon;
create function pg_temp.room(k text) returns uuid language sql as $$ select (v ->> 'room_id')::uuid from r where r.k = room.k $$;
create function pg_temp.game(k text) returns uuid language sql as $$ select (v ->> 'game_id')::uuid from r where r.k = game.k $$;
create function pg_temp.state(k text) returns text language sql security definer as $$
  select status || ' ' || coalesce(closed_reason, '-') from public.rooms where id = pg_temp.room(k)
$$;

create function pg_temp.levels(k text) returns text language sql security definer as $$
  select level_min || '-' || level_max from public.rooms where id = pg_temp.room(k)
$$;

-- 都开了显示、定过级、常去 21BC；1、2 是 1 级女生（换算后是负数），3 是 2 级多的女生
update public.profiles set show_as_regular = true, assessed_at = now(), rating = 4
  where id in (select pg_temp.u(n) from generate_series(1, 12) n);
update public.profiles set gender = 'female', rating = case when id = pg_temp.u(3) then 2.4 else 1.0 end
  where id in (pg_temp.u(1), pg_temp.u(2), pg_temp.u(3));
insert into public.favorite_venues (user_id, venue_id) select pg_temp.u(n), 'v-us-ca-21-badminton-club-21bc' from generate_series(1, 12) n;

-- 等级不低于 1 -----------------------------------------------------------------------------
select pg_temp.login(1);
insert into r select 'dbl', public.invite_player(pg_temp.u(2), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(2, '19:00'), pg_temp.at(2, '21:00'),
                                                 null, 120, 'doubles');
select pg_temp.login(2);
select lives_ok(format('select public.respond_invite(%L, true)', pg_temp.room('dbl')), '两位 1 级女生约双打：能答应');
select is(pg_temp.levels('dbl'), '1-2', '水平范围 1–2');
select pg_temp.login(1);
select lives_ok(format('select public.create_room(%L, %L, %L, %L, %L, 1, 3)', 'doubles', 'public', 'v-us-ca-21-badminton-club-21bc',
                       pg_temp.at(3, '19:00'), pg_temp.at(3, '21:00')), '1 级女生能开不限性别的局');
select pg_temp.login(3);
insert into r select 'pub', jsonb_build_object('room_id', public.create_room('doubles', 'public', 'v-us-ca-21-badminton-club-21bc',
                                                                             pg_temp.at(4, '19:00'), pg_temp.at(4, '21:00'), 1, 3));
select pg_temp.login(1);
select is(public.join_room(pg_temp.room('pub')), 'member', '1 级女生能加入 1–3 级的公开局');

-- 同一时间约了几个人：一个成局，其他的自动撤回 ---------------------------------------------------
select pg_temp.login(4);
insert into r select 'b5', public.invite_player(pg_temp.u(5), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(5, '19:00'), pg_temp.at(5, '21:00'), null, 120);
insert into r select 'b6', public.invite_player(pg_temp.u(6), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(5, '19:30'), pg_temp.at(5, '21:30'), null, 120);
insert into r select 'b7', public.invite_player(pg_temp.u(7), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(6, '19:00'), pg_temp.at(6, '21:00'), null, 120);
-- 10 也在同一时间约了 4：这份在等 4 回复
select pg_temp.login(10);
insert into r select 'to4', public.invite_player(pg_temp.u(4), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(5, '19:00'), pg_temp.at(5, '21:00'), null, 120);

select pg_temp.login(5);
insert into r select 'b5_yes', public.respond_invite(pg_temp.room('b5'), true);
select isnt(pg_temp.game('b5_yes'), null, '5 答应：成局');
select is(pg_temp.state('b5'), 'started -', '成局的这份照常');
select is(pg_temp.state('b6'), 'closed owner_closed', '同一时间约 6 的那份自动撤回');
select alike(pg_temp.last(6), 'Invite withdrawn / Rf4 already has a game at %:30 PM.', '告诉 6：撤回了，因为 4 已经有球局');
select is(pg_temp.state('b7'), 'open -', '别的时间约 7 的那份不动');
select is(pg_temp.state('to4'), 'open -', '等 4 回复的那份不动');
select pg_temp.login(6);
select ok(not exists (select 1 from jsonb_array_elements(public.nearby_invites()) x where (x ->> 'id') = pg_temp.room('b6')::text),
          '6 的邀请列表里没有了');
select lives_ok(format('select public.invite_player(%L, %L, %L, %L, null, 120)', pg_temp.u(4), 'v-us-ca-21-badminton-club-21bc',
                       pg_temp.at(7, '19:00'), pg_temp.at(7, '21:00')), '撤回不算拒绝：6 还能约 4');
select pg_temp.login(4);
select throws_ok(format('select public.respond_invite(%L, true)', pg_temp.room('to4')), '23P01', 'overlapping', '4 自己有球局：答应不了');

-- 换个时间提出的人后来有了球局：他提的那份也撤回
select pg_temp.login(8);
insert into r select 'c9', public.invite_player(pg_temp.u(9), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(8, '17:00'), pg_temp.at(8, '19:00'), null, 120);
select pg_temp.login(9);
select public.counter_invite(pg_temp.room('c9'), null, pg_temp.at(8, '20:00'), pg_temp.at(8, '22:00'), null, 120);
select pg_temp.login(10);
insert into r select 'd9', public.invite_player(pg_temp.u(9), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(8, '20:30'), pg_temp.at(8, '22:30'), null, 120);
select pg_temp.login(9);
select lives_ok(format('select public.respond_invite(%L, true)', pg_temp.room('d9')), '9 答应了 10');
select is(pg_temp.state('c9'), 'closed owner_closed', '9 给 8 提的那个时间撤回');
select alike(pg_temp.last(8), 'Invite withdrawn / Rf9 already has a game at %', '告诉 8');

-- 撤回没赶上（那份正被别人操作）时：对方有球局，说“TA 约不了”
reset role;
insert into public.games (id, mode, starts_at, ends_at, venue_id)
  values ('00000000-0000-0000-0000-00000000450a', 'singles', pg_temp.at(6, '19:00'), pg_temp.at(6, '21:00'), 'v-us-ca-21-badminton-club-21bc');
insert into public.game_players (game_id, user_id, team, rating)
  values ('00000000-0000-0000-0000-00000000450a', pg_temp.u(4), 1, 4), ('00000000-0000-0000-0000-00000000450a', pg_temp.u(11), 2, 4);
select is(pg_temp.state('b7'), 'closed owner_closed', '别的方式成的局也会撤回重叠的邀请');
update public.rooms set status = 'open', closed_reason = null, awaiting_id = pg_temp.u(7) where id = pg_temp.room('b7');
insert into public.room_invites (room_id, user_id, invited_by) values (pg_temp.room('b7'), pg_temp.u(7), pg_temp.u(4));
select pg_temp.login(7);
select throws_ok(format('select public.respond_invite(%L, true)', pg_temp.room('b7')), 'P0002', 'not_available', '对方有球局：TA 约不了');

-- 签到定下的时间不记爽约 ------------------------------------------------------------------------
select pg_temp.login(11);
insert into r select 'loose', public.invite_player(pg_temp.u(12), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(9, '14:00'), pg_temp.at(9, '18:00'), 'afternoon');
select pg_temp.login(12);
insert into r select 'loose_yes', public.respond_invite(pg_temp.room('loose'), true);
reset role;
select is((select time_set from public.games where id = pg_temp.game('loose_yes')), false, '还没定具体时间');
update public.games set window_start = pg_temp.half() - interval '1 hour', starts_at = pg_temp.half() - interval '1 hour',
                        window_end = pg_temp.half() + interval '4 hours', ends_at = pg_temp.half() + interval '4 hours', daypart = null
  where id = pg_temp.game('loose_yes');
select pg_temp.login(11);
select lives_ok(format('select public.check_in(%L)', pg_temp.game('loose_yes')), '11 一个人签到');
reset role;
select is((select time_set || ' ' || time_by_check_in from public.games where id = pg_temp.game('loose_yes')), 'true true', '时间按现在定下，记了一笔');
update public.games set starts_at = starts_at - interval '3 hours', ends_at = ends_at - interval '3 hours', review_prompted = true
  where id = pg_temp.game('loose_yes');
select pg_temp.login(11);
select lives_ok(format('select public.review_player(%L, %L, %L, %L, %L, %L, false)', pg_temp.game('loose_yes'), pg_temp.u(12),
                       'no_show', 'accurate', '{}', '{}'), '11 说 12 没来');
reset role;
select is((select count(*)::int from public.strikes where user_id = pg_temp.u(12)), 0, '12 没答应过这个时间：不记爽约');
-- 自己定的时间照旧
update public.games set time_by_check_in = false where id = pg_temp.game('loose_yes');
select is(public.judged_no_show(pg_temp.game('loose_yes'), pg_temp.u(12)), true, '定好时间的球局照旧算爽约');

select * from finish();
rollback;
