# Homekey

Homekey is a fork of [Neru](https://github.com/y3owk1n/neru), the keyboard-driven
mouse replacement, packaged for macOS as `Homekey.app` with its own icon, menu bar
glyph and a native settings window. Under the hood it is still Neru: the same
daemon, the same `neru` CLI, the same `~/.config/neru/config.toml`. This file
covers what the fork changes about building, installing and releasing it; for
everything else, read Neru's docs.

## Build

```bash
scripts/build-app.sh   # or: just app
```

It needs Go and the Xcode command line tools. In one go it builds the
version-stamped `neru` binary, the settings app (`NeruSettings.app`) and its
self-checks, then runs `scripts/dist.sh` to put together and sign
`build/dist/Homekey.app`. It installs nothing. It ends by printing the bundle
path and the install steps below.

## Install

The upstream installer (`scripts/install.sh`, `just install`) is **not** used
for Homekey: it expects `Neru.app`, and it stops the running daemon before it
notices. Its uninstall looks only for `Neru.app` too, so it would leave Homekey
and its login agent running. `just install` and `just uninstall` refuse on macOS
for that reason. Install by hand:

1. Quit the running app. If it starts at login, run `neru services uninstall`
   first so launchd does not restart it, then `neru stop`.
2. Replace the app, keeping one copy, since both bundles have the same bundle id:
   `rm -rf /Applications/Neru.app /Applications/Homekey.app`, then
   `ditto build/dist/Homekey.app /Applications/Homekey.app`. If you use the
   CLI from a shell, point its link at the new app:
   `ln -sfn /Applications/Homekey.app/Contents/MacOS/neru /usr/local/bin/neru`.
3. Start it with `open /Applications/Homekey.app`, or, to start it at every
   login, run `/Applications/Homekey.app/Contents/MacOS/neru services install`.
4. Re-grant Accessibility: System Settings > Privacy & Security >
   Accessibility, remove the old entry, then turn Homekey on.

## Uninstall

1. `neru services uninstall` if it starts at login, then `neru stop`.
2. `rm -rf /Applications/Homekey.app`, and `rm /usr/local/bin/neru` if you made
   the link.
3. Remove Homekey from System Settings > Privacy & Security > Accessibility.

Your config (`~/.config/neru`) and logs (`~/Library/Logs/neru`) stay; delete
them by hand if you want them gone. So does the "Homekey Local Signing"
identity, which Keychain Access can delete.

## One-time signing setup

macOS remembers the Accessibility grant against the app's code signature. An
ad-hoc signature (`codesign --sign -`) is pinned to a hash of the binary, so
every rebuild looks like a new app and the grant is lost. To avoid this, create
a stable identity once:

```bash
scripts/setup-signing.sh            # add --trust to also mark it trusted (asks for your password)
```

This creates a self-signed "Homekey Local Signing" certificate in your login
keychain, valid for 10 years. Running it again does nothing. `scripts/dist.sh` picks the
signing identity in this order:

1. `NERU_SIGN_IDENTITY`: a name or SHA-1 hash, for example your Apple
   Development identity.
2. "Homekey Local Signing", if it is in the keychain.
3. Ad hoc (`-`). CI always uses this, because it has no identity.

After the first build signed with the stable identity, re-grant Accessibility
once more. From then on rebuilds keep the grant. To check which identity a
build used, run `codesign -d -r- build/dist/Homekey.app`: its designated requirement names a
certificate, not a `cdhash`. The first signing may ask to use the key. Enter
your login password and click Always Allow.

## Releases

`.github/workflows/fork-release.yml` is run by hand from the Actions tab.
Give it a tag shaped like `v1.57.0-hk.1`: upstream's version plus an `-hk.N`
suffix, so fork tags never clash with upstream's when you fetch them. It creates
a normal (not pre-) release at the selected commit, so `/releases/latest`
returns it. It then calls `publish-artifacts.yml`, which builds the six zips
(`neru-{darwin,linux,windows}-{arm64,amd64}.zip`, each with a `.sha256`). The
macOS zips contain `bin/neru`, `Homekey.app` (settings app included) and
`share/man`. The plist versions get the digits only (`1.57.0`). The full tag is
in `NeruBuildID` and in `neru --version`.

Steps you take once, on GitHub:

- Enable Actions on the fork.
- In the Actions tab, disable `release-please`, `flakehub-publish-rolling`,
  `nix-hashes` and `website`. They publish as upstream or need upstream's
  secrets, and release-please would create upstream-numbered tags. Disable them
  there rather than deleting the files, so upstream merges stay clean.
- `nightly` works unchanged and keeps a rolling `nightly` prerelease of fork
  builds.

Release zips are signed ad hoc. Until Developer ID signing and notarization are
set up (the commented secrets in `publish-artifacts.yml`), people who install a
downloaded release have to re-grant Accessibility after every update.

## What stays "neru"

Only display names and icons are rebranded: `CFBundleName`/`CFBundleDisplayName`
and the permission prompts in `resources/Info.plist.template`, `resources/icon.icns`,
the menu bar glyphs, and the settings window. These identifiers deliberately
stay the same:

| Identifier | Why it stays |
| --- | --- |
| Bundle id `com.y3owk1n.neru` | Accessibility, Screen Recording and notification grants are keyed on it. The default menu bar hint target and users' copied configs name it. |
| launchd label `com.y3owk1n.neru` | Renaming it orphans the registered agent, and you end up running two KeepAlive daemons. |
| Executable `neru`, helper `Contents/Helpers/NeruSettings.app` | The settings app, the menu bar's "Settings…" item, oku and nix all look these up by name. |
| `~/.config/neru`, the `neru.sock` socket, `~/Library/Logs/neru` | Existing configs and logs keep working, and a CLI and a daemon from either build can still talk. |
| `Neru version <tag>` output | Version checks parse that prefix. |
| Go module path `github.com/y3owk1n/neru` | Every import and the version ldflags use it. Renaming it would conflict with every upstream merge. |

Because of this, Homekey and upstream Neru cannot be installed side by side.

## Icons

- App icon: `macos/branding/build-icon.sh` rebuilds `macos/branding/Homekey.icns`
  from `make-icon.swift`. Copy it to `resources/icon.icns`.
- Menu bar glyphs: render them with
  `swift macos/branding/make-tray-icons.swift active.png paused.png`, then run
  `just generate-tray-icons active.png paused.png`. This writes the two
  template PNGs embedded from `internal/adapter/systray/icon/`.
- Linux/Windows tray tile (`internal/adapter/systray/icon/tray-icon.png`, 64 px)
  and Windows exe icon (`assets/neru-appicon.png`): cut from the same art, then
  convert them to untagged sRGB with
  `sips --matchTo '/System/Library/ColorSync/Profiles/sRGB Profile.icc' FILE`
  and strip the remaining color chunks (re-encoding with Go's `image/png` does
  it). Go's PNG decoder and go-winres ignore embedded profiles, so a Display P3
  tile would show shifted colors there.
