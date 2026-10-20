-- 项目：混双两男两女、每边一男一女、等级各按各的算；混双只配混双；男单女单男双女双只能选自己的性别；
-- 混双局男女各两个位子，满了的那边进候补，空出来只补同一边
begin;
create extension if not exists pgtap with schema extensions;
select plan(21);

-- 1、3、5 号男 3 级；2 号女 3 级；4 号女 3+；6 号女 3 级
insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000009' || lpad(n::text, 2, '0'))::uuid, 'e' || n || '@test.local' from generate_series(1, 6) n;
insert into public.profiles (id, nickname, rating, gender)
  select ('00000000-0000-0000-0000-0000000009' || lpad(n::text, 2, '0'))::uuid, 'Event' || n,
         (array[3, 3, 3, 3.33, 3, 3])[n], (array['male', 'female', 'male', 'female', 'male', 'female'])[n]::public.gender
  from generate_series(1, 6) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000009' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create function pg_temp.at(d int, h numeric) returns timestamptz language sql as $$
  select date_trunc('day', now()) + make_interval(days => d) + h * interval '1 hour'
$$;
create function pg_temp.status(n int, d int) returns text language sql security definer as $$
  select status::text from public.match_tickets where user_id = pg_temp.u(n) and starts_at = pg_temp.at(d, 18)
$$;
create function pg_temp.mixed(n int, d int) returns uuid language sql as $$
  select pg_temp.login(n);
  select public.submit_ticket('doubles', pg_temp.at(d, 18), pg_temp.at(d, 20), '{v-us-ca-21-badminton-club-21bc}', 1, false, null, true)
$$;
create temp table ids (name text primary key, id uuid);
grant all on ids to authenticated;
create function pg_temp.id(k text) returns uuid language sql as $$ select id from ids where name = k $$;
create function pg_temp.code(k text) returns text language sql security definer as $$
  select code from public.rooms where id = pg_temp.id(k)
$$;
create function pg_temp.member(k text, n int) returns text language sql security definer as $$
  select case when waitlisted then 'waitlisted' else 'member' end from public.room_members where room_id = pg_temp.id(k) and user_id = pg_temp.u(n)
$$;

-- 不合项目的组合
select pg_temp.login(1);
select throws_ok($$ select public.submit_ticket('singles', pg_temp.at(2, 18), pg_temp.at(2, 20), '{v-us-ca-21-badminton-club-21bc}', 1, false, null, true) $$,
                 '22023', 'invalid_event', '没有混合单打');
select throws_ok($$ select public.submit_ticket('doubles', pg_temp.at(2, 18), pg_temp.at(2, 20), '{v-us-ca-21-badminton-club-21bc}', 1, false, 'female') $$,
                 '22023', 'gender_restricted', '男生不能约女双');

-- 混双：三男一女配不上
select pg_temp.mixed(1, 3);
select pg_temp.mixed(3, 3);
select pg_temp.mixed(5, 3);
select pg_temp.mixed(2, 3);
reset role;
select is(pg_temp.status(2, 3), 'searching', '三男一女凑不成混双');
-- 再来一个女生就成了；女 3 级和男 3 级在混双里是同一水平（不换算）
select pg_temp.mixed(6, 3);
reset role;
select is(pg_temp.status(6, 3), 'offered', '两男两女配上了');
select is((select count(*)::int from public.match_seats s join public.match_tickets t on t.id = s.ticket_id
           where t.user_id = pg_temp.u(6) and t.starts_at = pg_temp.at(3, 18)), 1, '自己有一个位子');
select is((select array_agg(c order by c) from (
             select count(*) filter (where p.gender = 'male')::int as c
             from public.match_seats s join public.profiles p on p.id = s.user_id
             where s.offer_id = (select offer_id from public.match_tickets where user_id = pg_temp.u(6) and starts_at = pg_temp.at(3, 18))
             group by s.team) x), array[1, 1], '每边一男');
select is((select array_agg(c order by c) from (
             select count(*) filter (where p.gender = 'female')::int as c
             from public.match_seats s join public.profiles p on p.id = s.user_id
             where s.offer_id = (select offer_id from public.match_tickets where user_id = pg_temp.u(6) and starts_at = pg_temp.at(3, 18))
             group by s.team) x), array[1, 1], '每边一女');
select is((select count(*)::int from public.match_tickets where starts_at = pg_temp.at(3, 18) and status = 'searching'), 1, '多出来的男生继续等');

-- 混双只配混双：三个混双加一个普通双打凑不成
select pg_temp.mixed(1, 4);
select pg_temp.mixed(2, 4);
select pg_temp.mixed(3, 4);
select pg_temp.login(4);
select public.submit_ticket('doubles', pg_temp.at(4, 18), pg_temp.at(4, 20), '{v-us-ca-21-badminton-club-21bc}', 8, false);
reset role;
select is(pg_temp.status(4, 4), 'searching', '普通双打不进混双');
select is((select mixed from public.match_tickets where user_id = pg_temp.u(2) and starts_at = pg_temp.at(4, 18)), true, '请求记下了混双');

-- 混双局：男女各两个位子；女 3 级在混双里按自己的等级算，能进 3 级局
select pg_temp.login(1);
insert into ids select 'mixed', public.create_room('doubles', 'public', 'v-us-ca-21-badminton-club-21bc', pg_temp.at(5, 19), pg_temp.at(5, 21),
                                                   3, 3, '{}', '', null, true);
select throws_ok($$ select public.create_room('singles', 'public', 'v-us-ca-21-badminton-club-21bc', pg_temp.at(6, 19), pg_temp.at(6, 21),
                                              3, 3, '{}', '', null, true) $$, '22023', 'invalid_event', '没有混合单打局');
select pg_temp.login(3);
select is(public.join_room(pg_temp.id('mixed')), 'member', '第二个男生进了');
select pg_temp.login(5);
select is(public.join_room(pg_temp.id('mixed')), 'waitlisted', '男生的位子满了，第三个男生候补');
select pg_temp.login(2);
select is(public.join_room(pg_temp.id('mixed')), 'member', '女 3 级按自己的等级进了 3 级混双局');
reset role;
select is(public.room_summary(pg_temp.id('mixed')) -> 'mixed_going', '{"male": 2, "female": 1}'::jsonb, '资料里有男女各几个人');
select is((public.room_summary(pg_temp.id('mixed')) ->> 'mixed')::boolean, true, '资料里标了混双');

-- 有男生退出，候补的男生补上
select pg_temp.login(3);
select public.leave_room(pg_temp.id('mixed'));
reset role;
select is(pg_temp.member('mixed', 5), 'member', '空出男生的位子，候补的男生补上');

-- 人齐开局：每边一男一女
select pg_temp.login(4);
select is(public.join_room(pg_temp.id('mixed')), 'member', '第二个女生进了');
select pg_temp.login(1);
insert into ids select 'game', public.start_room(pg_temp.id('mixed'));
reset role;
select is((select array_agg(c order by c) from (
             select count(*) filter (where p.gender = 'male')::int as c
             from public.game_players g join public.profiles p on p.id = g.user_id
             where g.game_id = pg_temp.id('game') group by g.team) x), array[1, 1], '开局后每边一男一女');

-- 私密混双局不排候补：这边满了直接告诉你
select pg_temp.login(2);
insert into ids select 'private', public.create_room('doubles', 'private', null, null, null, 1, 9, '{}', '', null, true);
select pg_temp.login(4);
select lives_ok(format($$ select public.join_room_code(%L) $$, pg_temp.code('private')), '第二个女生用房间码进了');
select pg_temp.login(6);
select throws_ok(format($$ select public.join_room_code(%L) $$, pg_temp.code('private')),
                 '54000', 'mixed_side_full', '第三个女生进不了');

select * from finish();
rollback;
