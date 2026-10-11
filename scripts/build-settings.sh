#!/usr/bin/env bash
#
# Build bin/libhomekeysettings.a: the Settings, Tutorial and Training windows
# (macos/NeruSettings), which `go build -tags homekey_ui` links into the daemon
# (internal/adapter/settingsui/open_darwin.go). Used by `just build-settings`,
# scripts/build-app.sh and release-ci-darwin, so the three cannot drift apart.
#
# Link the daemon with CC="xcrun clang": the toolchain and SDK of this swiftc.
# Another clang (Homebrew's) links against another SDK and misses SwiftUI
# symbols. go build does not hash this library either, so remove the binary
# before linking it again or a Swift-only change is left out.
#
#   scripts/build-settings.sh [arm64|amd64|x86_64]   (default: this Mac's)
set -euo pipefail
cd "$(dirname "$0")/.."

arch="${1:-$(uname -m)}"
[ "$arch" = amd64 ] && arch=x86_64
lib=bin/libhomekeysettings.a

echo "Building $lib ($arch)..."
rm -rf "bin/Homekey Settings.app" bin/NeruSettings.app # the helper apps it replaces
mkdir -p bin
xcrun swiftc -O -swift-version 5 -parse-as-library -emit-library -static \
    -module-name HomekeySettings -target "$arch-apple-macos14.0" \
    -import-objc-header internal/adapter/settingsui/settingsui.h \
    -o "$lib" macos/NeruSettings/Sources/*.swift
echo "✓ Build complete: $lib"
