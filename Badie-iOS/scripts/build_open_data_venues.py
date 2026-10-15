#!/usr/bin/env python3
"""从各地政府开放数据生成 App 内置的羽毛球馆目录（Badie/Resources/venues-XX.json）。

用法: build_open_data_venues.py <原始数据目录> <输出目录>

原始数据（下载方式见 docs/DESIGN.md §15）：
  hk/smartplay-badminton.json  康文署 SmartPLAY 羽毛球场空场数据（DATA.GOV.HK）
  sg/sport_facilities.csv      Sport Singapore「Sport Facilities」（data.gov.sg）
  sg/sportsg_facilities.geojson Sport Singapore「SportSG Sport Facilities」
  tw/national_venues.csv       運動部「全國運動場館資訊」（data.gov.tw 22849）
  uk/ap_sportshall.json, uk/ap_sites.json  Sport England Active Places（CC BY 4.0）
"""
import csv, json, re, sys, hashlib
from collections import defaultdict
from pathlib import Path

RAW, OUT = Path(sys.argv[1]), Path(sys.argv[2])


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")[:40]


def short_hash(text):
    return hashlib.sha1(text.encode()).hexdigest()[:8]


def write(country, source, attribution, venues):
    venues = sorted(venues, key=lambda v: v["id"])
    ids = [v["id"] for v in venues]
    assert len(ids) == len(set(ids)), f"{country}: duplicate ids"
    payload = {"country": country, "source": source, "attribution": attribution, "venues": venues}
    path = OUT / f"venues-{country}.json"
    path.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    print(f"{country}: {len(venues)} venues -> {path.name}")


def hong_kong():
    """SmartPLAY 能订的康文署羽毛球场馆；场数取单个时段可订场数的最大值（估算）。"""
    rows = json.loads((RAW / "hk/smartplay-badminton.json").read_text())
    venues, courts = {}, defaultdict(int)
    for r in rows:
        name = re.sub(r"\s*[（(].*?[）)]\s*$", "", r["Venue_Name_TC"]).strip()
        key = r["Venue_Name_EN"]
        slot = (key, r["Available_Date"], r["Session_Start_Time"], r["Facility_Location_Name_EN"])
        courts[slot] += int(r["Available_Courts"] or 0)
        venues.setdefault(key, {
            "id": "v-hk-" + slug(re.sub(r"\(.*?\)", "", key)),
            "name": name,
            "aliases": [re.sub(r"\s*\(.*?\)\s*", "", key).strip()],
            "lat": round(float(r["Venue_Latitude"]), 6), "lon": round(float(r["Venue_Longitude"]), 6),
            "street": r["Venue_Address_TC"], "city": r["District_Name_TC"], "region": "香港",
            "postcode": "", "country": "HK", "tz": "Asia/Hong_Kong",
            "phone": r.get("Venue_Phone_No.") or None,
            "web": "https://www.smartplay.lcsd.gov.hk/",
        })
    for (key, *_), count in courts.items():
        venues[key]["courts"] = max(venues[key].get("courts", 0), count)
    write("HK", "康樂及文化事務署 SmartPLAY", "資料來源：康樂及文化事務署 / DATA.GOV.HK", venues.values())


def singapore():
    """ActiveSG 体育中心 + 设有羽毛球场的社区中心（CC/RC）；私人公寓的球场不对外，排除。"""
    venues = []
    for f in json.loads((RAW / "sg/sportsg_facilities.geojson").read_text())["features"]:
        p, (lon, lat) = f["properties"], f["geometry"]["coordinates"]
        name = p["VENUE"]
        if not re.search(r"Sport Centre|Woodlands SC|Sport Village|Sport Park", name):
            continue
        street = " ".join(x for x in (p.get("ADDRESSBLOCKHOUSENUMBER"), p.get("ADDRESSSTREETNAME")) if x)
        venues.append({"id": "v-sg-" + slug(name), "name": name.replace("Woodlands SC", "Woodlands Sport Centre"),
                       "lat": round(lat, 6), "lon": round(lon, 6), "street": street, "city": "Singapore",
                       "region": "", "postcode": p.get("POSTAL_CODE") or "", "country": "SG", "tz": "Asia/Singapore",
                       "web": "https://www.activesgcircle.gov.sg/facilities"})
    seen = set()
    with open(RAW / "sg/sport_facilities.csv", encoding="utf-8-sig") as fh:
        for r in csv.DictReader(fh):
            name = r["VenueName"].strip()
            if r["SportsFacility"].strip().lower() != "badminton court" or name in seen:
                continue
            if not re.search(r"\bCC\b|Community Club|Community Centre|\bRC\b", name, re.I):
                continue
            seen.add(name)
            venues.append({"id": "v-sg-" + slug(name), "name": name, "lat": float(r["Latitude"]),
                           "lon": float(r["Longitude"]), "street": "", "city": "Singapore", "region": "",
                           "postcode": r["PostalCode"], "country": "SG", "tz": "Asia/Singapore",
                           "web": "https://www.onepa.gov.sg/facilities"})
    write("SG", "Sport Singapore / data.gov.sg",
          "Contains information from Sport Facilities from data.gov.sg, made available under the Singapore Open Data Licence v1.0",
          venues)


def taiwan():
    """運動部場館資料中有羽球設施、且對外開放（付費或免費）的場館。"""
    venues, seen = [], set()
    with open(RAW / "tw/national_venues.csv", encoding="utf-8-sig") as fh:
        for r in csv.DictReader(fh):
            if "羽球" not in r["設施項目"] + r["場館分類"] or r["開放情形"] not in ("付費對外開放使用", "免費對外開放使用"):
                continue
            try:
                lat, lon = float(r["緯度"]), float(r["經度"])
            except ValueError:
                continue
            address = r["地址"].strip()
            match = re.match(r"\[(\d+)\]\s*(.*)", address)
            postcode, address = (match.group(1), match.group(2)) if match else ("", address)
            county = address[:3]
            district = r["行政區"].strip()
            street = address[3:]
            if street.startswith(district):
                street = street[len(district):]
            web = r["場館官方網站"].strip()
            venue_id = "v-tw-" + short_hash(r["場館名稱"] + address)
            if venue_id in seen:  # 同一場館按設施分多行
                continue
            seen.add(venue_id)
            venues.append({"id": venue_id, "name": r["場館名稱"].strip(),
                           "lat": round(lat, 6), "lon": round(lon, 6), "street": street, "city": district,
                           "region": county, "postcode": postcode, "country": "TW", "tz": "Asia/Taipei",
                           "phone": r["場館實際管理人電話"].strip() or None,
                           "web": web if web.startswith("http") else None})
    write("TW", "運動部「全國運動場館資訊」", "資料來源：運動部「全國運動場館資訊」（政府資料開放授權條款第1版）", venues)


def england():
    """Active Places：仍在营业、个人可以直接订（Pay and Play / 免费 / 会员制）且有羽毛球场的场馆。
    俱乐部/社区性质（多为学校体育馆，只租给俱乐部）不收录；数据里的联系人姓名、邮箱一律不导入。"""
    def rows(name):
        data = json.loads((RAW / f"uk/{name}.json").read_text())
        return [x.get("attributes", x) for x in (data["features"] if isinstance(data, dict) else data)]

    open_access = {"Pay and Play", "Free Public Access", "Registered Membership use"}
    courts = defaultdict(int)
    for hall in rows("ap_sportshall"):
        if hall["facstatus"] == "Operational" and hall["accessibilitytypestr"] in open_access and (hall["badmintoncourts"] or 0) > 0:
            courts[hall["siteid"]] += hall["badmintoncourts"]

    def tidy(text):
        small = {"And", "Of", "The", "At", "In", "On", "For"}
        words = [w.capitalize() if w.isupper() else w for w in (text or "").split()]
        return " ".join(w.lower() if i and w in small else w for i, w in enumerate(words))

    venues = []
    for site in rows("ap_sites"):
        if site["siteid"] not in courts or site.get("lat") is None:
            continue
        street = " ".join(str(x) for x in (site.get("buildingnumber"), tidy(site.get("thoroughfarename"))) if x)
        phone = (site.get("telnumber") or "").strip()
        venues.append({"id": f"v-gb-{site['siteid']}", "name": tidy(site["sitename"]),
                       "lat": round(site["lat"], 6), "lon": round(site["long"], 6),
                       "street": street or tidy(site.get("buildingname")), "city": tidy(site.get("posttown")),
                       "region": tidy(site.get("countyname") or site.get("localauthorityname")),
                       "postcode": site.get("postcode") or "", "country": "GB", "tz": "Europe/London",
                       "courts": courts[site["siteid"]],
                       "phone": phone if phone.strip("0") else None,
                       "web": site.get("website") or None})
    write("GB", "Sport England Active Places", "Contains Data © Sport England (CC BY 4.0)", venues)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for build in (hong_kong, singapore, taiwan, england):
        build()
