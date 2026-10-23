-- 昵称#编号和加球友链接：同名不同号、改名沿用编号、精确搜索、链接能加关了搜索的人、重置后旧链接失效
begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000019' || lpad(n::text, 2, '0'))::uuid, 't' || n || '@test.local' from generate_series(1, 5) n;
-- 1-3 号同名（不分大小写），编号指定；5 号同名、编号自动分配
insert into public.profiles (id, nickname, tag)
  select ('00000000-0000-0000-0000-0000000019' || lpad(n::text, 2, '0'))::uuid,
         (array['Kai', 'kai', 'Kai', 'Mira', 'KAI'])[n], (array[1, 2, 3, 1, null])[n] from generate_series(1, 5) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000019' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create function pg_temp.tag(n int) returns int language sql as $$
  select tag::int from public.profiles where id = pg_temp.u(n)
$$;
create function pg_temp.code(n int) returns text language sql as $$
  select friend_code from public.profiles where id = pg_temp.u(n)
$$;

-- 编号
select ok(pg_temp.tag(5) between 4 and 9999, '自动分配的编号不和同名的人重复');
select ok(pg_temp.code(5) ~ '^[a-hjkmnp-z2-9]{8}$', '注册时就有加球友链接');
select throws_ok(format('update public.profiles set tag = 1 where id = %L', pg_temp.u(2)), '23505', null, '同名同号不能重复');

-- 改名：新名字下这个号没人用就沿用，被占了就换
select pg_temp.login(4);
select lives_ok($$ update public.profiles set nickname = 'Mirabel' where id = auth.uid() $$, '可以改名');
reset role;
select is(pg_temp.tag(4), 1, '改名后编号不变');
update public.profiles set nickname = 'kAI' where id = pg_temp.u(4);
select ok(pg_temp.tag(4) not in (1, 2, 3, pg_temp.tag(5)), '改成重名、编号被占了就换一个');
update public.profiles set nickname = 'Mira' where id = pg_temp.u(4);

-- 精确搜索；3 号关了被搜到
update public.profiles set discoverable = false where id = pg_temp.u(3);
select set_config('test.code3', pg_temp.code(3), true);
select pg_temp.login(4);
select is(jsonb_array_length(public.find_players('kai')), 3, '只写昵称：所有允许被搜到的同名的人');
select is(public.find_players('KAI#2') -> 0 ->> 'id', pg_temp.u(2)::text, '昵称#编号精确找到');
select is(jsonb_array_length(public.find_players('kai#2')), 1, '只有这一个人');
select is(jsonb_array_length(public.find_players('kai#3')), 0, '关了被搜到的人用编号也搜不到');
select ok(public.find_players('kai') -> 0 ? 'tag', '结果带编号');

-- 加球友链接：关了搜索也能通过链接加
select ok(public.player_card(pg_temp.u(3)) is null, '没打开链接之前看不到资料');
select is(public.open_friend_link(upper(current_setting('test.code3'))), pg_temp.u(3), '打开链接拿到对方（不分大小写）');
select is(public.send_friend_request(pg_temp.u(3)), 'requested', '打开链接后可以加球友');
select is(public.open_friend_link('zzzzzzzz'), null, '错的码什么都拿不到');

-- 重置：旧链接失效
select pg_temp.login(3);
select isnt(public.reset_friend_code(), current_setting('test.code3'), '重置后是新链接');
select pg_temp.login(1);
select is(public.open_friend_link(current_setting('test.code3')), null, '旧链接失效');

select * from finish();
rollback;
