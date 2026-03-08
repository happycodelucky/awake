# Build System Reference

## Overview

The primary build script is `scripts/bundle_app.sh`. It produces two output artifacts in the `dist/` directory:

- `dist/Awake.app` — the macOS application bundle
- `dist/Awake.zip` — a zipped copy of the app bundle suitable for distribution

The script requires Xcode or the Xcode Command Line Tools. It uses SwiftPM to compile the `AwakeMenuBar` product, generates the app icon, writes `Info.plist`, optionally embeds `Sparkle.framework`, and applies a code signature.

Basic usage:

```sh
./scripts/bundle_app.sh
```

Override any environment variable inline:

```sh
VERSION=2.1.0 ARCHS="arm64 x86_64" ./scripts/bundle_app.sh
```

---

## Environment Variables

All variables are optional. Defaults are applied when a variable is unset or empty.

| Variable | Default | Description |
|---|---|---|
| `APP_NAME` | `Awake` | Application name used for the bundle directory (`$APP_NAME.app`), the executable inside `MacOS/`, and `Info.plist` display fields. |
| `BUNDLE_ID` | `com.akkio.apps.awake` | `CFBundleIdentifier` written into `Info.plist`. |
| `VERSION` | `1.0.0` | `CFBundleShortVersionString` written into `Info.plist`. |
| `BUILD_NUMBER` | Current timestamp (`date +%Y%m%d%H%M%S`) | `CFBundleVersion` written into `Info.plist`. In CI this is set to the run number. |
| `DEPLOYMENT_TARGET` | `15.0` | Minimum macOS version. Passed to the Swift compiler as the `-target` triple and written into `LSMinimumSystemVersion`. |
| `ARCHS` | `arm64` | Space-separated list of target architectures (e.g. `arm64` or `arm64 x86_64`). Each arch is built separately and merged with `lipo` when more than one is specified. |
| `ADHOC_SIGN` | `1` | When `1` and no `SIGN_IDENTITY` is found, the bundle is signed with an ad-hoc identity (`-`). Set to `0` to produce an unsigned bundle. |
| `SIGN_IDENTITY` | Auto-detected | Explicit code-signing identity string (e.g. a Developer ID certificate common name). When set, takes precedence over `ADHOC_SIGN`. When unset, the script attempts to auto-detect the first valid identity from the keychain. |
| `SPARKLE_FEED_URL` | _(empty)_ | If non-empty, adds `SUFeedURL` to `Info.plist`. Required for Sparkle auto-updates to locate the appcast feed. |
| `SPARKLE_PUBLIC_ED_KEY` | _(empty)_ | If non-empty, adds `SUPublicEDKey` to `Info.plist`. Must match the Ed25519 key used to sign update archives. |
| `SPARKLE_CHECK_INTERVAL` | `86400` | `SUScheduledCheckInterval` value written into `Info.plist` (seconds). Defaults to 24 hours. |

---

## Build Pipeline

`bundle_app.sh` executes the following steps in order:

### 1. Toolchain Detection

The script locates the active developer directory via `xcode-select -p`. If Xcode is installed but the active directory still points at the Command Line Tools, set it first:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

All tools (`swift`, `swiftc`, `lipo`, `codesign`, `sips`) are resolved through `xcrun`.

### 2. Directory Setup

Creates `dist/` and `.build/bundle/`. Any existing `$APP_NAME.app` bundle is moved aside to a backup path (`dist/$APP_NAME-previous-$BUILD_NUMBER.app`) before the new bundle is written.

### 3. Icon Generation

Compiles `scripts/generate_app_icon.swift` into a standalone binary at `.build/bundle/generate_app_icon`:

```sh
swiftc \
  -sdk <macosx_sdk_path> \
  -target <host_arch>-apple-macosx<DEPLOYMENT_TARGET> \
  -module-cache-path .build/bundle/ModuleCache \
  scripts/generate_app_icon.swift \
  -o .build/bundle/generate_app_icon
```

Runs the compiled binary and writes the icon to `Contents/Resources/AppIcon.icns`:

```sh
.build/bundle/generate_app_icon dist/Awake.app/Contents/Resources/AppIcon.icns
```

### 4. Info.plist Generation

Writes `Contents/Info.plist` directly from a here-doc, embedding all relevant build variables (`APP_NAME`, `BUNDLE_ID`, `VERSION`, `BUILD_NUMBER`, `DEPLOYMENT_TARGET`, `SPARKLE_CHECK_INTERVAL`).

If `SPARKLE_FEED_URL` is non-empty, `SUFeedURL` is appended via `PlistBuddy`. If `SPARKLE_PUBLIC_ED_KEY` is non-empty, `SUPublicEDKey` is appended the same way.

### 5. SPM Build Per Architecture

For each architecture listed in `ARCHS`, SwiftPM builds the `AwakeMenuBar` product in release mode:

```sh
swift build \
  --package-path <root> \
  --scratch-path .build/bundle/spm-<arch> \
  -c release \
  --arch <arch> \
  --product AwakeMenuBar
```

Each resulting binary is copied to `.build/bundle/$APP_NAME-<arch>`.

### 6. lipo (Multi-Arch Only)

When more than one architecture is built, `lipo` merges the per-arch binaries into a single universal binary placed at `Contents/MacOS/$APP_NAME`:

```sh
lipo -create <binary-arm64> <binary-x86_64> -output Contents/MacOS/Awake
```

When only one architecture is built, the binary is copied directly without invoking `lipo`.

### 7. Sparkle.framework Embedding

If the SPM build produced a `Sparkle.framework` under `.build/bundle/`, the framework is copied into `Contents/Frameworks/`. No action is taken when the framework is absent.

### 8. Code Signing

See the Signing Modes section below for the full decision tree.

### 9. Zip Archive

Uses `ditto` to produce `dist/Awake.zip` from the completed app bundle:

```sh
ditto -c -k --keepParent dist/Awake.app dist/Awake.zip
```

---

## Signing Modes

The script selects one of three signing modes:

### Identity-Based Signing

Triggered when `SIGN_IDENTITY` is non-empty (either set explicitly or auto-detected from the keychain). The bundle receives a deep signature using that identity:

```sh
codesign --force --deep --sign "$SIGN_IDENTITY" dist/Awake.app
```

### Ad-Hoc Signing

Triggered when no `SIGN_IDENTITY` is available and `ADHOC_SIGN=1` (the default). Produces a locally runnable bundle that is not notarized and will not pass Gatekeeper on other machines:

```sh
codesign --force --deep --sign - dist/Awake.app
```

To force ad-hoc signing even when a signing identity is present, unset `SIGN_IDENTITY`:

```sh
SIGN_IDENTITY="" ADHOC_SIGN=1 ./scripts/bundle_app.sh
```

### Unsigned

Triggered when `ADHOC_SIGN=0` and no `SIGN_IDENTITY` is set. The bundle is produced without any code signature. The script prints a reminder at the end:

```sh
ADHOC_SIGN=0 ./scripts/bundle_app.sh
```

---

## Icon Generation

`scripts/generate_app_icon.swift` is a self-contained Swift program that renders the application icon using AppKit and Core Graphics. It takes a single argument: the output file path.

```sh
# Compile and run manually
swiftc scripts/generate_app_icon.swift -o /tmp/gen_icon
/tmp/gen_icon /tmp/AppIcon.icns   # .icns output
/tmp/gen_icon /tmp/AppIcon.png    # .png output
```

### What It Renders

The icon is a 1024x1024 canvas with the following layers, composited top to bottom:

- **Background gradient** — deep navy-to-teal linear gradient across the rounded-rectangle icon shape (corner radius 204 pt, inset 64 pt on all sides).
- **Radial glow** — a soft teal-green radial glow originating from the upper-right quadrant.
- **Shine band** — a semi-transparent white linear gradient in a rounded rectangle across the lower portion of the icon, simulating a glass highlight.
- **Track ring** — a white, semi-transparent rounded-rectangle stroke (the racetrack shape) representing the keep-awake control ring.
- **Active track segment** — a cyan-to-green gradient stroke overlaid on the right half of the track ring, indicating the active/awake state.
- **Core pill** — a dark rounded rectangle in the center of the track, creating the appearance of an inset display.
- **Halo glow** — a soft radial glow inside the core pill.
- **Outline** — a very faint white border around the icon shape.

### Output Formats

| Extension | Behavior |
|---|---|
| `.icns` | Produces a multi-resolution ICNS file with slices at 16, 32, 64, 128, 256, 512, and 1024 px. Required by `bundle_app.sh`. |
| `.png` | Produces a single 1024x1024 PNG. Useful for manual inspection. |

---

## CI Workflow (`ci.yml`)

**File:** `.github/workflows/ci.yml`

### Triggers

| Event | Condition |
|---|---|
| `push` | Only on the `main` branch |
| `pull_request` | All pull requests |
| `workflow_dispatch` | Manual trigger from the GitHub Actions UI |

### Runner

`macos-15` with `DEVELOPER_DIR` pointed at `/Applications/Xcode.app/Contents/Developer`.

### Steps

1. Check out the repository.
2. Print toolchain versions (`xcodebuild -version`, `swift --version`).
3. Run `swift build` to validate the Swift package compiles cleanly.
4. Run `./scripts/bundle_app.sh` with `VERSION=ci-<run_number>` and `BUILD_NUMBER=<run_number>`.
5. Upload `dist/Awake.app` and `dist/Awake.zip` as workflow artifacts named `awake-ci-artifacts`.

---

## Release Workflow (`release.yml`)

**File:** `.github/workflows/release.yml`

### Trigger

Manual only (`workflow_dispatch`) with two inputs:

| Input | Required | Description |
|---|---|---|
| `version` | Yes | Release version string without the `v` prefix (e.g. `2.1.0`). |
| `notes` | No | Release notes written into the GitHub Release body. When omitted, GitHub auto-generates notes from merged pull requests. |

### Runner

`macos-15` with `DEVELOPER_DIR` pointed at `/Applications/Xcode.app/Contents/Developer`.

### Steps

1. Check out the repository with full history (`fetch-depth: 0`).
2. Derive `TAG=v<version>` and set `BUILD_NUMBER` to the run number.
3. Print toolchain versions.
4. Run `./scripts/bundle_app.sh` with `VERSION=<version>`.
5. Compute `SHA256` of `dist/Awake.zip` via `shasum -a 256`.
6. Create and push the git tag `v<version>` (idempotent — skipped if the tag already exists locally or on origin).
7. Upload `dist/Awake.app` and `dist/Awake.zip` as workflow artifacts named `awake-release-v<version>`.
8. Publish the GitHub Release. If the release already exists, uploads `Awake.zip` to it; otherwise creates the release with the supplied or auto-generated notes.
9. Optionally publish the Homebrew cask by running `scripts/publish_homebrew_cask.sh`. This step is skipped when the `HOMEBREW_TAP_GITHUB_TOKEN` secret is not configured.

### Required Secrets and Variables (for Homebrew Publishing)

| Name | Kind | Description |
|---|---|---|
| `HOMEBREW_TAP_GITHUB_TOKEN` | Secret | GitHub token with write access to the Homebrew tap repository. When absent, the Homebrew step is skipped. |
| `HOMEBREW_TAP_REPOSITORY` | Variable | Full `owner/repo` path of the Homebrew tap (e.g. `myorg/homebrew-tap`). |
| `HOMEBREW_TAP_BRANCH` | Variable | Branch to commit the updated cask to. |
| `HOMEBREW_TAP_CASK_PATH` | Variable | Path within the tap repository where the cask file lives (e.g. `Casks/awake.rb`). |
