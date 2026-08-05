#!/bin/bash
# Builds Vinyl and installs it to /Applications.
#
# Requires full Xcode, not just the Command Line Tools — SwiftPM's manifest
# compiler is broken under CLT alone and xcodegen/xcodebuild will fail with
# an unhelpful error if `xcode-select -p` points at CLT instead of Xcode.app.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen not found. Install with: brew install xcodegen" >&2
    exit 1
fi

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building (Release)"
xcodebuild \
    -project VinylMac.xcodeproj \
    -scheme VinylMac \
    -configuration Release \
    -derivedDataPath build/DerivedData \
    build

APP=build/DerivedData/Build/Products/Release/VinylMac.app
if [ ! -d "$APP" ]; then
    echo "Build succeeded but $APP not found." >&2
    exit 1
fi

echo "==> Installing to /Applications/Vinyl.app"
# Quit the running instance first, if any, so the copy isn't fighting a live app,
# then relaunch afterwards — otherwise the desktop is left without Vinyl running.
WAS_RUNNING=""
if pgrep -f /Applications/Vinyl.app/Contents/MacOS/VinylMac >/dev/null 2>&1; then
    WAS_RUNNING=1
    osascript -e 'tell application "Vinyl" to quit' 2>/dev/null || true
fi
rm -rf /Applications/Vinyl.app
cp -R "$APP" /Applications/Vinyl.app

if [ -n "$WAS_RUNNING" ]; then
    echo "==> Relaunching"
    open -a /Applications/Vinyl.app
fi

echo "==> Done."
