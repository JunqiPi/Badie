-- OpenStreetMap 导入的露天羽毛球场（公园、学校、小区里的）标成 outdoor；iPhone / 安卓不读这一列，旧版不受影响
alter type public.venue_kind add value if not exists 'outdoor';

-- 附近的球馆：室内的排前面，露天场地排后面（人口密的地方露天场地很多，不能把球馆挤出前 200 个）
create or replace function public.venues_near(lat double precision, lng double precision, radius_km double precision,
                                   max_results int default 100)
returns table (venue public.venues, distance_m double precision)
language sql stable set search_path = '' as $$
  select v, extensions.st_distance(v.location, extensions.st_makepoint(venues_near.lng, venues_near.lat)::extensions.geography)
  from public.venues v
  where v.merged_into is null
    and extensions.st_dwithin(v.location, extensions.st_makepoint(venues_near.lng, venues_near.lat)::extensions.geography,
                              least(radius_km, 100) * 1000)
  order by coalesce(v.kind::text = 'outdoor', false), 2
  limit least(max_results, 200)
$$;
