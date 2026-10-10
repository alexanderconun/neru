#!/usr/bin/env bash
#
# Build bin/Homekey Settings.app, the settings window that ships inside
# Homekey.app/Contents/Helpers. Used by `just build-settings`,
# scripts/build-app.sh and CI, so the three cannot drift apart.
#
# The bundle's file name is what the Dock and Finder show, so it carries the
# display name rather than the source folder's (macos/NeruSettings).
set -euo pipefail
cd "$(dirname "$0")/.."

helper="bin/Homekey Settings.app"

echo "Building $helper..."
rm -rf "$helper" bin/NeruSettings.app # the helper's name before Homekey
mkdir -p "$helper/Contents/MacOS" "$helper/Contents/Resources"
swiftc -O -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macos14.0" \
    -o "$helper/Contents/MacOS/HomekeySettings" macos/NeruSettings/Sources/*.swift
cp macos/NeruSettings/Info.plist "$helper/Contents/"
cp resources/icon.icns "$helper/Contents/Resources/"
# dist.sh re-signs it with the bundle's identity; this only makes it runnable.
codesign --force --sign "${NERU_SIGN_IDENTITY:--}" "$helper"
echo "✓ Build complete: $helper"
