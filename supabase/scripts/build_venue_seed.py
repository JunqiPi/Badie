"""把 Badie-iOS/Badie/Resources 里的场馆目录（加上只进数据库、不打包进 App 的 supabase/data，
比如 build_osm_venues.py 生成的 OpenStreetMap 球馆）生成 supabase/seed.sql（本地开发、CI，以及同步到生产库）。

可以重复执行：目录里的场馆按 id 新增或更新（只动目录自己的字段，球友确认、收藏等不受影响）；
从目录里删掉的场馆不删除，而是隐藏并进审核队列，由管理员决定。

用法（在仓库根目录）:
    python3 supabase/scripts/build_venue_seed.py
"""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[2]
catalogs = sorted((root / "Badie-iOS/Badie/Resources").glob("*.json")) + sorted((root / "supabase/data").glob("*.json"))
kinds = {"curated": "curated", "openStreetMap": "open_street_map", None: "open_data"}
facilities = {"dedicated": "dedicated", "multiSport": "multi_sport", "recCenter": "rec_center",
              "school": "school", "communityHall": "community_hall", "outdoor": "outdoor"}


def sql(value):
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, (dict, list)) and not isinstance(value, str):
        value = json.dumps(value, ensure_ascii=False)
    return "'" + str(value).replace("'", "''") + "'"


def text_array(values):
    return "array[" + ", ".join(sql(v) for v in values) + "]::text[]" if values else "'{}'::text[]"


rows, ids = [], []
for path in catalogs:
    if path.name == "badie-venues.json":  # 网站构建时从数据库导出的，不是目录
        continue
    catalog = json.loads(path.read_text(encoding="utf-8"))
    source = kinds[catalog.get("kind")]
    for v in catalog["venues"]:
        approx = bool(v.get("approx"))
        status = "unconfirmed" if approx else v.get("status", catalog.get("status", "verified"))
        kind = facilities[v["facility"]] if v.get("facility") else None
        ids.append(v["id"])
        rows.append("(" + ", ".join([
            sql(v["id"]), sql(v["name"]), text_array(v.get("aliases", [])),
            f"'SRID=4326;POINT({v['lon']} {v['lat']})'::extensions.geography",
            sql(v["street"]), sql(v.get("unit")), sql(v["city"]), sql(v["region"]), sql(v["postcode"]),
            sql(v["country"]), sql(v["tz"]), sql(v.get("courts")), sql(v.get("price")) + "::jsonb" if v.get("price") else "null",
            sql(v.get("phone")), sql(v.get("web")), sql(v.get("entrance")),
            f"'{source}'", sql(v.get("attr") or catalog.get("attribution")), f"'{status}'", sql(approx),
            sql(kind), sql(v.get("playTimes")), sql(v.get("checked")),
        ]) + ")")

assert rows, "no venue catalogs found"
assert len(ids) == len(set(ids)), "duplicate venue ids across catalogs"

REMOVED = "removed from the official catalog"
COLLECTED = r"^v-[a-z]{2}-b[0-9a-f]{10}$"
catalog_fields = ["name", "aliases", "location", "street", "unit", "city", "region", "postal_code", "time_zone_id",
                  "court_count", "pricing", "phone", "website", "entrance_note", "attribution", "location_approximate",
                  "kind", "play_times", "checked_on"]
sql_text = f"""-- 由 supabase/scripts/build_venue_seed.py 生成，不要手改

insert into public.venues (id, name, aliases, location, street, unit, city, region, postal_code, country_code,
  time_zone_id, court_count, pricing, phone, website, entrance_note, source, attribution, status, location_approximate,
  kind, play_times, checked_on) values
{",\n".join(rows)}
on conflict (id) do update set
  {", ".join(f"{f} = excluded.{f}" for f in catalog_fields)},
  status = case when excluded.status = 'verified' then excluded.status else venues.status end,
  hidden_pending_review = venues.hidden_pending_review and venues.review_flag is distinct from '{REMOVED}',
  review_flag = nullif(venues.review_flag, '{REMOVED}')
where venues.source = excluded.source and venues.merged_into is null;

-- 我们自己整理、直接写进数据库的球馆（id 是 v-国家-b 加 10 位十六进制，见 build_imported_venues.py）不在目录文件里，不隐藏
update public.venues set hidden_pending_review = true, review_flag = '{REMOVED}'
where source in ('curated', 'open_data', 'open_street_map') and merged_into is null and not hidden_pending_review
  and id !~ '{COLLECTED}'
  and id <> all ('{{{",".join(ids)}}}'::text[]);
"""
(root / "supabase/seed.sql").write_text(sql_text, encoding="utf-8")
print(f"{len(rows)} venues from {len(catalogs)} catalogs")
