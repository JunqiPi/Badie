-- 场馆目录导入（seed.sql 由 supabase/scripts/build_venue_seed.py 生成）
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

select cmp_ok((select count(*)::int from public.venues where source = 'open_data'), '>', 3000, '政府开放数据已导入');
select is((select count(*)::int from public.venues where source = 'curated' and country_code = 'US'), 276, '美国收录 276 处');
select is((select court_count from public.venues where id = 'v-us-ca-orange-county-badminton-club'), 12, 'OCBC 场地数');
select ok((select kind = 'rec_center' and play_times like 'Free open play%' and pricing ->> 'perPerson' = '0' and checked_on = '2026-10-16'
           from public.venues where id = 'v-us-ca-balboa-park-activity-center'), '社区中心：类型、开放时段、免费、核实日期');
select is((select pricing ->> 'perPerson' from public.venues where id = 'v-us-ca-labc'), '10', 'LABC 散客价');
select ok((select bool_and(location_approximate and status = 'unconfirmed') from public.venues where country_code = 'KR'),
          '韩国数据只有大概位置，标为待确认');

select ok((select distance_m between 15000 and 18000 from public.venues_near(34.0765, -118.0462, 30)
           where (venue).id = 'v-us-ca-santa-fe-springs-badminton-club'), 'LABC 到 Santa Fe Springs 约 16 公里');
select is((select (venue).id from public.venues_near(34.0765, -118.0462, 30) limit 1), 'v-us-ca-labc', '按距离排序，最近的在前');

select * from finish();
rollback;
