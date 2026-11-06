"""把 App Store Connect 里还没提交的版本号改掉（比如误填的 1.001 改成 1.0.1）。网页上没有地方改，只能用 API。

用法：python3 asc_version.py <原来的版本号> <新版本号>
环境变量同 asc_signing.py：ASC_KEY_ID、ASC_ISSUER_ID、ASC_KEY_PATH。日志只打印版本号（仓库是公开的）
"""
import sys
import urllib.parse

import asc_signing as asc

BUNDLE_ID = "com.badie.app"


def main():
    old, new = sys.argv[1], sys.argv[2]
    asc.TOKEN = asc.make_token()
    apps = asc.api("GET", "/apps?" + urllib.parse.urlencode({"filter[bundleId]": BUNDLE_ID}))["data"]
    if not apps:
        sys.exit(f"找不到 {BUNDLE_ID}")
    versions = asc.api("GET", f"/apps/{apps[0]['id']}/appStoreVersions?" + urllib.parse.urlencode({
        "filter[platform]": "IOS", "filter[versionString]": old}))["data"]
    if not versions:
        print(f"没有版本号是 {old} 的版本，不用改")
        return
    version = versions[0]
    state = version["attributes"].get("appStoreState") or version["attributes"].get("appVersionState")
    asc.api("PATCH", f"/appStoreVersions/{version['id']}", {"data": {
        "type": "appStoreVersions", "id": version["id"], "attributes": {"versionString": new}}})
    print(f"改好了：{old} → {new}（状态 {state}）")


if __name__ == "__main__":
    main()
