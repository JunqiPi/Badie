-- 注册来源：建资料时可以写 ref 和 heard_from，格式不对会被拒绝；之后不能改；统计只有管理员（SQL 编辑器）能看
begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000009' || lpad(n::text, 2, '0'))::uuid, 's' || n || '@test.local' from generate_series(1, 4) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000009' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;

select pg_temp.login(1);
select lives_ok($$ insert into public.profiles (id, nickname, country_code, gender, ref, heard_from)
                   values (pg_temp.u(1), 'Source1', 'US', 'male', 'card', 'level_card') $$, '建资料时可以写来源');
select pg_temp.login(2);
select lives_ok($$ insert into public.profiles (id, nickname, country_code, gender)
                   values (pg_temp.u(2), 'Source2', 'US', 'female') $$, '不写来源也行');
select pg_temp.login(3);
select throws_ok($$ insert into public.profiles (id, nickname, country_code, gender, ref)
                    values (pg_temp.u(3), 'Source3', 'US', 'male', '<script>') $$, '23514', null, '来源只能是短的字母数字');
select throws_ok($$ insert into public.profiles (id, nickname, country_code, gender, heard_from)
                    values (pg_temp.u(3), 'Source3', 'US', 'male', 'tv') $$, '23514', null, '“从哪里知道”只能选给定的选项');

select pg_temp.login(1);
select is((select ref from public.profiles where id = pg_temp.u(1)), 'card', '本人读得到自己的来源');
select throws_ok($$ update public.profiles set ref = 'other' where id = pg_temp.u(1) $$, '42501', null, '建好之后不能改来源');
select is((select count(*) from public.profiles where id = pg_temp.u(2)), 0::bigint, '看不到别人的资料（包括来源）');
select throws_ok($$ select * from public.signup_sources() $$, '42501', null, '登录用户不能查统计');

reset role;
select is((select sum(signups) from public.signup_sources() where ref = 'card' and heard_from = 'level_card'), 1::numeric, '统计按来源数人');

select * from finish();
rollback;
