-- 同馆常客和球群消息请求：只在同球群之间、新账号不能发、对方能关掉、忽略对方不知道、回复就算接受、限量
begin;
create extension if not exists pgtap with schema extensions;
select plan(22);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000011' || lpad(n::text, 2, '0'))::uuid, 'q' || n || '@test.local' from generate_series(1, 7) n;
insert into public.profiles (id, nickname, discoverable)
  select ('00000000-0000-0000-0000-0000000011' || lpad(n::text, 2, '0'))::uuid,
         (array['Ava', 'Ben', 'Cal', 'Dee', 'Eve', 'Fay', 'Gus'])[n], false from generate_series(1, 7) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000011' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create function pg_temp.dm(n int) returns jsonb language sql as $$
  select t from jsonb_array_elements(public.my_threads()) t where t ->> 'kind' = 'dm' and t ->> 'id' = pg_temp.u(n)::text
$$;

-- 球群：Ava、Ben、Cal、Eve；Ava 打过 3 场（和 Dee），Cal 是新账号；Eve 关掉了消息请求
insert into public.play_groups (id, name, venue_id, owner_id, level_min, level_max, invite_code)
  values ('00000000-0000-0000-0000-000000001199', 'Sunday Club', 'v-us-ca-21-badminton-club-21bc', pg_temp.u(1), 1, 9, 'QQQQQQ');
insert into public.group_members (group_id, user_id, role)
  select '00000000-0000-0000-0000-000000001199', pg_temp.u(n), case when n = 1 then 'owner' else 'member' end::public.group_role
  from unnest(array[1, 2, 3, 5]) n;
with g as (
  insert into public.games (mode, starts_at, ends_at, venue_id)
    select 'singles', now() - k * interval '1 day', now() - k * interval '1 day' + interval '1 hour', 'v-us-ca-21-badminton-club-21bc'
    from generate_series(2, 4) k
  returning id)
insert into public.game_players (game_id, user_id, team, rating)
  select g.id, x.u, x.t, 3 from g, (values (pg_temp.u(1), 1), (pg_temp.u(4), 2)) x(u, t);
update public.profiles set allow_message_requests = false where id = pg_temp.u(5);

-- 能不能私信写在资料页上
select pg_temp.login(1);
select is(public.player_card(pg_temp.u(2)) -> 'message', '{"status": "request", "group": "Sunday Club"}', '同球群可以发一条请求（不带球群 id）');
select is(public.player_card(pg_temp.u(4)) -> 'message' ->> 'status', 'none', '一起打过球但不同群：先加好友');
select is(public.player_card(pg_temp.u(5)) -> 'message' ->> 'status', 'none', '对方关掉了消息请求');
select pg_temp.login(3);
select is(public.player_card(pg_temp.u(2)) -> 'message' ->> 'status', 'new_account', '打满 3 场前不能发');
select throws_ok($$ select public.send_message('dm', pg_temp.u(2), 'Hi') $$, '42501', 'chat_closed', '新账号发不出去');

-- 发请求：不能带联系方式，只能一条
select pg_temp.login(1);
select is(public.open_thread('dm', pg_temp.u(2)) ->> 'access', 'request', '还没发过：可以发请求');
select throws_ok($$ select public.send_message('dm', pg_temp.u(2), 'Text me 5551234567') $$, '22023', 'no_contact_info', '请求里不能留联系方式');
select lives_ok($$ select public.send_message('dm', pg_temp.u(2), 'Hi Ben, want to hit on Sunday?') $$, '发出请求');
select is(public.open_thread('dm', pg_temp.u(2)) ->> 'access', 'requested', '等对方接受');
select throws_ok($$ select public.send_message('dm', pg_temp.u(2), 'Hello?') $$, '22023', 'request_pending', '接受前不能再发');
select is(pg_temp.dm(2) ->> 'request', 'outgoing', '我的会话列表里有这条请求');

-- 收到的一方：有通知，会话列表里标着 incoming；忽略后看不到，对方不知道
select pg_temp.login(2);
select is(pg_temp.dm(1) ->> 'request', 'incoming', '收到的请求');
select is((pg_temp.dm(1) ->> 'unread')::int, 1, '算未读');
reset role;
select is((select title from public.notifications where user_id = pg_temp.u(2) and kind = 'message_request'), 'Ava wants to chat', '收到通知');
select pg_temp.login(2);
select public.respond_message_request(pg_temp.u(1), false);
select is(pg_temp.dm(1), null, '忽略后不再显示');
select pg_temp.login(1);
select is(public.open_thread('dm', pg_temp.u(2)) ->> 'access', 'requested', '对方忽略了，我这边还是“等待接受”');

-- 回复就算接受
select pg_temp.login(2);
select lives_ok($$ select public.send_message('dm', pg_temp.u(1), 'Sure, 10am?') $$, '忽略后也可以回复');
select pg_temp.login(1);
select is(pg_temp.dm(2) ->> 'access', 'open', '接受后可以继续聊');

-- 每天最多 10 条请求
reset role;
insert into auth.users (id, email) select gen_random_uuid(), 'extra' || n || '@test.local' from generate_series(1, 10) n;
insert into public.message_requests (from_id, to_id) select pg_temp.u(1), id from auth.users where email like 'extra%@test.local';
select pg_temp.login(1);
select throws_ok($$ select public.send_message('dm', pg_temp.u(3), 'Hi Cal') $$, '54000', 'too_many_message_requests', '一天最多 10 条');

-- 同馆常客：本人开启才出现，屏蔽了看不到；常客的资料能点开
reset role;
insert into public.favorite_venues (user_id, venue_id)
  select pg_temp.u(n), 'v-us-ca-21-badminton-club-21bc' from unnest(array[1, 6, 7]) n;
update public.profiles set show_as_regular = (id = pg_temp.u(6)) where id in (pg_temp.u(6), pg_temp.u(7));
select pg_temp.login(1);
select is((select array_agg(r ->> 'nickname') from jsonb_array_elements(public.venue_regulars()) r), '{Fay}', '只有开启了的常客');
select ok(public.player_card(pg_temp.u(6)) is not null and public.player_card(pg_temp.u(7)) is null, '能看常客的资料，没开启的看不到');
reset role;
insert into public.blocks (blocker, blocked) values (pg_temp.u(6), pg_temp.u(1));
select pg_temp.login(1);
select is(public.venue_regulars(), '[]', '屏蔽关系看不到');

select * from finish();
rollback;
