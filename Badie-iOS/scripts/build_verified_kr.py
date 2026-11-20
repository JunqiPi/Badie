#!/usr/bin/env python3
"""把对照官网核对过的韩国球馆写成网站用的目录（Badie-iOS/data/catalogs/verified-KR.json）。

用法: build_verified_kr.py <核对结果目录，里面是 output-*.json> [--checked 2026-11-20]

核对结果每条有 address（官网上的道路名地址）、价格、开放时间、来源。只收 badminton 为 true、有地址、
有价格或时间的。坐标用 Nominatim（OpenStreetMap）按地址查：单线程，每次间隔 1.1 秒（它的使用规则），
查到的地点必须在地址写的区 / 市里，查不到就不收（宁缺毋滥）。结果缓存在 <目录>/geocode-cache.json，重跑不重复查。
"""
import json, re, sys, time, urllib.parse, urllib.request
from pathlib import Path

SRC = Path(sys.argv[1])
CHECKED = sys.argv[sys.argv.index('--checked') + 1] if '--checked' in sys.argv else time.strftime('%Y-%m-%d')
OUT = Path(__file__).resolve().parent.parent / 'data' / 'catalogs' / 'verified-KR.json'
CACHE = SRC / 'geocode-cache.json'
UA = 'Badie venue directory (https://badie.rsvp)'

cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}


def nominatim(query):
    if query in cache:
        return cache[query]
    time.sleep(1.1)
    url = 'https://nominatim.openstreetmap.org/search?' + urllib.parse.urlencode(
        {'q': query, 'format': 'jsonv2', 'countrycodes': 'kr', 'limit': 3, 'addressdetails': 1, 'accept-language': 'ko'})
    with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': UA}), timeout=30) as r:
        cache[query] = json.loads(r.read())
    CACHE.write_text(json.dumps(cache, ensure_ascii=False))
    return cache[query]


def locate(v, city):
    """先按“区 + 官网名”查设施，再按地址查；只要落到具体建筑或设施上的（整条马路的不算），而且在同一个区 / 市"""
    names = [v.get('officialName'), v['name']]
    queries = [f"{city} {n}" for n in names if n] + [v['address'], re.sub(r'\s*\(.*?\)|,.*$', '', v['address'])]
    for q in dict.fromkeys(queries):
        for hit in nominatim(q):
            if not (city and city in hit.get('display_name', '')):
                continue
            if hit.get('category') == 'highway' or int(hit.get('place_rank', 0)) < 28:
                continue
            return round(float(hit['lat']), 6), round(float(hit['lon']), 6)
    return None


def street_of(address, region, city):
    rest = address.replace(region, '').strip()
    return rest[len(city):].strip() if rest.startswith(city) else rest


venues, skipped = [], []
rows = [r for f in sorted(SRC.glob('output-*.json')) for r in json.loads(f.read_text())]
inputs = {r['id']: r for f in sorted(SRC.glob('input-*.json')) for r in json.loads(f.read_text())}
for v in rows:
    src = inputs.get(v['id'], {})
    has_values = v.get('perPerson') is not None or v.get('perCourtHour') is not None or v.get('playTimes')
    if v.get('badminton') is not True or not v.get('address') or not has_values or not v.get('sources'):
        continue
    city, region = src.get('city', ''), src.get('region', '')
    point = locate(v, city.split()[-1] if city else '')
    if not point:
        skipped.append(v['name'])
        continue
    price = {k: int(v[k]) for k in ('perPerson', 'perCourtHour') if v.get(k) is not None}
    entry = {
        'id': v['id'], 'name': v.get('officialName') or v['name'], 'lat': point[0], 'lon': point[1],
        'street': street_of(v['address'], region, city), 'city': city, 'region': region, 'postcode': v.get('postcode') or '',
        'country': 'KR', 'tz': 'Asia/Seoul', 'web': v.get('web') or v['sources'][0], 'facility': 'recCenter', 'checked': CHECKED,
    }
    if price:
        entry['price'] = price
    if v.get('playTimes'):
        entry['playTimes'] = v['playTimes']
    venues.append(entry)

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps({
    'country': 'KR', 'kind': 'curated', 'status': 'verified',
    'source': 'Badie research: checked against official pages (ward offices, facility management corporations)',
    'attribution': 'Coordinates © OpenStreetMap contributors, ODbL 1.0',
    'venues': sorted(venues, key=lambda e: e['id']),
}, ensure_ascii=False, indent=1) + '\n')
print(f'{len(venues)} venues -> {OUT}; not located: {len(skipped)}')
for name in skipped:
    print('  not located:', name)
