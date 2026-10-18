-- 球局（房间）：公开局按水平加入、满员候补和递补、受邀不看水平、房间码进私密局、开局分队、过期关闭、屏蔽、注销
begin;
create extension if not exists pgtap with schema extensions;
select plan(43);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000007' || lpad(n::text, 2, '0'))::uuid, 'r' || n || '@test.local' from generate_series(1, 8) n;
insert into public.profiles (id, nickname, rating)
  select ('00000000-0000-0000-0000-0000000007' || lpad(n::text, 2, '0'))::uuid, 'Room' || n,
         (array[4.33, 4, 5, 3, 4, 4, 8, 3.67])[n] from generate_series(1, 8) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000007' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create function pg_temp.notes(n int, k text) returns int language sql security definer as $$
  select count(*)::int from public.notifications where user_id = pg_temp.u(n) and kind = k
$$;
create function pg_temp.last_title(n int) returns text language sql security definer as $$
  select title from public.notifications where user_id = pg_temp.u(n) order by id desc limit 1
$$;
create function pg_temp.at(d int, h numeric) returns timestamptz language sql as $$
  select date_trunc('day', now()) + make_interval(days => d) + h * interval '1 hour'
$$;
create temp table ids (name text primary key, id uuid);
grant all on ids to authenticated;
create function pg_temp.id(k text) returns uuid language sql as $$ select id from ids where name = k $$;
create function pg_temp.room(k text) returns public.rooms language sql security definer as $$
  select * from public.rooms where id = pg_temp.id(k)
$$;
create function pg_temp.member(k text, n int) returns public.room_members language sql security definer as $$
  select * from public.room_members where room_id = pg_temp.id(k) and user_id = pg_temp.u(n)
$$;

-- 1 号和 4、8 号是球友；1 号屏蔽了 6 号
insert into public.friendships (user_a, user_b) values (least(pg_temp.u(1), pg_temp.u(4)), greatest(pg_temp.u(1), pg_temp.u(4))),
  (least(pg_temp.u(1), pg_temp.u(8)), greatest(pg_temp.u(1), pg_temp.u(8)));
insert into public.blocks (blocker, blocked) values (pg_temp.u(1), pg_temp.u(6));
update public.profiles set locale = 'zh-Hans' where id = pg_temp.u(8);

-- 权限
set local role anon;
select throws_ok($$ select public.rooms_near(37.5, -122) $$, '42501', null, '没登录不能看');
select pg_temp.login(2);
select throws_ok($$ select * from public.rooms $$, '42501', null, '表不能直接读');
select throws_ok($$ select public.close_room(gen_random_uuid(), 'expired') $$, '42501', null, '内部函数不能直接调');

-- 建公开局：时间、球馆、联系方式都要检查；房主水平一定在范围内
select pg_temp.login(1);
select throws_ok($$ select public.create_room('doubles', 'public', null, null, null, 5, 6) $$, '22023', 'missing_details', '公开局要有球馆和时间');
select throws_ok($$ select public.create_room('doubles', 'public', 'v-us-ca-21-badminton-club-21bc', now() - interval '1 hour', now() + interval '1 hour', 5, 6) $$,
                 '22023', 'too_soon', '不能是过去的时间');
select throws_ok($$ select public.create_room('doubles', 'public', 'v-us-ca-21-badminton-club-21bc', pg_temp.at(1, 19), pg_temp.at(1, 19.5), 5, 6) $$,
                 '22023', 'invalid_slot', '至少 1 小时');
select throws_ok($$ select public.create_room('doubles', 'public', 'v-us-ca-21-badminton-club-21bc', pg_temp.at(1, 19), pg_temp.at(1, 21), 5, 6, '{}', 'call 6265550123') $$,
                 '22023', 'no_contact_info', '备注里不能留联系方式');
insert into ids select 'public', public.create_room('doubles', 'public', 'v-us-ca-21-badminton-club-21bc', pg_temp.at(1, 19), pg_temp.at(1, 21),
                                                    5, 6, '{casual,casual}', ' Bring a shuttle ');
select is(array[(pg_temp.room('public')).level_min, (pg_temp.room('public')).level_max]::int[], array[4, 6], '范围放宽到包含房主的 4 级');
select is((pg_temp.room('public')).tags, '{casual}', '标签去重');
select is(public.room_page(pg_temp.id('public')) ->> 'my_status', 'owner', '房主');
select is(jsonb_array_length(public.room_page(pg_temp.id('public')) -> 'members'), 1, '房主自己在名单里');

-- 附近的公开局：屏蔽关系看不到、也加入不了
select pg_temp.login(2);
select ok(public.rooms_near(37.5, -122.0) @> jsonb_build_array(jsonb_build_object('id', pg_temp.id('public'))), '附近能看到');
select pg_temp.login(6);
select ok(not public.rooms_near(37.5, -122.0) @> jsonb_build_array(jsonb_build_object('id', pg_temp.id('public'))), '被屏蔽的人看不到');
select throws_ok($$ select public.join_room(pg_temp.id('public')) $$, 'P0002', 'room_not_found', '被屏蔽的人加入不了');
select pg_temp.login(7);
select throws_ok($$ select public.join_room(pg_temp.id('public')) $$, '22023', 'level_out_of_range', '水平不在范围内');

-- 加入：满了进候补（公开局最多 4 人候补）
select pg_temp.login(2); select is(public.join_room(pg_temp.id('public')), 'member', '2 号加入');
select is(pg_temp.notes(1, 'room'), 1, '房主收到通知');
select pg_temp.login(3); select public.join_room(pg_temp.id('public'));
select pg_temp.login(5); select public.join_room(pg_temp.id('public'));
select pg_temp.login(8); select is(public.join_room(pg_temp.id('public')), 'waitlisted', '满了，8 号候补');
select is(public.join_room(pg_temp.id('public')), 'waitlisted', '重复加入不报错');

select pg_temp.login(4);
select is(public.room_page(pg_temp.id('public')) ->> 'members', null, '外人看不到名单');
select is(public.room_page(pg_temp.id('public')) ->> 'code', null, '外人看不到房间码');
select is(array[(public.room_page(pg_temp.id('public')) ->> 'going')::int, (public.room_page(pg_temp.id('public')) ->> 'waitlist')::int],
          array[4, 1], '外人看得到人数');

-- 退出和移出：候补按顺序补上
select pg_temp.login(2); select public.leave_room(pg_temp.id('public'));
select is((pg_temp.member('public', 8)).waitlisted, false, '2 号退出，8 号补上');
select is(pg_temp.last_title(8), '候补成功，你已加入球局', '递补通知按收件人的语言');
select pg_temp.login(3);
select throws_ok($$ select public.remove_room_member(pg_temp.id('public'), pg_temp.u(5)) $$, '42501', 'not_room_owner', '只有房主能移人');
select pg_temp.login(1); select public.remove_room_member(pg_temp.id('public'), pg_temp.u(3));
select is(pg_temp.notes(3, 'room_removed'), 1, '被移出的人收到通知');

-- 人不齐不能开局；邀请球友（受邀不看水平）
select throws_ok($$ select public.start_room(pg_temp.id('public')) $$, '22023', 'not_enough_players', '人不齐不能开局');
select is(public.invite_to_room(pg_temp.id('public'), array[pg_temp.u(4), pg_temp.u(7), pg_temp.u(8)]), 1, '只邀请了不在房间里的球友');
select pg_temp.login(4);
select ok(public.my_rooms() @> jsonb_build_array(jsonb_build_object('id', pg_temp.id('public'), 'my_status', 'invited')), '受邀的人在我的房间里看得到');
select is(public.join_room(pg_temp.id('public')), 'member', '受邀的 3 级球友能加入 4–6 级的局');

-- 开局：双打按水平 1、4 名一队；候补的人另行通知
select pg_temp.login(1);
insert into ids select 'game', public.start_room(pg_temp.id('public'));
reset role;
select is((pg_temp.room('public')).status, 'started', '已开局');
select is((select count(*)::int from public.game_players where game_id = pg_temp.id('game')), 4, '生成 4 人的球局');
select is((select array_agg(user_id order by user_id) from public.game_players where game_id = pg_temp.id('game') and team = 1),
          array[pg_temp.u(1), pg_temp.u(4)], '最高和最低一队');
select is(pg_temp.notes(5, 'matched'), 1, '球友收到约成通知（会发邮件）');
select pg_temp.login(1);
select throws_ok($$ select public.create_room('singles', 'public', 'v-us-ca-21-badminton-club-21bc', pg_temp.at(1, 20), pg_temp.at(1, 22), 4, 4) $$,
                 '23P01', 'overlapping', '和已有球局时间冲突');

-- 私密局：只能凭房间码进；单打满了直接报满
select pg_temp.login(2);
insert into ids select 'private', public.create_room('singles', 'private', null, null, null, 1, 9);
select pg_temp.login(3);
select is(public.room_page(pg_temp.id('private')), null, '私密局外人看不到');
select throws_ok($$ select public.join_room(pg_temp.id('private')) $$, 'P0002', 'room_not_found', '不能直接加入私密局');
select is(public.join_room_code(lower((pg_temp.room('private')).code)), pg_temp.id('private'), '房间码不分大小写');
select pg_temp.login(4);
select throws_ok(format('select public.join_room_code(%L)', (pg_temp.room('private')).code), '54000', 'room_full', '私密局不候补');

-- 过期：没设时间的 30 分钟没动静、有时间的到点没开局
reset role;
update public.rooms set last_activity_at = now() - interval '31 minutes' where id = pg_temp.id('private');
select public.expire_rooms();
select is((pg_temp.room('private')).closed_reason, 'expired', '30 分钟没动静就关闭');
select is(pg_temp.notes(3, 'room_closed'), 1, '成员收到关闭通知');

-- 房主改时间通知成员；注销账号等于解散
select pg_temp.login(5);
insert into ids select 'later', public.create_room('doubles', 'public', 'v-us-ca-21-badminton-club-21bc', pg_temp.at(2, 19), pg_temp.at(2, 21), 3, 5);
select pg_temp.login(2); select public.join_room(pg_temp.id('later'));
select pg_temp.login(5); select public.update_room(pg_temp.id('later'), 'v-us-ca-21-badminton-club-21bc', pg_temp.at(2, 18), pg_temp.at(2, 20));
select is(pg_temp.last_title(2), 'Game details changed', '改时间通知成员');
select public.delete_account();
select is(pg_temp.last_title(2), 'Game cancelled', '房主注销，成员收到取消通知');

select * from finish();
rollback;
