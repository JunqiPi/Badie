#!/usr/bin/env python3
"""把 iPhone 用的系统图标名对应到 Material Symbols（圆角、700 粗细），生成安卓的矢量图。

iPhone 的界面代码里写的是系统图标名（比如 "bolt.fill"）。安卓的代码写 Sym.boltFill，
由这里生成。要加图标：在 icons.json 里加一行，再跑一遍。

    npm pack @material-symbols/svg-700@0.48.2 && tar xzf material-symbols-svg-700-0.48.2.tgz
    python3 scripts/gen_icons.py package/rounded

图标是 Google 的 Material Symbols，Apache 2.0 许可。
"""
import json
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
source = pathlib.Path(sys.argv[1])
mapping = json.loads((root / "scripts/icons.json").read_text())
drawable = root / "app/src/main/res/drawable"

for old in drawable.glob("sym_*.xml"):
    old.unlink()

for name in sorted(set(mapping.values())):
    svg = (source / f"{name}.svg").read_text()
    paths = re.findall(r'<path d="([^"]+)"', svg)
    assert paths and 'viewBox="0 -960 960 960"' in svg, name
    body = "".join(
        f'        <path android:fillColor="#FF000000" android:pathData="{d}" />\n' for d in paths
    )
    (drawable / f"sym_{name.replace('-', '_')}.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:width="24dp" android:height="24dp"\n'
        '    android:viewportWidth="960" android:viewportHeight="960">\n'
        '    <group android:translateY="960">\n'
        f"{body}"
        "    </group>\n"
        "</vector>\n"
    )

def constant(sf):
    """bolt.fill -> boltFill；person.3.fill -> person3Fill"""
    head, *rest = sf.split(".")
    return head + "".join(part.capitalize() for part in rest)


rows = "".join(
    f'    /** {sf} */\n    val {constant(sf)} = SymbolId(R.drawable.sym_{name.replace("-", "_")})\n'
    for sf, name in sorted(mapping.items())
)
(root / "app/src/main/kotlin/com/badie/app/design/Sym.kt").write_text(
    "// 自动生成（scripts/gen_icons.py），不要手改\n"
    "package com.badie.app.design\n\n"
    "import com.badie.app.R\n\n"
    "/** 图标。名字是 iPhone 的系统图标名去掉点：bolt.fill 写成 Sym.boltFill */\n"
    "object Sym {\n"
    f"{rows}"
    "}\n"
)
print(f"{len(set(mapping.values()))} 个图标，{len(mapping)} 个名字")
