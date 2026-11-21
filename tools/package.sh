#!/usr/bin/env bash
# Builds every deliverable into dist/ and writes SHA256SUMS.txt.
# Usage: tools/package.sh [--skip-ios]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="1.0.1"
DIST="$ROOT/dist"
SKIP_IOS=false
[ "${1:-}" = "--skip-ios" ] && SKIP_IOS=true

rm -rf "$DIST"
mkdir -p "$DIST"

echo "==> Android APK"
(
  cd apps/android
  ./gradlew assembleDebug --console=plain -q
)
cp apps/android/app/build/outputs/apk/debug/app-debug.apk "$DIST/LinkDeck-$VERSION-android.apk"

echo "==> macOS app"
if [ ! -d apps/macos/build/LinkDeck.app ]; then
  ( cd apps/macos && ./build.sh >/dev/null )
fi
ditto -c -k --sequesterRsrc --keepParent \
  apps/macos/build/LinkDeck.app "$DIST/LinkDeck-$VERSION-macos.zip"

echo "==> PWA bundle"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp apps/pwa/index.html apps/pwa/styles.css apps/pwa/app.js apps/pwa/sw.js \
   apps/pwa/manifest.webmanifest apps/pwa/blocklist.txt apps/pwa/cosmetic.js \
   apps/pwa/404.html "$STAGE"/
cp -R apps/pwa/icons "$STAGE"/
( cd "$STAGE" && zip -qr "$DIST/LinkDeck-$VERSION-pwa.zip" . )

if [ "$SKIP_IOS" = false ]; then
  echo "==> iOS unsigned IPA"
  ( cd apps/ios && ./build-ipa.sh >/dev/null )
  cp apps/ios/LinkDeck-unsigned.ipa "$DIST/LinkDeck-$VERSION-ios-unsigned.ipa"
fi

echo "==> Checksums"
( cd "$DIST" && shasum -a 256 * > SHA256SUMS.txt )

echo
ls -lh "$DIST"
cat "$DIST/SHA256SUMS.txt"
