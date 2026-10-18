-- 按昵称搜球友：只搜得到愿意被搜到的人、屏蔽互相看不到、通配符不生效、限速；搜到的人可以看资料和加球友
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000009' || lpad(n::text, 2, '0'))::uuid, 's' || n || '@test.local' from generate_series(1, 6) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000009' || lpad(n::text, 2, '0'))::uuid,
         (array['Searcher', 'Alicia', 'alice', 'Alina', 'Bob', 'Alfred'])[n] from generate_series(1, 6) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000009' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create function pg_temp.names(q text) returns text[] language sql as $$
  select coalesce(array_agg(x ->> 'nickname' order by n), '{}') from jsonb_array_elements(public.find_players(q)) with ordinality as r(x, n)
$$;

-- 4 号不让别人搜到；6 号屏蔽了 1 号
update public.profiles set discoverable = false where id = pg_temp.u(4);
insert into public.blocks (blocker, blocked) values (pg_temp.u(6), pg_temp.u(1));

set local role anon;
select throws_ok($$ select public.find_players('ali') $$, '42501', null, '没登录不能搜');

select pg_temp.login(1);
select is(pg_temp.names('a'), '{}', '至少 2 个字');
select is(pg_temp.names('ALI'), '{alice,Alicia}', '开头匹配、不分大小写；不让搜的和屏蔽关系的不出现');
select is(pg_temp.names('alice'), '{alice}', '完全一样的在前');
select is(pg_temp.names('%e'), '{}', '% 不当通配符');
select is(pg_temp.names('al_ce'), '{}', '_ 不当通配符');
select is(public.find_players('alicia') -> 0 ->> 'relationship', 'none', '还不是球友');

-- 搜到的人可以看资料、加球友；不让搜的人看不到
select ok(public.player_card(pg_temp.u(2)) is not null, '可以看搜到的人的资料');
select ok(public.player_card(pg_temp.u(4)) is null, '不让搜的陌生人看不到资料');
select is(public.send_friend_request(pg_temp.u(2)), 'requested', '可以加搜到的人');
select is(public.find_players('alicia') -> 0 ->> 'relationship', 'requested', '结果里显示已申请');

-- 自己可以关掉
select pg_temp.login(2);
select lives_ok($$ update public.profiles set discoverable = false where id = pg_temp.u(2) $$, '本人可以关掉被搜到');

-- 限速：10 分钟 30 次
select pg_temp.login(5);
select public.find_players('al') from generate_series(1, 30);
select throws_ok($$ select public.find_players('al') $$, '54000', 'too_many_searches', '第 31 次被限流');
reset role;
select is((select count(*)::int from public.player_searches where user_id = pg_temp.u(5)), 30, '只记次数，不记搜了什么');

select * from finish();
rollback;
