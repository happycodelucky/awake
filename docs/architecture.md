# Awake Architecture Reference

Technical reference for agents and developers working on the Awake codebase.

---

## Overview

Awake is a macOS menu bar utility that prevents the system from sleeping for a user-selected duration. It is written in Swift using SwiftUI for its interface and IOKit power assertions to physically block idle sleep at the OS level. The app runs as a process with activation policy `.accessory`, meaning it has no Dock icon and lives entirely in the menu bar.

Key characteristics:

- **Menu bar only.** The entire UI is a `MenuBarExtra` window popover — no regular app windows.
- **Timer-driven.** A one-second repeating `Timer` ticks on the main run loop, advancing `@Published` state that SwiftUI observes directly.
- **IOKit power assertions.** Two assertion types cover two distinct sleep behaviors: one that also blocks display sleep and one that allows it.
- **Managed policy awareness.** At launch and on a 60-second throttle thereafter, the controller reads `/Library/Managed Preferences` plists to detect MDM-enforced screensaver, lock, and auto-logout policies that Awake cannot override. When relevant policies are found, a warning card surfaces in the UI.
- **State persistence.** Session state (end date, duration, paused remaining) and behavior preference (sleep behavior) survive across relaunches via `UserDefaults`.
- **Sparkle updates.** Update checking is conditional — Sparkle only activates when the app bundle contains both `SUFeedURL` and `SUPublicEDKey` Info.plist keys.

Minimum deployment target: **macOS 15.0**. Default build target: **Apple Silicon (arm64)**.

---

## Package Structure

The Swift package (`Package.swift`) is split into a library and an executable. The split keeps all UI and business logic in a testable, preview-friendly target that has no dependency on the app entry point.

| Product / Target | Path | Role |
|---|---|---|
| `AwakeUI` (library) | `Sources/AwakeUI/` | All business logic, IOKit integration, SwiftUI views, Sparkle wrapper, and reusable components. This target can be imported by tests or tooling without an `@main` entry point. |
| `AwakeMenuBar` (executable) | `Sources/AwakeMenuBarApp/` | Thin `@main` entry point. Creates `AwakeController` and `AppUpdater` as `@StateObject`s, declares the `MenuBarExtra` scene, and configures the activation policy. |

The executable target declares `AwakeUI` as its only dependency:

```
AwakeMenuBar → AwakeUI → Sparkle (conditional)
```

Sparkle is a dependency of `AwakeUI`, not the executable. This means the library controls all update integration.

---

## Dependencies

| Dependency | Version | How it is used |
|---|---|---|
| [Sparkle](https://github.com/sparkle-project/Sparkle) | `>= 2.8.0` (resolved: 2.9.0) | Automatic update checking and installation. `AppUpdater` wraps `SPUUpdater` and `SPUUserDriver`. Active only when `SUFeedURL` and `SUPublicEDKey` are present in the app bundle's Info.plist; the wrapper silently disables itself otherwise. |
| IOKit (`IOKit.pwr_mgt`) | System | `IOPMAssertionCreateWithName` / `IOPMAssertionRelease` for power assertions. Imported in `AwakeController.swift`. |
| AppKit | System | `NSApplication`, `NSEvent` (modifier key monitoring in `MenuContentView`), and `NSUserName()` (managed policy user path). |
| SwiftUI | System | All views and the `MenuBarExtra` scene. |
| Foundation | System | `Timer`, `UserDefaults`, `PropertyListSerialization`, `URL`, `Date`, `TimeInterval`. |

---

## Source Files

### `Sources/AwakeUI/`

| File | Primary types | Role |
|---|---|---|
| `AwakeController.swift` | `AwakeController`, `ManagedPolicyState`, `BehaviorPolicyNotice`, `SleepBehavior` | Central `@MainActor ObservableObject`. Owns the one-second clock timer, IOKit power assertions, session lifecycle (`start`, `pause`, `resume`, `stop`), `UserDefaults` persistence (`saveState` / `restoreSavedState`), and managed policy loading. All `@Published` properties drive the SwiftUI layer. |
| `MenuContentView.swift` | `MenuContentView`, `ModifierKeyObserver` | Root SwiftUI view rendered inside the `MenuBarExtra` window. Composes the header badge, `TimerHeroView`, `UpdateNoticeCard`, preset grid, behavior toggle, `PolicyWarningCard`, and quit button. `ModifierKeyObserver` tracks the Option key so the action button toggles between its primary and alternate action in both active and paused states. |
| `AppUpdater.swift` | `AppUpdater`, `UpdateNotice`, `UpdateNotice.Kind` | `@MainActor ObservableObject` that wraps `SPUUpdater` (the Sparkle engine) and implements both `SPUUpdaterDelegate` and `SPUUserDriver`. Translates Sparkle lifecycle callbacks into a single `@Published var notice: UpdateNotice?` value consumed by `MenuContentView`. |
| `Components.swift` | `TimerHeroView`, `CircleActionIcon`, `PolicyWarningCard`, `UpdateNoticeCard` | Self-contained SwiftUI view components. `TimerHeroView` renders the racetrack ring progress, large countdown text, and context-sensitive action button with animated state transitions (ring progress, text crossfades, digit rolling, button scale/opacity). `CircleActionIcon` animates SF Symbol morphs via `.symbolEffect(.replace)` and fill-color transitions when the Option key toggles the action. `PolicyWarningCard` shows expandable MDM policy warnings. `UpdateNoticeCard` shows update state and action buttons. |
| `Styles.swift` | `PresetButtonStyle`, `FooterButtonStyle`, `UpdateCardPrimaryButtonStyle`, `UpdateCardSecondaryButtonStyle` | `ButtonStyle` implementations that apply consistent rounded-rectangle material backgrounds, pressed-state scale effects, and typography to the four distinct button roles in the UI. |
| `RacetrackRingShape.swift` | `RacetrackRingShape` | `InsettableShape` that draws a stadium/racetrack outline (two semicircles connected by straight lines). Used by `TimerHeroView` for both the track layer and the `.trim`-animated progress layer. |

### `Sources/AwakeMenuBarApp/`

| File | Primary types | Role |
|---|---|---|
| `AwakeMenuBarApp.swift` | `AwakeMenuBarApp` | `@main` App entry point. Sets activation policy to `.accessory` (no Dock icon), owns `AwakeController` and `AppUpdater` as `@StateObject`s, and declares the `MenuBarExtra` scene. The label closure renders the mug icon and optional countdown pill in the menu bar. |

---

## Data Flow

The following describes the path from a user preset tap to the UI reflecting the new timer state:

```
User taps preset button (MenuContentView)
  → controller.start(minutes:)
      sets now, sessionDuration, endDate (= now + duration), clears pausedRemaining
      → saveState()          persists endDate/duration to UserDefaults
      → syncPowerAssertion() calls acquirePowerAssertionIfNeeded()
          → IOPMAssertionCreateWithName(sleepBehavior.assertionType, ...)
              sets powerAssertionIsActive = true

clockTimer fires every 1 second (on RunLoop.main in .common mode)
  → now = Date()
  → refreshManagedPolicyState()   (throttled to once per 60 s)
  → if endDate <= now: stop()
      → saveState(), syncPowerAssertion() → IOPMAssertionRelease(...)

SwiftUI observes @Published properties on AwakeController:
  now, endDate, sessionDuration, pausedRemaining,
  powerAssertionIsActive, sleepBehavior, managedPolicyState
  → MenuContentView body re-evaluates
  → TimerHeroView receives updated progress and timeText
  → AwakeMenuBarApp label receives menuBarClockText and powerAssertionIsActive
```

`AwakeController` is `@MainActor`. All mutations happen on the main actor. The `clockTimer` callback dispatches back to `MainActor` via `Task { @MainActor in ... }` because `Timer` callbacks run on whatever thread schedules them.

---

## State Persistence

Session and behavior state are persisted to `UserDefaults.standard` using four keys. On relaunch, `restoreSavedState()` is called from `init()` before the clock starts.

| Key | Type stored | Meaning |
|---|---|---|
| `awake.endDate` | `Double` (Unix timestamp via `timeIntervalSince1970`) | When the active session expires. Cleared when the session stops or is paused. If the restored end date is in the past, all three session keys are cleared and the session is treated as expired. |
| `awake.duration` | `Double` (seconds) | The full length of the session originally started. Used to compute ring progress. Cleared when the session stops. |
| `awake.pausedRemaining` | `Double` (seconds) | The remaining time at the moment the user paused. Non-zero value takes precedence over `awake.endDate` during restore — the controller enters paused state rather than active state. |
| `awake.sleepBehavior` | `String` (raw value of `SleepBehavior`) | Either `"keepDisplayAwake"` or `"allowDisplaySleep"`. Persisted on every behavior change. Restored unconditionally at launch. |

Restore logic priority:

1. If `awake.pausedRemaining > 0`: restore as paused (no `endDate`, `pausedRemaining` is set).
2. Else if `awake.endDate > 0` and the decoded date is in the future: restore as active.
3. Else if the decoded date is in the past: clear all three session keys; idle state.

---

## Power Assertions

Awake holds at most one IOKit power assertion at a time. The assertion type is determined by `SleepBehavior`, which is user-configurable from the behavior toggle in the popover.

| `SleepBehavior` case | IOKit assertion type constant | Effect |
|---|---|---|
| `keepDisplayAwake` | `kIOPMAssertionTypePreventUserIdleDisplaySleep` | Prevents both display sleep and system idle sleep. The display stays on for the duration. |
| `allowDisplaySleep` | `kIOPMAssertionTypeNoIdleSleep` | Prevents system idle sleep but allows the display to turn off. Suitable for long background jobs where the screen does not need to stay on. |

Assertion lifecycle:

- **Acquired** in `acquirePowerAssertionIfNeeded()` via `IOPMAssertionCreateWithName`. Called by `syncPowerAssertion()` whenever `isActive` transitions to `true` (start, resume) or when the behavior type changes while a session is active.
- **Released** in `releasePowerAssertion()` via `IOPMAssertionRelease`. Called by `syncPowerAssertion()` whenever `isActive` is `false` (stop, pause, natural expiry) or when swapping assertion types.
- **On error:** `IOPMAssertionCreateWithName` returning anything other than `kIOReturnSuccess` sets `powerAssertionIsActive = false` and populates `assertionErrorMessage`, which the UI surfaces in the status line.
- **On dealloc:** `deinit` releases any held assertion to avoid kernel-level leaks.

---

## Managed Policy Detection

`ManagedPolicyState.load(forUser:)` reads two Apple MDM plist domains from `/Library/Managed Preferences`. Each domain is read twice — once at the system level and once at the per-user level — then merged with user values winning over system values (`uniquingKeysWith: { _, userValue in userValue }`).

**Plist paths read:**

| Domain | System path | Per-user path |
|---|---|---|
| Screen saver | `/Library/Managed Preferences/com.apple.screensaver.plist` | `/Library/Managed Preferences/<username>/com.apple.screensaver.plist` |
| Login window | `/Library/Managed Preferences/com.apple.loginwindow.plist` | `/Library/Managed Preferences/<username>/com.apple.loginwindow.plist` |

**Keys detected and their meaning:**

| Key | Domain | `ManagedPolicyState` field | Relevance |
|---|---|---|---|
| `idleTime` | `com.apple.screensaver` | `screenSaverIdleTime` | Seconds of inactivity before the managed screensaver starts. Triggers a warning if non-nil. |
| `loginWindowIdleTime` | `com.apple.screensaver` | `loginWindowIdleTime` | Seconds before the screensaver runs on the login window screen. |
| `askForPassword` | `com.apple.screensaver` | `asksForPasswordAfterScreenSaver` | If true, a password is required after the screensaver or sleep. Triggers a warning. |
| `askForPasswordDelay` | `com.apple.screensaver` | `askForPasswordDelay` | Seconds before the password prompt appears after screensaver. |
| `autoLogoutDelay` | `com.apple.loginwindow` | `autoLogoutDelay` | Seconds of inactivity before the user is auto-logged out. Triggers a warning if non-nil. |
| `com.apple.login.mcx.DisableAutoLoginClient` | `com.apple.loginwindow` | `disablesAutoLogin` | Indicates whether automatic login is disabled by policy. |

`ManagedPolicyState.hasRelevantWarnings` is `true` when any of `screenSaverIdleTime`, `asksForPasswordAfterScreenSaver`, or `autoLogoutDelay` is set. Only when this is `true` does `AwakeController.behaviorPolicyNotice` return a non-nil `BehaviorPolicyNotice`, which `MenuContentView` uses to show `PolicyWarningCard`.

Policy state is loaded once at launch (forced) and then refreshed on a 60-second throttle inside the `clockTimer` callback.
