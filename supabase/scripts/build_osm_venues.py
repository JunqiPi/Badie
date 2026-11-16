"""从 OpenStreetMap 生成全世界（中国大陆、朝鲜除外）的羽毛球场目录：supabase/data/osm-venues.json。

OSM 里标了 sport=badminton 的都收，除了商店、标了不对外开放的、军事区里的：
- 有名字的用自己的名字；
- 没名字（或名字只是“羽毛球场”）但在一栋有名字的体育馆、体育中心里：用那栋楼；
- 没名字的露天场地叫“所在公园 / 学校 / 小区 · 羽毛球场”，50 米内同一处的几块并成一个，记下场地数；
- 不在室内的标成露天（kind = outdoor）。
和 Badie-iOS/Badie/Resources 里已有的球馆离得很近或同名的跳过。

数据来自 QLever（qlever.dev，每周同步 OSM 全球数据），只读 OSM 的数据，© OpenStreetMap 贡献者，ODbL 1.0。
这份文件本身也按 ODbL 公开（仓库是公开的）。

用法（在仓库根目录；需要 pip install reverse_geocoder==1.5.1 timezonefinder==6.5.9）:
    python3 supabase/scripts/build_osm_venues.py            # 下载并生成
    python3 supabase/scripts/build_osm_venues.py --cache D  # 用 D 目录里已下载的数据（没有就下载到那里）
然后跑 build_venue_seed.py。
"""
import argparse
import json
import math
import re
import unicodedata
import urllib.parse
import urllib.request
from collections import defaultdict
from pathlib import Path

import reverse_geocoder
from timezonefinder import TimezoneFinder

root = Path(__file__).resolve().parents[2]
OUT = root / "supabase/data/osm-venues.json"
QLEVER = "https://qlever.dev/api/osm-planet"
SKIP_COUNTRIES = {"CN", "KP"}

PREFIX = """PREFIX osmkey: <https://www.openstreetmap.org/wiki/Key:>
PREFIX geo: <http://www.opengis.net/ont/geosparql#>
PREFIX geof: <http://www.opengis.net/def/function/geosparql/>
PREFIX ogc: <http://www.opengis.net/rdf#>
PREFIX osm2rdf: <https://osm2rdf.cs.uni-freiburg.de/rdf#>
"""
BADMINTON = '?o osmkey:sport ?s . FILTER(CONTAINS(?s, "badminton"))'
QUERIES = {
    "tags": f"""SELECT ?o ?k ?v WHERE {{ {BADMINTON} ?o ?k ?v .
        FILTER(STRSTARTS(STR(?k), "https://www.openstreetmap.org/wiki/Key:")) }}""",
    "centroid": f"SELECT ?o (geof:centroid(?w) AS ?c) WHERE {{ {BADMINTON} ?o geo:hasGeometry/geo:asWKT ?w }}",
    # 每个点所在（或相交）的建筑、体育中心
    "around": f"""SELECT ?o ?b ?bl ?bb ?bn ?ba WHERE {{ {BADMINTON} ?o ogc:sfIntersects|ogc:sfWithin ?b .
        FILTER(STRSTARTS(STR(?b), "https://www.openstreetmap.org/way") || STRSTARTS(STR(?b), "https://www.openstreetmap.org/relation"))
        OPTIONAL {{ ?b osmkey:leisure ?bl }} OPTIONAL {{ ?b osmkey:building ?bb }} OPTIONAL {{ ?b osmkey:name ?bn }}
        OPTIONAL {{ ?b osmkey:amenity ?ba }}
        FILTER(BOUND(?bb) || ?bl IN ("sports_centre", "sports_hall")) }}""",
    # 没名字的场地所在的、有名字的公园 / 学校 / 小区 / 军事区
    "places": f"""SELECT ?o ?b ?bn ?bl ?ba ?blu ?area WHERE {{ {BADMINTON} FILTER NOT EXISTS {{ ?o osmkey:name ?on }}
        ?o ogc:sfWithin|ogc:sfIntersects ?b . ?b osmkey:name ?bn . FILTER NOT EXISTS {{ ?b osmkey:boundary ?bd }}
        FILTER(STRSTARTS(STR(?b), "https://www.openstreetmap.org/way") || STRSTARTS(STR(?b), "https://www.openstreetmap.org/relation"))
        OPTIONAL {{ ?b osmkey:leisure ?bl }} OPTIONAL {{ ?b osmkey:amenity ?ba }} OPTIONAL {{ ?b osmkey:landuse ?blu }}
        OPTIONAL {{ ?b osm2rdf:area ?area }} FILTER(BOUND(?bl) || BOUND(?ba) || BOUND(?blu)) }}""",
}
# 没名字的场地叫什么（按当地语言）
COURT = {"KR": "배드민턴장", "JP": "バドミントンコート", "TW": "羽球場", "HK": "羽毛球場", "MO": "羽毛球場",
         "ID": "Lapangan bulu tangkis", "MY": "Gelanggang badminton", "VN": "Sân cầu lông", "TH": "สนามแบดมินตัน",
         "FR": "Terrain de badminton", "BE": "Terrain de badminton", "DE": "Badmintonfeld", "AT": "Badmintonfeld",
         "ES": "Pista de bádminton", "RU": "Площадка для бадминтона", "UA": "Майданчик для бадмінтону"}

# 去掉这些词后什么都不剩的名字只是“羽毛球场”，不算球馆名
GENERIC = set("""badminton badmintons court courts hall halls indoor outdoor pitch pitches field ground grounds the of
and a no nr number area sport sports gym gymnasium arena centre center club room multi purpose multipurpose
lapangan gor sân cầu lông nhà thi đấu campo de del cancha quadra platz feld halle terrain salle hal sal bulutangkis
bulu tangkis tangkis gedung bádminton batminton badmiton badmintor badmington indoor college badmintonplatz badmintonhalle badmintonbane court1 court2 basketball volleyball
tennis futsal netball table squash""".split())
GENERIC_CJK = re.compile(r"^(体育|體育|헬스장|羽毛球|羽球|球|场|場|馆|館|室|地|号|號|배드민턴|장|체육관|코트|バドミントン|コート|体育館|สนาม|แบดมินตัน|\d|\s)+$")
STORE = re.compile(r"decathlon|superstore|\bstore\b|\bshop\b|水池|tanque|tennis school|テニス", re.I)
HOME_BUILDINGS = {"apartments", "residential", "house", "detached", "terrace", "semidetached_house", "dormitory",
                  "school", "kindergarten", "church", "hotel", "roof", "garage", "garages", "hut", "shed"}
NOT_PUBLIC = {"private", "no"}


def sparql(query, cache, name):
    path = cache / f"{name}.tsv" if cache else None
    if path and path.exists():
        return path.read_text(encoding="utf-8")
    req = urllib.request.Request(QLEVER, data=urllib.parse.urlencode({"query": PREFIX + query}).encode(),
                                 headers={"Accept": "text/tab-separated-values", "User-Agent": "BadieVenueImport/1.0"})
    text = urllib.request.urlopen(req, timeout=600).read().decode("utf-8")
    if path:
        path.write_text(text, encoding="utf-8")
    return text


def literal(s):
    if not s.startswith('"'):
        return s
    s = s[1:s.rindex('"')]
    return re.sub(r'\\(["\\nt])', lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), s)


def osm_id(iri):
    return iri.strip("<>").replace("https://www.openstreetmap.org/", "")


def rows(text, width):
    for line in text.splitlines()[1:]:
        cells = line.split("\t")
        yield [literal(c) for c in cells + [""] * (width - len(cells))]


def generic(name):
    words = re.findall(r"[^\W_]+", unicodedata.normalize("NFKC", name).lower())
    return len(name) < 2 or GENERIC_CJK.match(name) is not None or all(w in GENERIC or w.isdigit() for w in words)


def clean_name(name):
    # “电视台;Mitto Badminton” 这种一个点上标了两家的：用和羽毛球有关的那家
    parts = [p.strip() for p in name.split(";") if p.strip()] or [""]
    name = next((p for p in parts if re.search(r"badminton|羽|배드민턴|バドミントン|แบดมินตัน", p, re.I)), parts[0])
    return re.sub(r"\s+", " ", name).strip()[:120]


def metres(a, b):
    dlat, dlon = math.radians(b[0] - a[0]), math.radians(b[1] - a[1])
    h = math.sin(dlat / 2) ** 2 + math.cos(math.radians(a[0])) * math.cos(math.radians(b[0])) * math.sin(dlon / 2) ** 2
    return 12_742_000 * math.asin(math.sqrt(h))


def tokens(name):
    return {w for w in re.findall(r"[^\W_]+", unicodedata.normalize("NFKC", name).lower()) if w not in GENERIC and len(w) > 1}


def same_name(a, b):
    ta, tb = tokens(a), tokens(b)
    return bool(ta and tb) and len(ta & tb) / min(len(ta), len(tb)) >= 0.6


def slug(text):
    return re.sub(r"[^a-z0-9]+", "", text.lower())


def candidates(cache):
    tags = defaultdict(dict)
    for o, k, v in rows(sparql(QUERIES["tags"], cache, "tags"), 3):
        tags[osm_id(o)][k.strip("<>").split("Key:")[1]] = v
    points = {}
    for o, c in rows(sparql(QUERIES["centroid"], cache, "centroid"), 2):
        m = re.search(r"POINT\(([-\d.]+) ([-\d.]+)\)", c)
        if m:
            points[osm_id(o)] = (float(m.group(2)), float(m.group(1)))
    around = defaultdict(list)
    for o, b, leisure, building, name, amenity in rows(sparql(QUERIES["around"], cache, "around"), 6):
        around[osm_id(o)].append({"id": osm_id(b), "leisure": leisure, "building": building, "name": name, "amenity": amenity})
    # 没名字的场地所在的公园、学校、小区（取最小的那个）
    places = {}
    for o, b, name, leisure, amenity, landuse, area in rows(sparql(QUERIES["places"], cache, "places"), 7):
        size = float(area) if area else math.inf
        if landuse == "military" or amenity == "military":
            places[osm_id(o)] = (-1, None)
        elif osm_id(o) not in places or (places[osm_id(o)][1] and size < places[osm_id(o)][0]):
            places[osm_id(o)] = (size, (osm_id(b), clean_name(name)))

    found = {}
    for oid, t in tags.items():
        if oid not in points or t.get("access") in NOT_PUBLIC or "shop" in t or "disused" in str(t):
            continue
        place = places.get(oid)
        if place and place[1] is None:  # 军事区里的
            continue
        name = clean_name(t.get("name", ""))
        if STORE.search(name):
            continue
        halls = [a for a in around[oid] if a["leisure"] in ("sports_centre", "sports_hall")
                 or (a["building"] and a["building"] not in HOME_BUILDINGS and a["amenity"] != "school")]
        indoor = (t.get("indoor") or t.get("covered")) != "no" and (
            t.get("leisure") in ("sports_centre", "sports_hall", "fitness_centre") or "building" in t
            or (t.get("indoor") or t.get("covered")) == "yes" or bool(halls))
        if name and not generic(name):
            found[oid] = {"osm": oid, "name": name, "tags": t, "point": points[oid], "strength": 2 if indoor else 1,
                          "outdoor": not indoor, "courts": 1}
            continue
        hall = next((h for h in halls if h["name"] and not generic(h["name"]) and not STORE.search(h["name"])), None)
        if hall and indoor:  # 没名字的场地在一栋有名字的体育馆里：用那栋楼
            found.setdefault(hall["id"], {"osm": hall["id"], "name": clean_name(hall["name"]), "tags": t,
                                          "point": points[oid], "strength": 2, "outdoor": False, "courts": 1})
            continue
        # 没名字的露天场地：叫“某某公园 · 羽毛球场”，同一处的几块场地并成一个
        where = place[1] if place and not generic(place[1][1]) else None
        found[oid] = {"osm": oid, "name": None, "where": where, "tags": t, "point": points[oid], "strength": 0,
                      "outdoor": not indoor, "courts": 1}
    return list(found.values())


def existing_venues():
    out = []
    for path in sorted((root / "Badie-iOS/Badie/Resources").glob("*.json")):
        for v in json.loads(path.read_text(encoding="utf-8"))["venues"]:
            out.append(((v["lat"], v["lon"]), [v["name"], *v.get("aliases", [])]))
    return out


def grid(items, key, cell=0.01):
    g = defaultdict(list)
    for item in items:
        p = key(item)
        g[(int(p[0] // cell), int(p[1] // cell))].append(item)
    return lambda p: (x for i in (-1, 0, 1) for j in (-1, 0, 1)
                      for x in g.get((int(p[0] // cell) + i, int(p[1] // cell) + j), ()))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cache", type=Path)
    args = parser.parse_args()
    if args.cache:
        args.cache.mkdir(parents=True, exist_ok=True)

    found = candidates(args.cache)
    # 同一家在 OSM 里画了两次（楼和里面的场地、两个点）：留更像球馆、名字更长的那个；
    # 没名字的露天场地挨着（50 米内、同一个公园 / 学校）的并成一处，记下几块场地
    found.sort(key=lambda c: (-c["strength"], -len(c["name"] or ""), c["osm"]))
    kept = []
    kept_grid = defaultdict(list)
    for c in found:
        cellkey = (int(c["point"][0] // 0.01), int(c["point"][1] // 0.01))
        neighbours = [x for i in (-1, 0, 1) for j in (-1, 0, 1) for x in kept_grid.get((cellkey[0] + i, cellkey[1] + j), ())]
        if c["name"]:
            if any(metres(c["point"], k["point"]) < 60 or (metres(c["point"], k["point"]) < 400 and same_name(c["name"], k["name"]))
                   for k in neighbours):
                continue
        else:
            if any(k["name"] and metres(c["point"], k["point"]) < 60 for k in neighbours):
                continue
            twin = next((k for k in neighbours if not k["name"] and k["where"] == c["where"]
                         and k["outdoor"] == c["outdoor"] and metres(c["point"], k["point"]) < 50), None)
            if twin:
                twin["courts"] += 1
                continue
        kept.append(c)
        kept_grid[cellkey].append(c)

    known = existing_venues()
    near_known = grid(known, lambda v: v[0], cell=0.02)
    fresh = [c for c in kept if not any(
        metres(c["point"], p) < 150 or (c["name"] and metres(c["point"], p) < 1000 and any(same_name(c["name"], n) for n in names))
        for p, names in near_known(c["point"]))]

    places = reverse_geocoder.search([c["point"] for c in fresh], mode=1) if fresh else []
    tzf = TimezoneFinder()
    venues = []
    for c, place in zip(fresh, places):
        country = place["cc"]
        if country in SKIP_COUNTRIES:
            continue
        t = c["tags"]
        street = " ".join(x for x in [t.get("addr:housenumber", ""), t.get("addr:street", "")] if x)
        if country in ("JP", "KR", "TW", "HK") and t.get("addr:street"):
            street = t.get("addr:street", "") + t.get("addr:housenumber", "")
        lat, lon = c["point"]
        kind, number = c["osm"].split("/")
        term = COURT.get(country, "Badminton court")
        name = c["name"] or (f"{c['where'][1]} · {term}" if c["where"] else term)
        venue = {
            "id": f"v-{country.lower()}-osm-{kind[0]}{number}",
            "name": name[:120],
            "lat": round(lat, 6), "lon": round(lon, 6),
            "street": street,
            "city": t.get("addr:city") or place["name"],
            "region": t.get("addr:state") or t.get("addr:province") or place["admin1"],
            "postcode": t.get("addr:postcode", ""),
            "country": country,
            "tz": tzf.timezone_at(lat=lat, lng=lon),
            "osm": c["osm"],
        }
        if c["outdoor"]:
            venue["facility"] = "outdoor"
        if c["courts"] > 1:
            venue["courts"] = c["courts"]
        # 别名：OSM 里各种语言的名字，换一种语言也能搜到；自动起名的场地加上英文的“Badminton court”
        aliases = []
        if c["name"]:
            for key, value in sorted(t.items()):
                if key.startswith("name:") or key in ("alt_name", "official_name", "int_name", "short_name", "old_name", "loc_name"):
                    aliases += [clean_name(v) for v in value.split(";")]
        elif term != "Badminton court":
            aliases.append(f"{c['where'][1]} · Badminton court" if c["where"] else "Badminton court")
        aliases = list(dict.fromkeys(a for a in aliases if 2 <= len(a) <= 120 and a != venue["name"]))[:12]
        if aliases:
            venue["aliases"] = aliases
        if t.get("website") or t.get("contact:website"):
            venue["web"] = t.get("website") or t.get("contact:website")
        if t.get("phone") or t.get("contact:phone"):
            venue["phone"] = (t.get("phone") or t.get("contact:phone")).split(";")[0].strip()
        venues.append(venue)

    venues.sort(key=lambda v: (v["country"], v["region"], v["city"], v["name"], v["id"]))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    catalog = {"source": "OpenStreetMap", "kind": "openStreetMap", "status": "unconfirmed",
               "attribution": "© OpenStreetMap contributors, ODbL 1.0", "venues": venues}
    OUT.write_text(json.dumps(catalog, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    by_country = defaultdict(int)
    for v in venues:
        by_country[v["country"]] += 1
    outdoor = sum(1 for v in venues if v.get("facility") == "outdoor")
    print(f"{len(found)} candidates, {len(kept)} after merging, {len(fresh)} new, {len(venues)} written ({outdoor} outdoor)")
    print(", ".join(f"{k} {n}" for k, n in sorted(by_country.items(), key=lambda x: -x[1])))


if __name__ == "__main__":
    main()
