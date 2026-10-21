-- 聊天推送：私信、球局群聊、球群群聊推给会话里的其他人；自己、没设备的、互相拉黑的不推；
-- 消息请求只推请求；推送服务取活时带上发消息的人，取走就删，过时的不推；客户端碰不到
begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

-- 1 号发消息；1、2 号是球友；1、2、3 号打一场球；1 号的球群里有 3、4、5 号；4 号拉黑了 1 号；5 号没有设备
insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000008' || lpad(n::text, 2, '0'))::uuid, 'c' || n || '@test.local' from generate_series(1, 5) n;
insert into public.profiles (id, nickname, rating, gender)
  select ('00000000-0000-0000-0000-0000000008' || lpad(n::text, 2, '0'))::uuid, 'Chat' || n, 3, 'male' from generate_series(1, 5) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000008' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create function pg_temp.pushes(n int) returns int language sql security definer as $$
  select count(*)::int from public.chat_pushes where user_id = pg_temp.u(n)
$$;
create function pg_temp.last_push(n int) returns public.chat_pushes language sql security definer as $$
  select * from public.chat_pushes where user_id = pg_temp.u(n) order by id desc limit 1
$$;

insert into public.friendships (user_a, user_b) values (least(pg_temp.u(1), pg_temp.u(2)), greatest(pg_temp.u(1), pg_temp.u(2)));
insert into public.push_devices (user_id, kind, token)
  select pg_temp.u(n), 'apns', repeat(n::text, 64) from unnest(array[1, 2, 3, 4]) n;
insert into public.push_devices (user_id, kind, token, keys)
  values (pg_temp.u(2), 'web', 'https://fcm.googleapis.com/fcm/send/chat2', '{"p256dh": "k", "auth": "a"}');
insert into public.blocks (blocker, blocked) values (pg_temp.u(4), pg_temp.u(1));

create temp table ids (name text primary key, id uuid);
grant all on ids to authenticated;
insert into public.games (mode, starts_at, ends_at, venue_id)
  values ('singles', now() + interval '1 day', now() + interval '1 day 2 hours', 'v-us-ca-21-badminton-club-21bc');
insert into ids select 'game', id from public.games where venue_id = 'v-us-ca-21-badminton-club-21bc' order by starts_at desc limit 1;
insert into public.game_players (game_id, user_id, team, rating)
  select (select id from ids where name = 'game'), pg_temp.u(n), case when n = 1 then 1 else 2 end, 3 from unnest(array[1, 2, 3]) n;

-- 私信：推给对方，标题是发消息的人，点开是和他的私信；自己不推
select pg_temp.login(1);
select public.send_message('dm', pg_temp.u(2), 'Same time next week?');
reset role;
select is(pg_temp.pushes(2), 1, '私信推给对方');
select is(pg_temp.pushes(1), 0, '自己发的不推给自己');
select is((pg_temp.last_push(2)).title, 'Chat1', '标题是发消息的人');
select is((pg_temp.last_push(2)).link, '/messages/dm/' || pg_temp.u(1) || '/', '点开是和他的私信');
select is((pg_temp.last_push(2)).group_name, null, '私信没有群名');

-- 推送里的消息也换掉不当词
select pg_temp.login(1);
select public.send_message('dm', pg_temp.u(2), 'you are a b1tch');
reset role;
select is((pg_temp.last_push(2)).body, 'you are a ***', '推送里的不当词也换成 ***');

-- 球局群聊：推给另外两个人，群名是球馆名，人数 3
select pg_temp.login(1);
select public.send_message('game', (select id from ids where name = 'game'), 'Bring shuttles?');
reset role;
select is(pg_temp.pushes(3), 1, '球局群聊推给其他球员');
select is((pg_temp.last_push(3)).group_name, (select name from public.venues where id = 'v-us-ca-21-badminton-club-21bc'), '球局群聊的群名是球馆名');
select is((pg_temp.last_push(3)).members, 3, '会话里一共 3 个人');
select is((pg_temp.last_push(3)).body, 'Chat1: Bring shuttles?', '群聊的内容前面是发消息的人');

-- 球群群聊：标题是球群名，内容带发消息的人；拉黑了的、没设备的不推
select pg_temp.login(1);
insert into ids select 'group', public.create_group('Thursday Smash', 'v-us-ca-21-badminton-club-21bc', '', 1, 9, 'open',
                                                   '[{"weekday": 5, "start": 1140, "end": 1260, "capacity": 8}]');
reset role;
insert into public.group_members (group_id, user_id) select (select id from ids where name = 'group'), pg_temp.u(n) from unnest(array[3, 4, 5]) n;
select pg_temp.login(1);
select public.send_message('group', (select id from ids where name = 'group'), 'Court 3 tonight');
reset role;
select is((pg_temp.last_push(3)).title, 'Thursday Smash', '球群群聊的标题是球群名');
select is((pg_temp.last_push(3)).body, 'Chat1: Court 3 tonight', '内容前面是发消息的人');
select is(pg_temp.pushes(4), 0, '拉黑了发消息的人就不推');
select is(pg_temp.pushes(5), 0, '没有设备的不排队');

-- 消息请求（同一个球群、不是球友）：只推“想和你聊天”那条通知，消息本身不推
-- （新账号不能发请求：先让 1 号打满 3 场）
with g as (
  insert into public.games (mode, starts_at, ends_at, venue_id)
    select 'singles', now() - k * interval '1 day', now() - k * interval '1 day' + interval '1 hour', 'v-us-ca-21-badminton-club-21bc'
    from generate_series(3, 5) k
  returning id)
insert into public.game_players (game_id, user_id, team, rating)
  select g.id, x.u, x.t, 3 from g, (values (pg_temp.u(1), 1), (pg_temp.u(2), 2)) x(u, t);
select pg_temp.login(1);
select public.send_message('dm', pg_temp.u(3), 'Hi from the group');
reset role;
select is(pg_temp.pushes(3), 2, '消息请求不另外推消息（3 号只有球局和球群的两条）');

-- 客户端看不到排队表，也不能自己排队
select pg_temp.login(2);
select throws_ok($$ select * from public.chat_pushes $$, '42501', null, '客户端不能读排队表');
select throws_ok(format($$ select public.queue_chat_push('dm', %L, 'x', %L, 'spam') $$, pg_temp.u(2), pg_temp.u(1)),
                 '42501', null, '客户端不能自己排队');
reset role;

-- 推送服务取活：每台设备一条，带上发消息的人；取走就删；2 分钟前的不推
insert into public.chat_pushes (user_id, thread, sender_id, title, body, link, created_at)
  values (pg_temp.u(2), 'dm:x', pg_temp.u(1), 'Old', 'stale', '/messages/', now() - interval '5 minutes');
create temp table batch as select public.claim_push_batch() as items;
select is((select count(*)::int from batch, jsonb_array_elements(items) i where i -> 'chat' ->> 'name' = 'Chat1' and i ->> 'kind' = 'web'),
          3, '2 号的浏览器也收到（两条私信、一条球局群聊）');
select is((select count(*)::int from batch, jsonb_array_elements(items) i where i ->> 'title' = 'Old'), 0, '过时的不推');
select is((select count(*)::int from public.chat_pushes), 0, '取走就从队里删掉');

select * from finish();
rollback;
