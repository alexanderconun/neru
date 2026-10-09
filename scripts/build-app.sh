#!/usr/bin/env bash
#
# Build build/dist/Homekey.app in one go: the version-stamped neru binary, the
# settings app and its self-checks, then scripts/dist.sh to bundle and sign.
# Needs only Go and the Xcode command line tools, no `just`. Installs nothing:
# it ends by printing the manual install steps.
#
#   scripts/build-app.sh
#
# The settings steps mirror the justfile's build-settings and check-settings
# recipes, and the ldflags its LDFLAGS; keep them in step.
set -euo pipefail
cd "$(dirname "$0")/.."

[ "$(uname -s)" = Darwin ] || { echo "build-app: Homekey.app builds on macOS only" >&2; exit 1; }

version="$(git describe --tags --always --dirty 2>/dev/null || echo dev)"
commit="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
date="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
pkg=github.com/y3owk1n/neru/internal/buildinfo

echo "Building neru $version..."
mkdir -p bin
CGO_ENABLED=1 go build \
    -ldflags="-s -w -X $pkg.Version=$version -X $pkg.GitCommit=$commit -X $pkg.BuildDate=$date" \
    -o bin/neru ./cmd/neru

echo "Building NeruSettings.app..."
rm -rf bin/NeruSettings.app
mkdir -p bin/NeruSettings.app/Contents/MacOS bin/NeruSettings.app/Contents/Resources
swiftc -O -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macos14.0" \
    -o bin/NeruSettings.app/Contents/MacOS/NeruSettings macos/NeruSettings/Sources/*.swift
cp macos/NeruSettings/Info.plist bin/NeruSettings.app/Contents/
cp resources/icon.icns bin/NeruSettings.app/Contents/Resources/
# dist.sh re-signs it with the bundle's identity; this only makes it runnable.
codesign --force --sign "${NERU_SIGN_IDENTITY:--}" bin/NeruSettings.app

echo "Checking the settings logic..."
# shellcheck disable=SC2046 # one path per source file, no spaces in them
swiftc -swift-version 5 -o bin/check-settings \
    $(ls macos/NeruSettings/Sources/*.swift | grep -v '/App.swift$') macos/NeruSettings/Tests/*.swift
./bin/check-settings

NERU_DIST_VERSION="$version" bash scripts/dist.sh bin/neru build/dist

app="$PWD/build/dist/Homekey.app"
# The leaf certificate's name; an ad-hoc signature has none. No head in the
# pipe: under pipefail an early exit could SIGPIPE sed and abort the script.
signer="$(codesign -dv "$app" 2>&1 | sed -n 's/^Authority=//p')"
signer="${signer%%$'\n'*}"
cat <<EOF

✓ $app
  version $version, signed ${signer:-ad hoc}

Nothing was installed. To install it by hand:
  1. Quit the running app. If it starts at login, unregister that first so
     launchd does not restart it, then stop it:
       neru services uninstall    # only if you use the login service
       neru stop
  2. Replace the app (keep one copy: both share the bundle id):
       rm -rf /Applications/Neru.app /Applications/Homekey.app
       ditto "$app" /Applications/Homekey.app
     Point the CLI link (the upstream installer put it in /usr/local/bin) at it:
       ln -sfn /Applications/Homekey.app/Contents/MacOS/neru /usr/local/bin/neru
  3. Start it: open /Applications/Homekey.app
     or, to start at every login:
       /Applications/Homekey.app/Contents/MacOS/neru services install
  4. Re-grant Accessibility once: System Settings > Privacy & Security >
     Accessibility, remove the old Neru/Homekey entry, then turn Homekey on.
EOF
if [ -z "$signer" ]; then
    cat <<EOF
  5. This build is signed ad hoc, so every rebuild needs step 4 again. Run
     scripts/setup-signing.sh once and rebuild: from then on the grant stays.
EOF
fi
