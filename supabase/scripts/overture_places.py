"""在 Overture Maps 的地点数据里按名字找球馆，给只查到城市的球馆补上精确位置（build_imported_venues.py --overture 用）。

Overture Maps（Meta、微软、亚马逊等发布的开放地图数据，地点数据 CDLA Permissive 2.0）放在 S3 上，一期 16 个 Parquet 文件、
约 12 GB。文件按地理位置排序，每一块（row group）记着自己的经纬度范围，所以只按需分段下载球馆附近的那几块，不下整个文件。
用 urllib 走系统的代理，不需要 S3 客户端。需要 pip install pyarrow==21.0.0，网络要放行 overturemaps-us-west-2.s3.us-west-2.amazonaws.com。
"""
import io
import re
import time
import urllib.request
from collections import defaultdict

import pyarrow.parquet as pq

import unicodedata

from build_osm_venues import metres, tokens

BASE = "https://overturemaps-us-west-2.s3.us-west-2.amazonaws.com"
RELEASE = "2026-10-21.0"
ATTRIBUTION = "© Overture Maps Foundation (CDLA Permissive 2.0)"
RADIUS_DEG = 0.2      # 只查到城市的球馆：在城市中心周围这么大的范围里找（约 20 公里）
MAX_METRES = 25_000
SHOPS = {"sporting_goods_store", "shopping", "retail", "store"}
SPORTY = re.compile(r"sport|badminton|gym|fitness|recreation|court|stadium|arena|club|athlet|leisure|school|college|"
                    r"universit|community_center", re.I)
BADMINTON = re.compile(r"badminton|bulu ?tangkis|c[aầ]u l[oô]ng|\bgor\b|羽|배드민턴|バドミントン|แบดมินตัน", re.I)


def _plain(name):
    text = unicodedata.normalize("NFKD", name.replace("đ", "d").replace("Đ", "D").lower())
    return "".join(ch for ch in text if ch.isalnum())


def same_place(ours, theirs, category):
    """名字一样；或者至少 2 个实词相同、一方的实词都在另一方里，而且对方是体育类的地点。
    只看共同的词太松：“Phoenix badminton academy”会配上“Phoenix”，“Badminton Power”会配上花店“Flower Power”"""
    if _plain(ours) == _plain(theirs):
        return True
    a, b = tokens(ours), tokens(theirs)
    if len(a & b) < 2 or not (a <= b or b <= a):
        return False
    return bool(SPORTY.search(category or "")) or bool(BADMINTON.search(theirs))


class RangeFile(io.RawIOBase):
    """只读、可跳转的远程文件：每次读都是一个 HTTP Range 请求"""

    def __init__(self, url, size):
        self.url, self.size, self.pos, self.downloaded, self.blocks = url, size, 0, 0, {}

    def readable(self):
        return True

    def seekable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, offset, whence=0):
        self.pos = {0: offset, 1: self.pos + offset, 2: self.size + offset}[whence]
        return self.pos

    BLOCK = 4 << 20  # 每次下载 4 MB 一段并缓存：pyarrow 会读很多小段，一段一个请求太慢

    def _block(self, i):
        if i not in self.blocks:
            start, end = i * self.BLOCK, min((i + 1) * self.BLOCK, self.size) - 1
            for attempt in range(4):
                try:
                    req = urllib.request.Request(self.url, headers={"Range": f"bytes={start}-{end}"})
                    data = urllib.request.urlopen(req, timeout=120).read()
                    break
                except Exception:
                    if attempt == 3:
                        raise
                    time.sleep(3 * (attempt + 1))
            self.downloaded += len(data)
            if len(self.blocks) >= 32:
                self.blocks.pop(next(iter(self.blocks)))
            self.blocks[i] = data
        return self.blocks[i]

    def read(self, n=-1):
        if n is None or n < 0:
            n = self.size - self.pos
        n = max(0, min(n, self.size - self.pos))
        out = bytearray()
        while len(out) < n:
            i, off = divmod(self.pos, self.BLOCK)
            chunk = self._block(i)[off:off + n - len(out)]
            out += chunk
            self.pos += len(chunk)
        return bytes(out)

    def readinto(self, b):
        data = self.read(len(b))
        b[:len(data)] = data
        return len(data)


def _files():
    prefix = f"release/{RELEASE}/theme=places/type=place/"
    xml = urllib.request.urlopen(f"{BASE}/?list-type=2&prefix={prefix}", timeout=60).read().decode()
    return [(k, int(s)) for k, s in re.findall(r"<Key>([^<]+\.parquet)</Key>.*?<Size>(\d+)</Size>", xml)]


def find(targets, log=print):
    """targets: [(key, name, (lat, lon))] → {key: {"lat", "lon", "name", "street", "postcode"}}

    同名（build_osm_venues.same_name）、25 公里内、不是商店的地点里离城市中心最近的那个。"""
    cell = defaultdict(list)  # 1 度一格，快速找某个范围附近的球馆
    for t in targets:
        cell[(int(t[2][0] // 1), int(t[2][1] // 1))].append(t)

    def near(x0, x1, y0, y1):
        return [t for i in range(int((y0 - RADIUS_DEG) // 1), int((y1 + RADIUS_DEG) // 1) + 1)
                for j in range(int((x0 - RADIUS_DEG) // 1), int((x1 + RADIUS_DEG) // 1) + 1)
                for t in cell.get((i, j), ())
                if y0 - RADIUS_DEG <= t[2][0] <= y1 + RADIUS_DEG and x0 - RADIUS_DEG <= t[2][1] <= x1 + RADIUS_DEG]

    fine = defaultdict(list)  # 0.2 度一格：每个地点只和附近格子里的球馆比名字
    for t in targets:
        fine[(int(t[2][0] // RADIUS_DEG), int(t[2][1] // RADIUS_DEG))].append(t)

    best, downloaded = {}, 0
    for key, size in _files():
        f = RangeFile(f"{BASE}/{key}", size)
        pf = pq.ParquetFile(f)
        md = pf.metadata
        idx = {md.schema.column(i).path: i for i in range(md.num_columns)}
        groups = []
        for g in range(md.num_row_groups):
            rg = md.row_group(g)
            st = {k: rg.column(idx[f"bbox.{k}"]).statistics for k in ("xmin", "xmax", "ymin", "ymax")}
            if near(st["xmin"].min, st["xmax"].max, st["ymin"].min, st["ymax"].max):
                groups.append(g)
        for g in groups:
            tab = pf.read_row_group(g, columns=["names", "bbox", "basic_category", "addresses"])
            names = tab.column("names").combine_chunks().field("primary").to_pylist()
            bbox = tab.column("bbox").combine_chunks()
            xs, ys = bbox.field("xmin").to_pylist(), bbox.field("ymin").to_pylist()
            cats = tab.column("basic_category").to_pylist()
            addrs = tab.column("addresses").to_pylist()
            for n, x, y, c, a in zip(names, xs, ys, cats, addrs):
                if not n or x is None or c in SHOPS:
                    continue
                gi, gj = int(y // RADIUS_DEG), int(x // RADIUS_DEG)
                for t in (t for di in (-1, 0, 1) for dj in (-1, 0, 1) for t in fine.get((gi + di, gj + dj), ())):
                    if not same_place(t[1], n, c):
                        continue
                    d = metres(t[2], (y, x))
                    if d <= MAX_METRES and (t[0] not in best or d < best[t[0]][0]):
                        first = (a or [{}])[0] or {}
                        best[t[0]] = (d, {"lat": round(y, 6), "lon": round(x, 6), "name": n, "category": c,
                                          "street": first.get("freeform") or "", "postcode": first.get("postcode") or ""})
        downloaded += f.downloaded
        log(f"{key.rsplit('/', 1)[-1][:10]}: {len(groups)} blocks, {len(best)} found, {downloaded / 1e6:.0f} MB")
    return {k: v for k, (_, v) in best.items()}
