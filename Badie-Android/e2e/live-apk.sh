#!/usr/bin/env bash
# 网站上正在发的安装包（https://badie.rsvp/android/badie.apk）在模拟器上能不能打开：装上、启动、看到欢迎页、
# 点“邮箱登录 / 注册”进到邮箱那一页，整个过程 App 不崩。不登录（正式后端要人机验证）。
# android-e2e.yml 的 live-apk 那一组在模拟器开好后调用：bash Badie-Android/e2e/live-apk.sh <apk>。可选 E2E_OUT（截图、日志放哪）
set -uo pipefail

APK=$1
APP=com.badie.app
OUT=${E2E_OUT:-build/live-apk}
mkdir -p "$OUT"

# 正式包和测试用的调试包签名不一样，先卸掉
adb uninstall $APP >/dev/null 2>&1 || true
adb install "$APK" >/dev/null || { echo "装不上"; exit 1; }
adb shell settings put global hide_error_dialogs 1
adb logcat -c
adb logcat -b crash -c 2>/dev/null || true

# 界面结构里找某句话的位置（Compose 的文字在 text 或 content-desc 里）；找到就打印中心点“x y”
find_text() {
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  adb exec-out cat /sdcard/ui.xml > "$OUT/ui.xml" 2>/dev/null
  python3 -I - "$OUT/ui.xml" "$@" <<'PY'
import re, sys, xml.etree.ElementTree as ET
try:
    root = ET.parse(sys.argv[1]).getroot()
except Exception:
    sys.exit(1)
for node in root.iter("node"):
    if any(t in (node.get("text") or "") or t in (node.get("content-desc") or "") for t in sys.argv[2:]):
        x1, y1, x2, y2 = map(int, re.findall(r"\d+", node.get("bounds")))
        print((x1 + x2) // 2, (y1 + y2) // 2)
        sys.exit(0)
sys.exit(1)
PY
}

# wait_text <秒> <这句话的几种语言...>
wait_text() {
  local seconds=$1; shift
  local end=$((SECONDS + seconds))
  while [ $SECONDS -lt $end ]; do
    find_text "$@" && return 0
    sleep 2
  done
  return 1
}

crashed() {
  adb logcat -d -b crash 2>/dev/null | grep -q "Process: $APP" && return 0
  adb logcat -d 2>/dev/null | grep -A3 "FATAL EXCEPTION" | grep -q "Process: $APP"
}

fail() {
  echo "没通过：$1"
  adb exec-out screencap -p > "$OUT/live-end.png" 2>/dev/null || true
  adb logcat -d -v time > "$OUT/logcat-live.txt" 2>&1 || true
  adb logcat -d -b crash > "$OUT/crash-live.txt" 2>&1 || true
  grep -A20 "FATAL EXCEPTION" "$OUT/logcat-live.txt" | head -40
  exit 1
}

adb shell am start -W -n $APP/.MainActivity >/dev/null || fail "打不开"

# 欢迎页：三个登录方式都在（模拟器的语言可能是英文或中文）
wait_text 60 "Sign in or sign up with email" "邮箱登录 / 注册" >/dev/null || fail "60 秒内没看到欢迎页"
find_text "Continue with Google" "使用 Google 账号继续" >/dev/null || fail "欢迎页上没有 Google 登录"
find_text "Continue with Apple" "通过 Apple 继续" >/dev/null || fail "欢迎页上没有 Apple 登录"
adb exec-out screencap -p > "$OUT/live-welcome.png" 2>/dev/null || true
crashed && fail "欢迎页时崩了"
echo "欢迎页：好的"

# 点邮箱登录，进到邮箱那一页
xy=$(find_text "Sign in or sign up with email" "邮箱登录 / 注册") || fail "找不到邮箱登录的按钮"
adb shell input tap $xy
wait_text 30 "Sign in with email" "用邮箱登录" "Sign up for Badie" "注册 Badie" >/dev/null || fail "点了邮箱登录没进到邮箱那一页"
sleep 5
adb exec-out screencap -p > "$OUT/live-email.png" 2>/dev/null || true
crashed && fail "邮箱那一页崩了"
[ -n "$(adb shell pidof $APP)" ] || fail "App 的进程没了"
echo "邮箱那一页：好的"

adb logcat -d -v time > "$OUT/logcat-live.txt" 2>&1 || true
echo "通过：网站上的安装包能打开，欢迎页和邮箱那一页都正常，没有崩溃"
