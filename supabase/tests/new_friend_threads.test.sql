-- 新球友：7 天内没聊过也在会话列表里，超过 7 天没聊过就不显示
begin;
create extension if not exists pgtap with schema extensions;
select plan(3);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000031' || lpad(n::text, 2, '0'))::uuid, 'nf' || n || '@test.local' from generate_series(1, 2) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000031' || lpad(n::text, 2, '0'))::uuid, 'NewFriend' || n from generate_series(1, 2) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000031' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create function pg_temp.dm(n int) returns jsonb language sql as $$
  select t from jsonb_array_elements(public.my_threads()) t where t ->> 'kind' = 'dm' and t ->> 'id' = pg_temp.u(n)::text
$$;

insert into public.friend_requests (from_id, to_id) values (pg_temp.u(1), pg_temp.u(2));
select pg_temp.login(2);
select public.respond_friend_request(pg_temp.u(1), true);
select is(pg_temp.dm(1) -> 'last', 'null'::jsonb, '刚成为球友：没聊过也在会话列表里');
select pg_temp.login(1);
select isnt(pg_temp.dm(2), null, '对方那边也有');

reset role;
update public.friendships set created_at = now() - interval '8 days';
select pg_temp.login(1);
select is(pg_temp.dm(2), null, '超过 7 天没聊过就不显示');

select * from finish();
rollback;
