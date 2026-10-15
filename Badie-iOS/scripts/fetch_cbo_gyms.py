#!/usr/bin/env python3
"""从中羽在线场馆库（badmintoncn.com/cbo_gym，已获站方许可）取场馆名称与位置。

只保存名称和地址/坐标，不取评论、联系人等任何用户信息；每 2 秒最多 1 个请求。
用法: fetch_cbo_gyms.py inspect <输出目录>   保存验证页，打印其中的脚本，用于确认解法
"""
import sys
import urllib.request
from http.cookiejar import CookieJar
from pathlib import Path

BASE = "https://www.badmintoncn.com/cbo_gym/"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

jar = CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))


def get(url):
    request = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Language": "zh-CN,zh;q=0.9"})
    with opener.open(request, timeout=30) as response:
        return response.read().decode("utf-8", "replace")


def inspect(out_dir):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    html = get(BASE)
    (out / "challenge.html").write_text(html)
    start = html.find("<script>")
    print(len(html), "bytes; cookies:", [c.name for c in jar])
    print(html[start:start + 200])
    print("...")
    print(html[-2500:])


if __name__ == "__main__":
    if sys.argv[1] == "inspect":
        inspect(sys.argv[2])
