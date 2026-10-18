-- 注销账号：以后的球局取消并通知、约球请求撤回、球群交接、候补递补、数据删除、管理员不能自助注销
begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000006' || lpad(n::text, 2, '0'))::uuid, 'a' || n || '@test.local' from generate_series(1, 7) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000006' || lpad(n::text, 2, '0'))::uuid, 'Account' || n from generate_series(1, 7) n;
insert into public.admin_users (user_id, role) values ('00000000-0000-0000-0000-000000000607', 'owner');

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000006' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create function pg_temp.notes(n int, k text) returns int language sql security definer as $$
  select count(*)::int from public.notifications where user_id = pg_temp.u(n) and kind = k
$$;
-- 明天（球馆当地）19:00–21:00，4 个名额
create function pg_temp.schedule() returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object(
    'weekday', extract(dow from (now() at time zone 'America/Los_Angeles') + interval '1 day'),
    'start', 1140, 'end', 1260, 'capacity', 4, 'fee', ''))
$$;
create function pg_temp.at(d int, h numeric) returns timestamptz language sql as $$
  select date_trunc('day', now()) + make_interval(days => d) + h * interval '1 hour'
$$;
create temp table ids (name text primary key, id uuid);
grant all on ids to authenticated;
create function pg_temp.id(k text) returns uuid language sql as $$ select id from ids where name = k $$;
create function pg_temp.tomorrow(k text) returns uuid language sql security definer as $$
  select id from public.group_sessions where group_id = pg_temp.id(k) order by starts_at limit 1
$$;

-- 1 号建了两个群：一个有成员（3 号是组织者，2 号更早加入），一个只有自己
select pg_temp.login(1);
insert into ids select 'busy', public.create_group('Thursday doubles', 'v-us-ca-21-badminton-club-21bc', '', 1, 9, 'open', pg_temp.schedule());
insert into ids select 'empty', public.create_group('Just me', 'v-us-ca-21-badminton-club-21bc', '', 1, 9, 'open', pg_temp.schedule());
select public.sign_up_session(pg_temp.tomorrow('busy'));
select pg_temp.login(2); select public.join_group(pg_temp.id('busy')); select public.sign_up_session(pg_temp.tomorrow('busy'));
select pg_temp.login(3); select public.join_group(pg_temp.id('busy')); select public.sign_up_session(pg_temp.tomorrow('busy'));
select pg_temp.login(4); select public.join_group(pg_temp.id('busy')); select public.sign_up_session(pg_temp.tomorrow('busy'));
select pg_temp.login(5); select public.join_group(pg_temp.id('busy')); select public.sign_up_session(pg_temp.tomorrow('busy'));
reset role;
update public.group_members set role = 'organizer' where group_id = pg_temp.id('busy') and user_id = pg_temp.u(3);
select ok((select waitlisted from public.session_signups where session_id = pg_temp.tomorrow('busy') and user_id = pg_temp.u(5)),
          '准备：5 号在候补');

-- 后天和 6 号有一场单打；大后天还在找人，和 6 号配上了、等确认
with g as (
  insert into public.games (mode, starts_at, ends_at, venue_id)
  values ('singles', pg_temp.at(2, 18), pg_temp.at(2, 20), 'v-us-ca-21-badminton-club-21bc') returning id)
insert into ids select 'game', id from g;
insert into public.game_players (game_id, user_id, team, rating) values
  (pg_temp.id('game'), pg_temp.u(1), 1, 3), (pg_temp.id('game'), pg_temp.u(6), 2, 3);
select pg_temp.login(1);
select public.submit_ticket('singles', pg_temp.at(3, 18), pg_temp.at(3, 20), '{v-us-ca-21-badminton-club-21bc}', 2, false);
select pg_temp.login(6);
select public.submit_ticket('singles', pg_temp.at(3, 18), pg_temp.at(3, 20), '{v-us-ca-21-badminton-club-21bc}', 2, false);
reset role;
select is((select status::text from public.match_tickets where user_id = pg_temp.u(6)), 'offered', '准备：6 号的请求等确认');

-- 注销
select pg_temp.login(1);
select lives_ok($$ select public.delete_account() $$, '可以注销自己的账号');
reset role;
select is((select count(*)::int from auth.users where id = pg_temp.u(1)), 0, '账号已删除');
select is((select count(*)::int from public.profiles where id = pg_temp.u(1)), 0, '资料一并删除');
select is((select count(*)::int from public.group_members where user_id = pg_temp.u(1)), 0, '球群成员记录一并删除');

select is((select status::text from public.games where id = pg_temp.id('game')), 'cancelled', '以后的球局取消');
select is(pg_temp.notes(6, 'cancelled'), 1, '对方收到球局取消的通知');
select is((select status::text from public.match_tickets where user_id = pg_temp.u(6)), 'searching', '对方的请求回去继续找');
select is(pg_temp.notes(6, 'requeued'), 1, '对方收到“还在找”');

select is((select owner_id from public.play_groups where id = pg_temp.id('busy')), pg_temp.u(3), '球群交给组织者（优先于更早加入的成员）');
select is(public.group_role_of(pg_temp.id('busy'), pg_temp.u(3)), 'owner', '新群主的角色是群主');
select is((select title from public.notifications where user_id = pg_temp.u(3) and kind = 'group'), 'You now run Thursday doubles',
          '新群主收到通知');
select is((select count(*)::int from public.play_groups where id = pg_temp.id('empty')), 0, '没有其他成员的球群随账号删除');
select ok(not (select waitlisted from public.session_signups where session_id = pg_temp.tomorrow('busy') and user_id = pg_temp.u(5)),
          '空出的名额让给候补');

select pg_temp.login(7);
select throws_ok($$ select public.delete_account() $$, '42501', null, '管理员要先撤掉身份才能注销');

select * from finish();
rollback;
