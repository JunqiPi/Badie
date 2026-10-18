-- 双打挑战：两边都要带一位自己的球友当搭档，接受后开一场 2 对 2，搭档都收到通知
begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000013' || lpad(n::text, 2, '0'))::uuid, 'd' || n || '@test.local' from generate_series(1, 5) n;
insert into public.profiles (id, nickname, country_code, created_at, challenge_policy)
  select ('00000000-0000-0000-0000-0000000013' || lpad(n::text, 2, '0'))::uuid, (array['Ann', 'Bo', 'Cy', 'Di', 'Ed'])[n], 'US',
         now() - interval '10 days', 'everyone'
  from generate_series(1, 5) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000013' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create function pg_temp.send(partner int) returns uuid language sql as $$
  select public.send_challenge(pg_temp.u(3), 'v-us-ca-21-badminton-club-21bc', date_trunc('hour', now()) + interval '1 day',
                               date_trunc('hour', now()) + interval '1 day 2 hours', 'Two on two?', pg_temp.u(partner))
$$;

-- Ann 和 Bo 是球友；Cy 和 Di 是球友；Ed 谁也不认识
insert into public.friendships (user_a, user_b)
  select least(pg_temp.u(a), pg_temp.u(b)), greatest(pg_temp.u(a), pg_temp.u(b)) from (values (1, 2), (3, 4)) f(a, b);

select pg_temp.login(1);
select throws_ok($$ select pg_temp.send(5) $$, '22023', 'invalid_partner', '搭档必须是自己的球友');
select lives_ok($$ select pg_temp.send(2) $$, 'Ann 带 Bo 向 Cy 发起双打挑战');
reset role;
select is((select title from public.notifications where user_id = pg_temp.u(2) and kind = 'challenge'), 'You’re someone’s doubles partner', '搭档收到通知');

select pg_temp.login(3);
select is(public.my_challenges() -> 'incoming' -> 0 ->> 'mode', 'doubles', '收到的是双打挑战');
select is(public.my_challenges() -> 'incoming' -> 0 -> 'partner' ->> 'nickname', 'Bo', '能看到对方的搭档');
select throws_ok($$ select public.respond_challenge((public.my_challenges() -> 'incoming' -> 0 ->> 'id')::uuid, true) $$,
                 '22023', 'invalid_partner', '接受双打要选搭档');
select throws_ok($$ select public.respond_challenge((public.my_challenges() -> 'incoming' -> 0 ->> 'id')::uuid, true, pg_temp.u(2)) $$,
                 '22023', 'invalid_partner', '不能选对面的人');
select lives_ok($$ select public.respond_challenge((public.my_challenges() -> 'incoming' -> 0 ->> 'id')::uuid, true, pg_temp.u(4)) $$,
                'Cy 带 Di 接受');

reset role;
select is((select array_agg(p.nickname || gp.team order by gp.team, p.nickname)
           from public.game_players gp join public.profiles p on p.id = gp.user_id
           join public.games g on g.id = gp.game_id
           where g.mode = 'doubles' and gp.game_id = (select game_id from public.challenges where challenger_id = pg_temp.u(1))),
          '{Ann1,Bo1,Cy2,Di2}', '一场 2 对 2 的双打，搭档各在自己那队');

select * from finish();
rollback;
