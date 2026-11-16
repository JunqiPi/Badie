#!/usr/bin/env python3
"""生成网站的 web/public/.well-known/assetlinks.json：有了它，点 badie.rsvp 的链接才会直接进安卓 App（App Links）。

指纹是签名证书的 SHA-256：每次跑发版工作流（Android release）的运行摘要里都有。网站下载的包和以后 Play 上的包用同一把密钥
（见 docs/RELEASE.md 的“签名”），所以一个指纹就够了。

用法（在仓库根目录）：
    python3 Badie-Android/scripts/assetlinks.py AA:BB:...:FF [另一个指纹]
然后提交这个文件、推 main，网站部署后用 docs/RELEASE.md 里的办法检查。
"""
import json
import pathlib
import re
import sys

PACKAGE = "com.badie.app"
OUT = pathlib.Path(__file__).resolve().parents[2] / "web/public/.well-known/assetlinks.json"


def main(fingerprints: list[str]) -> None:
    if not fingerprints:
        sys.exit(__doc__)
    cleaned = []
    for fingerprint in fingerprints:
        value = fingerprint.strip().upper()
        if not re.fullmatch(r"([0-9A-F]{2}:){31}[0-9A-F]{2}", value):
            sys.exit(f"不像 SHA-256 指纹（应该是 32 组两位十六进制、用冒号隔开）：{fingerprint}")
        cleaned.append(value)
    statement = [{
        "relation": ["delegate_permission/common.handle_all_urls"],
        "target": {"namespace": "android_app", "package_name": PACKAGE, "sha256_cert_fingerprints": cleaned},
    }]
    OUT.write_text(json.dumps(statement, indent=2) + "\n")
    print(f"已写入 {OUT.relative_to(OUT.parents[3])}")


if __name__ == "__main__":
    main(sys.argv[1:])
