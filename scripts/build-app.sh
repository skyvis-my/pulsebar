#!/bin/zsh
# Builds a universal (Apple silicon + Intel) release Pulsebar.app into ./build and ad-hoc signs it.
# VERSION=0.2.0 ./scripts/build-app.sh stamps that version into Info.plist.
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release $ARCHS
APP=build/Pulsebar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release $ARCHS --show-bin-path)/Pulsebar" "$APP/Contents/MacOS/Pulsebar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
codesign --force --sign - "$APP"
echo "Built $APP"
