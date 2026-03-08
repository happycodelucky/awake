# Awake

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue.svg?style=for-the-badge&logo=apple)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-black.svg?style=for-the-badge&logo=apple)
[![CI](https://img.shields.io/github/actions/workflow/status/happycodelucky/awake/ci.yml?style=for-the-badge&label=ci)](https://github.com/happycodelucky/awake/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/happycodelucky/awake?style=for-the-badge)](https://github.com/happycodelucky/awake/releases/latest)
[![License: PolyForm NC](https://img.shields.io/badge/license-PolyForm%20NC%201.0-orange.svg?style=for-the-badge)](LICENSE)
[![Maintained](https://img.shields.io/badge/Maintained%3F-yes-green.svg?style=for-the-badge)](https://github.com/happycodelucky/awake/graphs/commit-activity)

> **AI Experiment:** This app was almost entirely written by AI (Codex & Claude Code), with only minor human edits. It's an experiment in AI-assisted software development — the design, architecture, and code are AI-generated. Use it, learn from it, fork it.

**Keeps your Mac awake** — beyond what `caffeinate` can do.

Awake is a macOS menu bar utility that prevents your Mac from sleeping for a set duration. Unlike `caffeinate`, it's MDM-aware: it reads your managed profiles and warns you when enterprise policies — auto-logout, screensaver timeouts, login window idle settings — may still interrupt your session. Built for long-running local work like AI agents, builds, downloads, and unattended tasks.

![Awake screenshot](assets/screenshot.png)
<!-- TODO: Replace with actual screenshot or GIF -->

## Features

- **Timer presets** — 5m, 10m, 15m, 30m, 1h, 2h, 4h, 8h, 12h — pick one and go
- **Pause & resume** — hold Option to pause instead of stop, preserving remaining time
- **Two sleep modes** — keep the display on for presentations, or let it sleep while the system stays awake for background work
- **MDM policy detection** — warns you when enterprise policies like auto-logout or screensaver timeouts may interrupt your session
- **Persistent sessions** — timer survives app restarts and picks up where it left off
- **Auto-updates** — checks for new versions via Sparkle and shows update prompts in the menu
- **Menu bar native** — lives in your menu bar with a live countdown, stays out of your way

## Install

[Download the latest release →](https://github.com/happycodelucky/awake/releases/latest)

Or install via Homebrew:

```bash
brew tap happycodelucky/tap
brew install --cask awake
```

## Build from Source

Requires Xcode (not just Command Line Tools), Apple Silicon Mac, macOS 15.0+.

```bash
./scripts/bundle_app.sh
open dist/Awake.app
```

See [docs/build.md](docs/build.md) for environment variables, signing options, and CI/CD details.

## Usage

1. Click the **Awake** mug icon in your menu bar
2. Pick a duration preset
3. A countdown pill appears in the menu bar — your Mac won't sleep until it hits zero
4. Toggle **Keep display awake** off if you only need background protection
5. Hold **Option** while clicking stop to pause instead

If your Mac is managed by an enterprise profile, Awake shows a warning card describing which policies may still interrupt your session. See the [MDM awareness guide](guide/mdm-awareness.md) for details.

## Documentation

| Audience | Location | Contents |
|----------|----------|----------|
| Users | [`guide/`](guide/) | [Getting started](guide/getting-started.md), [Features](guide/features.md), [MDM awareness](guide/mdm-awareness.md) |
| Developers & agents | [`docs/`](docs/) | [Architecture](docs/architecture.md), [Build system](docs/build.md), [Homebrew](docs/homebrew.md), [Sparkle](docs/sparkle.md), [MDM policies](docs/mdm-policies.md) |

## Roadmap

- [ ] **IPC / MCP control** — allow AI agents and external tools to start, stop, and query Awake sessions programmatically
- [ ] Swift tests for timer logic and policy parsing
- [ ] Automatic release promotion from tags once the release process settles

## License

[PolyForm Noncommercial License 1.0.0](LICENSE)

Free to use, modify, and share for non-commercial purposes. Commercial use is not permitted.
