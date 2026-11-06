-- 照片头像和卡片背景：只能传到自己的文件夹、最多 4 个文件；地址只给打过交道的人；管理员能一起撤下
begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000015' || lpad(n::text, 2, '0'))::uuid, 'a' || n || '@test.local' from generate_series(1, 3) n;
insert into public.profiles (id, nickname, discoverable)
  select ('00000000-0000-0000-0000-0000000015' || lpad(n::text, 2, '0'))::uuid, 'Pic' || chr(64 + n), false from generate_series(1, 3) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000015' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create function pg_temp.file(n int, k int) returns text language sql as $$
  select pg_temp.u(n) || '/00000000-0000-0000-0000-0000000000' || lpad(k::text, 2, '0') || '.jpg'
$$;
-- 1 号和 2 号是球友；3 号谁也不认识
insert into public.friendships (user_a, user_b) values (pg_temp.u(1), pg_temp.u(2));
insert into public.admin_users (user_id) values (pg_temp.u(3));

select pg_temp.login(1);
select throws_ok($$ insert into storage.objects (bucket_id, name, owner) values ('avatars', pg_temp.file(2, 1), pg_temp.u(1)) $$,
                 '42501', null, '不能传到别人的文件夹');
select lives_ok($$ insert into storage.objects (bucket_id, name, owner) select 'avatars', pg_temp.file(1, k), pg_temp.u(1) from generate_series(1, 4) k $$,
                '传到自己的文件夹');
select throws_ok($$ insert into storage.objects (bucket_id, name, owner) values ('avatars', pg_temp.file(1, 5), pg_temp.u(1)) $$,
                 '42501', null, '最多 4 个文件');
select throws_ok($$ select public.set_avatar('../x.jpg') $$, '22023', 'invalid_avatar', '只能用自己传的文件');
select lives_ok($$ select public.set_avatar(pg_temp.file(1, 2)) $$, '换上照片');
select throws_ok($$ select public.set_card_photo(pg_temp.file(2, 1)) $$, '22023', 'invalid_avatar', '卡片背景也只能用自己传的文件');
select lives_ok($$ select public.set_card_photo(pg_temp.file(1, 3)) $$, '换上卡片背景');

select pg_temp.login(2);
select is(public.avatars(array[pg_temp.u(1)]) -> 0 ->> 'path', pg_temp.file(1, 2), '球友看得到照片地址');
select is(public.player_card(pg_temp.u(1)) ->> 'card_photo', pg_temp.file(1, 3), '球友的资料卡带上卡片背景');
select pg_temp.login(3);
select is(public.avatars(array[pg_temp.u(1)]), '[]', '不认识的人拿不到地址');

-- 管理员撤下
select lives_ok($$ select public.admin_clear_avatar(pg_temp.u(1), 'Not a real photo') $$, '管理员撤下照片');
reset role;
select is((select avatar_path from public.profiles where id = pg_temp.u(1)), null, '改回文字头像');
select is((select card_photo_path from public.profiles where id = pg_temp.u(1)), null, '卡片背景也撤下');

select * from finish();
rollback;
