#!/usr/bin/env bash
# Capture README screenshots from the iPhone simulator using the debug-only
# INKYTAP_SCREEN deep links (see DemoData.swift). Output: docs/screenshots/*.png
set -euo pipefail
cd "$(dirname "$0")/.."

SIM="${SIM:-iPhone 17}"
BUNDLE_ID=io.github.donny.inkytap
APP=build/DerivedData/Build/Products/Debug-iphonesimulator/InkyTap.app
OUT=docs/screenshots
WIDTH="${WIDTH:-540}"

xcodegen generate >/dev/null
xcodebuild -project InkyTap.xcodeproj -scheme InkyTap -destination "platform=iOS Simulator,name=$SIM" \
  -derivedDataPath build/DerivedData build -quiet
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null
xcrun simctl ui "$SIM" appearance light
xcrun simctl status_bar "$SIM" override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 --operatorName ""
xcrun simctl install "$SIM" "$APP"
mkdir -p "$OUT"

capture() { # name screen
  xcrun simctl terminate "$SIM" "$BUNDLE_ID" 2>/dev/null || true
  if [[ -n "$2" ]]; then
    SIMCTL_CHILD_INKYTAP_SCREEN="$2" xcrun simctl launch "$SIM" "$BUNDLE_ID" >/dev/null
  else
    xcrun simctl launch "$SIM" "$BUNDLE_ID" >/dev/null
  fi
  sleep 3
  xcrun simctl io "$SIM" screenshot --type png "$OUT/$1.png" >/dev/null
  sips --resampleWidth "$WIDTH" "$OUT/$1.png" >/dev/null
  echo "captured $OUT/$1.png"
}

capture home ""
capture send-photo sendPhoto
capture device-probe probe
capture test-pattern testPattern
xcrun simctl status_bar "$SIM" clear
