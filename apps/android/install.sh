#!/usr/bin/env bash
# Build the debug APK and install it on the first connected device.
set -euo pipefail
cd "$(dirname "$0")"

./gradlew assembleDebug --console=plain
APK="app/build/outputs/apk/debug/app-debug.apk"
cp "$APK" LinkDeck-debug.apk

if adb devices | grep -q "device$"; then
  adb install -r LinkDeck-debug.apk
  adb shell am start -n dev.linkdeck.app/.ui.MainActivity
  echo "Installed and launched."
else
  echo "APK ready at $(pwd)/LinkDeck-debug.apk — no device connected."
fi
