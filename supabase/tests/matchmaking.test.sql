-- 约球规则测试（与 iOS MatchmakingTests / RankingTests 的规则一致）
begin;
create extension if not exists pgtap with schema extensions;
select plan(54);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000001' || lpad(n::text, 2, '0'))::uuid, 'm' || n || '@test.local' from generate_series(1, 13) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000001' || lpad(n::text, 2, '0'))::uuid, 'Player' || n from generate_series(1, 12) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000001' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
-- 第 n 天（UTC）h 点
create function pg_temp.at(d int, h numeric) returns timestamptz language sql as $$
  select date_trunc('day', now()) + make_interval(days => d) + h * interval '1 hour'
$$;
-- 测试里查看后台状态（客户端没有读表权限）
create function pg_temp.ticket(n int) returns public.match_tickets language sql security definer as $$
  select * from public.match_tickets where user_id = pg_temp.u(n) order by created_at desc, starts_at desc limit 1
$$;

-- 确认期限
select is(public.offer_respond_by('2026-10-25 19:00-07', '2026-10-20 08:00-07', 'America/Los_Angeles'),
          '2026-10-20 20:00-07'::timestamptz, '离开赛 ≥26 小时：给 12 小时');
select is(public.offer_respond_by('2026-10-25 19:00-07', '2026-10-20 15:00-07', 'America/Los_Angeles'),
          '2026-10-21 09:00-07'::timestamptz, '落在夜里：顺延到早上 9 点');
select is(public.offer_respond_by('2026-10-20 22:00-07', '2026-10-20 12:00-07', 'America/Los_Angeles'),
          '2026-10-20 14:00-07'::timestamptz, '离开赛 6–26 小时：给 2 小时');
select is(public.offer_respond_by('2026-10-20 15:00-07', '2026-10-20 12:45-07', 'America/Los_Angeles'),
          '2026-10-20 13:00-07'::timestamptz, '不晚于开赛前 2 小时');

-- 资料与等级
select pg_temp.login(1);
select is((select count(*)::int from public.profiles), 1, '只能读到自己的资料');
select throws_ok($$ update public.profiles set rating = 9 $$, '42501', null, '不能直接改等级');
select pg_temp.login(2);
select is((public.save_assessment(3.4, '{"answers": []}')).rating, 3.33, '问卷分数取整到档（3+）');
select throws_ok($$ select public.save_assessment(4, '{}') $$, '22023', null, '90 天内不能重测');
select throws_ok($$ select public.save_assessment(8, '{}') $$, '22023', null, '问卷最高 6+');
reset role;
select throws_ok($$ insert into public.profiles (id, nickname) values (pg_temp.u(13), 'call 5551234') $$,
                 '23514', null, '昵称不能留电话');

-- 发起请求的检查
select set_config('role', 'anon', true);
select throws_ok($$ select public.submit_ticket('singles', pg_temp.at(2, 18), pg_temp.at(2, 20), '{v-us-ca-21-badminton-club-21bc}', 1, false) $$,
                 '42501', null, '未登录不能发起');
select pg_temp.login(1);
select throws_ok($$ select public.submit_ticket('singles', now() + interval '1 hour', now() + interval '3 hours', '{v-us-ca-21-badminton-club-21bc}', 1, false) $$,
                 '22023', null, '开赛前 2.5 小时内不能发起');
select throws_ok($$ select public.submit_ticket('singles', pg_temp.at(2, 18.2), pg_temp.at(2, 20), '{v-us-ca-21-badminton-club-21bc}', 1, false) $$,
                 '22023', null, '时间要对齐半点');
select throws_ok($$ select public.submit_ticket('singles', pg_temp.at(2, 18), pg_temp.at(2, 20), '{no-such-venue}', 1, false) $$,
                 '22023', null, '球馆要存在');

-- 单打：1 号（3 级）和 2 号（3+）时间重叠 1 小时，同一家球馆
select lives_ok($$ select public.submit_ticket('singles', pg_temp.at(2, 18), pg_temp.at(2, 20), '{v-us-ca-21-badminton-club-21bc}', 1, false) $$,
                '登录后可以发起');
select is((pg_temp.ticket(1)).status::text, 'searching', '没人时挂着等');
select throws_ok($$ select * from public.match_tickets $$, '42501', null, '请求表不能直接读');
select pg_temp.login(2);
select lives_ok($$ select public.submit_ticket('singles', pg_temp.at(2, 19), pg_temp.at(2, 21),
                                               '{v-us-ca-almaden-community-center,v-us-ca-21-badminton-club-21bc}', 1, false) $$, '2 号发起');
reset role;
select is((select array[status::text, (select status::text from public.match_tickets where user_id = pg_temp.u(2))] from public.match_tickets where user_id = pg_temp.u(1)),
          '{offered,offered}', '两人都收到提议');
select is((select array[starts_at, ends_at] from public.match_offers), array[pg_temp.at(2, 19), pg_temp.at(2, 20)], '时间取共同空闲');
select is((select venue_id from public.match_offers), 'v-us-ca-21-badminton-club-21bc', '球馆取大家都能去的');
select is((select count(*)::int from public.notifications where kind = 'offer'), 2, '两人都收到通知');

select pg_temp.login(1);
select is(jsonb_array_length(public.my_matchmaking() -> 0 -> 'offer' -> 'players'), 2, '提议里能看到对手');
select is((select count(*)::int from public.notifications), 1, '只能读到自己的通知');
select lives_ok($$ select public.respond_offer((pg_temp.ticket(1)).offer_id, true) $$, '1 号接受');
select is((pg_temp.ticket(1)).status::text, 'offered', '还在等 2 号');
select pg_temp.login(2);
select lives_ok($$ select public.respond_offer((pg_temp.ticket(2)).offer_id, true) $$, '2 号接受');
select is((pg_temp.ticket(2)).status::text, 'matched', '全部确认后约成');
select is(jsonb_array_length(public.my_games()), 1, '球局出现在我的球局里');
select throws_ok($$ select public.submit_ticket('singles', pg_temp.at(2, 19), pg_temp.at(2, 21), '{v-us-ca-21-badminton-club-21bc}', 1, false) $$,
                 '23P01', null, '已有球局的时间不能再约');

-- 水平差：3 号（6 级，只接受差 1 级）不和 4 号（3 级）配
reset role;
update public.profiles set rating = 6 where id = pg_temp.u(3);
select pg_temp.login(3);
select public.submit_ticket('singles', pg_temp.at(3, 18), pg_temp.at(3, 20), '{v-us-ca-21-badminton-club-21bc}', 1, false);
select pg_temp.login(4);
select public.submit_ticket('singles', pg_temp.at(3, 18), pg_temp.at(3, 20), '{v-us-ca-21-badminton-club-21bc}', 8, false);
select is((pg_temp.ticket(4)).status::text, 'searching', '水平差超出任一方的容忍范围就不配');

-- 拒绝：5 号拒绝后两人都继续找，但不会再配到一起
select pg_temp.login(5);
select public.submit_ticket('singles', pg_temp.at(4, 18), pg_temp.at(4, 20), '{v-us-ca-21-badminton-club-21bc}', 2, false);
select pg_temp.login(6);
select public.submit_ticket('singles', pg_temp.at(4, 18), pg_temp.at(4, 20), '{v-us-ca-21-badminton-club-21bc}', 2, false);
select pg_temp.login(5);
select public.respond_offer((pg_temp.ticket(5)).offer_id, false);
reset role;
select is((select array_agg(status::text order by user_id) from public.match_tickets where user_id in (pg_temp.u(5), pg_temp.u(6))),
          '{searching,searching}', '拒绝后两人都回到搜索');
select is((select count(*)::int from public.notifications where user_id = pg_temp.u(6) and kind = 'requeued'), 1, '对方收到“还在找”');

-- 超时：7 号加入后和其中一人配上，两人都没回复 → 请求暂停，提议作废
select pg_temp.login(7);
select public.submit_ticket('singles', pg_temp.at(4, 18), pg_temp.at(4, 20), '{v-us-ca-21-badminton-club-21bc}', 2, false);
reset role;
select is((pg_temp.ticket(7)).status::text, 'offered', '新来的人配上了');
select public.process_matchmaking((select respond_by + interval '1 minute' from public.match_seats where user_id = pg_temp.u(7)));
select is((pg_temp.ticket(7)).status::text, 'paused', '没回复的请求暂停');
select is((select status::text from public.match_offers o join public.match_seats s on s.offer_id = o.id where s.user_id = pg_temp.u(7)),
          'failed', '提议作废');
select pg_temp.login(7);
select lives_ok($$ select public.resume_ticket((pg_temp.ticket(7)).id) $$, '回来后可以继续找');

-- 双打：8–11 号都开了自动接受，直接约成；按水平 1+4 对 2+3 分队
reset role;
update public.profiles set rating = 4.33 where id = pg_temp.u(11);
update public.profiles set rating = 4 where id = pg_temp.u(10);
select pg_temp.login(8);
select public.submit_ticket('doubles', pg_temp.at(5, 18), pg_temp.at(5, 21), '{v-us-ca-21-badminton-club-21bc}', 2, true);
select pg_temp.login(9);
select public.submit_ticket('doubles', pg_temp.at(5, 18), pg_temp.at(5, 21), '{v-us-ca-21-badminton-club-21bc}', 2, true);
select pg_temp.login(10);
select public.submit_ticket('doubles', pg_temp.at(5, 18), pg_temp.at(5, 21), '{v-us-ca-21-badminton-club-21bc}', 2, true);
select is((pg_temp.ticket(10)).status::text, 'searching', '三个人凑不成双打');
select pg_temp.login(11);
select public.submit_ticket('doubles', pg_temp.at(5, 19), pg_temp.at(5, 21), '{v-us-ca-21-badminton-club-21bc}', 2, true);
reset role;
select is((pg_temp.ticket(11)).status::text, 'matched', '四人都自动接受：直接约成');
select is((select array_agg(team order by rating desc, team) from public.game_players gp join public.games g on g.id = gp.game_id where g.mode = 'doubles'),
          '{1,2,1,2}'::smallint[], '最强和最弱一队');
select is((select count(*)::int from public.notifications where kind like 'offer%' and user_id = pg_temp.u(11)), 0, '直接约成只发一条通知');

-- 赛果：把 1、2 号的单打挪到已开始
update public.games set starts_at = now() - interval '1 hour', ends_at = now() + interval '1 hour' where mode = 'singles';
select pg_temp.login(1);
select lives_ok($$ select public.check_in((pg_temp.ticket(1)).game_id) $$, '开赛后可以签到');
select is(public.report_result((pg_temp.ticket(1)).game_id, 'team2'), 'awaiting', '一方报：等另一方');
select pg_temp.login(2);
select is(public.report_result((pg_temp.ticket(2)).game_id, 'team1'), 'disputed', '说法不一致：有分歧');
select is(public.report_result((pg_temp.ticket(2)).game_id, 'team2'), 'verified', '改成一致：确认');
select pg_temp.login(1);
select throws_ok($$ select public.report_result((pg_temp.ticket(1)).game_id, 'team1') $$, '22023', null, '确认后不能再改');
select is(public.my_record() -> 'wins', '1'::jsonb, '确认的胜场计入战绩');

-- 记不清：双打某一队全员记不清 → 不计入
reset role;
insert into public.result_reports (game_id, reporter_id, outcome)
  select game_id, user_id, null from public.game_players gp join public.games g on g.id = gp.game_id where g.mode = 'doubles' and team = 1;
select is((select status from public.game_result((select id from public.games where mode = 'doubles'))), 'unsure', '一队都记不清：不计入');

-- 开赛前 2 小时内退出 = 临时取消；其他人优先重新找
update public.games set starts_at = now() + interval '1 hour', ends_at = now() + interval '3 hours' where mode = 'doubles';
select pg_temp.login(8);
select lives_ok($$ select public.cancel_game((pg_temp.ticket(8)).game_id) $$, '可以退出');
reset role;
select ok((select late_cancel from public.game_players where user_id = pg_temp.u(8)), '记为临时取消');
select is((select count(*)::int from public.match_tickets where user_id in (pg_temp.u(9), pg_temp.u(10), pg_temp.u(11)) and status = 'searching' and priority),
          3, '其他人优先重新找');

-- 防刷：同时最多 5 个请求
select pg_temp.login(12);
select public.submit_ticket('doubles', pg_temp.at(d, 8), pg_temp.at(d, 10), '{v-us-ca-albert-d-salgado-recreation-center}', 1, false)
  from generate_series(6, 10) d;
select throws_ok($$ select public.submit_ticket('doubles', pg_temp.at(11, 8), pg_temp.at(11, 10), '{v-us-ca-albert-d-salgado-recreation-center}', 1, false) $$,
                 '54000', null, '第 6 个请求被限流');

-- 到锁定时间还没约成：结束，并通知
reset role;
select public.process_matchmaking(pg_temp.at(3, 16) + interval '1 minute');
select is((pg_temp.ticket(4)).status::text, 'expired', '开赛前 2 小时没约成：结束');
select is((select count(*)::int from public.notifications where user_id = pg_temp.u(4) and kind = 'expired'), 1, '收到“这次没约到”');

select * from finish();
rollback;
