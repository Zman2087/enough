#!/bin/sh
# Type-check Enough. On macOS this compiles the app with xcodebuild, which is
# what catches main-actor mistakes in App/. On Linux, UIKit is unavailable, so
# this checks the shared Swift package under strict concurrency instead.
set -eu
cd "$(dirname "$0")/.."

if command -v xcodebuild >/dev/null 2>&1; then
  xcodebuild \
    -project Enough.xcodeproj \
    -scheme Enough \
    -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    CODE_SIGNING_ALLOWED=NO \
    build
  xcodebuild \
    -project Enough.xcodeproj \
    -scheme "Enough Personal" \
    -configuration Personal \
    -destination 'generic/platform=iOS Simulator' \
    CODE_SIGNING_ALLOWED=NO \
    build
else
  echo "xcodebuild is not installed; type-checking FilterEngine with strict concurrency."
  echo "The iOS app target is type-checked on the macOS CI runner."
  swift build -Xswiftc -strict-concurrency=complete
fi
