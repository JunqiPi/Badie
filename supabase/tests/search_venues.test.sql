-- 按名字搜球馆：换一种语言、不打重音、只打城市也能搜到，近的在前
begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

select ok(exists (select 1 from public.search_venues('Benchakitti') where id = 'v-th-benjakitti-sports-center'), '英文别名');
select ok(exists (select 1 from public.search_venues('เบญจกิติ') where id = 'v-th-benjakitti-sports-center'), '泰文名');
select ok(exists (select 1 from public.search_venues('benja kitti') where id = 'v-th-benjakitti-sports-center'), '多打了空格');
select ok(exists (select 1 from public.search_venues('playfit') where id = 'v-gb-ark-walworth-academy'), '不分大小写，搜别名');
select ok((select bool_and(country_code = 'FR') from public.search_venues('gymnasé')), '不打重音也一样（gymnase）');
select is((select country_code from public.search_venues('badminton', 34.07, -118.04, 1)), 'US', '同名的多，离得近的在前');
select is((select count(*)::int from public.search_venues('a')), 0, '一个字不搜');

select * from finish();
rollback;
