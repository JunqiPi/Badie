-- 网站构建时用：把我们自己整理、直接写进数据库的球馆导出成球馆目录（json）。这批数据不在公开仓库里。
-- id 规则和 build_imported_venues.py、build_venue_seed.py 一致。只导出位置准的、没隐藏、没合并的；
-- 每家带上自己的坐标来源（attr：OpenStreetMap 或 Overture Maps），网站页脚按它署名
select json_build_object(
  'source', 'Badie research: venues we collected; coordinates from OpenStreetMap or Overture Maps',
  'kind', 'curated', 'status', 'unconfirmed',
  'attribution', 'Coordinates © OpenStreetMap contributors, ODbL 1.0',
  'venues', coalesce(json_agg(json_build_object(
    'id', v.id, 'name', v.name,
    'lat', round(extensions.st_y(v.location::extensions.geometry)::numeric, 6),
    'lon', round(extensions.st_x(v.location::extensions.geometry)::numeric, 6),
    'street', v.street, 'city', v.city, 'region', v.region, 'postcode', v.postal_code,
    'country', v.country_code, 'tz', v.time_zone_id, 'attr', v.attribution) order by v.id), '[]'::json))
from public.venues v
where v.id ~ '^v-[a-z]{2}-b[0-9a-f]{10}$' and v.merged_into is null and not v.hidden_pending_review
  and not v.location_approximate;
