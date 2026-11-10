"""把更新说明和描述写进 App Store Connect 的某个版本（文字在 store_text.json，按语言）。

用法：
  python3 asc_text.py list <版本号>     只看：这个版本各语言现在的更新说明和描述各多少字。不改任何东西
  python3 asc_text.py upload <版本号>   写进去（只能改还没提交的版本）
环境变量同 asc_signing.py。日志只打印语言和字数（仓库是公开的）
"""
import json
import os
import sys

import asc_signing as asc
import asc_screenshots as shots


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("list", "upload"):
        sys.exit(__doc__)
    mode, number = sys.argv[1], sys.argv[2]
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "store_text.json"), encoding="utf-8") as file:
        texts = json.load(file)
    shots.refresh_token()
    _, versions = shots.find_versions()
    version = next((v for v in versions if v["attributes"]["versionString"] == number), None)
    if version is None:
        sys.exit(f"还没有版本 {number}")
    if mode == "upload" and shots.state_of(version) not in shots.EDITABLE:
        sys.exit(f"版本 {number} 的状态是 {shots.state_of(version)}，改不了文字")
    for localization in shots.everything(f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations"):
        locale = localization["attributes"]["locale"]
        if mode == "upload":
            if locale not in texts:
                print(f"  {locale}: store_text.json 里没有这种语言，没动")
                continue
            localization = asc.api("PATCH", f"/appStoreVersionLocalizations/{localization['id']}", {"data": {
                "type": "appStoreVersionLocalizations", "id": localization["id"],
                "attributes": {"whatsNew": texts[locale]["whatsNew"], "description": texts[locale]["description"]}}})["data"]
        attributes = localization["attributes"]
        print(f"  {locale}: 更新说明 {len(attributes.get('whatsNew') or '')} 字，描述 {len(attributes.get('description') or '')} 字")


if __name__ == "__main__":
    main()
