"""各国的体育馆（OpenStreetMap）：supabase/data/osm-gyms-<国家>.json。

很多国家能打羽毛球的公共体育馆（日本的市民体育館、韩国的구민체육센터、台湾的國民運動中心……）在 OSM 里不标
sport=badminton，build_osm_venues.py 收不到（東京体育館就没收到）。这里按当地的叫法收名字：
- 名字符合这个国家的写法（COUNTRIES[cc]["names"]），而且是体育场馆（leisure 或 building 是 sports_centre /
  sports_hall，或者 stadium 但名字带“体育馆”一类的词）；
- 不收打不了羽毛球的（武道館、泳池、冰场、各种球场……）和军队、警察、单位自用的（COUNTRIES[cc]["skip"]）；
- 学校、大学的体育馆也收（不少学校晚上、周末开放给俱乐部和社区），标成学校体育馆（kind = school），
  附近列表里排在公共场馆后面（COUNTRIES[cc]["school"]）；
- 不收名字只是通称的（“体育館”“체육관”）：多半是学校里没起名的，也认不出是哪一家；
- 和已有的球馆（App 自带的、supabase/data 里的、--exclude 给的）150 米内或 1 公里内同名的不收。
英文名（name:en）、alt_name、official_name 做别名（冠名、英文都能搜到）。城市、省用 OSM 的行政区划。
状态“待确认”：大多是公共体育馆，也可能混进单位自用的。© OpenStreetMap 贡献者，ODbL 1.0。

用法（在仓库根目录；需要 pip install timezonefinder==6.5.9）:
    python3 supabase/scripts/build_osm_gyms.py JP KR [--exclude 线上库导出的 badie-venues.json ...] [--cache 目录]
    python3 supabase/scripts/build_osm_gyms.py --count DE FR ...   # 只数一数、看几个例子，不写文件
然后跑 build_venue_seed.py。--exclude 用 supabase/scripts/export_collected_venues.sql 导出（我们整理的球馆不在仓库里）。
"""
import argparse
import json
import random
import re
from pathlib import Path

from timezonefinder import TimezoneFinder

from build_osm_venues import grid, metres, osm_id, rows, same_name, sparql

root = Path(__file__).resolve().parents[2]
SCHOOLS = "学校|小学|中学|高校|高等|大学|학교|초등|중학|고등|대학|學|國小|國中|高中|[Ss]chool|[Cc]ollege|[Uu]niversity"

# names：名字里要有的词；skip：不收的；generic：名字只是这些通称的不收；city / region：行政区划的 admin_level
COUNTRIES = {
    "JP": {"school": f"{SCHOOLS}|号館|棟|校舎", "names": "体育館|アリーナ|スポーツセンター|総合運動場|体育センター",
           "skip": f"武道館|弓道|柔道|剣道|相撲|卓球|プール|競技場|野球|球場|陸上|サッカー|テニス|ゴルフ|スケート|"
                   "ボウリング|研修|社員|従業員|病院|刑務所|拘置所|自衛隊|駐屯地|基地|警察|消防",
           "generic": r"[第大小中新旧東西南北一二三四五六七八九十0-9０-９ 　()（）・]*"
                      r"(体育館|アリーナ|サブアリーナ|メインアリーナ|屋内運動場|体育センター|スポーツセンター)"
                      r"[ 　()（）0-9０-９一二三四五六七八九十号棟]*",
           "word": "体育館|アリーナ", "city": [7, 8], "region": 4},
    "KR": {"school": SCHOOLS, "names": "체육관|체육센터|스포츠센터|배드민턴",
           "skip": f"태권도|수영|골프|볼링|헬스|피트니스|당구|검도|유도|합기도|복싱|주짓수|클라이밍|빙상|아이스|"
                   "야구|축구|씨름|레슬링|역도|사격|양궁|무도|교회|부대|사단|경찰|교도소|아파트|사옥|연수원",
           "generic": r"(실내|다목적|제[0-9일이삼]+)?\s*(체육관|체육센터|스포츠센터|배드민턴장)\s*[0-9]*",
           "word": "체육관|배드민턴", "city": [6], "region": 4},
    "TW": {"school": SCHOOLS, "names": "運動中心|體育館|体育馆|羽球|羽毛球",
           "skip": f"游泳|泳池|網球|棒球|射箭|保齡|國軍|營區|監獄",
           "generic": r"(綜合)?(體育館|運動中心|羽球館|羽球場)", "word": "體育館|羽球", "city": [7, 8, 6], "region": 4},
    "HK": {"school": SCHOOLS, "names": "體育館|[Ss]ports [Cc]entre",
           "skip": "營|監獄", "generic": r"(體育館|[Ss]ports [Cc]entre)", "word": "體育館|[Ss]ports [Cc]entre",
           "city": [6, 5], "region": 4},
    "MY": {"school": f"{SCHOOLS}|Sekolah|SK |SMK|SJK|Universiti|Kolej", "names": "Dewan Badminton|Dewan Serbaguna|Dewan Orang Ramai|Dewan Komuniti|Kompleks Sukan|Sports Complex|"
                    "Sports Centre|Badminton|Stadium Tertutup",
           "skip": f"Masjid|Surau|Kem |Polis|Tentera|Penjara",
           "generic": r"(Dewan Serbaguna|Dewan Orang Ramai|Dewan Komuniti|Dewan Badminton|Kompleks Sukan)",
           "word": "Stadium|Dewan", "city": [6, 7, 5], "region": 4},
    "ID": {"school": f"{SCHOOLS}|Sekolah|SD |SMP|SMA|SMK|Universitas|Kampus", "names": "GOR[ .]|Gedung Olahraga|Gelanggang|Badminton|Bulu ?[Tt]angkis",
           "skip": f"Masjid|Polres|Polda|Kodim|Lanud|Lapas|[Ff]utsal|"
                   "[Ss]epak|[Bb]asket|[Vv]oli|[Rr]enang|[Kk]olam",
           "generic": r"(GOR|Gedung Olahraga|Lapangan Badminton|Lapangan Bulu ?[Tt]angkis)", "word": "GOR|Gedung",
           "city": [5], "region": 4},
    "TH": {"school": f"{SCHOOLS}|โรงเรียน|มหาวิทยาลัย", "names": "โรงยิม|แบดมินตัน|ศูนย์กีฬา|ยิมเนเซียม|Badminton|Gymnasium",
           "skip": f"ค่าย|กองทัพ|ตำรวจ|พนักงาน|ว่ายน้ำ|ฟุตซอล",
           "generic": r"(โรงยิม|ศูนย์กีฬา|ยิมเนเซียม|Gymnasium)", "word": "โรงยิม|Gymnasium", "city": [6], "region": 4},
    "VN": {"school": f"{SCHOOLS}|Trường|Đại học", "names": "Nhà thi đấu|[Cc]ầu lông|Trung tâm [Tt]hể dục [Tt]hể thao|Trung tâm [Vv]ăn hóa",
           "skip": f"[Bb]ơi|[Tt]ennis|[Bb]óng đá|Quân|Công an",
           "generic": r"(Nhà thi đấu|Sân cầu lông|Trung tâm thể dục thể thao)", "word": "Nhà thi đấu", "city": [6], "region": 4},
    "PH": {"school": f"{SCHOOLS}|FEU|UST|UP |DLSU|Ateneo|Academy", "names": "Gymnasium|Sports Complex|Sports Center|Badminton",
           # 菲律宾的 Covered Court 多是篮球场
           "skip": "Camp |Military|Police|Barracks|Covered Court|Basketball", "generic": r"(Gymnasium|Sports Complex|Sports Center)",
           "word": "Gymnasium", "city": [7, 6], "region": 4},
    "IN": {"school": SCHOOLS, "names": "Indoor Stadium|Badminton|Sports Complex",
           "skip": f"Cantonment|Army|Police|Air Force", "generic": r"(Indoor Stadium|Sports Complex)",
           "word": "Indoor Stadium|Badminton", "city": [5, 6], "region": 4},
    # 德国、法国：Sporthalle / Gymnase 很多是学校、俱乐部的（打羽毛球主要在这些地方的俱乐部）
    "DE": {"school": f"{SCHOOLS}|[Ss]chule|Gymnasium", "names": "Sporthalle|Mehrzweckhalle|Turnhalle", "skip": "Bundeswehr|Kaserne",
           "generic": r"(Sporthalle|Mehrzweckhalle|Turnhalle)", "word": "halle", "city": [8, 6], "region": 4},
    "FR": {"school": f"{SCHOOLS}|Lycée|Collège|École|Ecole", "names": "Gymnase|Salle omnisports|Salle des sports|Complexe sportif",
           "skip": "Caserne", "generic": r"(Gymnase|Salle omnisports|Salle des sports)",
           "word": "Gymnase|Salle", "city": [8], "region": 4},
    "GB": {"school": f"{SCHOOLS}|Academy", "names": "Leisure Centre|Sports Centre|Sports Hall", "skip": f"Barracks|RAF |Tennis|Golf|Swim|Pool",
           "generic": r"(Leisure Centre|Sports Centre|Sports Hall)", "word": "Centre|Hall", "city": [8, 10, 6, 5], "region": 4},
    "US": {"school": f"{SCHOOLS}|Elementary|Middle|High|Academy", "names": "Recreation Center|Rec Center|Gymnasium",  # Community Center 多半没有体育馆
           "skip": f"Church|Air Force|Army|Navy|Fort |Gymnastics|Kids|Jungle|"
                   "Little|Tumbl|Cheer|Aquatic|Pool|Senior",
           "generic": r"(Recreation Center|Rec Center|Community Center|Gymnasium)", "word": "Center|Gymnasium",
           "city": [8, 7, 6], "region": 4},
    "AU": {"school": f"{SCHOOLS}|Grammar", "names": "Leisure Centre|Sports Centre|Recreation Centre|Badminton|Stadium",
           "skip": f"Barracks|Aquatic|Swim|Pool|Tennis|Football|Cricket|Racecourse|Speedway",
           "generic": r"(Leisure Centre|Sports Centre|Recreation Centre)",
           "word": "Centre|Badminton", "city": [7, 6, 8], "region": 4},
    "CA": {"school": f"{SCHOOLS}|Secondary|Elementary", "names": "Community Centre|Recreation Centre|Community Center|Recreation Center|Badminton",
           "skip": f"Church|Forces|Curling|Ice|Rink|Hockey|Arena$|Aquatic|Pool|Seniors?",
           "generic": r"(Community Centre|Recreation Centre|Community Center|Recreation Center)",
           "word": "Centre|Center|Badminton", "city": [8, 6, 7], "region": 4},
}


def query(cc, cfg):
    return f"""SELECT ?o ?n ?l ?b (geof:centroid(?w) AS ?c) ?en ?alt ?official ?access WHERE {{
  ?o osmkey:name ?n . FILTER(REGEX(?n, "({cfg['names']})")) FILTER(!REGEX(?n, "({cfg['skip']})"))
  {{ ?o osmkey:leisure ?l . FILTER(?l IN ("sports_centre", "sports_hall", "stadium")) }}
  UNION {{ ?o osmkey:building ?b . FILTER(?b IN ("sports_hall", "sports_centre", "stadium")) }}
  ?country osmkey:ISO3166-1:alpha2 "{cc}" . ?country ogc:sfContains ?o .
  OPTIONAL {{ ?o osmkey:name:en ?en }} OPTIONAL {{ ?o osmkey:alt_name ?alt }} OPTIONAL {{ ?o osmkey:official_name ?official }}
  OPTIONAL {{ ?o osmkey:access ?access }}
  ?o geo:hasGeometry/geo:asWKT ?w }}"""


def areas(ids, levels, cache, cc):
    """每个地方所在的行政区（admin_level → 名字）"""
    out = {}
    wanted = ", ".join(str(x) for x in sorted(set(levels)))
    for i in range(0, len(ids), 500):
        values = " ".join(f"<https://www.openstreetmap.org/{x}>" for x in ids[i:i + 500])
        text = sparql(f"""SELECT ?o ?bn ?lvl WHERE {{ VALUES ?o {{ {values} }}
            ?b ogc:sfContains ?o . ?b osmkey:boundary "administrative" . ?b osmkey:name ?bn . ?b osmkey:admin_level ?lvl .
            FILTER(?lvl IN ({wanted})) }}""", cache, f"gyms-{cc.lower()}-areas{i}")
        for o, name, level in rows(text, 3):
            if level.isdigit():
                out.setdefault(osm_id(o), {})[int(level)] = name
    return out


def existing(cc, extras, out_path):
    out = []
    paths = sorted((root / "Badie-iOS/Badie/Resources").glob("*.json")) + sorted((root / "supabase/data").glob("*.json"))
    for path in [p for p in paths if p != out_path] + list(extras):
        for v in json.loads(path.read_text(encoding="utf-8"))["venues"]:
            if v["country"] == cc:
                out.append(((v["lat"], v["lon"]), [v["name"], *v.get("aliases", [])]))
    return out


def candidates(cc, cfg, cache):
    generic = re.compile(f"^\\s*{cfg['generic']}\\s*$")
    found = {}
    for o, n, leisure, building, c, en, alt, official, access in rows(sparql(query(cc, cfg), cache, f"gyms-{cc.lower()}"), 9):
        m = re.search(r"POINT\(([-\d.]+) ([-\d.]+)\)", c)
        n = n.strip()
        if not m or access in ("private", "no") or generic.match(n):
            continue
        if "stadium" in (leisure, building) and not re.search(cfg["word"], n):
            continue
        item = found.setdefault(osm_id(o), {"osm": osm_id(o), "name": n, "point": (float(m.group(2)), float(m.group(1))),
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
    return found, kept


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("countries", nargs="+")
    parser.add_argument("--exclude", type=Path, action="append", default=[],
                        help="线上库导出的我们整理的球馆（export_collected_venues.sql），可以给多个")
    parser.add_argument("--cache", type=Path)
    parser.add_argument("--count", action="store_true", help="只数一数、看几个例子，不写文件")
    args = parser.parse_args()
    if args.cache:
        args.cache.mkdir(parents=True, exist_ok=True)
    tzf = TimezoneFinder()

    for cc in args.countries:
        cfg = COUNTRIES[cc]
        out_path = root / f"supabase/data/osm-gyms-{cc}.json"
        found, kept = candidates(cc, cfg, args.cache)
        known = existing(cc, args.exclude, out_path)
        near = grid(known, lambda v: v[0], cell=0.02)
        fresh = [c for c in kept if not any(
            metres(c["point"], p) < 150 or (metres(c["point"], p) < 1000 and any(same_name(c["name"], n) for n in names))
            for p, names in near(c["point"]))]
        if args.count:
            random.seed(1)
            sample = " / ".join(c["name"] for c in random.sample(fresh, min(6, len(fresh))))
            print(f"{cc}: {len(known)} in catalogs, {len(kept)} gyms in OSM, {len(fresh)} new — {sample}", flush=True)
            continue

        where = areas([c["osm"] for c in fresh], cfg["city"] + [cfg["region"]], args.cache, cc)
        venues = []
        for c in fresh:
            a = where.get(c["osm"], {})
            names = [a[lvl] for lvl in cfg["city"] if lvl in a]
            # 日本：市 + 政令市的区（“札幌市中央区”）；别的国家：取第一个有的级别
            city = "".join(dict.fromkeys(names)) if cc == "JP" else (names[0] if names else "")
            kind, number = c["osm"].split("/")
            lat, lon = c["point"]
            venue = {"id": f"v-{cc.lower()}-osmg-{kind[0]}{number}", "name": c["name"][:120],
                     "lat": round(lat, 6), "lon": round(lon, 6), "street": "", "city": city,
                     "region": a.get(cfg["region"], ""), "postcode": "", "country": cc,
                     "tz": tzf.timezone_at(lat=lat, lng=lon), "osm": c["osm"]}
            if c["aliases"]:
                venue["aliases"] = [x[:120] for x in c["aliases"][:6]]
            if re.search(cfg["school"], " ".join([c["name"], *c["aliases"]])):
                venue["facility"] = "school"
            venues.append(venue)
        venues.sort(key=lambda v: (v["region"], v["city"], v["name"], v["id"]))
        catalog = {"source": f"OpenStreetMap (gymnasiums in {cc})", "kind": "openStreetMap", "status": "unconfirmed",
                   "attribution": "© OpenStreetMap contributors, ODbL 1.0", "venues": venues}
        out_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print(f"{cc}: {len(found)} found, {len(kept)} after merging, {len(venues)} written "
              f"({sum(1 for v in venues if v.get('aliases'))} with aliases, {sum(1 for v in venues if not v['city'])} without city)",
              flush=True)


if __name__ == "__main__":
    main()
