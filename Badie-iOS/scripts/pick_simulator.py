"""Print the UDID of the newest available iPhone simulator (prefers a non-Max Pro model; --max prefers a Pro Max, the 6.9-inch size App Store screenshots need)."""
import json
import re
import subprocess
import sys

devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))["devices"]
best = None
for runtime, entries in devices.items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for device in entries:
        name = device["name"]
        if not name.startswith("iPhone"):
            continue
        preferred = 1 if re.fullmatch(r"iPhone \d+ Pro Max" if "--max" in sys.argv else r"iPhone \d+ Pro", name) else 0
        score = (version, preferred)
        if best is None or score > best[0]:
            best = (score, device["udid"], name, runtime)

if best is None:
    sys.exit("No iPhone simulator available")
print(f"Using {best[2]} ({best[3]})", file=sys.stderr)
print(best[1])
