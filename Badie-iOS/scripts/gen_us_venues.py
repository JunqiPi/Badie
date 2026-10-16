"""由 data/us_venues.json（调研记录：来源、冲突说明）生成 App 和网页共用的 Badie/Resources/curated-US.json

用法（在 Badie-iOS 目录下）:
    python3 scripts/gen_us_venues.py data/us_venues.json Badie/Resources/curated-US.json
"""
import json, re, sys

src, out = sys.argv[1], sys.argv[2]
venues = json.load(open(src, encoding="utf-8"))

notes = {
    "Bellevue Badminton Club - Bellevue": "不接受散客 walk-in，需提前预约",
    "Bellevue Badminton Club - Redmond": "不接受散客 walk-in，需提前预约",
    "PickleBall Badminton Center": "与匹克球共用场地，羽毛球最多 6 片",
}


facilities = {"dedicated": "dedicated", "multi_sport": "multiSport", "rec_center": "recCenter",
              "school_or_college": "school", "community_hall": "communityHall"}


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")[:40].rstrip("-")


entries = []
for v in venues:
    name = v["name"]
    missing = [k for k in ("street", "city", "state", "postalCode", "timeZone") if not v.get(k)]
    assert not missing, f"{name}: missing {missing}"
    # 已发布的场馆 id 固定写在数据里（改名后收藏、确认记录仍跟着 id 走）
    entry = {"id": v.get("id") or f"v-us-{v['state'].lower()}-{slug(name)}", "name": name}
    aliases = [a for a in (v.get("aliases") or []) + (v.get("hostedBy") or []) if a and a != name]
    aliases = list(dict.fromkeys(aliases))
    if v.get("nameZh") and v["nameZh"] not in aliases:
        aliases.append(v["nameZh"])
    if aliases:
        entry["aliases"] = aliases
    entry |= {"lat": round(v["latitude"], 6), "lon": round(v["longitude"], 6), "street": v["street"]}
    if v.get("unit"):
        entry["unit"] = v["unit"]
    entry |= {"city": v["city"], "region": v["state"], "postcode": v["postalCode"], "country": "US", "tz": v["timeZone"]}
    if v.get("courtCount"):
        entry["courts"] = v["courtCount"]
    drop, rent = v.get("dropInFee"), v.get("courtRentalPerHour")
    price = {k: int(p) for k, p in (("perPerson", drop), ("perCourtHour", rent)) if p is not None}
    if price:
        entry["price"] = price
        walk_in = [] if drop is None else ["免费" if drop == 0 else f"散客 ${int(drop)}/人次"]
        entry["priceNote"] = " · ".join(walk_in + ([f"包场 ${int(rent)}/场·时"] if rent else []))
    if v.get("phone"):
        entry["phone"] = v["phone"]
    if v.get("website"):
        entry["web"] = v["website"]
    if v.get("venueType"):
        entry["facility"] = facilities[v["venueType"]]
    if v.get("schedule"):
        entry["playTimes"] = v["schedule"]
    if v.get("verifiedAt"):
        entry["checked"] = v["verifiedAt"]
    if name in notes:
        entry["entrance"] = notes[name]
    entries.append(entry)

ids = [e["id"] for e in entries]
assert len(ids) == len(set(ids)), "duplicate ids"
catalog = {"country": "US", "source": "Badie research (data/us_venues.json)", "kind": "curated", "status": "verified", "venues": entries}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(catalog, fh, ensure_ascii=False, indent=1)
    fh.write("\n")
print("venues:", len(entries))
