-- 高水平认证：证据按类型检查、同时只能一份、管理员审核、认证后等级不超过认证档位、最多往下拉 1 档
begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000014' || lpad(n::text, 2, '0'))::uuid, 'v' || n || '@test.local' from generate_series(1, 8) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000014' || lpad(n::text, 2, '0'))::uuid, 'Ver' || chr(64 + n) from generate_series(1, 8) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000014' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
insert into public.admin_users (user_id) values (pg_temp.u(2));

-- 证据按类型检查
select pg_temp.login(1);
select throws_ok($$ select public.request_verification('tournament', 7, 'https://example.com/results', 'Alex Chen') $$,
                 '22023', 'invalid_evidence', '赛事成绩要 tournamentsoftware.com');
select throws_ok($$ select public.request_verification('bwf', 9, 'bwfbadminton.com/rankings', 'Alex Chen') $$,
                 '22023', 'invalid_evidence', 'BWF 要具体的球员页');
select throws_ok($$ select public.request_verification('bwf', 8, 'bwfbadminton.com/player/123/alex', 'Alex Chen') $$,
                 '22023', 'invalid_level', 'BWF 从 9− 起');
select throws_ok($$ select public.request_verification('national', 8, '123456789012342', 'Alex Chen') $$,
                 '22023', 'invalid_level', '二级证书最高 7');
select lives_ok($$ select public.request_verification('national', 7, '123456789012342', 'Alex Chen') $$, '二级证书申请 7');
select throws_ok($$ select public.request_verification('bwf', 9, 'bwfbadminton.com/player/123/alex', 'Alex Chen') $$,
                 '22023', 'verification_pending', '同时只能一份');
select is(public.my_verification() ->> 'status', 'pending', '能看到自己的申请');
select ok(not public.my_verification() ? 'user_id', '不带用户 id');

-- 只有管理员能审核
select pg_temp.login(3);
select throws_ok($$ select public.admin_verification_queue() $$, '42501', 'admin_only', '普通用户看不到审核队列');
reset role;
insert into public.admin_users (user_id) values (pg_temp.u(1));
select pg_temp.login(1);
select throws_ok($$ select public.admin_review_verification((public.admin_verification_queue() -> 0 ->> 'id')::uuid, 7) $$,
                 '42501', 'not_allowed', '管理员不能审核自己的申请');
reset role;
delete from public.admin_users where user_id = pg_temp.u(1);
select pg_temp.login(2);
select is(jsonb_array_length(public.admin_verification_queue()), 1, '管理员看到待审核的申请');
select public.admin_review_verification((public.admin_verification_queue() -> 0 ->> 'id')::uuid, 7);
reset role;
select is((select array[verified_kind::text, rating::text] from public.profiles where id = pg_temp.u(1)), '{national,7.00}', '通过后显示认证档位');
select is((select title from public.notifications where user_id = pg_temp.u(1) and kind = 'verification'), 'Level verified: 7', '收到通知');

-- 认证后：球友评价最多往下拉 1 档，不会超过认证档位
insert into public.games (id, mode, starts_at, ends_at, venue_id)
  values ('00000000-0000-0000-0000-000000001499', 'singles', now() - interval '3 hours', now() - interval '2 hours', 'v-us-ca-21-badminton-club-21bc');
insert into public.game_reviews (game_id, reviewer_id, reviewee_id, attendance, level_check, peer_rating)
  select '00000000-0000-0000-0000-000000001499', pg_temp.u(n), pg_temp.u(1), 'on_time', 'lower', 5 from generate_series(4, 8) n;
select public.refresh_rating(pg_temp.u(1));
select is((select rating from public.profiles where id = pg_temp.u(1)), 6.67, '评价低也只往下拉 1 档');
update public.game_reviews set peer_rating = 9 where reviewee_id = pg_temp.u(1);
select public.refresh_rating(pg_temp.u(1));
select is((select rating from public.profiles where id = pg_temp.u(1)), 7.00, '评价高也不超过认证档位');

-- 不通过：带上说明；30 天内最多申请 3 次
select pg_temp.login(1);
select public.request_verification('national', 8.33, '12345678901234X', 'Alex Chen');
select pg_temp.login(2);
select public.admin_review_verification((public.admin_verification_queue() -> 0 ->> 'id')::uuid, null, 'Name doesn’t match');
reset role;
select is((select body from public.notifications where user_id = pg_temp.u(1) and title = 'Verification not approved'), 'Name doesn’t match',
          '不通过的说明发给本人');
select pg_temp.login(1);
select public.request_verification('national', 8.33, '12345678901234X', 'Alex Chen');
select public.withdraw_verification();
select throws_ok($$ select public.request_verification('national', 8.33, '12345678901234X', 'Alex Chen') $$,
                 '54000', 'too_many_verifications', '30 天内最多 3 次');

select * from finish();
rollback;
