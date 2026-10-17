-- 胜率、榜单和约战测试（与 iOS RankingTests、ChallengeTests 的规则一致）
begin;
create extension if not exists pgtap with schema extensions;
select plan(27);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000004' || lpad(n::text, 2, '0'))::uuid, 'r' || n || '@test.local' from generate_series(1, 10) n;
insert into public.profiles (id, nickname, country_code, created_at)
  select ('00000000-0000-0000-0000-0000000004' || lpad(n::text, 2, '0'))::uuid, 'Rank' || n, 'US', now() - interval '10 days'
  from generate_series(1, 10) n;
update public.profiles set created_at = now() where id = '00000000-0000-0000-0000-000000000408';
update public.profiles set rating = 6 where id = '00000000-0000-0000-0000-000000000409';

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000004' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
-- 一场双方确认过的单打：本周和本月开头之后第 k 分钟开始，winner 赢
create function pg_temp.played(k int, a int, b int, winner int) returns void language plpgsql as $$
declare
  id uuid;
  start timestamptz := greatest(date_trunc('week', now() at time zone 'UTC') at time zone 'UTC', date_trunc('month', now())) + k * interval '1 minute';
begin
  insert into public.games (mode, starts_at, ends_at, venue_id) values ('singles', start, start + interval '1 hour', 'v-us-ca-21-badminton-club-21bc')
    returning games.id into id;
  insert into public.game_players (game_id, user_id, team, rating)
    select id, pg_temp.u(p), t, (select rating from public.profiles where profiles.id = pg_temp.u(p)) from (values (a, 1), (b, 2)) x(p, t);
  insert into public.result_reports (game_id, reporter_id, outcome)
    select id, pg_temp.u(p), case when winner = a then 'team1' else 'team2' end::public.result_outcome from unnest(array[a, b]) p;
end
$$;
create function pg_temp.entry(board jsonb, n int) returns jsonb language sql as $$
  select e from jsonb_array_elements(board -> 'entries') e where e ->> 'id' = pg_temp.u(n)::text
$$;

-- 1 号：赢 2 号 4 场（同一对手每月最多计 3 场）、赢 3 号 1 场、输给 4 号 1 场
select pg_temp.played(10, 1, 2, 1);
select pg_temp.played(11, 1, 3, 1);
select pg_temp.played(12, 1, 2, 1);
select pg_temp.played(13, 1, 2, 1);
select pg_temp.played(14, 1, 2, 1);
select pg_temp.played(15, 1, 4, 4);
-- 5 号：赢 6 号、赢 7 号、输给 6 号；8 号是新账号
select pg_temp.played(20, 5, 6, 5);
select pg_temp.played(21, 5, 7, 5);
select pg_temp.played(22, 5, 6, 6);
select pg_temp.played(30, 8, 9, 8);
select pg_temp.played(31, 8, 10, 8);
select pg_temp.played(32, 8, 9, 8);

-- 月度胜率
reset role;
select is(public.win_rate(pg_temp.u(1)) ->> 'games', '5', '同一对手每月最多计 3 场');
select is(public.win_rate(pg_temp.u(1)) ->> 'wins', '4', '胜场');
select is(public.win_rate(pg_temp.u(1)) ->> 'opponents', '3', '不同对手数');
select is(public.win_rate(pg_temp.u(1)) ->> 'public', 'true', '满 5 场公开');
select is(public.win_rate(pg_temp.u(5)) ->> 'public', 'false', '不满 5 场不公开');

select pg_temp.login(2);
select is(public.player_card(pg_temp.u(1)) -> 'win_rate' ->> 'wins', '4', '别人能看到公开的胜率');
select pg_temp.login(6);
select is(public.player_card(pg_temp.u(5)) -> 'win_rate', 'null'::jsonb, '不满 5 场别人看不到');
select pg_temp.login(5);
select is(public.player_card(pg_temp.u(5)) -> 'win_rate' ->> 'games', '3', '自己总能看到');
select pg_temp.login(1);
select is((public.my_record() ->> 'losses')::int, 1, '战绩里的负场');

-- 全球周榜：输 10 赢 15，同一对手第 2 场减半、第 3 场起不计
select is(pg_temp.entry(public.weekly_board('global'), 1) ->> 'points', '48', '15 + 15 + 7.5 + 0 + 0 + 10 ≈ 48');
select is(pg_temp.entry(public.weekly_board('global'), 5) ->> 'points', '35', '15 + 15 + 10 × 0.5');
select is(pg_temp.entry(public.weekly_board('global'), 1) ->> 'rank', '1', '积分高的排前面');
select is(pg_temp.entry(public.weekly_board('global'), 6), null, '不满 3 场不上榜');
select is(pg_temp.entry(public.weekly_board('global'), 8), null, '注册不满 7 天不上榜');
select is(public.weekly_board('global') -> 'me' ->> 'rank', '1', '总能看到我的位置');
select pg_temp.login(5);
select is(public.weekly_board('global') -> 'progress' ->> 'games', '3', '没上榜也能看到自己的进度');
update public.profiles set show_on_boards = false where id = pg_temp.u(5);
select is(pg_temp.entry(public.weekly_board('global'), 5), null, '可以关闭上榜');
update public.profiles set show_on_boards = true where id = pg_temp.u(5);

-- 场馆月榜：每天最多计 3 场；至少 3 场、2 位对手
select pg_temp.login(1);
select is((select e ->> 'games' from jsonb_array_elements(public.venue_board('v-us-ca-21-badminton-club-21bc') -> 'bands' -> 0 -> 'entries') e
           where e ->> 'id' = pg_temp.u(1)::text), '3', '同一天最多计 3 场');
select is((select e ->> 'rank' from jsonb_array_elements(public.venue_board('v-us-ca-21-badminton-club-21bc') -> 'bands' -> 0 -> 'entries') e
           where e ->> 'id' = pg_temp.u(5)::text), '2', '场数相同比胜场：1 号是馆主，5 号第二');

-- 约战
select is(public.player_card(pg_temp.u(2)) ->> 'challenge', 'available', '水平相近的人可以挑战');
select lives_ok($$ select public.send_challenge(pg_temp.u(2), 'v-us-ca-21-badminton-club-21bc',
                                               date_trunc('hour', now()) + interval '1 day', date_trunc('hour', now()) + interval '1 day 2 hours', 'Rematch?') $$,
                '发起挑战');
select is(public.player_card(pg_temp.u(2)) ->> 'challenge', 'already_pending', '等回应时不能重复挑战');
select pg_temp.login(2);
select public.respond_challenge((public.my_challenges() -> 'incoming' -> 0 ->> 'id')::uuid, false);
select pg_temp.login(1);
select is(public.my_challenges() -> 'outgoing' -> 0 ->> 'status', 'not_happening', '被拒绝只显示“未成行”');
select is(public.player_card(pg_temp.u(2)) ->> 'challenge', 'cooldown', '被拒后 7 天内不能再挑战同一人');

select public.send_challenge(pg_temp.u(3), 'v-us-ca-21-badminton-club-21bc',
                             date_trunc('hour', now()) + interval '2 days', date_trunc('hour', now()) + interval '2 days 1 hour', '');
select pg_temp.login(3);
select isnt(public.respond_challenge((public.my_challenges() -> 'incoming' -> 0 ->> 'id')::uuid, true), null, '接受后生成球局');
select pg_temp.login(4);
update public.profiles set challenge_policy = 'nobody' where id = pg_temp.u(4);
select pg_temp.login(1);
select is(public.player_card(pg_temp.u(4)) ->> 'challenge', 'hidden', '不接受挑战的人不显示按钮');
select throws_ok($$ select * from public.challenges $$, '42501', null, '约战表不能直接读');

select * from finish();
rollback;
