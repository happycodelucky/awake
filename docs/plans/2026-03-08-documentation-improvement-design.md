# Documentation & Comment Improvement Design

**Date:** 2026-03-08
**Status:** Approved

## Goal

Improve project documentation at three levels: external user-facing guides (`guide/`), internal agent/developer reference docs (`docs/`), and inline code comments. Improve the README.md as a polished entry point linking to both.

## New Directory Structure

```
guide/                          # End-user documentation
  getting-started.md            # Installation, first launch, menu bar basics
  features.md                   # Timer presets, pause/resume, sleep modes, persistence
  mdm-awareness.md              # What MDM warnings mean, detected policies, limitations

docs/                           # Agent & developer documentation
  architecture.md               # Package structure, key types, data flow, state model
  homebrew.md                   # Cask template, tap repo setup, local rendering, release flow
  sparkle.md                    # Sparkle integration, configuration, update lifecycle
  build.md                      # bundle_app.sh internals, env vars, signing, CI/CD, icons
  mdm-policies.md               # Policy detection internals, plist reading, merge logic
  plans/                        # Design docs and brainstorming artifacts
```

## README.md Changes

- Merge redundant "About" and "Overview" sections
- Improve feature descriptions with brief rationale
- Add links to `guide/` and `docs/` where appropriate
- Move detailed Homebrew tap setup to `docs/homebrew.md`, keep README concise
- Make "Usage" section more scannable

## AGENTS.md Changes

Add documentation maintenance rules requiring updates to `guide/` for user-facing changes and `docs/` for architecture/integration changes.

## Code Comment Improvements

- Add `AGENT:` markers for design rationale throughout source files
- Replace mechanical comments with behavior/constraint explanations
- Add file-level documentation headers to each source file
- Ensure consistent SwiftDoc parameter/return documentation
