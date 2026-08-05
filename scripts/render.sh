#!/bin/bash
# Builds and runs the RenderHarness target, rendering DesktopSceneView for every fixture
# cover under Fixtures/ to a PNG under renders/. No music player and no live desktop
# window involved — this is how to judge a visual change without screenshotting the
# actual desktop.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen not found. Install with: brew install xcodegen" >&2
    exit 1
fi

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building RenderHarness (Debug)"
xcodebuild \
    -project VinylMac.xcodeproj \
    -scheme RenderHarness \
    -configuration Debug \
    -derivedDataPath build/DerivedData \
    build

BIN=build/DerivedData/Build/Products/Debug/RenderHarness
if [ ! -x "$BIN" ]; then
    echo "Build succeeded but $BIN not found." >&2
    exit 1
fi

echo "==> Rendering fixtures"
"$BIN" Fixtures renders
