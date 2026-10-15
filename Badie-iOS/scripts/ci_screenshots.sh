#!/usr/bin/env bash
# 在模拟器中逐个打开演示页面并截图（仅 DEBUG 构建支持 -BBDemoScreen 启动参数）
# 用法: ci_screenshots.sh <simulator-udid> <path/to/Badie.app> <output-dir>
set -euo pipefail

UDID="$1"
APP="$2"
OUT="$3"
BUNDLE="com.badie.app"
SCREENS="${SCREENS:-welcome login levelQuiz levelResult levelGuide levelGuideElite verification home createMenu matchSetup matchSetupVenues venuePicker venueSearch venueDetail addVenue courts matching matchFound ticketWaiting offerWaiting homeTicket ticket games groups groupDetail groupChat playerProfile messages chat friends room joinRoom survey profile editProfile settings notifications leaderboard venueLeaderboard challenges gameResult}"
# 深色模式只截关键页面（CI 模拟器较慢，全部截两遍会超时）
DARK_SCREENS="${DARK_SCREENS:-home matchFound offerWaiting groupDetail playerProfile chat profile}"
# 英文界面抽查
EN_SCREENS="${EN_SCREENS:-welcome levelQuiz levelResult home matchSetup matchFound games groupDetail playerProfile survey profile settings leaderboard venueLeaderboard challenges}"

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

# 每一轮：文件名前缀 外观 语言 区域 页面列表
capture() {
  local prefix="$1" appearance="$2" language="$3" locale="$4" list="$5"
  xcrun simctl ui "$UDID" appearance "$appearance" || true
  for screen in $list; do
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
    # App 使用洛杉矶时区（CI 机器是 UTC），时间显示与演示城市一致
    SIMCTL_CHILD_TZ="America/Los_Angeles" xcrun simctl launch "$UDID" "$BUNDLE" \
      -BBDemoScreen "$screen" -AppleLanguages "($language)" -AppleLocale "$locale" >/dev/null
    sleep 5
    xcrun simctl io "$UDID" screenshot "$OUT/${prefix}-${screen}.png" >/dev/null 2>&1
    echo "captured ${prefix}-${screen}"
  done
}

capture light light zh-Hans zh_CN "$SCREENS"
capture dark dark zh-Hans zh_CN "$DARK_SCREENS"
capture en light en en_US "$EN_SCREENS"
# 其他语言各抽两页，检查排版与字体
for pair in zh-Hant:zh_TW ja:ja_JP ko:ko_KR id:id_ID ms:ms_MY th:th_TH vi:vi_VN hi:hi_IN; do
  capture "${pair%%:*}" light "${pair%%:*}" "${pair##*:}" "home levelResult"
done
