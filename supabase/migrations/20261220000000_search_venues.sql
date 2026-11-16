-- 按名字搜球馆：名字、别名（OSM 里各种语言的名字）、城市都算；不分大小写和重音，忽略空格和标点（泰文的元音符号也当分隔）。
-- 名字对上的排在只有城市对上的前面，同一档里离 (lat, lng) 近的在前，露天场地在后。

-- 预先算好搜索用的字（每次搜都现算一万多行要 0.3 秒），加三元组索引
create function public.venue_search_key(value text)
returns text language sql immutable parallel safe set search_path = '' as $$
  select replace(public.normalize_venue_name(value), ' ', '')
$$;

-- 名字和别名放在一起，用 | 隔开（搜索词里不会有 |）
create function public.venue_names_key(name text, aliases text[])
returns text language sql immutable parallel safe set search_path = '' as $$
  select public.venue_search_key(name) || '|' || coalesce((select string_agg(public.venue_search_key(a), '|') from unnest(aliases) a), '')
$$;

alter table public.venues
  add column name_key text generated always as (public.venue_names_key(name, aliases)) stored,
  add column city_key text generated always as (public.venue_search_key(city)) stored;
create index venues_name_key_trgm on public.venues using gin (name_key extensions.gin_trgm_ops);
create index venues_city_key_trgm on public.venues using gin (city_key extensions.gin_trgm_ops);

create function public.search_venues(q text, lat double precision default null, lng double precision default null,
                                     max_results int default 8)
returns setof public.venues
language sql stable set search_path = '' as $$
  with k as (select '%' || public.venue_search_key(search_venues.q) || '%' as pattern)
  select v.*
  from public.venues v, k
  where v.merged_into is null
    and char_length(k.pattern) >= 4
    and (v.name_key like k.pattern or v.city_key like k.pattern)
  order by
    v.name_key not like k.pattern,
    case when search_venues.lat is null or search_venues.lng is null then 0
         else extensions.st_distance(v.location,
                extensions.st_makepoint(search_venues.lng, search_venues.lat)::extensions.geography) end,
    coalesce(v.kind::text = 'outdoor', false),
    v.name
  limit least(greatest(search_venues.max_results, 1), 50)
$$;

grant execute on function public.search_venues(text, double precision, double precision, int) to anon, authenticated;
