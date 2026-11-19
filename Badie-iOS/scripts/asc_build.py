"""看 TestFlight 构建处理完没有，并把它挂到 App Store Connect 的版本上（提交审核前的最后一步）。

用法：
  python3 asc_build.py list <版本号>     只看：这个版本的构建、挂上了哪个、审核备注有没有填。不改任何东西
  python3 asc_build.py attach <版本号>   等最新的构建（或环境变量 BUILD 给的那个）处理完（最多等 25 分钟），挂到这个版本上。
                                         还没有这个版本就先建（描述等文字苹果会从上一版带过来），审核信息没填就从上一版复制；
                                         review_notes.json 里这个版本有新段落的，接在审核备注后面（已经有的不重复加，drop 里的旧段落去掉）
环境变量同 asc_signing.py。日志只打印版本号、构建号和状态（仓库是公开的）
"""
import json
import os
import sys
import time
import urllib.parse

import asc_signing as asc
import asc_screenshots as shots


def builds_of(app_id, number):
    query = urllib.parse.urlencode({"filter[app]": app_id, "filter[preReleaseVersion.version]": number,
                                    "sort": "-uploadedDate", "limit": 5})
    return asc.api("GET", f"/builds?{query}")["data"]


REVIEW_FIELDS = ("contactFirstName", "contactLastName", "contactPhone", "contactEmail",
                 "demoAccountName", "demoAccountPassword", "demoAccountRequired", "notes")


def copy_review_detail(version, versions):
    """新版本的审核信息（联系人、演示账号、备注）从最近一个填过的版本复制过来。不打印内容"""
    for other in versions:
        if other["id"] == version["id"]:
            continue
        source = (asc.api("GET", f"/appStoreVersions/{other['id']}/appStoreReviewDetail", missing_ok=True) or {}).get("data")
        if not source:
            continue
        attributes = {key: source["attributes"].get(key) for key in REVIEW_FIELDS if source["attributes"].get(key) is not None}
        created = asc.api("POST", "/appStoreReviewDetails", {"data": {
            "type": "appStoreReviewDetails", "attributes": attributes,
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}}}}})["data"]
        print(f"审核信息从版本 {other['attributes']['versionString']} 复制过来了")
        return created
    return None


def add_review_notes(review, number):
    """把 review_notes.json 里这个版本的段落接在审核备注后面，已经有的跳过。不打印内容"""
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "review_notes.json"), encoding="utf-8") as file:
        entry = json.load(file).get(number, {})
    paragraphs, dropped = (entry, []) if isinstance(entry, list) else (entry.get("add", []), entry.get("drop", []))
    original = review["attributes"].get("notes") or ""
    # 改过的段落：先去掉旧的那段
    kept = [p for p in original.split("\n\n") if p.strip() and p.strip() not in dropped]
    missing = [p for p in paragraphs if p not in kept]
    notes = "\n\n".join(kept + missing)
    if notes == original.strip():
        return review
    if len(notes) > 4000:
        sys.exit(f"审核备注加上新段落有 {len(notes)} 字，超过 4000，没改")
    updated = asc.api("PATCH", f"/appStoreReviewDetails/{review['id']}", {"data": {
        "type": "appStoreReviewDetails", "id": review["id"], "attributes": {"notes": notes}}})["data"]
    print(f"审核备注加了 {len(missing)} 段，去掉了 {len(original.split(chr(10) * 2)) - len(kept) if dropped else 0} 段旧的")
    return updated


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("list", "attach"):
        sys.exit(__doc__)
    mode, number = sys.argv[1], sys.argv[2]
    shots.refresh_token()
    app_id, versions = shots.find_versions()
    for other in versions[:5]:
        print(f"版本 {other['attributes']['versionString']}：{shots.state_of(other)}")
    version = next((v for v in versions if v["attributes"]["versionString"] == number), None)
    if version is None and mode == "attach":
        version = asc.api("POST", "/appStoreVersions", {"data": {
            "type": "appStoreVersions", "attributes": {"platform": "IOS", "versionString": number},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
        print(f"新建了版本 {number}")
    if version is None:
        sys.exit(f"还没有版本 {number}")

    wanted = os.environ.get("BUILD", "").strip()
    builds = builds_of(app_id, number)
    if mode == "attach":
        for _ in range(50):
            target = next((b for b in builds if b["attributes"]["version"] == wanted), None) if wanted else (builds[0] if builds else None)
            if target and target["attributes"]["processingState"] != "PROCESSING":
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
        target = next((b for b in builds if b["attributes"]["version"] == wanted), None) if wanted else (builds[0] if builds else None)
        if not target or target["attributes"]["processingState"] != "VALID":
            sys.exit(f"构建 {wanted or '（最新的）'} 还不能用，没有挂")
        if shots.state_of(version) not in shots.EDITABLE:
            sys.exit(f"版本 {number} 的状态是 {shots.state_of(version)}，改不了（在 App Store Connect 里把它从待提交的审核里移出来再跑）")
        asc.api("PATCH", f"/appStoreVersions/{version['id']}/relationships/build",
                {"data": {"type": "builds", "id": target["id"]}})

    attached = (asc.api("GET", f"/appStoreVersions/{version['id']}/build", missing_ok=True) or {}).get("data")
    print(f"挂在版本 {number} 上的构建：{attached['attributes']['version'] if attached else '没有'}")
    review = (asc.api("GET", f"/appStoreVersions/{version['id']}/appStoreReviewDetail", missing_ok=True) or {}).get("data")
    if review is None and mode == "attach":
        review = copy_review_detail(version, versions)
    if review and mode == "attach":
        review = add_review_notes(review, number)
    if review:
        attributes = review["attributes"]
        print(f"审核信息：备注 {len(attributes.get('notes') or '')} 字，演示账号{'已填' if attributes.get('demoAccountName') else '没填'}")
    else:
        print("审核信息：还没填")


if __name__ == "__main__":
    main()
