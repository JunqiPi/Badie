"""把商店截图传到 App Store Connect 的某个版本上，替换这个版本各语言原有的截图。

用法：
  python3 asc_screenshots.py list <版本号>              只看：各版本的状态、这个版本各语言现有的截图数。不改任何东西
  python3 asc_screenshots.py upload <版本号> <截图目录>   截图目录下是 …6.3-inch/<语言>/1-xxx.jpg 和 …6.9-inch/<语言>/…
                                                       （就是 App Store screenshots 工作流的两个产物）
upload 时版本不存在会先新建；截图只能改在还没提交的版本上。
环境变量同 asc_signing.py：ASC_KEY_ID、ASC_ISSUER_ID、ASC_KEY_PATH。日志只打印版本号、语言和张数（仓库是公开的）
"""
import hashlib
import os
import sys
import time
import urllib.parse
import urllib.request

import asc_signing as asc

BUNDLE_ID = "com.badie.app"
# 产物里的文件夹 → App Store Connect 的语言代码
LOCALES = {"en": "en-US", "zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant", "ja": "ja", "ko": "ko",
           "hi": "hi", "id": "id", "ms": "ms", "th": "th", "vi": "vi"}
# 尺寸 → 截图组的类型：6.3 英寸（1206 × 2622）和 6.9 英寸（1320 × 2868）
DISPLAY_TYPES = {"6.3-inch": "APP_IPHONE_61", "6.9-inch": "APP_IPHONE_67"}
# 这些状态下还能改截图
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}

token_made_at = 0.0


def refresh_token():
    """令牌 20 分钟过期，传 180 张图要一会儿：超过 10 分钟就换一个"""
    global token_made_at
    if time.time() - token_made_at > 600:
        asc.TOKEN = asc.make_token()
        token_made_at = time.time()


def state_of(version):
    return version["attributes"].get("appVersionState") or version["attributes"].get("appStoreState")


def everything(path):
    """翻页取完"""
    items, separator = [], "&" if "?" in path else "?"
    response = asc.api("GET", f"{path}{separator}limit=200")
    while True:
        items += response["data"]
        following = response.get("links", {}).get("next")
        if not following:
            return items
        response = asc.api("GET", following.split("/v1", 1)[1])


def find_versions():
    apps = asc.api("GET", "/apps?" + urllib.parse.urlencode({"filter[bundleId]": BUNDLE_ID}))["data"]
    if not apps:
        sys.exit(f"找不到 {BUNDLE_ID}")
    app_id = apps[0]["id"]
    versions = asc.api("GET", f"/apps/{app_id}/appStoreVersions?" + urllib.parse.urlencode({"filter[platform]": "IOS", "limit": 20}))["data"]
    for version in versions:
        print(f"版本 {version['attributes']['versionString']}：{state_of(version)}")
    return app_id, versions


def screenshot_sets(localization_id):
    return {s["attributes"]["screenshotDisplayType"]: s["id"]
            for s in everything(f"/appStoreVersionLocalizations/{localization_id}/appScreenshotSets")}


def show(version):
    for localization in everything(f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations"):
        counts = {kind: len(everything(f"/appScreenshotSets/{set_id}/appScreenshots"))
                  for kind, set_id in screenshot_sets(localization["id"]).items()}
        print(f"  {localization['attributes']['locale']}: " + (", ".join(f"{k} {n} 张" for k, n in sorted(counts.items())) or "没有截图"))


def upload_file(set_id, path):
    with open(path, "rb") as file:
        content = file.read()
    created = asc.api("POST", "/appScreenshots", {"data": {
        "type": "appScreenshots",
        "attributes": {"fileName": os.path.basename(path), "fileSize": len(content)},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})["data"]
    for operation in created["attributes"]["uploadOperations"]:
        part = content[operation["offset"]:operation["offset"] + operation["length"]]
        request = urllib.request.Request(operation["url"], data=part, method=operation["method"],
                                         headers={h["name"]: h["value"] for h in operation["requestHeaders"]})
        with urllib.request.urlopen(request, timeout=120):
            pass
    asc.api("PATCH", f"/appScreenshots/{created['id']}", {"data": {
        "type": "appScreenshots", "id": created["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(content).hexdigest()}}})
    return created["id"]


def upload(app_id, versions, number, root):
    version = next((v for v in versions if v["attributes"]["versionString"] == number), None)
    if version is None:
        version = asc.api("POST", "/appStoreVersions", {"data": {
            "type": "appStoreVersions", "attributes": {"platform": "IOS", "versionString": number},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
        print(f"新建了版本 {number}")
    if state_of(version) not in EDITABLE:
        sys.exit(f"版本 {number} 的状态是 {state_of(version)}，改不了截图")

    folders = {}  # 尺寸 → 目录
    for name in sorted(os.listdir(root)):
        for size in DISPLAY_TYPES:
            if name.endswith(size) and os.path.isdir(os.path.join(root, name)):
                folders[size] = os.path.join(root, name)
    if set(folders) != set(DISPLAY_TYPES):
        sys.exit(f"截图目录里要有 {' 和 '.join(DISPLAY_TYPES)} 两组，现在只有 {sorted(folders)}")

    by_locale = {l["attributes"]["locale"]: l["id"]
                 for l in everything(f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")}
    uploaded = []
    for folder, locale in LOCALES.items():
        refresh_token()
        if locale not in by_locale:
            print(f"  {locale}: 这个版本没有这种语言，跳过")
            continue
        sets = screenshot_sets(by_locale[locale])
        other = sorted(set(sets) - set(DISPLAY_TYPES.values()))
        if other:
            print(f"  {locale}: 还有别的尺寸的截图组没动：{', '.join(other)}")
        for size, kind in DISPLAY_TYPES.items():
            directory = os.path.join(folders[size], folder)
            files = sorted((f for f in os.listdir(directory) if f.endswith(".jpg")), key=lambda f: int(f.split("-")[0]))
            set_id = sets.get(kind) or asc.api("POST", "/appScreenshotSets", {"data": {
                "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": kind},
                "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": by_locale[locale]}}}}})["data"]["id"]
            for old in everything(f"/appScreenshotSets/{set_id}/appScreenshots"):
                asc.api("DELETE", f"/appScreenshots/{old['id']}")
            ids = [upload_file(set_id, os.path.join(directory, f)) for f in files]
            # 顺序按文件名开头的数字
            asc.api("PATCH", f"/appScreenshotSets/{set_id}/relationships/appScreenshots",
                    {"data": [{"type": "appScreenshots", "id": i} for i in ids]})
            uploaded += [(locale, size, i) for i in ids]
            print(f"  {locale} {size}: 传了 {len(ids)} 张")
    for locale in sorted(set(by_locale) - set(LOCALES.values())):
        print(f"  {locale}: 没有对应的截图，没动")

    # 等苹果处理完，看有没有被拒收的（比如尺寸不对）
    waiting, failed = list(uploaded), []
    for _ in range(40):
        refresh_token()
        still = []
        for locale, size, screenshot_id in waiting:
            delivery = asc.api("GET", f"/appScreenshots/{screenshot_id}")["data"]["attributes"].get("assetDeliveryState") or {}
            if delivery.get("state") == "FAILED":
                failed.append((locale, size, "; ".join(e.get("code", "") for e in delivery.get("errors") or [])))
            elif delivery.get("state") != "COMPLETE":
                still.append((locale, size, screenshot_id))
        waiting = still
        if not waiting:
            break
        time.sleep(15)
    print(f"处理完成 {len(uploaded) - len(waiting) - len(failed)} 张，失败 {len(failed)} 张，还在处理 {len(waiting)} 张")
    for locale, size, reason in failed:
        print(f"  失败：{locale} {size} {reason}")
    if failed:
        sys.exit(1)


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("list", "upload") or (sys.argv[1] == "upload" and len(sys.argv) < 4):
        sys.exit(__doc__)
    refresh_token()
    app_id, versions = find_versions()
    if sys.argv[1] == "upload":
        upload(app_id, versions, sys.argv[2], sys.argv[3])
        _, versions = find_versions()
    version = next((v for v in versions if v["attributes"]["versionString"] == sys.argv[2]), None)
    if version is None:
        print(f"还没有版本 {sys.argv[2]}")
    else:
        show(version)


if __name__ == "__main__":
    main()
