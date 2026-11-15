-- 示例球友：真人少时补在后面、真人够了不补、没定级的人不补、约不了、跳过不报错
begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000047' || lpad(n::text, 2, '0'))::uuid, 'sp' || n || '@test.local' from generate_series(1, 9) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000047' || lpad(n::text, 2, '0'))::uuid, 'Samp' || n from generate_series(1, 9) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000047' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create function pg_temp.list() returns jsonb language sql as $$
  select public.nearby_players(37.514849, -121.986485, 20)
$$;
create function pg_temp.samples() returns int language sql as $$
  select count(*)::int from jsonb_array_elements(pg_temp.list()) x where public.is_sample_player((x -> 'user' ->> 'id')::uuid)
$$;
create temp table r (k text primary key, v text);
grant all on r to authenticated, anon;

-- 都定了级；2–8 号收藏了弗里蒙特的一家球馆、愿意被看到
update public.profiles set assessed_at = now(), show_as_regular = true where id in (select pg_temp.u(n) from generate_series(1, 8) n);
insert into public.favorite_venues (user_id, venue_id)
  select pg_temp.u(n), (select v.id from public.venues v
                        where extensions.st_dwithin(v.location, extensions.st_makepoint(-121.986485, 37.514849)::extensions.geography, 20000)
                          and v.merged_into is null order by v.id limit 1)
  from generate_series(2, 4) n;

-- 1 号看：附近只有 3 个真人，后面补 17 个示例
select pg_temp.login(1);
insert into r select 'real', jsonb_array_length(public.nearby_real_players(37.514849, -121.986485, 20))::text;
insert into r select 'total', jsonb_array_length(pg_temp.list())::text;
insert into r select 'samples', pg_temp.samples()::text;
insert into r select 'first_real', (not public.is_sample_player((pg_temp.list() -> 0 -> 'user' ->> 'id')::uuid))::text;
insert into r select 'photo', pg_temp.list() -> 3 -> 'user' ->> 'card_photo';
insert into r select 'rating_ok', (abs((pg_temp.list() -> 3 -> 'user' ->> 'rating')::numeric - (select coalesce(p.rating, 3) from public.profiles p where p.id = pg_temp.u(1))) <= 1.01
                                    or (pg_temp.list() -> 3 -> 'user' ->> 'rating')::numeric in (1, 6.33))::text;
insert into r select 'has_venue', (jsonb_array_length(pg_temp.list() -> 3 -> 'venues') = 1)::text;
reset role;
select is((select v from r where k = 'real'), '3', '附近有 3 个真人');
select is((select v from r where k = 'total'), '20', '真人加示例一共 20 张');
select is((select v from r where k = 'samples'), '17', '补了 17 个示例');
select is((select v from r where k = 'first_real'), 'true', '真人排在前面');
select is((select v from r where k = 'photo'), 'samples/01.jpg', '示例的卡片照片是带“示例”角标的图');
select is((select v from r where k = 'rating_ok'), 'true', '示例的等级在我上下一级以内');
select is((select v from r where k = 'has_venue'), 'true', '示例常去的是我附近真实的球馆');

-- 约示例：约不了；跳过示例：不报错
select pg_temp.login(1);
select throws_ok($$ select public.invite_player('00000000-0000-4000-8000-000000000001'::uuid, 'singles', now() + interval '1 day', now() + interval '1 day 2 hours', null) $$,
                 'P0002', 'not_available', '示例约不了');
select lives_ok($$ select public.skip_nearby('00000000-0000-4000-8000-000000000001'::uuid) $$, '跳过示例不报错');
reset role;

-- 再来 3 个真人（一共 6 个）：不补示例
insert into public.favorite_venues (user_id, venue_id)
  select pg_temp.u(n), (select venue_id from public.favorite_venues where user_id = pg_temp.u(2)) from generate_series(5, 7) n;
select pg_temp.login(1);
insert into r select 'enough', pg_temp.samples()::text;
reset role;
select is((select v from r where k = 'enough'), '0', '附近真人到 6 个就不补示例');

-- 9 号没定级：不补示例
select pg_temp.login(9);
insert into r select 'unrated', jsonb_array_length(pg_temp.list())::text;
reset role;
select is((select v from r where k = 'unrated'), '0', '没定级的人不补示例');

select * from finish();
rollback;
