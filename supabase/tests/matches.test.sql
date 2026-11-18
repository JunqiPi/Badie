-- 比赛：比分规则、各赛制的对阵（轮换搭档不重复搭档、轮空平均）、积分榜的并列规则、谁能输比分、撤销、退赛、分组出线和决赛、结束、删除
begin;
create extension if not exists pgtap with schema extensions;
select plan(59);

-- 1 是组织者，2–9 是他的球友，10 屏蔽了 1
insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000048' || lpad(n::text, 2, '0'))::uuid, 'mt' || n || '@test.local' from generate_series(1, 10) n;
insert into public.profiles (id, nickname, rating)
  select ('00000000-0000-0000-0000-0000000048' || lpad(n::text, 2, '0'))::uuid, 'M' || n, 1 + n % 8 from generate_series(1, 10) n;
create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000048' || lpad(n::text, 2, '0'))::uuid
$$;
insert into public.friendships (user_a, user_b) select least(pg_temp.u(1), pg_temp.u(n)), greatest(pg_temp.u(1), pg_temp.u(n)) from generate_series(2, 10) n;
insert into public.blocks (blocker, blocked) values (pg_temp.u(10), pg_temp.u(1));

-- 只换身份（auth.uid()）
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create temp table ids (name text primary key, id uuid);
create function pg_temp.id(k text) returns uuid language sql as $$ select id from ids where name = k $$;
-- n 个访客名字的参赛名单
create function pg_temp.names(n int) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('name', 'Guest ' || chr(64 + i)) order by i) from generate_series(1, n) i
$$;
-- 一场比赛里，同一对搭档最多搭了几次、每人打的场数最多差几
create function pg_temp.max_partner(m uuid) returns int language sql as $$
  select coalesce(max(c), 0)::int from (
    select count(*) as c from public.match_games g, lateral (values (g.side_a), (g.side_b)) s(pair)
    where g.match_id = m and g.status <> 'cancelled' group by least(s.pair[1], s.pair[2]), greatest(s.pair[1], s.pair[2])) x
$$;
create function pg_temp.spread(m uuid) returns int language sql as $$
  select (max(c) - min(c))::int from (
    select count(g.id) as c from public.match_players p left join public.match_games g on g.match_id = m and p.id = any(g.side_a || g.side_b)
    where p.match_id = m and p.withdrawn_at is null group by p.id) x
$$;
create function pg_temp.player(m uuid, k text) returns uuid language sql as $$
  select id from public.match_players where match_id = m and name = k
$$;
create function pg_temp.playing(m uuid) returns setof public.match_games language sql as $$
  select * from public.match_games where match_id = m and status = 'playing' order by court
$$;
-- 把正在打的全部按 11:5 打完（a 赢）
create function pg_temp.finish_all(m uuid) returns void language plpgsql as $$
declare
  g public.match_games;
begin
  loop
    select * into g from public.match_games where match_id = m and status = 'playing' order by round, seq limit 1;
    exit when g.id is null;
    perform public.match_score(g.id, array[11, 5], g.version);
  end loop;
end
$$;

-- 比分规则
select is(public.score_winner(array[21, 20], 21, 1, true), null, '21:20 没拉开 2 分');
select is(public.score_winner(array[22, 20], 21, 1, true), 1::smallint, '22:20 合规');
select is(public.score_winner(array[29, 30], 21, 1, true), 2::smallint, '30:29 到封顶');
select is(public.score_winner(array[31, 29], 21, 1, true), null, '超过封顶不合规');
select is(public.score_winner(array[21, 20], 21, 1, false), 1::smallint, '不要求领先 2 分时 21:20 合规');
select is(public.score_winner(array[15, 13], 15, 1, true), 1::smallint, '15 分一局');
select is(public.score_winner(array[21, 10, 10, 21, 21, 15], 21, 3, true), 1::smallint, '三局两胜打满三局');
select is(public.score_winner(array[21, 10, 21, 10, 21, 10], 21, 3, true), null, '赢了两局还有第三局不合规');
select is(public.score_winner(array[21, 10], 21, 3, true), null, '三局两胜只填一局不算完');
select is(public.loose_winner(array[18, 15]), 1::smallint, '时间到没打完：分高的赢');

-- 预计
select is(public.match_preview('rotating', 8, 2, 21, 1) ->> 'rounds', '7', '8 人轮换搭档 7 轮');
select is(public.match_preview('rotating', 8, 2, 21, 1) ->> 'minutes', '105', '2 片场地约 105 分钟');
select is(public.match_preview('singles', 5, 2, 21, 1, false, null, null, 3) ->> 'rounds', '3', '只打 3 轮');

-- 8 人双打轮换搭档：7 轮 14 场，每人 7 场，没有重复的搭档
select pg_temp.login(1);
insert into ids select 'rot', public.create_match('Wed match', null, 2, 'rotating', 21, 1, true,
  (select jsonb_agg(jsonb_build_object('user_id', pg_temp.u(n))) from generate_series(2, 9) n));
select is((select count(*)::int from public.match_games where match_id = pg_temp.id('rot')), 14, '8 人轮换搭档一共 14 场');
select is(pg_temp.max_partner(pg_temp.id('rot')), 1, '8 人 7 轮没有重复的搭档');
select is(pg_temp.spread(pg_temp.id('rot')), 0, '每人都打 7 场');
select is((select count(*)::int from pg_temp.playing(pg_temp.id('rot'))), 2, '两片场地都上了第一轮');
select is((select count(*)::int from public.notifications where kind = 'match' and title = 'Match started: Wed match'), 8, '参赛的 8 个人收到比赛开始');

-- 各种人数的轮换搭档：轮空最多差 1，同一对搭档最多 2 次
select is((select count(*)::int from generate_series(4, 20) n,
                lateral (select public.create_match('R' || n, null, 3, 'rotating', 11, 1, true, pg_temp.names(n)) as m) c
           where pg_temp.spread(c.m) > 1 or pg_temp.max_partner(c.m) > 2), 0, '4–20 人：每人场数最多差 1，同一对搭档最多 2 次');
select is((select count(*)::int from generate_series(4, 16) n,
                lateral (select public.create_match('Q' || n, null, 3, 'rotating', 11, 1, true, pg_temp.names(n)) as m) c
           where n in (4, 5, 6, 8, 9, 10, 11, 13, 14, 15, 16) and pg_temp.max_partner(c.m) > 1), 0, '常见人数没有重复的搭档');

-- 谁能输比分：这一场的球员能输一次；别人报 score_taken；不在这场的不能输
create temp table g1 as select * from pg_temp.playing(pg_temp.id('rot')) limit 1;
create temp table g2 as select * from pg_temp.playing(pg_temp.id('rot')) offset 1 limit 1;
create function pg_temp.member_of(g bigint, side int, k int) returns int language sql as $$
  select substr(p.user_id::text, 35)::int from public.match_games mg join public.match_players p
    on p.id = (case when side = 1 then mg.side_a else mg.side_b end)[k] where mg.id = g
$$;
select pg_temp.login(pg_temp.member_of((select id from g1), 2, 1));
select throws_ok(format('select public.match_score(%s, array[21, 30], 0)', (select id from g1)), '22023', 'score_invalid', '球员输不合规的比分报错');
select lives_ok(format('select public.match_score(%s, array[18, 21], 0)', (select id from g1)), '球员能输自己那场');
select pg_temp.login(pg_temp.member_of((select id from g1), 1, 1));
select throws_ok(format('select public.match_score(%s, array[21, 18], 1)', (select id from g1)), '40001', 'score_taken', '已经有比分了，球员不能再输');
select lives_ok(format('select public.match_flag(%s)', (select id from g1)), '球员可以点不对');
select pg_temp.login(pg_temp.member_of((select id from g2), 1, 1));
select throws_ok(format('select public.match_score(%s, array[21, 18], 0)', (select id from g1)), '42501', 'not_allowed', '不在这场的人不能输');
select pg_temp.login(1);
select is((select (g ->> 'flagged')::boolean from jsonb_array_elements(public.match_state(pg_temp.id('rot')) -> 'games') g
           where (g ->> 'id')::bigint = (select id from g1)), true, '组织者看到有人点了不对');
select is((select g ->> 'scored_by' from jsonb_array_elements(public.match_state(pg_temp.id('rot')) -> 'games') g
           where (g ->> 'id')::bigint = (select id from g1)), 'M' || pg_temp.member_of((select id from g1), 2, 1), '写明谁填的');
select throws_ok(format('select public.match_score(%s, array[21, 18], 0)', (select id from g1)), '40001', 'score_changed', '组织者带旧版本改报 score_changed');
select lives_ok(format('select public.match_score(%s, array[21, 18], 1)', (select id from g1)), '组织者能改比分');
select is((select winner from public.match_games where id = (select id from g1)), 1::smallint, '改完换了赢的一边');
select throws_ok(format('select public.match_score(%s, array[18, 15], 0)', (select id from g2)), '22023', 'score_invalid', '没打完的比分先报错');
select lives_ok(format('select public.match_score(%s, array[18, 15], 0, true)', (select id from g2)), '组织者坚持保存（时间到了）');
select is((select count(*)::int from pg_temp.playing(pg_temp.id('rot'))), 2, '空出来的场地排上了下一场');
-- 撤销刚才那次：比分回去，刚排上的那场撤下来
select lives_ok($$ select public.match_undo(pg_temp.id('rot')) $$, '10 秒内能撤销');
select is((select status from public.match_games where id = (select id from g2)), 'playing', '撤销后那场还在打');
select is((select count(*)::int from pg_temp.playing(pg_temp.id('rot')) where id <> (select id from g2)
           and not (side_a || side_b) && (select side_a || side_b from g2)), 0, '因为它排上的场次退回去了');

-- 退赛：M8 受伤，这一场算对方赢；后面的轮次重排，不再有他
select lives_ok(format('select public.match_withdraw(%L, %s)', pg_temp.player(pg_temp.id('rot'), 'M9'),
                       coalesce((select id from public.match_games where match_id = pg_temp.id('rot') and status = 'playing'
                                 and pg_temp.player(pg_temp.id('rot'), 'M9') = any(side_a || side_b)), 0)), '退赛');
select is((select count(*)::int from public.match_games where match_id = pg_temp.id('rot') and status = 'queued'
           and pg_temp.player(pg_temp.id('rot'), 'M9') = any(side_a || side_b)), 0, '退赛的人后面没有场次');
select ok((select count(*) from public.match_games where match_id = pg_temp.id('rot') and status = 'queued') > 0, '后面的轮次重排了');

-- 单打循环 5 人：5 轮 10 场，每两人正好一场，每人轮空一次
insert into ids select 'single', public.create_match('Singles', null, 2, 'singles', 11, 1, true, pg_temp.names(5));
select is((select count(*)::int from public.match_games where match_id = pg_temp.id('single')), 10, '5 人单打循环 10 场');
select is((select count(distinct round)::int from public.match_games where match_id = pg_temp.id('single')), 5, '5 轮');
select is((select count(*)::int from (select least(side_a[1], side_b[1]), greatest(side_a[1], side_b[1]) from public.match_games
           where match_id = pg_temp.id('single') group by 1, 2 having count(*) = 1) x), 10, '每两人正好碰一次');

-- 积分榜：三人各赢一场（A 赢 B、B 赢 C、C 赢 A），净胜分和总得分也一样 → 并列
insert into ids select 'tri', public.create_match('Tri', null, 3, 'singles', 21, 1, true, pg_temp.names(3));
create function pg_temp.score_pair(m uuid, x text, y text, a int, b int) returns void language sql as $$
  select public.match_score(g.id, case when g.side_a[1] = pg_temp.player(m, x) then array[a, b] else array[b, a] end, g.version, true)
  from public.match_games g where g.match_id = m
    and array[pg_temp.player(m, x), pg_temp.player(m, y)] <@ (g.side_a || g.side_b)
$$;
select pg_temp.score_pair(pg_temp.id('tri'), 'Guest A', 'Guest B', 21, 15);
select pg_temp.score_pair(pg_temp.id('tri'), 'Guest B', 'Guest C', 21, 15);
select pg_temp.score_pair(pg_temp.id('tri'), 'Guest C', 'Guest A', 21, 15);
select is((select count(*)::int from jsonb_array_elements(public.match_ranking(pg_temp.id('tri'))) e where (e ->> 'tied')::boolean and (e ->> 'rank')::int = 1),
          3, '三人分不开写并列第 1');
select is((select status from public.matches where id = pg_temp.id('tri')), 'done', '都打完了自动结束');

-- 两人并列看他们之间的胜负：4 人单打，A、B 都是 2 胜 1 负、净胜分一样，A 赢了 B
insert into ids select 'h2h', public.create_match('H2H', null, 2, 'singles', 21, 1, true, pg_temp.names(4));
select pg_temp.score_pair(pg_temp.id('h2h'), 'Guest A', 'Guest B', 21, 19);
select pg_temp.score_pair(pg_temp.id('h2h'), 'Guest C', 'Guest A', 21, 19);
select pg_temp.score_pair(pg_temp.id('h2h'), 'Guest A', 'Guest D', 21, 19);
select pg_temp.score_pair(pg_temp.id('h2h'), 'Guest B', 'Guest C', 21, 19);
select pg_temp.score_pair(pg_temp.id('h2h'), 'Guest B', 'Guest D', 21, 19);
select pg_temp.score_pair(pg_temp.id('h2h'), 'Guest D', 'Guest C', 21, 19);
select is((select string_agg(e ->> 'name', ',' order by (e ->> 'rank')::int) from jsonb_array_elements(public.match_ranking(pg_temp.id('h2h'))) e
           where (e ->> 'rank')::int <= 2), 'Guest A,Guest B', '两人并列时赢了对方的排前面');

-- 分组循环 + 决赛：8 人 2 组，每组前 2 出线打半决赛，再打决赛
insert into ids select 'grp', public.create_match('Groups', null, 4, 'groups', 11, 1, true, pg_temp.names(8), null, 2, 2);
select is((select count(distinct pool)::int from public.match_players where match_id = pg_temp.id('grp')), 2, '分成 2 组');
select is((select count(*)::int from public.match_games where match_id = pg_temp.id('grp')), 12, '每组 4 人循环，一共 12 场');
select pg_temp.finish_all(pg_temp.id('grp'));
select is((select count(*)::int from public.match_games where match_id = pg_temp.id('grp') and stage = 'semi'), 2, '小组赛打完排两场半决赛');
select is((select count(*)::int from public.match_games where match_id = pg_temp.id('grp') and stage = 'semi'
           and (select pool from public.match_players where id = side_a[1]) = (select pool from public.match_players where id = side_b[1])), 0,
          '半决赛同组的错开');
select pg_temp.finish_all(pg_temp.id('grp'));
select is((select count(*)::int from public.match_games where match_id = pg_temp.id('grp') and stage = 'final'), 1, '半决赛打完排决赛');
select pg_temp.finish_all(pg_temp.id('grp'));
select is((select e ->> 'rank' from jsonb_array_elements(public.match_ranking(pg_temp.id('grp'))) e
           where e -> 'members' = to_jsonb((select case when winner = 1 then side_a else side_b end from public.match_games
                                            where match_id = pg_temp.id('grp') and stage = 'final'))), '1', '决赛赢的是冠军');

-- 双打固定搭档：没给搭档按实力配
insert into ids select 'fixed', public.create_match('Fixed', null, 2, 'fixed', 21, 1, true,
  (select jsonb_agg(jsonb_build_object('user_id', pg_temp.u(n))) from generate_series(1, 8) n));
select is((select count(distinct team)::int from public.match_players where match_id = pg_temp.id('fixed')), 4, '8 人配成 4 队');
select is((select count(*)::int from public.match_games where match_id = pg_temp.id('fixed')), 6, '4 队循环 6 场');

-- 屏蔽了你的人选不到；提前结束；删掉
select throws_ok($$ select public.create_match('X', null, 1, 'singles', 21, 1, true,
                     jsonb_build_array(jsonb_build_object('user_id', pg_temp.u(10)), jsonb_build_object('name', 'Tina'))) $$,
                 'P0002', 'player_not_found', '屏蔽了你的人选不到');
select pg_temp.login(2);
select throws_ok($$ select public.match_end(pg_temp.id('fixed')) $$, '42501', 'not_allowed', '参赛的人不能结束比赛');
select pg_temp.login(1);
select lives_ok($$ select public.match_end(pg_temp.id('fixed')) $$, '组织者提前结束');
select is((select count(*)::int from public.notifications where kind = 'match' and title like 'Match over: you placed #_'), 8, '参赛的人收到自己的名次');
select lives_ok($$ select public.match_delete(pg_temp.id('rot')) $$, '组织者删掉一场');
select is((select count(*)::int from public.notifications where title = 'Match cancelled: Wed match'), 8, '参赛的人收到比赛取消了');

select * from finish();
rollback;
