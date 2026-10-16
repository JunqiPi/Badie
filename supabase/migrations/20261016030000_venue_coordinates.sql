-- 网页和 App 直接读经纬度（geography 列在 JSON 里是二进制串）
alter table public.venues
  add column lat double precision generated always as (extensions.st_y(location::extensions.geometry)) stored,
  add column lon double precision generated always as (extensions.st_x(location::extensions.geometry)) stored;

-- 加了 lat / lon 列以后，SQL 函数里同名的参数会被列名盖住（列名优先），参数一律写全名
create or replace function public.venues_near(lat double precision, lng double precision, radius_km double precision,
                                   max_results int default 100)
returns table (venue public.venues, distance_m double precision)
language sql stable set search_path = '' as $$
  select v, extensions.st_distance(v.location, extensions.st_makepoint(venues_near.lng, venues_near.lat)::extensions.geography)
  from public.venues v
  where v.merged_into is null
    and extensions.st_dwithin(v.location, extensions.st_makepoint(venues_near.lng, venues_near.lat)::extensions.geography,
                              least(radius_km, 100) * 1000)
  order by 2
  limit least(max_results, 200)
$$;

create or replace function public.venue_duplicates(name text, lat double precision, lng double precision,
                                        apple_place_id text default null, alternate_place_ids text[] default '{}')
returns table (venue_id text, venue_name text, kind text, distance_m double precision)
language sql stable set search_path = '' as $$
  with candidates as (
    select v.id, v.name, v.aliases, v.apple_place_id,
           extensions.st_distance(v.location, extensions.st_makepoint(venue_duplicates.lng, venue_duplicates.lat)::extensions.geography) as meters
    from public.venues v
    where v.merged_into is null
      and (extensions.st_dwithin(v.location, extensions.st_makepoint(venue_duplicates.lng, venue_duplicates.lat)::extensions.geography, 200)
           or (v.apple_place_id is not null
               and v.apple_place_id = any (array_append(coalesce(venue_duplicates.alternate_place_ids, '{}'),
                                                        venue_duplicates.apple_place_id))))
  ), classified as (
    select id, name, meters,
      case
        when apple_place_id is not null
          and apple_place_id = any (array_append(coalesce(venue_duplicates.alternate_place_ids, '{}'),
                                                 venue_duplicates.apple_place_id)) then 'same_place'
        when meters <= 200 and (public.venue_names_similar(venue_duplicates.name, candidates.name)
          or exists (select 1 from unnest(aliases) alias where public.venue_names_similar(venue_duplicates.name, alias)))
          then 'likely'
        when meters <= 40 then 'same_building'
      end as kind
    from candidates
  )
  select id, name, kind, meters from classified where kind is not null
  order by case kind when 'same_place' then 0 when 'likely' then 1 else 2 end, meters
$$;
