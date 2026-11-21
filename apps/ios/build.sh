#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. Install it with: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate --spec project.yml

xcodebuild \
  -project LinkDeck.xcodeproj \
  -scheme LinkDeck \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  build
