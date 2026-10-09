#!/usr/bin/env bash
# Rebuilds macos/branding/Homekey.icns from make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
swift make-icon.swift "$work/master.png"
set="$work/Homekey.iconset"
mkdir "$set"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$work/master.png" --out "$set/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$work/master.png" --out "$set/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$set" -o Homekey.icns
echo "✓ macos/branding/Homekey.icns"
