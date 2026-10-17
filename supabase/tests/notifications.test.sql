-- 通知按收件人的语言：资料里的语言、时间格式、模板翻译和填参数
begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000005' || lpad(n::text, 2, '0'))::uuid, 'n' || n || '@test.local' from generate_series(1, 2) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000005' || lpad(n::text, 2, '0'))::uuid, 'Notes' || n from generate_series(1, 2) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000005' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create function pg_temp.last(n int) returns public.notifications language sql security definer as $$
  select * from public.notifications where user_id = pg_temp.u(n) order by id desc limit 1
$$;

-- 语言存在资料里，本人可以改
select is((select locale from public.profiles where id = pg_temp.u(1)), 'en', '默认英文');
select pg_temp.login(1);
select lives_ok($$ update public.profiles set locale = 'zh-Hans' where id = pg_temp.u(1) $$, '本人可以改语言');
select throws_ok($$ update public.profiles set locale = 'xx' where id = pg_temp.u(1) $$, '23514', null, '只能是支持的语言');
select throws_ok($$ select * from public.notification_texts $$, '42501', null, '译文表不能直接读');
select throws_ok($$ select public.notify(pg_temp.u(2), 'friend', 'x', 'y') $$, '42501', null, '客户端不能直接发通知');
reset role;

-- 时间：球馆当地时间，按语言的习惯
select is(public.when_text('2026-10-18T02:00:00Z', 'America/Los_Angeles', 'en'), 'Sat, Oct 17, 7:00 PM', '英文');
select is(public.when_text('2026-10-18T02:00:00Z', 'America/Los_Angeles', 'zh-Hans'), '10月17日 周六 19:00', '中文 24 小时制');
select is(public.when_text('2026-10-18T02:00:00Z', 'Asia/Seoul', 'ko'), '10월 18일 (일) 11:00', '韩文，按球馆时区');

-- 模板：翻译后一次性填参数；没有译文用英文
select is(public.render_text('zh-Hans', 'Welcome to {group}', '{"group": "Thu doubles"}'), '欢迎加入 Thu doubles', '翻译并填参数');
select is(public.render_text('en', '{name} wants to be friends.', '{"name": "{court}", "court": "X"}'), '{court} wants to be friends.',
          '昵称里的占位符不会被再替换');
select is(public.render_text('ja', 'Not translated {x}', '{}'), 'Not translated {x}', '没有译文就用英文，缺的参数原样留着');

-- 实际发通知：同一场球，中文用户收到中文、英文用户收到英文
insert into public.games (mode, starts_at, ends_at, venue_id)
  values ('singles', now() - interval '2 hours', now() - interval '1 minute', 'v-us-ca-21-badminton-club-21bc');
insert into public.game_players (game_id, user_id, team, rating)
  select g.id, pg_temp.u(n), n, 3 from public.games g, generate_series(1, 2) n
  where g.venue_id = 'v-us-ca-21-badminton-club-21bc' and g.ends_at > now() - interval '2 minutes' and not g.review_prompted;
select public.prompt_reviews();
select is((pg_temp.last(1)).title, '这场球打得怎么样？', '中文标题');
select matches((pg_temp.last(1)).body, '^\d+月\d+日 周. \d\d:\d\d · .+。48 小时内给球友评价，内容不公开。$', '中文正文带本地化时间');
select is((pg_temp.last(2)).title, 'How was your game?', '英文用户收到英文');

-- 译文齐全：每种语言都有全部模板，占位符和英文一致
select is((select count(distinct english)::int from public.notification_texts group by locale having count(*) <> (select count(distinct english) from public.notification_texts) limit 1),
          null, '每种语言的模板数一样');
select is((select count(*)::int from public.notification_texts
           where array(select m[1] from regexp_matches(translated, '\{\w+\}', 'g') m order by 1)
                 <> array(select m[1] from regexp_matches(english, '\{\w+\}', 'g') m order by 1)),
          0, '占位符和英文一致');

select * from finish();
rollback;
