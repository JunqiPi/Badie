-- 男女：女子等级换算（−1.5）后再比；约球、公开局、球群可以只限男生 / 女生；约战按换算后的等级；排行榜按性别分开
begin;
create extension if not exists pgtap with schema extensions;
select plan(27);

-- 1 号男 3 级；2 号女 4.5（换算 3）；3 号女 3（换算 1.5）；4 号女 4+（换算 2.83）；5 号男 3 级
insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000008' || lpad(n::text, 2, '0'))::uuid, 'g' || n || '@test.local' from generate_series(1, 5) n;
insert into public.profiles (id, nickname, rating, gender)
  select ('00000000-0000-0000-0000-0000000008' || lpad(n::text, 2, '0'))::uuid, 'Gender' || n,
         (array[3, 4.5, 3, 4.33, 3])[n], (array['male', 'female', 'female', 'female', 'male'])[n]::public.gender
  from generate_series(1, 5) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000008' || lpad(n::text, 2, '0'))::uuid
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
create temp table ids (name text primary key, id uuid);
grant all on ids to authenticated;
create function pg_temp.id(k text) returns uuid language sql as $$ select id from ids where name = k $$;
create function pg_temp.sees_room(k text) returns boolean language sql as $$
  select exists (select 1 from jsonb_array_elements(public.rooms_near(v.lat, v.lon)) r where (r ->> 'id')::uuid = pg_temp.id(k))
  from public.venues v where v.id = 'v-us-ca-21-badminton-club-21bc'
$$;

-- 换算
select is(public.open_rating(4.5, 'female'), 3.0, '女子 4.5 ≈ 男子 3');
select is(public.open_rating(3, 'male'), 3::numeric, '男子不变');
select is(public.open_rating(3, null), 3::numeric, '没填性别按男子算');

-- 本人可以改自己的性别
select pg_temp.login(1);
select lives_ok($$ update public.profiles set gender = 'male' where id = pg_temp.u(1) $$, '可以改自己的性别');

-- 约球：男 3 级和女 4.5 级（换算后一样）能配上
select pg_temp.login(1);
select public.submit_ticket('singles', pg_temp.at(2, 18), pg_temp.at(2, 20), '{v-us-ca-21-badminton-club-21bc}', 1, false);
select pg_temp.login(2);
select public.submit_ticket('singles', pg_temp.at(2, 18), pg_temp.at(2, 20), '{v-us-ca-21-badminton-club-21bc}', 1, false);
reset role;
select is(pg_temp.status(2, 2), 'offered', '男 3 和女 4.5 换算后水平一样，配上了');
select is(pg_temp.status(1, 2), 'offered', '男生这边也配上了');

-- 女 3 级（换算 1.5）和男 3 级差 1.5 级，超出容忍范围
select pg_temp.login(1);
select public.submit_ticket('singles', pg_temp.at(4, 18), pg_temp.at(4, 20), '{v-us-ca-21-badminton-club-21bc}', 1, false);
select pg_temp.login(3);
select public.submit_ticket('singles', pg_temp.at(4, 18), pg_temp.at(4, 20), '{v-us-ca-21-badminton-club-21bc}', 1, false);
reset role;
select is(pg_temp.status(3, 4), 'searching', '同样是 3 级，女生换算后比男生低 1.5 级，配不上');

-- 只和女生打：男生配不上，女生之间按女子等级比
select pg_temp.login(5);
select public.submit_ticket('singles', pg_temp.at(3, 18), pg_temp.at(3, 20), '{v-us-ca-21-badminton-club-21bc}', 2, false);
select pg_temp.login(3);
select public.submit_ticket('singles', pg_temp.at(3, 18), pg_temp.at(3, 20), '{v-us-ca-21-badminton-club-21bc}', 2, false, 'female');
reset role;
select is(pg_temp.status(3, 3), 'searching', '只和女生打：不配男生');
select pg_temp.login(4);
select public.submit_ticket('singles', pg_temp.at(3, 18), pg_temp.at(3, 20), '{v-us-ca-21-badminton-club-21bc}', 2, false, 'female');
reset role;
select is(pg_temp.status(4, 3), 'offered', '两个只和女生打的女生配上了');
select is(pg_temp.status(5, 3), 'searching', '男生还在找');
select is((select play_with::text from public.match_tickets where user_id = pg_temp.u(4) and starts_at = pg_temp.at(3, 18)), 'female',
          '请求记下了和谁打');

-- 女生局：只有女生能看到、能加入；男生不能开女生局
select pg_temp.login(2);
insert into ids select 'women', public.create_room('singles', 'public', 'v-us-ca-21-badminton-club-21bc', pg_temp.at(5, 19), pg_temp.at(5, 21),
                                                   4, 5, '{}', '', 'female');
select pg_temp.login(1);
select throws_ok($$ select public.join_room(pg_temp.id('women')) $$, '22023', 'gender_restricted', '男生进不了女生局');
select ok(not pg_temp.sees_room('women'), '男生看不到女生局');
select throws_ok($$ select public.create_room('singles', 'public', 'v-us-ca-21-badminton-club-21bc', pg_temp.at(6, 19), pg_temp.at(6, 21),
                                              3, 4, '{}', '', 'female') $$, '22023', 'gender_restricted', '男生不能开女生局');
select pg_temp.login(4);
select ok(pg_temp.sees_room('women'), '女生看得到');
select is(public.join_room(pg_temp.id('women')), 'member', '女 4+ 按女子等级在 4–5 级范围里');
reset role;
select is(public.room_summary(pg_temp.id('women')) ->> 'gender', 'female', '球局资料里有性别限制');

-- 男女都能来的局按男子等级：女 4.5（换算 3）能进 3 级局，女 3（换算 1.5）不行
select pg_temp.login(1);
insert into ids select 'mixed', public.create_room('singles', 'public', 'v-us-ca-21-badminton-club-21bc', pg_temp.at(7, 19), pg_temp.at(7, 21), 3, 3);
select pg_temp.login(2);
select is(public.join_room(pg_temp.id('mixed')), 'member', '女 4.5 换算后是 3 级，进了 3 级局');
select pg_temp.login(3);
select throws_ok($$ select public.join_room(pg_temp.id('mixed')) $$, '22023', 'level_out_of_range', '女 3 换算后不到 3 级');

-- 女生球群
select pg_temp.login(2);
insert into ids select 'club', public.create_group('Ladies Night', 'v-us-ca-21-badminton-club-21bc', '', 4, 5, 'open',
                                                   '[{"weekday": 3, "start": 1140, "end": 1260, "capacity": 8}]', 'female');
select pg_temp.login(5);
select throws_ok($$ select public.join_group(pg_temp.id('club')) $$, '22023', 'gender_restricted', '男生进不了女生球群');
select pg_temp.login(4);
select is(public.join_group(pg_temp.id('club')), 'member', '女生能进');

-- 约战“水平相近”按换算后的等级
select pg_temp.login(1);
select is(public.player_card(pg_temp.u(2)) ->> 'challenge', 'available', '男 3 约战女 4.5：换算后相近');
select is(public.player_card(pg_temp.u(3)) ->> 'challenge', 'level_out_of_range', '男 3 约战女 3：换算后差 1.5 级');
select is(public.player_card(pg_temp.u(2)) ->> 'gender', 'female', '资料页显示性别');

-- 排行榜：默认看自己性别的榜，也可以切换
select pg_temp.login(2);
select is(public.weekly_board() ->> 'gender', 'female', '女生默认看女子榜');
select is(public.weekly_board('global', 0, 'male') ->> 'gender', 'male', '可以切到男子榜');
select is(public.venue_board('v-us-ca-21-badminton-club-21bc') ->> 'gender', 'female', '场馆榜也按性别');

select * from finish();
rollback;
