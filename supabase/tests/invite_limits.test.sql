-- 一次右滑很多张：同一天最多同时等 3 个人回复；时间重叠的邀请也能发，有人接受成局后其余的自动撤回
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000037' || lpad(n::text, 2, '0'))::uuid, 'il' || n || '@test.local' from generate_series(1, 6) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000037' || lpad(n::text, 2, '0'))::uuid, 'Lim' || n from generate_series(1, 6) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000037' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create function pg_temp.at(d int, h int) returns timestamptz language sql as $$
  select date_trunc('day', now()) + make_interval(days => d, hours => h)
$$;
create function pg_temp.status(t uuid) returns text language sql security definer as $$
  select status::text from public.match_tickets where id = t
$$;
create temp table ids (k text primary key, id uuid);
grant all on ids to authenticated;
create function pg_temp.id(key text) returns uuid language sql as $$ select id from ids where k = key $$;

-- 2–5 号第 3 天晚上都在找单打（直接写进去：用 submit_ticket 的话他们会先互相配上）
insert into ids select 't' || n, gen_random_uuid() from generate_series(2, 5) n;
insert into public.match_tickets (id, user_id, mode, starts_at, ends_at, venue_ids, skill_tolerance, auto_accept, lock_at, last_minute, status)
  select pg_temp.id('t' || n), pg_temp.u(n), 'singles', pg_temp.at(3, 18), pg_temp.at(3, 21), '{v-us-ca-21-badminton-club-21bc}', 2, false,
         pg_temp.at(3, 16), false, 'searching'
  from generate_series(2, 5) n;

-- 1 号连着右滑：时间都重叠，前 3 个都能发出去，第 4 个超了
select pg_temp.login(1);
insert into ids select 'o2', public.invite_ticket(pg_temp.id('t2'), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(3, 18));
select lives_ok($$ insert into ids select 'o3', public.invite_ticket(pg_temp.id('t3'), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(3, 18)) $$,
                '时间重叠的邀请也能发');
insert into ids select 'o4', public.invite_ticket(pg_temp.id('t4'), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(3, 19));
select throws_ok($$ select public.invite_ticket(pg_temp.id('t5'), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(3, 18)) $$,
                 '54000', 'too_many_invites', '同一天最多同时等 3 个人回复');

-- 2 号接受：成局；和这场重叠的另外两份邀请自动撤回，3、4 号的请求接着找人，并收到通知
select pg_temp.login(2);
select public.respond_offer(pg_temp.id('o2'), true);
reset role;
select is(pg_temp.status(pg_temp.id('t2')), 'matched', '先接受的成局');
select is((select status::text from public.match_offers where id = pg_temp.id('o3')), 'failed', '重叠的邀请撤回了');
select is(pg_temp.status(pg_temp.id('t3')), 'searching', '对方的请求接着找人');
select is(pg_temp.status(pg_temp.id('t4')), 'searching', '19 点那份也重叠，也撤回');
select is((select title from public.notifications where user_id = pg_temp.u(3) order by id desc limit 1), 'Invite withdrawn', '对方收到撤回通知');
select is((select count(*)::int from public.match_tickets where user_id = pg_temp.u(1) and status in ('searching', 'offered')), 0,
          '我为邀请建的请求都取消了，不留着');

select * from finish();
rollback;
