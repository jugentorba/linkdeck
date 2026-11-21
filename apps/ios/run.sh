#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

BUNDLE_ID="dev.linkdeck.app"
APP_PATH="build/Build/Products/Debug-iphonesimulator/LinkDeck.app"

if [[ "${1:-}" != "--no-build" ]]; then
  ./build.sh
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at $APP_PATH. Run ./build.sh first." >&2
  exit 1
fi

DEVICE_ID="$(xcrun simctl list devices booted | sed -nE 's/.*iPhone 17 \(([0-9A-F-]+)\).*/\1/p' | head -n 1)"

if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(xcrun simctl list devices available | sed -nE 's/.*iPhone 17 \(([0-9A-F-]+)\).*/\1/p' | head -n 1)"
fi

if [[ -z "$DEVICE_ID" ]]; then
  RUNTIME_ID="$(xcrun simctl list runtimes | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+' | grep -v 'iPhone' | head -n 1)"
  if [[ -z "$RUNTIME_ID" ]]; then
    echo "No iOS simulator runtime found. Install one in Xcode." >&2
    exit 1
  fi
  DEVICE_ID="$(xcrun simctl create "iPhone 17" com.apple.CoreSimulator.SimDeviceType.iPhone-17 "$RUNTIME_ID")"
fi

if ! xcrun simctl list devices booted | grep -q "$DEVICE_ID"; then
  xcrun simctl boot "$DEVICE_ID" || true
  open -a Simulator >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$DEVICE_ID" -b
fi

xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"

sleep 7
xcrun simctl io "$DEVICE_ID" screenshot screenshot.png

echo "Installed and launched $BUNDLE_ID on $DEVICE_ID"
echo "Screenshot: $(pwd)/screenshot.png"
