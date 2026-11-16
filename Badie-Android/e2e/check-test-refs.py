#!/usr/bin/env python3
# 压缩包的端到端测试（-Pbadie.minify=true）构建完先查一遍：测试 APK 调到的 App 里的类和方法，压缩后的 App 里都还在。
# 测试 APK 不带 App 已有的库，R8 删掉了测试要用的方法，测试一跑就是 NoSuchMethodError；这里在装到模拟器前就能看出来，
# 缺的要加到 app/e2e-keep.pro。用法：python3 e2e/check-test-refs.py <dexdump> <android.jar> <app.apk> <test.apk>
import re, subprocess, sys, zipfile, tempfile, os, collections
dexdump, android_jar, app_apk, test_apk = sys.argv[1:5]
# 系统自带的类（按 android.jar 的清单）。OPTIONAL：JUnit、Hamcrest 等里可选的引用，用不到
with zipfile.ZipFile(android_jar) as z:
    FRAMEWORK_CLASSES = {"L" + n[:-6] + ";" for n in z.namelist() if n.endswith(".class")}
OPTIONAL = ("Lorg/easymock/", "Lorg/jmock/", "Ljava/beans/", "Ljavax/lang/model/",
            # 手机上有、android.jar 里没有的：测试库（android.test）和 Unsafe
            "Landroid/test/", "Lsun/misc/")

def dumps(apk, disasm):
    d = tempfile.mkdtemp()
    with zipfile.ZipFile(apk) as z:
        for n in z.namelist():
            if re.fullmatch(r"classes\d*\.dex", n):
                z.extract(n, d)
                args = [dexdump] + (["-d"] if disasm else []) + [os.path.join(d, n)]
                yield subprocess.run(args, capture_output=True, text=True, errors="replace").stdout

def parse_classes(text, classes):
    cur = None; section = None; pending = None
    for line in text.splitlines():
        s = line.strip()
        m = re.match(r"Class descriptor\s*: '(.*)'", s)
        if m:
            cur = m.group(1); classes[cur] = {"super": None, "ifaces": [], "members": set()}; section = None; continue
        if cur is None: continue
        m = re.match(r"Superclass\s*: '(.*)'", s)
        if m: classes[cur]["super"] = m.group(1); continue
        if s.startswith("Interfaces"): section = "if"; continue
        if s.startswith(("Static fields", "Instance fields", "Direct methods", "Virtual methods")): section = "m"; continue
        if s.startswith("source_file_idx"): section = None; continue
        if section == "if":
            m = re.match(r"#\d+\s*: '(.*)'", s)
            if m: classes[cur]["ifaces"].append(m.group(1))
        elif section == "m":
            m = re.match(r"name\s*: '(.*)'", s)
            if m: pending = m.group(1); continue
            m = re.match(r"type\s*: '(.*)'", s)
            if m and pending is not None:
                classes[cur]["members"].add(pending + ":" + m.group(1)); pending = None

app, test = {}, {}
for t in dumps(app_apk, False): parse_classes(t, app)
refs = collections.defaultdict(set)
for t in dumps(test_apk, True):
    parse_classes(t, test)
    for m in re.finditer(r", (L[^;\s]+;)\.([^:\s]+):(\S+) // (?:method|field)@", t):
        refs[(m.group(1), m.group(2) + ":" + m.group(3))].add(1)
    for m in re.finditer(r"(?:new-instance|check-cast|const-class|instance-of|new-array|filled-new-array)[^,]*, \[*(L[^;\s]+;) // type@", t):
        refs[(m.group(1), None)].add(1)
for c, info in test.items():
    for r in [info["super"]] + info["ifaces"]:
        if r: refs[(r, None)].add(1)

def has(cls, member, seen=None):
    seen = seen or set()
    if cls in seen: return False
    seen.add(cls)
    if cls in FRAMEWORK_CLASSES: return True
    info = app.get(cls) or test.get(cls)
    if info is None: return False
    if member is None or member in info["members"]: return True
    name = member.split(":")[0]
    if name in ("<init>", "<clinit>"): return False
    return any(has(p, member, seen) for p in [info["super"]] + info["ifaces"] if p)

missing = sorted({(c, m) for (c, m) in refs if c not in test and not c.startswith(OPTIONAL) and not has(c, m)}, key=lambda r: (r[0], r[1] or ""))
for c, m in missing:
    print("App 里没有：" + (c if m is None else f"{c}.{m}"))
if missing:
    print("测试 APK 调到的这些被 R8 删掉了，在 app/e2e-keep.pro 里留下")
    sys.exit(1)
print(f"测试 APK 调到的 {len(refs)} 个类和方法，压缩后的 App 里都有")
