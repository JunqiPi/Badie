"""日本的体育馆（OpenStreetMap）：supabase/data/osm-gyms-JP.json。

日本的公共体育馆（市民体育館、区民体育館、スポーツセンター、アリーナ）基本都能打羽毛球，很多有“個人開放”，
但 OSM 里很少标 sport=badminton，build_osm_venues.py 收不到（東京体育館就没收到）。这里按名字收：
- 名字带“体育館 / アリーナ / スポーツセンター / 体育センター / 総合運動場”，而且是体育场馆（leisure 或 building 是
  sports_centre / sports_hall，或者 stadium 但名字带体育館 / アリーナ）；
- 不收武道館、学校、大学、园区里的楼（“10号館 (体育館)”）、单位自用的、泳池、田径 / 棒球 / 足球场等；
- 和已有的球馆（App 自带的、supabase/data 里的、--exclude 给的）150 米内或 1 公里内同名的不收。
英文名（name:en）、alt_name、official_name 放进别名（冠名、英文都能搜到）。城市、都道府县用 OSM 的行政区划。
状态“待确认”：大多是公共体育馆，也可能混进单位自用的。© OpenStreetMap 贡献者，ODbL 1.0。

用法（在仓库根目录）:
    python3 supabase/scripts/build_osm_gyms_jp.py [--exclude 线上库导出的 badie-venues.json] [--cache 目录]
然后跑 build_venue_seed.py。--exclude 用 supabase/scripts/export_collected_venues.sql 导出（我们整理的球馆不在仓库里）。
"""
import argparse
import json
import re
from pathlib import Path

from build_osm_venues import grid, literal, metres, osm_id, rows, same_name, sparql

root = Path(__file__).resolve().parents[2]
OUT = root / "supabase/data/osm-gyms-JP.json"

NAMES = "(体育館|アリーナ|スポーツセンター|総合運動場|体育センター)"
NOT_FOR_BADMINTON = ("(武道館|学校|小学|中学|高校|高等|大学|弓道|柔道|剣道|相撲|卓球|プール|競技場|野球|球場|陸上|サッカー|"
                     "テニス|ゴルフ|スケート|ボウリング|"
                     # 大学、单位园区里的楼（“10号館 (体育館)”“27棟 体育館”）、单位自用的
                     "号館|棟|校舎|研修|社員|従業員|病院|刑務所|拘置所|自衛隊|駐屯地|基地|警察|消防)")
QUERY = f"""SELECT ?o ?n ?l ?b (geof:centroid(?w) AS ?c) ?en ?alt ?official ?access WHERE {{
  ?o osmkey:name ?n . FILTER(REGEX(?n, "{NAMES}")) FILTER(!REGEX(?n, "{NOT_FOR_BADMINTON}"))
  {{ ?o osmkey:leisure ?l . FILTER(?l IN ("sports_centre", "sports_hall", "stadium")) }}
  UNION {{ ?o osmkey:building ?b . FILTER(?b IN ("sports_hall", "sports_centre", "stadium")) }}
  ?jp osmkey:ISO3166-1:alpha2 "JP" . ?jp ogc:sfContains ?o .
  OPTIONAL {{ ?o osmkey:name:en ?en }} OPTIONAL {{ ?o osmkey:alt_name ?alt }} OPTIONAL {{ ?o osmkey:official_name ?official }}
  OPTIONAL {{ ?o osmkey:access ?access }}
  ?o geo:hasGeometry/geo:asWKT ?w }}"""


def areas(ids, cache):
    """每个地方所在的都道府县（admin_level 4）、市区町村（7）、政令市的区（8）"""
    out = {}
    for i in range(0, len(ids), 500):
        values = " ".join(f"<https://www.openstreetmap.org/{x}>" for x in ids[i:i + 500])
        text = sparql(f"""SELECT ?o ?bn ?lvl WHERE {{ VALUES ?o {{ {values} }}
            ?b ogc:sfContains ?o . ?b osmkey:boundary "administrative" . ?b osmkey:name ?bn . ?b osmkey:admin_level ?lvl .
            FILTER(?lvl IN (4, 7, 8)) }}""", cache, f"gyms-jp-areas{i}")
        for o, name, level in rows(text, 3):
            if level.isdigit():
                out.setdefault(osm_id(o), {})[int(level)] = name
    return out


def existing(extra):
    out = []
    paths = sorted((root / "Badie-iOS/Badie/Resources").glob("*.json")) + sorted((root / "supabase/data").glob("*.json"))
    paths = [p for p in paths if p != OUT] + ([extra] if extra else [])
    for path in paths:
        for v in json.loads(path.read_text(encoding="utf-8"))["venues"]:
            if v["country"] == "JP":
                out.append(((v["lat"], v["lon"]), [v["name"], *v.get("aliases", [])]))
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--exclude", type=Path, help="线上库导出的我们整理的球馆（export_collected_venues.sql）")
    parser.add_argument("--cache", type=Path)
    args = parser.parse_args()
    if args.cache:
        args.cache.mkdir(parents=True, exist_ok=True)

    # 名字只是“体育館”“第二体育館”“アリーナ”这种通称的：多半是学校、园区里没起名的体育馆，也认不出是哪一家
    generic = re.compile(r"^[第大小中新旧東西南北一二三四五六七八九十0-9０-９ 　()（）・]*"
                         r"(体育館|アリーナ|サブアリーナ|メインアリーナ|屋内運動場|体育センター|スポーツセンター)"
                         r"[ 　()（）0-9０-９一二三四五六七八九十号棟]*$")
    found = {}
    for o, n, leisure, building, c, en, alt, official, access in rows(sparql(QUERY, args.cache, "gyms-jp"), 9):
        m = re.search(r"POINT\(([-\d.]+) ([-\d.]+)\)", c)
        if not m or access in ("private", "no"):
            continue
        if "stadium" in (leisure, building) and not re.search(r"(体育館|アリーナ)", n):
            continue
        if generic.match(n.strip()):
            continue
        item = found.setdefault(osm_id(o), {"osm": osm_id(o), "name": n.strip(), "point": (float(m.group(2)), float(m.group(1))),
                                            "aliases": []})
        for a in (en, *(alt or "").split(";"), official):
            a = a.strip()
            if a and a != item["name"] and a not in item["aliases"]:
                item["aliases"].append(a)

    # 同一个体育馆画了两遍（楼和整片设施）：留名字长的那个
    kept = []
    for c in sorted(found.values(), key=lambda c: (-len(c["name"]), c["osm"])):
        if not any(metres(c["point"], k["point"]) < 100 and (same_name(c["name"], k["name"]) or c["name"] in k["name"])
                   for k in kept):
            kept.append(c)

    known = existing(args.exclude)
    near = grid(known, lambda v: v[0], cell=0.02)
    fresh = [c for c in kept if not any(
        metres(c["point"], p) < 150 or (metres(c["point"], p) < 1000 and any(same_name(c["name"], n) for n in names))
        for p, names in near(c["point"]))]

    where = areas([c["osm"] for c in fresh], args.cache)
    venues = []
    for c in fresh:
        a = where.get(c["osm"], {})
        kind, number = c["osm"].split("/")
        lat, lon = c["point"]
        venue = {
            "id": f"v-jp-osmg-{kind[0]}{number}",
            "name": c["name"][:120],
            "lat": round(lat, 6), "lon": round(lon, 6),
            "street": "",
            "city": a.get(7, "") + (a.get(8, "") if a.get(8, "") != a.get(7, "") else ""),
            "region": a.get(4, ""),
            "postcode": "",
            "country": "JP",
            "tz": "Asia/Tokyo",
            "osm": c["osm"],
        }
        if c["aliases"]:
            venue["aliases"] = [x[:120] for x in c["aliases"][:6]]
        venues.append(venue)

    venues.sort(key=lambda v: (v["region"], v["city"], v["name"], v["id"]))
    catalog = {"source": "OpenStreetMap (gymnasiums in Japan)", "kind": "openStreetMap", "status": "unconfirmed",
               "attribution": "© OpenStreetMap contributors, ODbL 1.0", "venues": venues}
    OUT.write_text(json.dumps(catalog, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"{len(found)} found, {len(kept)} after merging, {len(venues)} written "
          f"({sum(1 for v in venues if v.get('aliases'))} with aliases, {sum(1 for v in venues if not v['city'])} without city)")


if __name__ == "__main__":
    main()
