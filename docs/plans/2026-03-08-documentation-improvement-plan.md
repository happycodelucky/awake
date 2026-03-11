# Documentation & Comment Improvement Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Improve project documentation across three levels — developer/agent docs (`docs/`), end-user guides (`guide/`), and inline code comments — while polishing README.md and updating AGENTS.md with maintenance rules.

**Architecture:** No code changes. Documentation-only pass spanning markdown files, AGENTS.md rules, and Swift inline comments. README.md is restructured to link into both `docs/` and `guide/` folders.

**Tech Stack:** Markdown, SwiftDoc comments

---

### Task 1: Create `docs/architecture.md`

**Files:**
- Create: `docs/architecture.md`

**Step 1: Write the architecture doc**

```markdown
# Architecture

Awake is a native macOS menu bar utility built with Swift and SwiftUI. It uses
IOKit power assertions to prevent idle sleep and reads managed device policies
from `/Library/Managed Preferences` to warn users about enterprise
restrictions.

## Package Structure

The Swift package (`Package.swift`) defines two targets:

| Target | Type | Path | Purpose |
|--------|------|------|---------|
| `AwakeUI` | Library | `Sources/AwakeUI/` | Core business logic, UI components, and Sparkle integration |
| `AwakeMenuBar` | Executable | `Sources/AwakeMenuBarApp/` | App entry point — hosts the controller and menu bar scene |

The library/executable split allows the UI and logic to be tested or reused
independently from the app lifecycle.

### Dependencies

- **Sparkle 2.8.0+** — automatic update framework (conditionally enabled when
  `SUFeedURL` and `SUPublicEDKey` are present in the bundle's Info.plist)

### System Frameworks

- **IOKit** — power assertion creation and release
- **AppKit** — menu bar integration, event monitoring
- **SwiftUI** — all UI rendering via `MenuBarExtra`
- **Foundation** — property list parsing, user defaults, file I/O

## Source Files

| File | Role |
|------|------|
| `AwakeSessionManager.swift` | Timer lifecycle, IOKit power assertions, managed policy loading, UserDefaults persistence |
| `MenuContentView.swift` | Menu bar popover layout — presets grid, behavior toggle, policy warnings, update notices |
| `AppUpdater.swift` | Wraps Sparkle's `SPUUpdater` and `SPUUserDriver` into observable `UpdateNotice` state |
| `Components.swift` | Reusable views — `TimerHeroView`, `CircleActionIcon`, `PolicyWarningCard`, `UpdateNoticeCard` |
| `Styles.swift` | Custom `ButtonStyle` implementations for presets, footer, and update card actions |
| `RacetrackRingShape.swift` | Custom `InsettableShape` that draws the rounded racetrack used by the timer ring |
| `AwakeMenuBarApp.swift` | `@main` entry point — creates `AwakeSessionManager` and `AppUpdater`, hosts `MenuBarExtra` scene |

## Data Flow

```
User taps preset → AwakeSessionManager.start(minutes:)
  → sets endDate, sessionDuration
  → saveState() persists to UserDefaults
  → syncPowerAssertion() acquires IOKit assertion
  → clockTimer fires every 1s:
      → updates `now`
      → checks if endDate has passed → stop()
      → refreshes managed policy state (throttled to 60s)
  → UI observes @Published properties via @ObservedObject
```

## State Persistence

Timer state survives app restarts via four UserDefaults keys:

| Key | Value |
|-----|-------|
| `awake.endDate` | Unix timestamp of session end |
| `awake.duration` | Original session duration in seconds |
| `awake.pausedRemaining` | Remaining seconds when paused |
| `awake.sleepBehavior` | `keepDisplayAwake` or `allowDisplaySleep` |

On launch, `restoreSavedState()` checks whether the persisted end date is still
in the future. If so, the session resumes. If it has expired, the keys are
cleared.

## Power Assertions

Awake uses two IOKit assertion types depending on the selected sleep behavior:

| Behavior | IOKit Type | Effect |
|----------|-----------|--------|
| Keep display awake | `kIOPMAssertionTypePreventUserIdleDisplaySleep` | Prevents both display and system idle sleep |
| Allow display sleep | `kIOPMAssertionTypeNoIdleSleep` | Prevents system idle sleep only |

Assertions are acquired when a session starts and released when it stops,
pauses, or the controller is deallocated.

## Managed Policy Detection

Enterprise/MDM policies are read from `/Library/Managed Preferences/`. The
loader merges system-level plists with user-specific plists (the user-specific
value wins on conflict). Detected policy domains:

| Domain | Keys Inspected |
|--------|---------------|
| `com.apple.screensaver` | `idleTime`, `loginWindowIdleTime`, `askForPassword`, `askForPasswordDelay` |
| `com.apple.loginwindow` | `autoLogoutDelay`, `com.apple.login.mcx.DisableAutoLoginClient` |

Policy state is refreshed on a 60-second throttle to avoid excessive disk I/O.
```

**Step 2: Commit**

```bash
git add docs/architecture.md
git commit -m "Docs: add architecture reference for agents and developers"
```

---

### Task 2: Create `docs/build.md`

**Files:**
- Create: `docs/build.md`

**Step 1: Write the build system doc**

Document `bundle_app.sh` internals, all environment variables, signing modes,
icon generation, CI/CD workflows, and the output artifact structure. Reference
exact env var names from the script: `APP_NAME`, `BUNDLE_ID`, `VERSION`,
`BUILD_NUMBER`, `DEPLOYMENT_TARGET`, `ARCHS`, `ADHOC_SIGN`, `SIGN_IDENTITY`,
`SPARKLE_FEED_URL`, `SPARKLE_PUBLIC_ED_KEY`, `SPARKLE_CHECK_INTERVAL`.

Document the CI workflow (`ci.yml`) — triggers, what it validates, artifact
upload. Document the Release workflow (`release.yml`) — manual trigger with
version input, tag creation, GitHub release, Homebrew cask publishing.

Document the icon generation pipeline: `generate_app_icon.swift` is compiled
during `bundle_app.sh`, generates a 1024×1024 icon with gradient background and
racetrack ring, outputs to `Resources/AppIcon.icns`.

**Step 2: Commit**

```bash
git add docs/build.md
git commit -m "Docs: add build system reference"
```

---

### Task 3: Create `docs/homebrew.md`

**Files:**
- Create: `docs/homebrew.md`

**Step 1: Write the Homebrew doc**

Document the cask template at `packaging/homebrew/Casks/awake.rb.template`,
the placeholder tokens (`__VERSION__`, `__SHA256__`, `__URL__`, `__VERIFIED__`,
`__HOMEPAGE__`), the render script (`render_homebrew_cask.sh`), and the publish
script (`publish_homebrew_cask.sh`).

Document tap repository setup: repo naming convention, required secrets
(`HOMEBREW_TAP_GITHUB_TOKEN`), optional variables (`HOMEBREW_TAP_REPOSITORY`,
`HOMEBREW_TAP_BRANCH`, `HOMEBREW_TAP_CASK_PATH`).

Include the local rendering example from the current README.

**Step 2: Commit**

```bash
git add docs/homebrew.md
git commit -m "Docs: add Homebrew tap and cask reference"
```

---

### Task 4: Create `docs/sparkle.md`

**Files:**
- Create: `docs/sparkle.md`

**Step 1: Write the Sparkle integration doc**

Document how Sparkle is conditionally enabled (requires both `SUFeedURL` and
`SUPublicEDKey` in Info.plist). Document the `AppUpdater` class roles: it
implements both `SPUUpdaterDelegate` and `SPUUserDriver`, translating Sparkle
callbacks into an `@Published UpdateNotice` that the menu UI observes.

Document the update lifecycle phases: `available` → `downloading` →
`preparing` → `readyToInstall` → `installing`. Document how to configure
Sparkle via `bundle_app.sh` env vars.

**Step 2: Commit**

```bash
git add docs/sparkle.md
git commit -m "Docs: add Sparkle update integration reference"
```

---

### Task 5: Create `docs/mdm-policies.md`

**Files:**
- Create: `docs/mdm-policies.md`

**Step 1: Write the MDM policies technical doc**

Document the policy detection internals: which plist files are read, how
system and user plists are merged, type extraction helpers (`timeInterval`,
`bool`), the 60-second throttle, and the `list_managed_policies.swift`
diagnostic script (usage, flags: `--verbose`, `--user-only`).

This is the developer/agent counterpart to the user-facing
`guide/mdm-awareness.md`.

**Step 2: Commit**

```bash
git add docs/mdm-policies.md
git commit -m "Docs: add MDM policy detection technical reference"
```

---

### Task 6: Create `guide/getting-started.md`

**Files:**
- Create: `guide/getting-started.md`

**Step 1: Write the getting started guide**

Cover three installation methods: direct download from GitHub Releases,
Homebrew install (`brew tap` + `brew install --cask`), and building from
source. Include first-launch experience — the mug icon appears in the menu bar,
click to open, pick a preset. Mention that macOS may ask to confirm opening
an app from an unidentified developer (ad-hoc signed).

Keep it brief and user-friendly. No developer jargon.

**Step 2: Commit**

```bash
git add guide/getting-started.md
git commit -m "Docs: add getting started user guide"
```

---

### Task 7: Create `guide/features.md`

**Files:**
- Create: `guide/features.md`

**Step 1: Write the features guide**

Document each user-facing feature with brief explanations:
- Timer presets (5m through 12h) — what the countdown means
- Pause & resume — hold Option while clicking the action button
- Two sleep modes — when to use each (background work vs. presentations)
- Persistent sessions — timer survives app restarts
- Menu bar countdown — what the pill shows, format changes at thresholds
- Auto-updates — how Sparkle update notices appear in the menu

**Step 2: Commit**

```bash
git add guide/features.md
git commit -m "Docs: add features user guide"
```

---

### Task 8: Create `guide/mdm-awareness.md`

**Files:**
- Create: `guide/mdm-awareness.md`

**Step 1: Write the MDM awareness user guide**

Explain in plain language what the orange warning card means, what managed
policies are (enterprise/MDM profiles), which policies Awake detects
(screensaver idle, auto-logout, password-after-screensaver), what the "Known"
and "Likely" sections mean, and what users can and can't do about them
(Awake prevents idle sleep but cannot bypass managed lock/logout policies).

**Step 2: Commit**

```bash
git add guide/mdm-awareness.md
git commit -m "Docs: add MDM awareness user guide"
```

---

### Task 9: Improve README.md

**Files:**
- Modify: `README.md`

**Step 1: Rewrite README.md**

Key changes:
- Merge the redundant "About" and "Overview" sections into a single clear intro
- Keep the feature list but add brief rationale for each
- Add a "Documentation" section linking to `guide/` and `docs/`
- Slim down the Homebrew section — keep install commands, move tap setup details
  to `docs/homebrew.md`
- Slim down the GitHub Actions section — move details to `docs/build.md`
- Keep Usage, Roadmap, License sections (light polish)
- Keep all existing badges

**Step 2: Commit**

```bash
git add README.md
git commit -m "Docs: improve README structure and add documentation links"
```

---

### Task 10: Update AGENTS.md with documentation maintenance rules

**Files:**
- Modify: `AGENTS.md`

**Step 1: Add documentation maintenance section**

Append after the "Required Documentation" section:

```markdown
## Documentation Maintenance

- When adding new features or changing user-facing behavior, update the relevant
  guide in `guide/`.
- When changing architecture, build system, integrations, or internal design,
  update the relevant doc in `docs/`.
- When creating new integrations or subsystems, add a new doc in `docs/`.
- Design plans and brainstorming artifacts go in `docs/plans/`.
- Keep `guide/` written for end users — no developer jargon, no code.
- Keep `docs/` written for agents and developers — include file paths, type
  names, and implementation details.
```

**Step 2: Commit**

```bash
git add AGENTS.md
git commit -m "Docs: add documentation maintenance rules to AGENTS.md"
```

---

### Task 11: Add file-level headers and `AGENT:` comments to source files

**Files:**
- Modify: `Sources/AwakeUI/AwakeSessionManager.swift:1-6`
- Modify: `Sources/AwakeUI/MenuContentView.swift:1-3`
- Modify: `Sources/AwakeUI/AppUpdater.swift:1-2`
- Modify: `Sources/AwakeUI/Components.swift:1`
- Modify: `Sources/AwakeUI/Styles.swift:1`
- Modify: `Sources/AwakeUI/RacetrackRingShape.swift:1`
- Modify: `Sources/AwakeMenuBarApp/AwakeMenuBarApp.swift:1-3`

**Step 1: Add file-level documentation headers**

Add a file-level `///` comment block at the top of each source file describing
its role in the architecture. Example for `AwakeSessionManager.swift`:

```swift
// MARK: - AwakeSessionManager
// Core timer lifecycle, IOKit power assertions, and managed policy detection.
// This is the central state object observed by all UI views.
```

**Step 2: Add `AGENT:` comments for design rationale**

Key locations to add `AGENT:` markers:

- `AwakeSessionManager.swift:153` — `nonisolated(unsafe)` on `clockTimer`:
  ```swift
  // AGENT: clockTimer is nonisolated(unsafe) because Timer.scheduledTimer
  // requires a non-isolated context, but the callback dispatches back to
  // @MainActor via Task. The timer is only mutated in init/deinit.
  ```

- `AwakeSessionManager.swift:155` — `lastPolicyRefresh` throttle:
  ```swift
  // AGENT: Policy refresh is throttled to 60s because reading plist files
  // from /Library/Managed Preferences on every clock tick (1s) would cause
  // unnecessary disk I/O. 60s balances freshness with performance.
  ```

- `AwakeSessionManager.swift:156-160` — UserDefaults key naming:
  ```swift
  // AGENT: UserDefaults keys use the "awake." prefix to namespace them within
  // the app's defaults domain and avoid collisions with system or framework keys.
  ```

- `MenuContentView.swift:9` — `nonisolated(unsafe)` on event monitor:
  ```swift
  // AGENT: localMonitor is nonisolated(unsafe) because NSEvent.addLocalMonitorForEvents
  // returns an opaque token that AppKit manages. The monitor is added in init and
  // removed in deinit — no concurrent mutation occurs.
  ```

- `AppUpdater.swift:85-110` — conditional Sparkle startup:
  ```swift
  // AGENT: Sparkle is only started when both SUFeedURL and SUPublicEDKey are
  // present in Info.plist. This lets development builds skip update checks
  // without needing a separate build configuration or feature flag.
  ```

- `AwakeMenuBarApp.swift:13` — accessory activation policy:
  ```swift
  // AGENT: setActivationPolicy(.accessory) hides the app from the Dock and
  // Cmd-Tab switcher. This is standard for menu bar-only utilities. The
  // Info.plist also sets LSUIElement=true as a fallback.
  ```

**Step 3: Commit**

```bash
git add Sources/
git commit -m "Docs: add file headers and AGENT rationale comments to source files"
```

---

### Task 12: Improve mechanical comments in source files

**Files:**
- Modify: `Sources/AwakeUI/AwakeSessionManager.swift`
- Modify: `Sources/AwakeUI/MenuContentView.swift`
- Modify: `Sources/AwakeUI/Components.swift`
- Modify: `Sources/AwakeUI/Styles.swift`

**Step 1: Improve comment quality**

Scan for comments that merely restate the code and replace them with
behavior/constraint explanations. Examples:

- `AwakeSessionManager.swift` — `startClock()` comment "Starts the one-second timer"
  → "Starts the one-second timer that advances session state, checks for
  expiration, and throttles policy refreshes. The timer is added to `.common`
  run loop mode so it fires during modal tracking."

- `Components.swift` — `PolicyWarningCard` body comment "Builds the policy
  warning card UI" → "Builds the expandable policy warning card. The card
  starts collapsed showing only the title and disclaimer. Tapping 'More'
  reveals Known (confirmed active) and Likely (conditional) policy details."

- `Styles.swift` — all four button styles have identical comment patterns
  ("Builds the styled X button body"). Add what makes each style distinct
  (e.g., PresetButtonStyle uses `.regularMaterial` fill with a subtle
  press-state scale animation).

**Step 2: Commit**

```bash
git add Sources/
git commit -m "Docs: improve inline comments with behavior and constraint explanations"
```

---

### Task 13: Final build verification

**Step 1: Verify the build still passes**

```bash
pkill -x Awake || true
swift build 2>&1
```

Expected: Build succeeds with no errors.

**Step 2: Verify no broken links in docs**

Manually scan README.md, `docs/`, and `guide/` for any cross-references and
confirm the target files exist.
