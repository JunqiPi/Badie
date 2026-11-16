"""把我们自己整理的球馆表（CSV，两列：name,address）转成 Badie 的球馆目录：--cache 目录里的 badie-venues.json。
这份数据不进公开仓库（防止被一次拿走），直接写进线上数据库。

- 名字是“This centre listing could not be confirmed”的不收（网上收集、确认不了的）；
- 名字是“Badminton pitch in 某地 #123”这种 OSM 编号的不收：OpenStreetMap 的球场由 build_osm_venues.py 管；
- 和已有目录（App 自带的、supabase/data 里的）同名同城、或 60 米内、或 1 公里内同名的跳过；
- 中国大陆、朝鲜不收。

坐标先按名字到 OpenStreetMap 里批量找（QLever，一次 500 个名字）：同名的地方所在的市 / 区 / 省、邮编或 addr:city
出现在表里的地址中，就用它的位置。找不到的再用 Nominatim（OpenStreetMap 的地址搜索，每秒最多 1 次）按地址查，每条最多 3 次；
只查到城市 / 邮编一级的，标成位置大概（approx，状态“待确认”）。查过的结果存在 --cache 目录，重跑不重复查。
不打包进 App；坐标署名 © OpenStreetMap contributors（ODbL）。id 由名字和地址算出，重跑不会换。

用法（在仓库根目录；需要 pip install timezonefinder==6.5.9）:
    python3 supabase/scripts/build_imported_venues.py 球馆表.csv --cache 某个目录
然后跑 build_venue_seed.py。
"""
import argparse
import csv
import hashlib
import json
import re
import sys
import time
import unicodedata
import urllib.parse
import urllib.request
from pathlib import Path

from timezonefinder import TimezoneFinder

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_osm_venues import PREFIX, QLEVER, STORE, generic, grid, literal, metres, osm_id, rows, same_name  # noqa: E402

root = Path(__file__).resolve().parents[2]
NOMINATIM = "https://nominatim.openstreetmap.org/search"
SKIP_COUNTRIES = {"CN", "KP"}
UNCONFIRMED = re.compile(r"could not be confirmed", re.I)
OSM_NUMBERED = re.compile(r"#\d+$")
SHOP = re.compile(r"\bshop|\bstore\b|cửa hàng|toko\b", re.I)  # 商店不收（和 OSM 那批一样）
# Nominatim 的 place_rank：26 以上是街道、门牌、具体的地方；以下是区、城市、邮编
EXACT_RANK = 26


def norm(s):
    return re.sub(r"[\W_]+", "", unicodedata.normalize("NFKD", s).lower())


def clean_address(address):
    """去掉重复的段，认出“城市, CC, 城市”结尾里的国家代码。"""
    parts = [p.strip() for p in address.replace("\\n", " ").replace("\n", " ").split(",") if p.strip()]
    country = None
    if len(parts) >= 3 and re.fullmatch(r"[A-Z]{2}", parts[-2]) and parts[-1] == parts[-3]:
        country = parts[-2]
        parts = parts[:-2]
    out = []
    for p in parts:
        if p not in out:
            out.append(p)
    return ", ".join(out), country


class Geocoder:
    def __init__(self, cache):
        self.path = cache / "nominatim.jsonl"
        self.known = {}
        if self.path.exists():
            for line in self.path.read_text(encoding="utf-8").splitlines():
                item = json.loads(line)
                self.known[item["q"]] = item["r"]
        self.last = 0.0
        self.calls = 0

    def search(self, query, country=None, cached_only=False):
        key = f"{query}|{country or ''}"
        if key in self.known or cached_only:
            return self.known.get(key)
        params = {"q": query, "format": "jsonv2", "addressdetails": 1, "limit": 1}
        if country:
            params["countrycodes"] = country.lower()
        # 每秒最多 1 次：从上一次发出算起（不是从收到回复算起，不然一次要 2 秒多）
        wait = 1.05 - (time.time() - self.last)
        if wait > 0:
            time.sleep(wait)
        self.last = time.time()
        result = []
        for attempt in range(2):
            try:
                req = urllib.request.Request(NOMINATIM + "?" + urllib.parse.urlencode(params),
                                             headers={"User-Agent": "BadieVenueImport/1.0 (+https://badie.rsvp)"})
                result = json.loads(urllib.request.urlopen(req, timeout=30).read().decode("utf-8"))
                break
            except Exception as e:  # 有的地址 Nominatim 算不过来（503 超时）：再试一次，还不行就当查不到
                print(f"retry {query!r}: {e}", file=sys.stderr)
                time.sleep(2)
                self.last = time.time()
        self.calls += 1
        hit = result[0] if result else None
        self.known[key] = hit
        with self.path.open("a", encoding="utf-8") as f:
            f.write(json.dumps({"q": key, "r": hit}, ensure_ascii=False) + "\n")
        return hit


def fallbacks(query):
    """整条地址查不到时依次再试：去掉邮编和州缩写（“MH”“VIC”），再从前往后去掉楼名、门牌。
    不单独查邮编：别的国家也有同号的邮编。返回 [(查询, 查到的算不算精确位置)]。"""
    parts = query.split(", ") if query else []
    core = [p for p in parts if not re.fullmatch(r"[\d\s-]+", p) and not re.fullmatch(r"[A-Z]{2,3}", p)]
    out = [(query, True), (", ".join(core), True)] + [(", ".join(core[k:]), False) for k in range(1, len(core))]
    seen, result = set(), []
    for q, exact in out:
        if q and q not in seen:
            seen.add(q)
            result.append((q, exact))
    return result, core


def sparql(query, cache, name):
    path = cache / f"qlever-{hashlib.sha1(query.encode()).hexdigest()[:16]}-{name}.tsv"
    if path.exists():
        return path.read_text(encoding="utf-8")
    for attempt in range(4):
        try:
            req = urllib.request.Request(QLEVER, data=urllib.parse.urlencode({"query": PREFIX + query}).encode(),
                                         headers={"Accept": "text/tab-separated-values", "User-Agent": "BadieVenueImport/1.0"})
            text = urllib.request.urlopen(req, timeout=600).read().decode("utf-8")
            break
        except Exception as e:
            if attempt == 3:
                raise
            print(f"qlever retry: {e}", file=sys.stderr)
            time.sleep(10 * (attempt + 1))
    path.write_text(text, encoding="utf-8")
    return text


def osm_matches(todo, cache):
    """按名字在 OSM 里找同名的地方，核对它在不在地址写的城市里。返回 {(name, address): 像 Nominatim 结果的 dict}"""
    names = sorted({name for name, _ in todo if not generic(name)})
    quote = lambda s: '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'
    objects = {}
    for i in range(0, len(names), 500):
        values = " ".join(quote(n) for n in names[i:i + 500])
        text = sparql(f"""SELECT ?n ?o (geof:centroid(?w) AS ?c) ?city ?pc ?street ?hn WHERE {{ VALUES ?n {{ {values} }}
            ?o osmkey:name ?n . ?o geo:hasGeometry/geo:asWKT ?w .
            OPTIONAL {{ ?o osmkey:addr:city ?city }} OPTIONAL {{ ?o osmkey:addr:postcode ?pc }}
            OPTIONAL {{ ?o osmkey:addr:street ?street }} OPTIONAL {{ ?o osmkey:addr:housenumber ?hn }} }}""", cache, f"names{i}")
        for n, o, c, city, pc, street, hn in rows(text, 7):
            m = re.search(r"POINT\(([-\d.]+) ([-\d.]+)\)", c)
            if m:
                objects.setdefault(osm_id(o), {"name": n, "point": (float(m.group(2)), float(m.group(1))),
                                               "city": city, "postcode": pc, "street": street, "hn": hn, "areas": []})
    ids = sorted(objects)
    for i in range(0, len(ids), 500):
        values = " ".join(f"<https://www.openstreetmap.org/{x}>" for x in ids[i:i + 500])
        text = sparql(f"""SELECT ?o ?bn ?lvl ?iso WHERE {{ VALUES ?o {{ {values} }}
            ?b ogc:sfContains ?o . ?b osmkey:boundary "administrative" . ?b osmkey:name ?bn . ?b osmkey:admin_level ?lvl .
            OPTIONAL {{ ?b osmkey:ISO3166-1:alpha2 ?iso }} }}""", cache, f"areas{i}")
        for o, name, level, iso in rows(text, 4):
            if osm_id(o) in objects and level.isdigit():
                objects[osm_id(o)]["areas"].append((int(level), name, iso))
    by_name = {}
    for oid, obj in objects.items():
        by_name.setdefault(obj["name"], []).append(obj)

    found = {}
    for name, address in todo:
        words = plain_words(address)
        fits = []
        for obj in by_name.get(name, []):
            country = next((iso for level, _, iso in obj["areas"] if level == 2 and iso), "")
            places = sorted(((level, n) for level, n, _ in obj["areas"] if level >= 4 and plain_words(n) <= words), reverse=True)
            ok = places or (obj["postcode"] and norm(obj["postcode"]) in norm(address)) or \
                (obj["city"] and plain_words(obj["city"]) <= words)
            if country and ok:
                fits.append((obj, country, places))
        # 同名的好几处都对得上、又离得远：分不清是哪一家，交给地址查
        if not fits or any(metres(fits[0][0]["point"], f[0]["point"]) > 2000 for f in fits):
            continue
        obj, country, places = fits[0]
        region = next((n for level, n, _ in sorted(obj["areas"]) if level == 4), "")
        city = obj["city"] or (places[0][1] if places else next((n for level, n, _ in sorted(obj["areas"], reverse=True) if level <= 8), ""))
        found[(name, address)] = {
            "lat": obj["point"][0], "lon": obj["point"][1], "place_rank": 30, "name": name,
            "display_name": ", ".join(n for _, n, _ in sorted(obj["areas"], reverse=True)),
            "address": {"country_code": country.lower(), "city": city, "state": region, "postcode": obj["postcode"],
                        "road": obj["street"], "house_number": obj["hn"]},
        }
    return found


def plain_words(text):
    """不分大小写、不分声调的词（Đ 当 D）。"""
    text = unicodedata.normalize("NFKD", text.replace("đ", "d").replace("Đ", "D").lower())
    text = "".join(ch for ch in text if unicodedata.category(ch) != "Mn")
    return set(re.findall(r"[^\W_]+", text))


def locality(hit):
    a = hit.get("address", {})
    return next((a[k] for k in ("city", "town", "village", "municipality", "suburb", "county", "state_district", "state")
                 if a.get(k)), "")


def existing_venues():
    out = []
    paths = sorted((root / "Badie-iOS/Badie/Resources").glob("*.json")) + sorted((root / "supabase/data").glob("*.json"))
    for path in paths:
        for v in json.loads(path.read_text(encoding="utf-8"))["venues"]:
            out.append({"point": (v["lat"], v["lon"]), "names": [v["name"], *v.get("aliases", [])],
                        "places": {norm(x) for x in (v.get("city"), v.get("postcode")) if x}})
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("csv", type=Path)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--dry-run", action="store_true", help="只数一数，不查坐标")
    args = parser.parse_args()
    args.cache.mkdir(parents=True, exist_ok=True)

    known = existing_venues()
    by_name = {}
    for v in known:
        for n in v["names"]:
            by_name.setdefault(norm(n), []).append(v)

    counts = {"rows": 0, "unconfirmed": 0, "osm_numbered": 0, "duplicate_row": 0, "same_name_same_city": 0}
    todo, seen = [], set()
    with args.csv.open(encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            counts["rows"] += 1
            name = re.sub(r"\s+", " ", row["name"]).strip()[:120]
            address = row["address"].strip()
            if UNCONFIRMED.search(name) or not name:
                counts["unconfirmed"] += 1
                continue
            if OSM_NUMBERED.search(name):
                counts["osm_numbered"] += 1
                continue
            if STORE.search(name) or SHOP.search(name):
                counts["shop"] = counts.get("shop", 0) + 1
                continue
            if (norm(name), norm(address)) in seen:
                counts["duplicate_row"] += 1
                continue
            seen.add((norm(name), norm(address)))
            addr_norm = norm(address)
            if any(p and p in addr_norm for v in by_name.get(norm(name), []) for p in v["places"]):
                counts["same_name_same_city"] += 1
                continue
            todo.append((name, address))
    print(counts, "to geocode:", len(todo))
    if args.dry_run:
        return

    matched = osm_matches(todo, args.cache)
    print(f"{len(matched)} matched by name in OpenStreetMap", flush=True)
    geo = Geocoder(args.cache)
    found = []
    for i, (name, address) in enumerate(todo):
        if i % 200 == 0:
            print(f"{i}/{len(todo)} ({geo.calls} requests)", flush=True)
        query, country = clean_address(address)
        queries, core = fallbacks(query)
        if (name, address) in matched:
            hit = matched[(name, address)]
            found.append({"name": name, "address": address, "hit": hit, "approx": False, "core": core,
                          "point": (hit["lat"], hit["lon"])})
            continue
        hit, exact = None, False
        for q, whole in queries[:3]:
            hit = geo.search(q, country)
            # Nominatim 会模糊匹配：“P. Bình Thắng, Dĩ An”给出别的省的“Lãnh Binh Thăng”。查到的地方得在我们写的城市里
            if hit and plain_words(q.split(", ")[-1]) <= plain_words(hit["display_name"]):
                # 去掉楼名后查到的，门牌号对得上才算精确；不然只能说明在哪个城市
                number = hit.get("address", {}).get("house_number", "")
                exact = hit["place_rank"] >= EXACT_RANK and (whole or (number and number in re.findall(r"\w+", q)))
                break
            hit = None
        if not exact and not generic(name):
            # 按名字在附近找这家馆
            where = locality(hit) if hit else (query.split(", ")[-1] if query else "")
            # 名字在 OSM 里已经批量找过了：只用以前查过的结果，不再一条条查
            byname = geo.search(f"{name}, {where}" if where else name,
                                country or (hit["address"].get("country_code") if hit else None), cached_only=True)
            if byname and byname["place_rank"] >= EXACT_RANK and same_name(name, byname.get("name") or "") and (
                    not hit or metres((float(hit["lat"]), float(hit["lon"])),
                                      (float(byname["lat"]), float(byname["lon"]))) < 30_000):
                hit, exact = byname, True
        if not hit or (not exact and generic(name)):  # 只知道在哪个城市、名字又只是“羽毛球场”的：找不到是哪一家
            continue
        found.append({"name": name, "address": address, "hit": hit, "approx": not exact, "core": core,
                      "point": (float(hit["lat"]), float(hit["lon"]))})

    near_known = grid(known, lambda v: v["point"], cell=0.02)
    in_region = grid(known, lambda v: v["point"], cell=0.3)

    def near_existing(c):
        p = c["point"]
        if c["approx"]:  # 只知道在哪个城市：30 公里内有同名的就算同一家
            return any(metres(p, v["point"]) < 30_000 and any(same_name(c["name"], n) for n in v["names"])
                       for v in in_region(p))
        return any(metres(p, v["point"]) < 60 or (metres(p, v["point"]) < 1000
                   and any(same_name(c["name"], n) for n in v["names"])) for v in near_known(p))

    tzf = TimezoneFinder()
    venues, kept = [], []
    skipped = {"no_coordinates_or_vague": len(todo) - len(found), "country": 0, "near_existing": 0, "duplicate": 0}
    # 位置准的先放，同一家写了两遍时留准的那条
    for c in sorted(found, key=lambda c: (c["approx"], c["name"], c["address"])):
        a = c["hit"].get("address", {})
        country = (a.get("country_code") or "").upper()
        if not country or country in SKIP_COUNTRIES:
            skipped["country"] += 1
            continue
        p = c["point"]
        if near_existing(c):
            skipped["near_existing"] += 1
            continue
        if any(same_name(c["name"], k["name"]) and metres(p, k["point"]) < (30_000 if c["approx"] else 1000) for k in kept):
            skipped["duplicate"] += 1
            continue
        kept.append(c)
        if c["approx"]:  # 位置大概的：街道、城市用表里写的，不用 Nominatim 模糊命中的那个地方
            street = c["core"][0] if len(c["core"]) > 1 else ""
            city = c["core"][-1] if c["core"] else locality(c["hit"])
        else:
            street = " ".join(x for x in (a.get("house_number", ""), a.get("road", "")) if x)
            if country in ("JP", "KR", "TW", "HK") and a.get("road"):
                street = a.get("road", "") + a.get("house_number", "")
            first = c["address"].split(",")[0].strip()
            if not street and re.search(r"\d", first):
                street = first
            city = locality(c["hit"])
        digest = hashlib.sha1(f"{c['name']}|{c['address']}".encode()).hexdigest()[:10]
        venue = {
            "id": f"v-{country.lower()}-b{digest}",
            "name": c["name"],
            "lat": round(p[0], 6), "lon": round(p[1], 6),
            "street": street,
            "city": city,
            "region": a.get("state") or a.get("province") or a.get("region") or "",
            "postcode": a.get("postcode", ""),
            "country": country,
            "tz": tzf.timezone_at(lat=p[0], lng=p[1]),
        }
        if c["approx"]:
            venue["approx"] = True
        venues.append(venue)

    venues.sort(key=lambda v: (v["country"], v["region"], v["city"], v["name"], v["id"]))
    assert len({v["id"] for v in venues}) == len(venues)
    catalog = {"source": "Badie research: venues we collected; coordinates from OpenStreetMap (Nominatim)",
               "kind": "curated", "status": "unconfirmed",
               "attribution": "Coordinates © OpenStreetMap contributors, ODbL 1.0", "venues": venues}
    out = args.cache / "badie-venues.json"
    out.write_text(json.dumps(catalog, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    by_country = {}
    for v in venues:
        by_country[v["country"]] = by_country.get(v["country"], 0) + 1
    approx = sum(1 for v in venues if v.get("approx"))
    print(f"{len(venues)} written ({approx} approximate), skipped {skipped}, {geo.calls} requests")
    print(", ".join(f"{k} {n}" for k, n in sorted(by_country.items(), key=lambda x: -x[1])))


if __name__ == "__main__":
    main()
