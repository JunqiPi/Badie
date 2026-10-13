"""由 data/us_venues.json 生成 BadmintonBuddy/Models/CuratedVenues+US.swift

用法（在 BadmintonBuddy-iOS 目录下）:
    python3 scripts/gen_us_venues.py data/us_venues.json BadmintonBuddy/Models/CuratedVenues+US.swift
"""
import json, re, sys

src, out = sys.argv[1], sys.argv[2]
venues = json.load(open(src, encoding="utf-8"))

overrides = {"Los Angeles Badminton Club": "v-us-ca-labc", "Elite Rally Badminton Club": "v-us-ca-elite-rally"}
unconfirmed = {"OC SMASH Badminton Club"}
notes = {
    "Manhattan Beach Badminton Club": "会员制私人俱乐部，不接待散客",
    "Bellevue Badminton Club - Bellevue": "不接受散客 walk-in，需提前预约",
    "Bellevue Badminton Club - Redmond": "不接受散客 walk-in，需提前预约",
    "PickleBall Badminton Center": "与匹克球共用场地，羽毛球最多 6 片",
}

def swift_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

def slug(name):
    s = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return s[:40].rstrip("-")

used = set()
lines = []
for v in venues:
    name = v["name"]
    vid = overrides.get(name) or f"v-us-{v['state'].lower()}-{slug(name)}"
    assert vid not in used, vid
    used.add(vid)
    aliases = [a for a in v.get("aliases") or [] if a and a != name]
    if v.get("nameZh") and v["nameZh"] not in aliases:
        aliases.append(v["nameZh"])
    drop, rent = v.get("dropInFee"), v.get("courtRentalPerHour")
    if drop:
        pricing = f".dropIn(perPerson: {int(drop)})"
    elif rent:
        pricing = f".perCourtHour({int(rent)})"
    else:
        pricing = ".unknown"
    price_note = []
    if drop: price_note.append(f"散客 ${int(drop)}/人次")
    if rent: price_note.append(f"包场 ${int(rent)}/场·时")
    conflict = (v.get("conflicts") or "").replace("\n", " ")
    comment = f"        // 来源 {len(v['sources'])} 个：" + " ".join(v["sources"][:3])
    entry = [comment]
    if conflict:
        entry.append("        // 注意：" + conflict[:300])
    args = [
        f"id: {swift_str(vid)}",
        f"name: {swift_str(name)}",
        f"aliases: [{', '.join(swift_str(a) for a in aliases)}]",
        f"location: Coordinate(latitude: {v['latitude']:.6f}, longitude: {v['longitude']:.6f})",
        "address: PostalAddress(street: {}, unit: {}, city: {}, region: {}, postalCode: {}, countryCode: \"US\")".format(
            swift_str(v["street"]), swift_str(v["unit"]) if v.get("unit") else "nil",
            swift_str(v["city"]), swift_str(v["state"]), swift_str(v["postalCode"])),
        f"timeZoneId: {swift_str(v['timeZone'])}",
        f"courtCount: {v['courtCount'] if v.get('courtCount') else 'nil'}",
        f"pricing: {pricing}",
    ]
    if price_note:
        args.append(f"pricingNote: {swift_str(' · '.join(price_note))}")
    if v.get("phone"):
        args.append(f"phone: {swift_str(v['phone'])}")
    if v.get("website"):
        args.append(f"website: {swift_str(v['website'])}")
    if name in notes:
        args.append(f"entranceNote: {swift_str(notes[name])}")
    args.append("source: .curated")
    args.append(f"status: {'.unconfirmed' if name in unconfirmed else '.verified'}")
    body = ",\n            ".join(args)
    entry.append(f"        BadmintonCourt(\n            {body}\n        )")
    lines.append("\n".join(entry))

header = '''import Foundation

// MARK: - 美国收录球馆（首发市场）
//
// 由 docs/DESIGN.md §9 的调研生成：每家至少 2 个独立来源互相印证地址（官网、Yelp、地图条目、俱乐部目录），
// 坐标来自 US Census Geocoder 门牌地址匹配（Elite Rally 来自 OpenStreetMap，精确到街道）。
// 价格为工作日晚间非会员价，来自官网或公开预订页；未公开的标为未知，不估算。
// 已排除确认或疑似关门的球馆（如 Yan Long、Arcadia BC、IBC Irvine 等）。

extension BadmintonCourt {
    static let curatedUS: [BadmintonCourt] = [
'''
footer = '''
    ]
}
'''
body = ",\n".join(lines)
open(out, "w", encoding="utf-8").write(header + body + footer)
print("venues:", len(venues), "ids:", sorted(used)[:4])
