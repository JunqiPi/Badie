-- 爽约三档处罚：多数人说没来才算；第 1 次警告、第 2 次 7 天不能约球、第 3 次永久；180 天后重新计数；
-- 48 小时内申诉、申诉期间不执行；管理员维持或撤销；资料卡显示近 180 天次数
begin;
create extension if not exists pgtap with schema extensions;
select plan(21);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000029' || lpad(n::text, 2, '0'))::uuid, 'k' || n || '@test.local' from generate_series(1, 8) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000029' || lpad(n::text, 2, '0'))::uuid, 'Strike' || n from generate_series(1, 8) n;
insert into public.admin_users (user_id, role) values ('00000000-0000-0000-0000-000000002908', 'owner');

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000029' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
-- 1 小时前结束的单打：1 号没签到，对手说他没来
create function pg_temp.missed(opponent int) returns void language plpgsql as $$
declare
  id uuid;
begin
  reset role;
  insert into public.games (mode, starts_at, ends_at, venue_id, review_prompted)
    values ('singles', now() - interval '3 hours', now() - interval '1 hour', 'v-us-ca-21-badminton-club-21bc', true) returning games.id into id;
  insert into public.game_players (game_id, user_id, team, rating) values (id, pg_temp.u(1), 1, 3), (id, pg_temp.u(opponent), 2, 3);
  perform pg_temp.login(opponent);
  perform public.review_player(id, pg_temp.u(1), 'no_show', 'accurate', '{}', '{}', false);
  reset role;
end
$$;
create function pg_temp.strike(lvl int) returns bigint language sql security definer as $$
  select id from public.strikes where user_id = pg_temp.u(1) and level = lvl order by id desc limit 1
$$;
create function pg_temp.ticket(d int) returns uuid language sql as $$
  select public.submit_ticket('singles', date_trunc('day', now()) + make_interval(days => d) + interval '18 hours',
                              date_trunc('day', now()) + make_interval(days => d) + interval '20 hours', '{v-us-ca-21-badminton-club-21bc}', 2, false)
$$;

-- 签到了：有人说没来也不算
reset role;
insert into public.games (id, mode, starts_at, ends_at, venue_id, review_prompted)
  values ('00000000-0000-0000-0000-00000000290a', 'singles', now() - interval '3 hours', now() - interval '1 hour', 'v-us-ca-21-badminton-club-21bc', true);
insert into public.game_players (game_id, user_id, team, rating, checked_in_at)
  values ('00000000-0000-0000-0000-00000000290a', pg_temp.u(1), 1, 3, now() - interval '2 hours'), ('00000000-0000-0000-0000-00000000290a', pg_temp.u(7), 2, 3, null);
select pg_temp.login(7);
select public.review_player('00000000-0000-0000-0000-00000000290a', pg_temp.u(1), 'no_show', 'accurate', '{}', '{}', false);
-- 双打：另外 3 人里只有 1 人说没来，不算
reset role;
insert into public.games (id, mode, starts_at, ends_at, venue_id, review_prompted)
  values ('00000000-0000-0000-0000-00000000290b', 'doubles', now() - interval '3 hours', now() - interval '1 hour', 'v-us-ca-21-badminton-club-21bc', true);
insert into public.game_players (game_id, user_id, team, rating)
  select '00000000-0000-0000-0000-00000000290b', pg_temp.u(n), case when n in (1, 6) then 1 else 2 end, 3 from unnest(array[1, 6, 7, 5]) n;
select pg_temp.login(6);
select public.review_player('00000000-0000-0000-0000-00000000290b', pg_temp.u(1), 'no_show', 'accurate', '{}', '{}', false);
select pg_temp.login(1);
select is((public.my_strikes() ->> 'recent')::int, 0, '签到了、或双打只有 1 人说没来：都不算爽约');

-- 第 1 次：警告，还能约球
select pg_temp.missed(2);
select pg_temp.login(1);
select is((public.my_strikes() ->> 'recent')::int, 1, '第 1 次记下');
select is(public.my_strikes() ->> 'suspended_until', null, '第 1 次只警告');
select is((public.my_strikes() -> 'strikes' -> 0 ->> 'can_appeal')::boolean, true, '48 小时内可以申诉');
select isnt(pg_temp.ticket(3), null, '警告后还能匹配');
reset role;
select is((select count(*)::int from public.notifications where user_id = pg_temp.u(1) and kind = 'strike'), 1, '收到通知');

-- 第 2 次：7 天不能约球
select pg_temp.missed(3);
select pg_temp.login(1);
select ok((public.my_strikes() ->> 'suspended_until')::timestamptz between now() + interval '6 days 23 hours' and now() + interval '7 days 1 minute',
          '第 2 次：7 天不能约球');
select throws_ok($$ select pg_temp.ticket(4) $$, '42501', 'suspended', '不能约球时不能匹配');
reset role;
select is((select status::text from public.match_tickets where user_id = pg_temp.u(1) order by created_at limit 1), 'cancelled',
          '之前在找的请求一并取消');
select pg_temp.login(1);

-- 申诉：期间不执行
select throws_ok($$ select public.appeal_strike(pg_temp.strike(2), 'no') $$, '22023', 'invalid_appeal', '要写明情况');
select lives_ok($$ select public.appeal_strike(pg_temp.strike(2), 'I was there, forgot to check in.') $$, '可以申诉');
select is(public.my_strikes() ->> 'suspended_until', null, '申诉期间不执行');
select isnt(pg_temp.ticket(5), null, '申诉期间可以约球');

-- 管理员维持：从现在开始执行
select pg_temp.login(8);
select is(jsonb_array_length(public.admin_strike_appeals()), 1, '管理员看到待处理的申诉');
select public.admin_resolve_strike(pg_temp.strike(2), false, 'both opponents agree');
select pg_temp.login(1);
select isnt(public.my_strikes() ->> 'suspended_until', null, '维持后执行');

-- 第 3 次：永久；资料卡显示次数
select pg_temp.missed(4);
select pg_temp.login(1);
select is((public.my_strikes() ->> 'suspended_until')::timestamptz, 'infinity'::timestamptz, '第 3 次：永久不能约球');
select pg_temp.login(4);
select is((public.player_card(pg_temp.u(1)) ->> 'recent_no_shows')::int, 3, '资料卡显示近 180 天爽约次数');

-- 撤销：不再计入记录
select pg_temp.login(1);
select public.appeal_strike(pg_temp.strike(3), 'Game was moved, I told them in chat.');
select pg_temp.login(8);
select public.admin_resolve_strike(pg_temp.strike(3), true);
select pg_temp.login(1);
select is((public.my_strikes() ->> 'suspended_until')::timestamptz, now() + interval '7 days', '撤销第 3 次：回到第 2 次的 7 天');

-- 超过 48 小时不能申诉
reset role;
update public.strikes set created_at = now() - interval '3 days' where id = pg_temp.strike(1);
select pg_temp.login(1);
select throws_ok(format('select public.appeal_strike(%s, %L)', pg_temp.strike(1), 'I was there.'), '22023', 'appeal_closed', '超过 48 小时不能申诉');

-- 申诉 7 天没人处理：自动维持
reset role;
update public.strikes set status = 'appealed', appealed_at = now() - interval '8 days' where id = pg_temp.strike(1);
select public.expire_appeals();
select is((select status from public.strikes where id = pg_temp.strike(1)), 'upheld', '7 天没处理的申诉自动维持');

-- 180 天没再爽约：重新从第 1 次算
reset role;
update public.strikes set created_at = now() - interval '200 days', starts_at = now() - interval '200 days' where user_id = pg_temp.u(1);
select pg_temp.missed(5);
select is((select level::int from public.strikes where user_id = pg_temp.u(1) order by id desc limit 1), 1, '180 天后重新计数');

select * from finish();
rollback;
