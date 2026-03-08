# Awake

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue.svg?style=for-the-badge&logo=apple)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-black.svg?style=for-the-badge&logo=apple)
[![CI](https://img.shields.io/github/actions/workflow/status/happycodelucky/awake/ci.yml?style=for-the-badge&label=ci)](https://github.com/happycodelucky/awake/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/happycodelucky/awake?style=for-the-badge)](https://github.com/happycodelucky/awake/releases/latest)
[![License: PolyForm NC](https://img.shields.io/badge/license-PolyForm%20NC%201.0-orange.svg?style=for-the-badge)](LICENSE)
[![Maintained](https://img.shields.io/badge/Maintained%3F-yes-green.svg?style=for-the-badge)](https://github.com/happycodelucky/awake/graphs/commit-activity)

> **AI Experiment:** This app was almost entirely written by AI (Codex & Claude Code), with only minor human edits. It's an experiment in AI-assisted software development — the design, architecture, and code are AI-generated. Use it, learn from it, fork it.

## About

Awake is a native macOS menu bar app that keeps your Mac awake for a chosen duration while surfacing managed-device policies that may still interrupt your session. It is built for Apple Silicon Macs running macOS 15+ and is especially useful for long-running local work such as AI agents, builds, downloads, and unattended tasks.

## Overview

**Keeps your Mac awake** — beyond what `caffeinate` can do.

Awake is a macOS menu bar utility that prevents your Mac from sleeping for a set duration. Unlike `caffeinate`, it's MDM-aware: it reads your managed profiles and warns you when enterprise policies — auto-logout, screensaver timeouts, login window idle settings — may still interrupt your session. Originally built for long-running local AI agentic workflows, but useful whenever you need your Mac to stay awake and actually mean it.

![Awake screenshot](assets/screenshot.png)
<!-- TODO: Replace with actual screenshot or GIF -->

## Features

- **Timer presets** — 5m, 10m, 15m, 30m, 1h, 2h, 4h, 8h, 12h
- **Pause & resume** — hold Option to pause instead of stop
- **Two sleep modes** — keep the display awake, or allow display sleep while preventing system sleep (great for background work)
- **MDM policy detection** — reads `/Library/Managed Preferences` and warns you about policies that may override your session
- **Persistent sessions** — restores your timer across app restarts
- **Menu bar native** — lives in your menu bar, stays out of your way

## Download

[Download the latest release →](https://github.com/happycodelucky/awake/releases/latest)

If you publish the tap described below, Homebrew install is:

```bash
brew tap happycodelucky/tap
brew install --cask awake
```

## Build from Source

Requirements:

- Xcode (not just Command Line Tools)
- Apple Silicon Mac
- macOS 15.0+

```bash
# If Xcode is installed but xcode-select still points to CLT:
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

# Build the app bundle
./scripts/bundle_app.sh

# Output: dist/Awake.app
open dist/Awake.app
```

To build without ad-hoc signing:

```bash
ADHOC_SIGN=0 ./scripts/bundle_app.sh
```

## GitHub Actions

- `CI` runs on every push to `main`, on pull requests, and on manual dispatch. It validates `swift build` and the app bundling flow on `macos-15`.
- `Release` is manual for now. Trigger it from the Actions tab with a version like `1.0.0`; it builds `dist/Awake.app` and `dist/Awake.zip`, creates `v1.0.0` if needed, publishes `Awake.zip` to GitHub Releases, computes the SHA-256 checksum, and can push an updated Homebrew cask into a tap repo.
- There are no Swift tests in the package yet, so the current CI signal is a build-and-bundle smoke test.

## Homebrew Tap

The project repo now carries the authoritative cask template at `packaging/homebrew/Casks/awake.rb.template`. Release automation renders that template against the exact `Awake.zip` uploaded to GitHub Releases, then commits the updated cask into a dedicated tap repository.

Recommended setup:

1. Create a tap repo such as `happycodelucky/homebrew-tap`.
2. Add a repository secret named `HOMEBREW_TAP_GITHUB_TOKEN` in this repo with write access to the tap repo.
3. Optionally add repository variables if you want non-default values:
   - `HOMEBREW_TAP_REPOSITORY` defaults to `happycodelucky/homebrew-tap`
   - `HOMEBREW_TAP_BRANCH` defaults to `main`
   - `HOMEBREW_TAP_CASK_PATH` defaults to `Casks/awake.rb`
4. On each release workflow run, the cask publisher will render and push the updated cask automatically after the GitHub release succeeds.

Local rendering example:

```bash
SHA256="$(shasum -a 256 dist/Awake.zip | awk '{print $1}')"
./scripts/render_homebrew_cask.sh --version 1.0.0 --sha256 "$SHA256"
```

## Usage

1. Click the **Awake** icon in your menu bar (a mug icon)
2. Pick a duration preset
3. Optionally toggle **Allow Display Sleep** if you only need the system to stay awake
4. A countdown appears in the menu bar — your Mac won't sleep until it hits zero
5. Hold **Option** while clicking the icon to pause instead of stop a running session

If your Mac is managed by an MDM or enterprise profile, Awake will show a warning card describing which policies may still interrupt your session.

## Roadmap

- [ ] **IPC / MCP control** — allow AI agents and external tools to start, stop, and query Awake sessions programmatically
- [ ] Swift tests for timer logic and policy parsing
- [ ] Automatic release promotion from tags once the release process settles

## License

[PolyForm Noncommercial License 1.0.0](LICENSE)

Free to use, modify, and share for non-commercial purposes. Commercial use is not permitted.
