#!/usr/bin/env bash
# 在模拟器中逐个打开演示页面并截图（仅 DEBUG 构建支持 -BBDemoScreen 启动参数）
# 用法: ci_screenshots.sh <simulator-udid> <path/to/BadmintonBuddy.app> <output-dir>
set -euo pipefail

UDID="$1"
APP="$2"
OUT="$3"
BUNDLE="com.badmintonbuddy.app"
SCREENS="${SCREENS:-welcome login home matchSetup courts matching matchFound ticket games messages chat friends room joinRoom survey profile editProfile settings notifications}"

mkdir -p "$OUT"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl location "$UDID" set 39.9219,116.4433 || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant location "$BUNDLE" || true

# 预热一次带键盘的页面：系统键盘首次弹出时会显示“滑行输入”引导气泡，只出现一次
xcrun simctl launch "$UDID" "$BUNDLE" -BBDemoScreen joinRoom >/dev/null || true
sleep 6
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true

for appearance in light dark; do
  xcrun simctl ui "$UDID" appearance "$appearance" || true
  for screen in $SCREENS; do
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
    xcrun simctl launch "$UDID" "$BUNDLE" -BBDemoScreen "$screen" >/dev/null
    sleep 5
    xcrun simctl io "$UDID" screenshot "$OUT/${appearance}-${screen}.png" >/dev/null 2>&1
    echo "captured ${appearance}-${screen}"
  done
done
