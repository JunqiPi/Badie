#!/usr/bin/env bash
# 在模拟器上跑端到端测试（.github/workflows/android-e2e.yml 在模拟器开好后调用，也可以在自己电脑上跑）。
# 每一段是一次 `am instrument`（新的进程）：这样能测冷启动、被杀掉以后收推送；段和段之间这里可以替“另一个人”做事。
#
# 要的环境变量：SUPABASE_URL（电脑上的地址，如 http://127.0.0.1:54321）、PUBLISHABLE_KEY、SERVICE_ROLE_KEY、
# PUSH（1 = 推送配好了）。可选：E2E_OUT（截图、日志放哪）。APK 要先用 -Pbadie.supabaseUrl=http://10.0.2.2:54321 构建好。
set -uo pipefail

cd "$(dirname "$0")/.."
APP=com.badie.app
RUNNER=$APP.test/androidx.test.runner.AndroidJUnitRunner
OUT=${E2E_OUT:-build/e2e}
RUN=${E2E_RUN:-$(date +%s | tail -c 7)}
PUSH=${PUSH:-0}
mkdir -p "$OUT"
rm -f "$OUT"/*.mp4

# 模拟器里电脑的地址是 10.0.2.2
EMU_URL=${SUPABASE_URL/127.0.0.1/10.0.2.2}
EMU_MAILPIT=http://10.0.2.2:54324

adb install -r app/build/outputs/apk/debug/app-debug.apk >/dev/null
adb install -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk >/dev/null
# 动画关掉（等待更稳），位置放在洛杉矶（种子数据里的球馆在那）
for key in window_animation_scale transition_animation_scale animator_duration_scale; do adb shell settings put global $key 0; done
# 模拟器在 CI 上慢，桌面（Pixel Launcher）偶尔“没有响应”，弹窗会挡住 App：不弹这类错误框
adb shell settings put global hide_error_dialogs 1
adb emu geo fix -118.29 34.03 >/dev/null 2>&1 || true

adb logcat -c
adb logcat -v time > "$OUT/logcat.txt" 2>&1 &
LOGCAT=$!

passed=()
failed=()

# phase <名字> <测试类[#方法]> [clear]：clear 先清掉 App 的数据（没登录、没给权限）
phase() {
  local name=$1 target=$2 clear=${3:-}
  echo "::group::$name ($target)"
  [ "$clear" = clear ] && adb shell pm clear $APP >/dev/null
  adb shell rm -rf /sdcard/Android/data/$APP/files/e2e
  adb shell screenrecord --bit-rate 2000000 --time-limit 180 "/sdcard/$name.mp4" >/dev/null 2>&1 &
  local recorder=$!
  # 不回显这一行：里面有本机的 key
  adb shell am instrument -w -r \
    -e class "com.badie.app.e2e.$target" \
    -e supabaseUrl "$EMU_URL" -e publishableKey "$PUBLISHABLE_KEY" -e serviceKey "$SERVICE_ROLE_KEY" \
    -e mailpitUrl "$EMU_MAILPIT" -e run "$RUN" -e push "$PUSH" \
    $RUNNER > "$OUT/$name.txt" 2>&1
  adb shell pkill -INT screenrecord >/dev/null 2>&1 || true
  wait $recorder 2>/dev/null || true
  sleep 1
  if grep -q "^OK (" "$OUT/$name.txt" && ! grep -q "FAILURES!!!\|INSTRUMENTATION_FAILED\|Process crashed" "$OUT/$name.txt"; then
    passed+=("$name")
    grep -q "AssumptionViolatedException\|INSTRUMENTATION_STATUS_CODE: -4" "$OUT/$name.txt" && echo "（有跳过的测试）"
    echo "通过：$name"
    adb shell rm -f "/sdcard/$name.mp4"
  else
    failed+=("$name")
    echo "没通过：$name"
    grep -E "^(INSTRUMENTATION_STATUS: (test|stack)=|	at com\.badie|java\.|Caused by|AssertionError|IllegalStateException)" "$OUT/$name.txt" | head -60
    adb pull "/sdcard/$name.mp4" "$OUT/" >/dev/null 2>&1 || true
    adb pull /sdcard/Android/data/$APP/files/e2e "$OUT/$name-files" >/dev/null 2>&1 || true
    adb exec-out screencap -p > "$OUT/$name-end.png" 2>/dev/null || true
  fi
  echo "::endgroup::"
}

# 以 B 的身份发私信（推送那一段用：B 是 PushTest 建的 push-b-<这一轮>）
send_dm_as_b() {
  local token a
  token=$(curl -sf "$SUPABASE_URL/auth/v1/token?grant_type=password" -H "apikey: $PUBLISHABLE_KEY" -H "Content-Type: application/json" \
    -d "{\"email\":\"push-b-$RUN@test.local\",\"password\":\"shuttle rally court nine\"}" | jq -r .access_token)
  a=$(curl -sf "$SUPABASE_URL/auth/v1/admin/users?per_page=200" -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
    | jq -r --arg email "push-a-$RUN@test.local" '.users[] | select(.email == $email) | .id')
  curl -sf "$SUPABASE_URL/rest/v1/rpc/send_message" -H "apikey: $PUBLISHABLE_KEY" -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" -d "{\"p_kind\":\"dm\",\"p_id\":\"$a\",\"p_body\":\"$1\"}" >/dev/null
}

# 1. 注册、退出、密码登录；冷启动直接进主界面
phase account AccountTest clear
phase cold-start ColdStartTest

# 2. 聊天不用刷新（每个测试单独一段：新的进程、清掉数据，各用各的账号）
phase chat-dm ChatTest#directMessagesArriveWithoutRefreshing clear
phase chat-game ChatTest#gameGroupChatArrivesWithoutRefreshing clear

# 3. 推送：登记和退出时注销不用 FCM_SERVICE_ACCOUNT；真的收通知要
phase push-registration PushRegistrationTest clear
if [ "$PUSH" = 1 ]; then
  phase push PushTest clear
  # 被杀掉以后：打开 App（登录状态还在），回桌面，杀掉进程，B 发私信，等通知出来再点
  adb shell am start -W -n $APP/.MainActivity >/dev/null
  sleep 8
  adb shell input keyevent KEYCODE_HOME
  sleep 2
  adb shell am kill $APP
  sleep 2
  if [ -n "$(adb shell pidof $APP)" ]; then echo "App 的进程还在"; fi
  send_dm_as_b "Killed $RUN"
  for i in $(seq 1 60); do
    adb shell dumpsys notification --noredact | grep -q "Killed $RUN" && break
    sleep 1
  done
  phase push-killed PushKilledTest
else
  echo "::notice::没有配 FCM_SERVICE_ACCOUNT（GitHub Secrets），推送的测试跳过了"
fi

# 4. 别的地方也自己刷新；通知中心、下拉刷新
phase friend-request LiveRefreshTest#incomingFriendRequestShowsBadge clear
phase invite LiveRefreshTest#inviteFromAnotherPlayerShowsUpOnGames clear
phase room-lobby LiveRefreshTest#playerJoiningByCodeShowsInLobby clear
phase quick-match LiveRefreshTest#quickMatchOfferConfirmedBecomesGame clear
phase inbox-routing NotificationCenterTest#tappingFriendRequestOpensPlayerAndAccepts clear
phase pull-to-refresh NotificationCenterTest#pullToRefreshLoadsNewGame clear

kill $LOGCAT 2>/dev/null || true
echo "通过：${passed[*]:-无}"
echo "没通过：${failed[*]:-无}"
if [ ${#failed[@]} -eq 0 ]; then rm -f "$OUT/logcat.txt"; exit 0; fi
exit 1
