"""看 TestFlight 构建处理完没有，并把它挂到 App Store Connect 的版本上（提交审核前的最后一步）。

用法：
  python3 asc_build.py list <版本号>     只看：这个版本的构建、挂上了哪个、审核备注有没有填。不改任何东西
  python3 asc_build.py attach <版本号>   等最新的构建处理完（最多等 25 分钟），挂到这个版本上
环境变量同 asc_signing.py。日志只打印版本号、构建号和状态（仓库是公开的）
"""
import sys
import time
import urllib.parse

import asc_signing as asc
import asc_screenshots as shots


def builds_of(app_id, number):
    query = urllib.parse.urlencode({"filter[app]": app_id, "filter[preReleaseVersion.version]": number,
                                    "sort": "-uploadedDate", "limit": 5})
    return asc.api("GET", f"/builds?{query}")["data"]


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("list", "attach"):
        sys.exit(__doc__)
    mode, number = sys.argv[1], sys.argv[2]
    shots.refresh_token()
    app_id, versions = shots.find_versions()
    version = next((v for v in versions if v["attributes"]["versionString"] == number), None)
    if version is None:
        sys.exit(f"还没有版本 {number}")

    builds = builds_of(app_id, number)
    if mode == "attach":
        for _ in range(50):
            if builds and builds[0]["attributes"]["processingState"] != "PROCESSING":
                break
            print("构建还没处理完，等 30 秒" if builds else "还没有看到构建，等 30 秒")
            time.sleep(30)
            shots.refresh_token()
            builds = builds_of(app_id, number)
    for build in builds:
        attributes = build["attributes"]
        print(f"构建 {attributes['version']}：{attributes['processingState']}（{attributes['uploadedDate'][:16]}）")
    if not builds:
        print(f"版本 {number} 还没有构建")

    if mode == "attach":
        if not builds or builds[0]["attributes"]["processingState"] != "VALID":
            sys.exit("最新的构建不能用，没有挂")
        if shots.state_of(version) not in shots.EDITABLE:
            sys.exit(f"版本 {number} 的状态是 {shots.state_of(version)}，改不了")
        asc.api("PATCH", f"/appStoreVersions/{version['id']}/relationships/build",
                {"data": {"type": "builds", "id": builds[0]["id"]}})

    attached = (asc.api("GET", f"/appStoreVersions/{version['id']}/build", missing_ok=True) or {}).get("data")
    print(f"挂在版本 {number} 上的构建：{attached['attributes']['version'] if attached else '没有'}")
    review = (asc.api("GET", f"/appStoreVersions/{version['id']}/appStoreReviewDetail", missing_ok=True) or {}).get("data")
    if review:
        attributes = review["attributes"]
        print(f"审核信息：备注 {len(attributes.get('notes') or '')} 字，演示账号{'已填' if attributes.get('demoAccountName') else '没填'}")
    else:
        print("审核信息：还没填")


if __name__ == "__main__":
    main()
