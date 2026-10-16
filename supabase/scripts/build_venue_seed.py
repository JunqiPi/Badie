"""把 Badie-iOS/Badie/Resources 里的场馆目录生成 supabase/seed.sql（本地开发、CI，以及首次导入生产库）。

用法（在仓库根目录）:
    python3 supabase/scripts/build_venue_seed.py
"""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[2]
catalogs = sorted((root / "Badie-iOS/Badie/Resources").glob("*.json"))
kinds = {"curated": "curated", "openStreetMap": "open_street_map", None: "open_data"}


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


rows = []
for path in catalogs:
    catalog = json.loads(path.read_text(encoding="utf-8"))
    source = kinds[catalog.get("kind")]
    for v in catalog["venues"]:
        approx = bool(v.get("approx"))
        status = "unconfirmed" if approx else v.get("status", catalog.get("status", "verified"))
        rows.append("(" + ", ".join([
            sql(v["id"]), sql(v["name"]), text_array(v.get("aliases", [])),
            f"'SRID=4326;POINT({v['lon']} {v['lat']})'::extensions.geography",
            sql(v["street"]), sql(v.get("unit")), sql(v["city"]), sql(v["region"]), sql(v["postcode"]),
            sql(v["country"]), sql(v["tz"]), sql(v.get("courts")), sql(v.get("price")) + "::jsonb" if v.get("price") else "null",
            sql(v.get("phone")), sql(v.get("web")), sql(v.get("entrance")),
            f"'{source}'", sql(v.get("attr") or catalog.get("attribution")), f"'{status}'", sql(approx),
        ]) + ")")

header = "-- 由 supabase/scripts/build_venue_seed.py 生成，不要手改\n"
columns = ("insert into public.venues (id, name, aliases, location, street, unit, city, region, postal_code, country_code, "
           "time_zone_id, court_count, pricing, phone, website, entrance_note, source, attribution, status, location_approximate) values\n")
body = ",\n".join(rows)
(root / "supabase/seed.sql").write_text(header + columns + body + "\non conflict (id) do nothing;\n", encoding="utf-8")
print(f"{len(rows)} venues from {len(catalogs)} catalogs")
