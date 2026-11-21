#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. Install it with: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate --spec project.yml

echo "==> Building LinkDeck for iOS devices (unsigned)"
xcodebuild \
  -project LinkDeck.xcodeproj \
  -scheme LinkDeck \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build-ipa \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP="build-ipa/Build/Products/Release-iphoneos/LinkDeck.app"
IPA="LinkDeck-unsigned.ipa"

if [[ ! -d "$APP" ]]; then
  echo "error: expected app not found at $APP" >&2
  exit 1
fi

echo "==> Packaging $IPA"
rm -rf Payload "$IPA"
mkdir Payload
ditto "$APP" "Payload/LinkDeck.app"
zip -qry "$IPA" Payload
rm -rf Payload

echo "Built: $(pwd)/$IPA"
echo "This IPA is unsigned. Re-sign it with your development team or a sideloading tool before installing on a device."
