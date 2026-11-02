#!/usr/bin/env bash
# Build InkyTap for a USB-connected iPhone, install it, and launch it.
# Usage: scripts/deploy-device.sh [device-name-or-udid]
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME=InkyTap
BUNDLE_ID=io.github.donny.inkytap
DERIVED=build/DerivedData

# Pick the device: explicit arg, else the first physical device devicectl can see.
DEVICE="${1:-}"
if [[ -z "$DEVICE" ]]; then
  DEVICE=$(xcrun devicectl list devices --filter "reality == 'physical'" --json-output /dev/stdout 2>/dev/null \
    | python3 -c 'import json,sys; d=json.load(sys.stdin)["result"]["devices"]; print(d[0]["identifier"] if d else "")') || true
fi
if [[ -z "$DEVICE" ]]; then
  echo "No physical iPhone found. Plug it in with a cable, unlock it, tap 'Trust' if prompted, then rerun." >&2
  echo "Devices seen:" >&2
  xcrun devicectl list devices >&2
  exit 1
fi
echo "==> Target device: $DEVICE"

[[ -d InkyTap.xcodeproj ]] || xcodegen generate

echo "==> Building for device (automatic signing; registers the device with the team if needed)"
xcodebuild \
  -project InkyTap.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "platform=iOS,id=$DEVICE" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  build -quiet

APP="$DERIVED/Build/Products/Debug-iphoneos/$SCHEME.app"
echo "==> Installing $APP"
xcrun devicectl device install app --device "$DEVICE" "$APP"
echo "==> Launching $BUNDLE_ID"
xcrun devicectl device process launch --device "$DEVICE" --terminate-existing "$BUNDLE_ID"
echo "==> Done"
