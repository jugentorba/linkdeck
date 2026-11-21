#!/usr/bin/env bash
# Copies the shared blocklist, cosmetic filter and icons into each app.
# Run after editing anything under shared/.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "→ blocklist + cosmetic script"
cp shared/blocklist.txt apps/android/app/src/main/assets/blocklist.txt
cp shared/cosmetic.js   apps/android/app/src/main/assets/cosmetic.js
cp shared/blocklist.txt apps/macos/Resources/blocklist.txt
cp shared/cosmetic.js   apps/macos/Resources/cosmetic.js
cp shared/blocklist.txt apps/ios/LinkDeck/Resources/blocklist.txt
cp shared/cosmetic.js   apps/ios/LinkDeck/Resources/cosmetic.js
cp shared/blocklist.txt apps/pwa/blocklist.txt
cp shared/cosmetic.js   apps/pwa/cosmetic.js

echo "→ icons"
swift tools/make-icons.swift >/dev/null
rm -rf apps/android/app/src/main/res/mipmap-mdpi apps/android/app/src/main/res/mipmap-hdpi \
       apps/android/app/src/main/res/mipmap-xhdpi apps/android/app/src/main/res/mipmap-xxhdpi \
       apps/android/app/src/main/res/mipmap-xxxhdpi
cp -R shared/icon/android/mipmap-* apps/android/app/src/main/res/
cp shared/icon/AppIcon.icns apps/macos/Resources/AppIcon.icns
cp shared/icon/ios-AppIcon-1024.png apps/ios/LinkDeck/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
cp shared/icon/icon-1024.png apps/pwa/icons/icon-1024.png
cp shared/icon/icon-512.png  apps/pwa/icons/icon-512.png
cp shared/icon/icon-192.png  apps/pwa/icons/icon-192.png
cp shared/icon/icon-180.png  apps/pwa/icons/apple-touch-icon.png
cp shared/icon/icon-64.png   apps/pwa/icons/favicon.png

echo "Done. Rebuild the apps that changed."
