#!/usr/bin/env bash
# CI 에뮬레이터에서 주요 화면을 띄워 스크린샷을 남긴다. (iOS ios.yml의 미리보기 단계 대응)
set -u
APK="$1"
OUT="$2"
PKG=org.chargajoe.chajajwo
mkdir -p "$OUT"
adb install -r "$APK"
adb shell pm grant $PKG android.permission.ACCESS_FINE_LOCATION || true
adb shell pm grant $PKG android.permission.ACCESS_COARSE_LOCATION || true
adb shell pm grant $PKG android.permission.POST_NOTIFICATIONS || true
adb emu geo fix 126.9506 37.4593 || true
shot() {
  local name="$1"; shift
  adb shell am force-stop $PKG
  adb logcat -c || true
  adb shell am start -n $PKG/.MainActivity "$@"
  sleep 16
  adb exec-out screencap -p > "$OUT/$name.png"
  adb logcat -d > "$OUT/$name.log" || true
}
shot home
shot food-sheet --es preview "place:meal-63동"
shot building-card --es preview "building:63"
shot building-explore --es preview "building:63:explore"
shot amenities --es preview amenities
shot directions --es preview directions
shot dining --es preview dining
shot route --es preview route
{
  echo "--- home: SDK init / crash context"
  grep -A12 -E "카카오맵 초기화 실패|FATAL EXCEPTION|카카오맵 오류" "$OUT/home.log" | head -80
  echo "--- all screens: errors"
  grep -h -E " E (ChajajwoApp|CampusMap|AndroidRuntime|K3fAApi)" "$OUT"/*.log | cut -c 33- | sort | uniq -c | sort -rn | head -40
} > "$OUT/summary.txt" 2>&1 || true
