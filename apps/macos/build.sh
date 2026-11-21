#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

if command -v xcodegen >/dev/null 2>&1; then
  XCODEGEN="$(command -v xcodegen)"
else
  XCODEGEN="/opt/homebrew/bin/xcodegen"
fi

echo "==> Generating Xcode project"
"$XCODEGEN" generate

echo "==> Building LinkDeck (Release)"
xcodebuild \
  -project LinkDeck.xcodeproj \
  -scheme LinkDeck \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  build

PRODUCT="build/Build/Products/Release/LinkDeck.app"
DEST="build/LinkDeck.app"

if [ ! -d "$PRODUCT" ]; then
  echo "error: expected product not found at $PRODUCT" >&2
  exit 1
fi

echo "==> Staging $DEST"
rm -rf "$DEST"
ditto "$PRODUCT" "$DEST"

echo "==> Ad-hoc signing"
codesign --force --deep -s - "$DEST"
codesign --verify --deep --strict "$DEST"

echo "Built: $PWD/$DEST"
