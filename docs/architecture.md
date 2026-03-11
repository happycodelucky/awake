# Awake Architecture Reference

Technical reference for agents and developers working on the Awake codebase.

---

## Overview

Awake is a macOS menu bar utility that prevents the system from sleeping for a user-selected duration. It is written in Swift using SwiftUI for its interface and IOKit power assertions to physically block idle sleep at the OS level. The app runs as a process with activation policy `.accessory`, meaning it has no Dock icon and lives entirely in the menu bar.

Key characteristics:

- **Menu bar only.** The entire UI is an `NSPopover` attached to an `NSStatusItem` — no regular app windows. The popover hosts a SwiftUI `MenuContentView` via `NSHostingController`.
- **Timer-driven.** A one-second repeating `Timer` ticks on the main run loop, advancing `@Published` state that SwiftUI observes directly.
- **IOKit power assertions.** Two assertion types cover two distinct sleep behaviors: one that also blocks display sleep and one that allows it.
- **Managed policy awareness.** At launch and on a 60-second throttle thereafter, the controller reads `/Library/Managed Preferences` plists to detect MDM-enforced screensaver, lock, and auto-logout policies that Awake cannot override. When relevant policies are found, a warning card surfaces in the UI.
- **State persistence.** Session state (end date, duration, paused remaining), behavior preference (sleep behavior), and appearance mode survive across relaunches via `UserDefaults`.
- **Login item registration.** Optional start-at-login via `SMAppService.mainApp` (ServiceManagement framework). The toggle reads the actual system state rather than storing a boolean.
- **Sparkle updates.** Update checking is conditional — Sparkle only activates when the app bundle contains both `SUFeedURL` and `SUPublicEDKey` Info.plist keys.

Minimum deployment target: **macOS 15.0**. Default build target: **Apple Silicon (arm64)**.

---

## Project Structure

The Xcode project (`Awake.xcodeproj`) is generated from `project.yml` via XcodeGen. It contains a single App target:

| Target | Path | Role |
|---|---|---|
| `Awake` (App) | `Sources/Awake/` | Single target containing all business logic, IOKit integration, SwiftUI views, Sparkle wrapper, reusable components, and the `@main` entry point. SwiftUI Previews are enabled via the native Xcode App target preview host. |

The target dependency chain:

```
Awake → Sparkle (SPM remote package, conditional at runtime)
```

`Package.swift` is retained as a vestigial reference but is not used by the active build system. The active build is driven by `Awake.xcodeproj` via `xcodebuild`.

All source files are in `Sources/Awake/`. There are no cross-module `public` access modifiers — all types use the default internal access level within the single module.

---

## Dependencies

| Dependency | Version | How it is used |
|---|---|---|
| [Sparkle](https://github.com/sparkle-project/Sparkle) | `>= 2.8.0` (resolved: 2.9.0) | Automatic update checking and installation. `AppUpdater` wraps `SPUUpdater` and `SPUUserDriver`. Active only when `SUFeedURL` and `SUPublicEDKey` are present in the app bundle's Info.plist; the wrapper silently disables itself otherwise. |
| IOKit (`IOKit.pwr_mgt`) | System | `IOPMAssertionCreateWithName` / `IOPMAssertionRelease` for power assertions. Imported in `AwakeSessionManager.swift`. |
| ServiceManagement (`SMAppService`) | System | Login item registration. `SMAppService.mainApp.register()` / `.unregister()` in `AwakeSessionManager.setLaunchAtLogin(_:)`. |
| AppKit | System | `NSApplication`, `NSEvent` (modifier key monitoring in `MenuContentView`), and `NSUserName()` (managed policy user path). |
| SwiftUI | System | All views. Hosted in the `NSPopover` via `NSHostingController`. |
| Foundation | System | `Timer`, `UserDefaults`, `PropertyListSerialization`, `URL`, `Date`, `TimeInterval`. |

---

## Source Files

All source files live in `Sources/Awake/`.

| File | Primary types | Role |
|---|---|---|
| `AwakeMenuBarApp.swift` | `AwakeMenuBarApp`, `AwakeAppDelegate` | `@main` App entry point. `AwakeAppDelegate` owns the `NSStatusItem` and `NSPopover`, intercepts `awake://` URLs, and drives the status item button image by subscribing to `AwakeSessionManager.shared.objectWillChange`. `AwakeMenuBarApp` sets activation policy to `.accessory` and provides an empty `Settings` scene (required by SwiftUI). |
| `AwakeSessionManager.swift` | `AwakeSessionManager`, `ManagedPolicyState`, `BehaviorPolicyNotice`, `SleepBehavior`, `AppearanceMode` | Central `@MainActor ObservableObject`. Owns the one-second clock timer, IOKit power assertions, session lifecycle (`start`, `pause`, `resume`, `stop`), IPC session registry (`ipcSessions`), effective-state computation, `UserDefaults` persistence (`saveState` / `restoreSavedState` / `saveIPCSessions` / `restoreIPCSessions`), managed policy loading, login item registration (`SMAppService`), and appearance mode management. All `@Published` properties drive the SwiftUI layer. |
| `IPCSession.swift` | `IPCSession` | `Codable` value type representing a named IPC awake session with id, label, end date, and created date. Provides remaining-time and active-check helpers. |
| `IPCSessionListView.swift` | `IPCSessionListView` | SwiftUI card view listing active IPC sessions below the timer hero. Each row shows the session label, compact remaining time, and a deactivate button. Renders as a tight `VStack` for 7 or fewer sessions, or wraps in a `ScrollView` when more. |
| `MenuContentView.swift` | `MenuContentView`, `ModifierKeyObserver` | Root SwiftUI view rendered inside the `MenuBarExtra` window. Composes the header badge, `TimerHeroView`, `IPCSessionListView` (when IPC sessions are active), `UpdateNoticeCard`, preset grid, `PolicyWarningCard`, and quit button. Toggles between main timer controls and a settings panel via `@State showingSettings`. `ModifierKeyObserver` tracks the Option key so the action button toggles between primary and alternate actions. |
| `AppUpdater.swift` | `AppUpdater`, `UpdateNotice`, `UpdateNotice.Kind` | `@MainActor ObservableObject` that wraps `SPUUpdater` (the Sparkle engine) and implements both `SPUUpdaterDelegate` and `SPUUserDriver`. Translates Sparkle lifecycle callbacks into a single `@Published var notice: UpdateNotice?` value consumed by `MenuContentView`. |
| `Components.swift` | `TimerHeroView`, `CircleActionIcon`, `PolicyWarningCard`, `UpdateNoticeCard`, `SettingsGroupBox` | Self-contained SwiftUI view components. `SettingsGroupBox` wraps settings content in a material-filled rounded rectangle card. `TimerHeroView` renders the racetrack ring progress, large countdown text, and context-sensitive action button with animated state transitions. `CircleActionIcon` animates SF Symbol morphs via `.symbolEffect(.replace)` and fill-color transitions. `PolicyWarningCard` shows expandable MDM policy warnings. `UpdateNoticeCard` shows update state and action buttons. |
| `Styles.swift` | `PresetButtonStyle`, `FooterButtonStyle`, `FooterIconButtonStyle`, `DoneButtonStyle`, `UpdateCardPrimaryButtonStyle`, `UpdateCardSecondaryButtonStyle` | `ButtonStyle` implementations for all button roles in the UI. |
| `AwakeURL.swift` | `AwakeURLCommand`, `parseAwakeURL(_:)` | Pure URL parser for the `awake://` scheme. Validates incoming URLs and returns typed `AwakeURLCommand` values (`.activate` or `.deactivate`) for dispatch by `AwakeAppDelegate`. |
| `RacetrackRingShape.swift` | `RacetrackRingShape` | `InsettableShape` that draws a stadium/racetrack outline. Used by `TimerHeroView` for both the track layer and the `.trim`-animated progress layer. |

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

SwiftUI observes @Published properties on AwakeSessionManager:
  now, endDate, sessionDuration, pausedRemaining,
  powerAssertionIsActive, sleepBehavior, managedPolicyState
  → MenuContentView body re-evaluates
  → TimerHeroView receives updated progress and timeText
  → AwakeAppDelegate.managerSink fires, updateStatusItemImage() composites and sets NSStatusItem button image
```

`AwakeSessionManager` is `@MainActor`. All mutations happen on the main actor. The `clockTimer` callback dispatches back to `MainActor` via `Task { @MainActor in ... }` because `Timer` callbacks run on whatever thread schedules them.

---

## State Persistence

Session and behavior state are persisted to `UserDefaults.standard` using four keys. On relaunch, `restoreSavedState()` is called from `init()` before the clock starts.

| Key | Type stored | Meaning |
|---|---|---|
| `awake.endDate` | `Double` (Unix timestamp via `timeIntervalSince1970`) | When the active session expires. Cleared when the session stops or is paused. If the restored end date is in the past, all three session keys are cleared and the session is treated as expired. |
| `awake.duration` | `Double` (seconds) | The full length of the session originally started. Used to compute ring progress. Cleared when the session stops. |
| `awake.pausedRemaining` | `Double` (seconds) | The remaining time at the moment the user paused. Non-zero value takes precedence over `awake.endDate` during restore — the controller enters paused state rather than active state. |
| `awake.sleepBehavior` | `String` (raw value of `SleepBehavior`) | Either `"keepDisplayAwake"` or `"allowDisplaySleep"`. Persisted on every behavior change. Restored unconditionally at launch. |
| `awake.appearanceMode` | `String` (raw value of `AppearanceMode`) | One of `"system"`, `"light"`, or `"dark"`. Applied to `NSApp.appearance` at launch and whenever the user changes the picker. |

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

`ManagedPolicyState.hasRelevantWarnings` is `true` when any of `screenSaverIdleTime`, `asksForPasswordAfterScreenSaver`, or `autoLogoutDelay` is set. Only when this is `true` does `AwakeSessionManager.behaviorPolicyNotice` return a non-nil `BehaviorPolicyNotice`, which `MenuContentView` uses to show `PolicyWarningCard`.

Policy state is loaded once at launch (forced) and then refreshed on a 60-second throttle inside the `clockTimer` callback.

---

## URL Scheme IPC

Awake registers the `awake` custom URL scheme (`CFBundleURLTypes` in Info.plist) to allow external tools to control awake sessions programmatically. Two routes are supported:

- `awake://activate?session=<id>&label=<name>&duration=<seconds>` — creates or refreshes a named session.
- `awake://deactivate?session=<id>` — removes a named session.

**Session registry.** `AwakeSessionManager` maintains an `ipcSessions: [String: IPCSession]` dictionary alongside the existing app session state. Each `IPCSession` is a `Codable` value type storing `id`, `label`, `endDate`, and `createdDate`.

**Effective state.** Three computed properties merge the app session and IPC sessions:

- `effectiveEndDate` — the latest end date across all active sessions.
- `effectiveRemaining` — seconds until `effectiveEndDate` (accounts for paused app session).
- `effectiveSessionDuration` — duration of whichever session drives the effective end date (for ring progress).

All UI-facing properties (`isActive`, `progress`, `menuBarClockText`, `formattedRemaining()`) read from these effective values.

**URL handling.** `AwakeAppDelegate.application(_:open:)` receives URL events via AppKit's kAEGetURL Apple Event path. The pure parser `parseAwakeURL(_:)` in `AwakeURL.swift` validates and extracts typed `AwakeURLCommand` values, which are dispatched to `AwakeSessionManager.shared.activateIPCSession(id:label:duration:)` or `deactivateIPCSession(id:)`.

**Persistence.** IPC sessions are stored as a JSON array in `UserDefaults` under `"awake.ipcSessions"` with `secondsSince1970` date encoding. They are restored at launch and pruned every second by the clock timer.

**Duration cap.** IPC sessions are capped at 86,400 seconds (24 hours).

See `docs/url-scheme.md` for the full technical reference.
