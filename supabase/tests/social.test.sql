-- 社交规则测试：评价、等级校准、球友、私信、拉黑、举报（与 iOS 的规则一致）
begin;
create extension if not exists pgtap with schema extensions;
select plan(51);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000002' || lpad(n::text, 2, '0'))::uuid, 's' || n || '@test.local' from generate_series(1, 12) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000002' || lpad(n::text, 2, '0'))::uuid, 'Social' || n from generate_series(1, 12) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000002' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
-- 建一场球局：结束于 ended_ago 之前，players 按顺序分到 1、2 队
create function pg_temp.game(ended_ago interval, players int[]) returns uuid language plpgsql as $$
declare
  id uuid;
begin
  insert into public.games (mode, starts_at, ends_at, venue_id, review_prompted)
    values (case when cardinality(players) = 4 then 'doubles' else 'singles' end::public.game_mode,
            now() - ended_ago - interval '2 hours', now() - ended_ago, 'v-us-ca-21-badminton-club-21bc', true)
    returning games.id into id;
  insert into public.game_players (game_id, user_id, team, rating)
    select id, pg_temp.u(p), case when n % 2 = 1 then 1 else 2 end, 3 from unnest(players) with ordinality as x(p, n);
  return id;
end
$$;
create function pg_temp.notes(n int, k text) returns int language sql security definer as $$
  select count(*)::int from public.notifications where user_id = pg_temp.u(n) and kind = k
$$;

-- 1–4 号打了一场双打（1 小时前结束），1 号和 3 号签到了；还有一场 3 天前结束的单打
create temp table g as select pg_temp.game(interval '1 hour', array[1, 2, 3, 4]) as recent, pg_temp.game(interval '3 days', array[1, 2]) as old;
grant select on g to authenticated;
update public.game_players set checked_in_at = now() - interval '2 hours' where game_id = (select recent from g) and user_id in (pg_temp.u(1), pg_temp.u(2), pg_temp.u(4));

-- 资料页只对有交集的人开放
update public.profiles set discoverable = false where id = pg_temp.u(9);
select pg_temp.login(1);
select isnt(public.player_card(pg_temp.u(2)), null, '同一场打过球：能看资料');
select is(public.player_card(pg_temp.u(9)), null, '没有交集、也不让搜到：看不到');
select is(public.player_card(pg_temp.u(2)) ->> 'relationship', 'none', '还不是球友');
select is((public.player_card(pg_temp.u(2)) ->> 'games_together')::int, 2, '一起打过的场次');
select is(public.player_card(pg_temp.u(2)) ->> 'games_band', '1–4 games', '场次只给分档');
select is(public.player_card(pg_temp.u(2)) -> 'tags', '[]'::jsonb, '评价不够时没有标签');
select throws_ok($$ select * from public.game_reviews $$, '42501', null, '评价表不能直接读');
select throws_ok($$ select * from public.messages $$, '42501', null, '消息表不能直接读');

-- 评价
select lives_ok($$ select public.review_player((select recent from g), pg_temp.u(2), 'on_time', 'higher', '{friendly,skilled}', '{}', true) $$,
                '结束后可以评价');
select throws_ok($$ select public.review_player((select recent from g), pg_temp.u(2), 'on_time', 'higher', '{}', '{}', true) $$,
                 '23505', null, '每人只能评一次');
select throws_ok($$ select public.review_player((select recent from g), pg_temp.u(1), 'on_time', 'accurate', '{}', '{}', false) $$,
                 'P0002', null, '不能评自己');
select throws_ok($$ select public.review_player((select old from g), pg_temp.u(2), 'on_time', 'accurate', '{}', '{}', false) $$,
                 'P0002', null, '超过 48 小时不能评');
select throws_ok($$ select public.review_player((select recent from g), pg_temp.u(4), 'on_time', 'accurate', '{rich}', '{}', false) $$,
                 '23514', null, '标签只能从固定列表里选');
select lives_ok($$ select public.review_player((select recent from g), pg_temp.u(3), 'no_show', 'accurate', '{}', '{}', false) $$,
                '可以说对方没来');
select pg_temp.login(9);
select throws_ok($$ select public.review_player((select recent from g), pg_temp.u(2), 'on_time', 'accurate', '{}', '{}', false) $$,
                 'P0002', null, '不在这局的人不能评');

-- 双方都想再约：成为球友
select pg_temp.login(2);
select public.review_player((select recent from g), pg_temp.u(1), 'on_time', 'accurate', '{}', '{}', true);
select is(public.player_card(pg_temp.u(1)) ->> 'relationship', 'friend', '双方都想再约：直接成为球友');
select is(pg_temp.notes(1, 'friend'), 1, '双方都收到通知');

-- 爽约：没签到，并且同场多数人说没来（双打 3 人里至少 2 人）
select pg_temp.login(3);
select is((public.my_record() ->> 'no_shows')::int, 0, '只有一个人说没来：不算爽约');
select pg_temp.login(2);
select public.review_player((select recent from g), pg_temp.u(3), 'no_show', 'accurate', '{}', '{}', false);
select pg_temp.login(3);
select is((public.my_record() ->> 'no_shows')::int, 1, '没签到且两个人说没来：记一次爽约');
select pg_temp.login(4);
select is((public.my_record() ->> 'no_shows')::int, 0, '签到了：不算爽约');

-- 私信：球友可以聊，非球友不行
select pg_temp.login(1);
select lives_ok($$ select public.send_message('dm', pg_temp.u(2), '  Same time next week?  ') $$, '球友可以私信');
select throws_ok($$ select public.send_message('dm', pg_temp.u(3), 'hi') $$, '42501', null, '不是球友不能私信');
select throws_ok($$ select public.send_message('dm', pg_temp.u(2), '   ') $$, '22023', null, '不能发空消息');
select lives_ok($$ select public.send_message('game', (select recent from g), 'Thanks all, good games!') $$, '赛后 48 小时内球局群聊还开着');
select throws_ok($$ select public.send_message('game', (select old from g), 'hello?') $$, '42501', null, '超过 48 小时群聊关闭');
select pg_temp.login(9);
select throws_ok($$ select public.open_thread('game', (select recent from g)) $$, '42501', null, '不在这局看不到群聊');

select pg_temp.login(2);
select is((public.inbox_counts() ->> 'messages')::int, 2, '未读：一条私信、一条群聊');
select is(public.open_thread('dm', pg_temp.u(1)) -> 'messages' -> 0 ->> 'body', 'Same time next week?', '消息去掉首尾空格');
select is((public.inbox_counts() ->> 'messages')::int, 1, '打开后标为已读');

-- 发消息限流
select pg_temp.login(4);
select public.send_message('game', (select recent from g), 'msg ' || n) from generate_series(1, 20) n;
select throws_ok($$ select public.send_message('game', (select recent from g), 'one more') $$, '54000', null, '每分钟最多 20 条');

-- 好友申请
select pg_temp.login(3);
select is(public.send_friend_request(pg_temp.u(4)), 'requested', '可以给打过球的人发申请');
select throws_ok($$ select public.send_friend_request(pg_temp.u(9)) $$, '42501', null, '不能给不让搜到的陌生人发申请');
select pg_temp.login(4);
select is(jsonb_array_length(public.my_friends() -> 'requests'), 1, '收到申请');
select lives_ok($$ select public.respond_friend_request(pg_temp.u(3), false) $$, '可以忽略');
select pg_temp.login(3);
select is(public.player_card(pg_temp.u(4)) ->> 'relationship', 'requested', '被忽略的人仍看到“已申请”');
select is(public.send_friend_request(pg_temp.u(4)), 'requested', '被忽略后不会重复发出');
select is(pg_temp.notes(4, 'friend_request'), 1, '只通知一次');

-- 拉黑：解除球友、私信关闭、以后不再匹配到一起
select pg_temp.login(1);
select lives_ok($$ select public.block_user(pg_temp.u(2)) $$, '可以拉黑');
select is(public.player_card(pg_temp.u(2)) ->> 'relationship', 'blocked', '显示已拉黑');
select throws_ok($$ select public.send_message('dm', pg_temp.u(2), 'hi') $$, '42501', null, '拉黑后私信关闭');
select public.submit_ticket('singles', date_trunc('day', now()) + interval '3 days 18 hours', date_trunc('day', now()) + interval '3 days 20 hours',
                            '{v-us-ca-21-badminton-club-21bc}', 8, false);
reset role;
select ok((select pg_temp.u(2) = any (excluded_user_ids) from public.match_tickets where user_id = pg_temp.u(1)), '新请求自动排除被拉黑的人');
select pg_temp.login(2);
select is(public.send_friend_request(pg_temp.u(1)), 'requested', '被拉黑的人看不出被拉黑');
reset role;
select is((select count(*)::int from public.friend_requests where from_id = pg_temp.u(2)), 0, '但申请不会送达');

-- 举报：管理员收到通知
insert into public.admin_users (user_id) values (pg_temp.u(12));
select pg_temp.login(4);
select throws_ok($$ select public.report_user(pg_temp.u(3), 'spam', null) $$, '23514', null, '举报原因只能从列表里选');
select lives_ok($$ select public.report_user(pg_temp.u(3), 'harassment', 'Kept messaging me') $$, '可以举报');
select is(pg_temp.notes(12, 'report'), 1, '管理员收到通知');

-- 等级校准：评价满 5 次后按球友评价调整（没做问卷：85% 球友评价）
reset role;
insert into public.game_reviews (game_id, reviewer_id, reviewee_id, attendance, level_check, peer_rating)
  select (select recent from g), pg_temp.u(n), pg_temp.u(5), 'on_time', 'higher', 4 from generate_series(6, 9) n;
select public.refresh_rating(pg_temp.u(5));
select is((select rating from public.profiles where id = pg_temp.u(5)), 3.00, '不满 5 次评价：按问卷');
insert into public.game_reviews (game_id, reviewer_id, reviewee_id, attendance, level_check, peer_rating)
  values ((select recent from g), pg_temp.u(10), pg_temp.u(5), 'on_time', 'higher', 4);
select public.refresh_rating(pg_temp.u(5));
select is((select rating from public.profiles where id = pg_temp.u(5)), 4.00, '满 5 次：0.15×3 + 0.85×4 ≈ 4');

-- 正面标签：上个月底为止、≥5 人 ≥3 场，每个标签至少 2 人给过
insert into public.game_reviews (game_id, reviewer_id, reviewee_id, attendance, level_check, peer_rating, tags, created_at)
  select case when n % 3 = 0 then (select recent from g) when n % 3 = 1 then (select old from g) else pg_temp.game(interval '40 days', array[6, n]) end,
         pg_temp.u(n), pg_temp.u(6), 'on_time', 'accurate', 3,
         case when n = 7 then '{friendly,great_partner}'::text[] else '{friendly,skilled}'::text[] end,
         date_trunc('month', now()) - interval '1 day'
  from generate_series(7, 11) n;
select is(public.public_tags(pg_temp.u(6)), '{friendly,skilled}', '取至少 2 人给过的标签，按人数排序');
select is(public.public_tags(pg_temp.u(5)), '{}', '人数不够：不显示标签');

-- 私下提醒：60 天内 3 位不同球友提到同一点
insert into public.game_reviews (game_id, reviewer_id, reviewee_id, attendance, level_check, peer_rating, issues)
  select (select old from g), pg_temp.u(n), pg_temp.u(4), 'on_time', 'accurate', 3, '{rude}' from generate_series(10, 11) n;
select pg_temp.login(2);
select public.review_player((select recent from g), pg_temp.u(4), 'on_time', 'accurate', '{}', '{rude}', false);
select is(pg_temp.notes(4, 'nudge'), 1, '第 3 位提到：私下提醒一次');

select * from finish();
rollback;
