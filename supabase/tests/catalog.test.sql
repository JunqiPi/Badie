-- 场馆目录导入（seed.sql 由 supabase/scripts/build_venue_seed.py 生成）
begin;
create extension if not exists pgtap with schema extensions;
select plan(5);

select cmp_ok((select count(*)::int from public.venues where source = 'open_data'), '>', 3000, '政府开放数据已导入');
select is((select count(*)::int from public.venues where source = 'curated' and country_code = 'US'), 32, '美国收录 32 家');
select is((select court_count from public.venues where id = 'v-us-ca-labc'), 15, 'LABC 场地数');
select is((select pricing ->> 'perPerson' from public.venues where id = 'v-us-ca-labc'), '10', 'LABC 散客价');
select ok((select bool_and(location_approximate and status = 'unconfirmed') from public.venues where country_code = 'KR'),
          '韩国数据只有大概位置，标为待确认');

select * from finish();
rollback;
