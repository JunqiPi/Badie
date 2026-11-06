-- 首页按天看能约的人：只列在找人、没关掉可见的；左滑跳过；右滑约单打，对方确认就成局
begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000034' || lpad(n::text, 2, '0'))::uuid, 'dc' || n || '@test.local' from generate_series(1, 3) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000034' || lpad(n::text, 2, '0'))::uuid, 'Card' || n from generate_series(1, 3) n;
update public.profiles set show_searching = false where id = '00000000-0000-0000-0000-000000003403';

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000034' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create function pg_temp.at(d int, h int) returns timestamptz language sql as $$
  select date_trunc('day', now()) + make_interval(days => d, hours => h)
$$;
-- 第 d 天附近能约的人数（以那家球馆为中心）
create function pg_temp.cards(d int) returns jsonb language sql as $$
  select public.day_candidates(pg_temp.at(d, 0), pg_temp.at(d + 1, 0),
                               extensions.st_y(v.location::extensions.geometry), extensions.st_x(v.location::extensions.geometry), 20)
  from public.venues v where v.id = 'v-us-ca-21-badminton-club-21bc'
$$;
create function pg_temp.status(t uuid) returns text language sql security definer as $$
  select status::text from public.match_tickets where id = t
$$;
create temp table ids (k text primary key, id uuid);
grant all on ids to authenticated;
create function pg_temp.id(key text) returns uuid language sql as $$ select id from ids where k = key $$;

-- 2 号第 3 天在找，3 号第 4 天在找但关掉了可见
select pg_temp.login(2);
insert into ids select 't2', public.submit_ticket('singles', pg_temp.at(3, 18), pg_temp.at(3, 21), '{v-us-ca-21-badminton-club-21bc}', 2, false);
select pg_temp.login(3);
insert into ids select 't3', public.submit_ticket('singles', pg_temp.at(4, 18), pg_temp.at(4, 21), '{v-us-ca-21-badminton-club-21bc}', 2, false);

select pg_temp.login(1);
select is(jsonb_array_length(pg_temp.cards(3)), 1, '第 3 天能看到 2 号');
select is(pg_temp.cards(3) -> 0 -> 'user' ->> 'nickname', 'Card2', '卡片上有昵称');
select is(public.player_card(pg_temp.u(2)) ->> 'nickname', 'Card2', '卡片上的人能看资料');
select is(jsonb_array_length(pg_temp.cards(4)), 0, '关掉可见的看不到');

-- 左滑跳过就不再出现
select public.skip_candidate(pg_temp.id('t2'));
select is(jsonb_array_length(pg_temp.cards(3)), 0, '跳过后不再出现');
reset role;
delete from public.candidate_skips;

-- 右滑：给我们俩发提议，我这边已确认；2 号收到通知
select pg_temp.login(1);
insert into ids select 'offer', public.invite_ticket(pg_temp.id('t2'), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(3, 19));
select is(pg_temp.status(pg_temp.id('t2')), 'offered', '对方的请求收到提议');
reset role;
select is((select title from public.notifications where user_id = pg_temp.u(2) and kind = 'offer' order by id desc limit 1),
          'Card1 wants to play', '对方收到邀请通知');

-- 已经有提议的请求不能再约
select pg_temp.login(1);
select throws_ok($$ select public.invite_ticket(pg_temp.id('t2'), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(3, 19)) $$,
                 'P0002', 'not_available', '有提议了不能再约');

-- 对方确认就成局
select pg_temp.login(2);
select public.respond_offer(pg_temp.id('offer'), true);
select is(pg_temp.status(pg_temp.id('t2')), 'matched', '成局');
reset role;
select is((select count(*)::int from public.match_tickets where user_id = pg_temp.u(1) and status = 'matched'), 1, '我这边也成局');

select * from finish();
rollback;
