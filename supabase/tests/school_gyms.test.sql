-- 附近的球馆：室内的公共场馆在前，学校体育馆其次，露天场地最后
begin;
create extension if not exists pgtap with schema extensions;
select plan(1);

insert into public.venues (id, name, location, street, city, country_code, time_zone_id, source, status, kind) values
  ('v-test-sg-outdoor', 'Park Court', 'SRID=4326;POINT(10.0001 50.0001)'::extensions.geography, '', 'Testtown', 'DE', 'Europe/Berlin', 'open_street_map', 'unconfirmed', 'outdoor'),
  ('v-test-sg-school', 'School Gym', 'SRID=4326;POINT(10.0002 50.0002)'::extensions.geography, '', 'Testtown', 'DE', 'Europe/Berlin', 'open_street_map', 'unconfirmed', 'school'),
  ('v-test-sg-public', 'City Hall Gym', 'SRID=4326;POINT(10.0100 50.0100)'::extensions.geography, '', 'Testtown', 'DE', 'Europe/Berlin', 'open_street_map', 'unconfirmed', null);

select is((select array_agg((n.venue).id order by n.ord) from public.venues_near(50.0, 10.0, 5, 10) with ordinality as n(venue, distance_m, ord)
           where (n.venue).id like 'v-test-sg-%'),
          array['v-test-sg-public', 'v-test-sg-school', 'v-test-sg-outdoor'], '公共场馆在前（哪怕远一点），学校其次，露天最后');

select * from finish();
rollback;
