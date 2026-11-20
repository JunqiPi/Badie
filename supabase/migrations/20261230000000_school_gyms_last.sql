-- 学校、大学的体育馆（OpenStreetMap，kind = school）也收进来了：不少晚上、周末开放给俱乐部和社区，但散客多半去不了。
-- 附近的球馆：室内的公共场馆在前，学校体育馆其次，露天场地最后（同一类里近的在前）。注册时自动选常去球馆也就先选公共场馆
create or replace function public.venues_near(lat double precision, lng double precision, radius_km double precision,
                                   max_results int default 100)
returns table (venue public.venues, distance_m double precision)
language sql stable set search_path = '' as $$
  select v, extensions.st_distance(v.location, extensions.st_makepoint(venues_near.lng, venues_near.lat)::extensions.geography)
  from public.venues v
  where v.merged_into is null
    and extensions.st_dwithin(v.location, extensions.st_makepoint(venues_near.lng, venues_near.lat)::extensions.geography,
                              least(radius_km, 100) * 1000)
  order by case v.kind::text when 'outdoor' then 2 when 'school' then 1 else 0 end, 2
  limit least(max_results, 200)
$$;
