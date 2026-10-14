#!/usr/bin/env bash
# 在模拟器中逐个打开演示页面并截图（仅 DEBUG 构建支持 -BBDemoScreen 启动参数）
# 用法: ci_screenshots.sh <simulator-udid> <path/to/BadmintonBuddy.app> <output-dir>
set -euo pipefail

UDID="$1"
APP="$2"
OUT="$3"
BUNDLE="com.badmintonbuddy.app"
SCREENS="${SCREENS:-welcome login levelQuiz levelResult levelGuide levelGuideElite verification home createMenu matchSetup matchSetupVenues venuePicker venueSearch venueDetail addVenue courts matching matchFound ticketWaiting offerWaiting homeTicket ticket games groups groupDetail groupChat playerProfile messages chat friends room joinRoom survey profile editProfile settings notifications}"
# 深色模式只截关键页面（CI 模拟器较慢，全部截两遍会超时）
DARK_SCREENS="${DARK_SCREENS:-home matchFound offerWaiting groupDetail playerProfile chat profile}"

mkdir -p "$OUT"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
# 首发市场：洛杉矶圣盖博谷（与 Coordinate.fallbackCenter 一致）
xcrun simctl location "$UDID" set 34.0686,-118.0276 || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant location "$BUNDLE" || true

# 预热一次带键盘的页面：系统键盘首次弹出时会显示“滑行输入”引导气泡，只出现一次
xcrun simctl launch "$UDID" "$BUNDLE" -BBDemoScreen joinRoom >/dev/null || true
sleep 6
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true

for appearance in light dark; do
  xcrun simctl ui "$UDID" appearance "$appearance" || true
  if [ "$appearance" = "dark" ]; then LIST="$DARK_SCREENS"; else LIST="$SCREENS"; fi
  for screen in $LIST; do
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
    # App 使用洛杉矶时区（CI 机器是 UTC），时间显示与演示城市一致
    SIMCTL_CHILD_TZ="America/Los_Angeles" xcrun simctl launch "$UDID" "$BUNDLE" -BBDemoScreen "$screen" >/dev/null
    sleep 5
    xcrun simctl io "$UDID" screenshot "$OUT/${appearance}-${screen}.png" >/dev/null 2>&1
    echo "captured ${appearance}-${screen}"
  done
done
