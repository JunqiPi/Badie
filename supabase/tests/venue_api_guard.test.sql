-- 检查函数：不能直接整表读球馆表；按位置、搜索、按 id 照常；别的表、写操作、后台不受影响（还没启用，见迁移）
begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

create function pg_temp.request(path text, method text default 'GET') returns void language sql as $$
  select set_config('request.path', path, true), set_config('request.method', method, true);
$$;

insert into public.venues (id, name, location, street, city, country_code, time_zone_id, source, status)
values ('v-test-guard', 'Guard Hall', 'SRID=4326;POINT(-122.4 37.7)'::extensions.geography, '', 'San Francisco', 'US',
        'America/Los_Angeles', 'curated', 'verified')
on conflict (id) do nothing;

set local role anon;
select pg_temp.request('/venues');
select throws_ok('select public.check_request()', '42501', 'venues can only be read near a place or by search',
                 '没登录：不能直接读球馆表');
select pg_temp.request('/favorite_venues');
select lives_ok('select public.check_request()', '别的表照常');
select pg_temp.request('/rpc/venues_near', 'POST');
select lives_ok('select public.check_request()', 'RPC 照常');

set local role authenticated;
select pg_temp.request('/venues');
select throws_ok('select public.check_request()', '42501', null, '登录了也不能直接读球馆表');
select is((select name from public.venue_brief('v-test-guard')), 'Guard Hall', '按 id 查一家照常');

reset role;
select lives_ok('select public.check_request()', '后台（postgres、service_role）不受影响');

select is((select count(*) from public.venues_by_ids(array['v-test-guard', 'v-none']))::int, 1, '按一组 id 查照常');

select * from finish();
rollback;
