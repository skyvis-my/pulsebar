#!/bin/zsh
# Builds a release Pulsebar.app into ./build and ad-hoc signs it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP=build/Pulsebar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/Pulsebar" "$APP/Contents/MacOS/Pulsebar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
