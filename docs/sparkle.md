# Sparkle Update Integration

## Overview

Awake uses [Sparkle](https://sparkle-project.org/) 2.8.0+ for automatic update delivery. The dependency is declared in `Package.swift` as:

```swift
.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.0")
```

Sparkle is linked into the `AwakeUI` library target. At runtime it checks a remote appcast feed, downloads updates, validates them with an Ed25519 signature, and drives the installation sequence. Awake translates Sparkle's delegate and user-driver callbacks into SwiftUI-observable state so the menu bar popover can display inline update notices without any separate update window.

---

## Conditional Activation

Sparkle is only started when the app bundle contains both `SUFeedURL` and `SUPublicEDKey` in its `Info.plist`. This means dev builds produced without those keys never attempt update checks — no feature flag or compile-time conditional is required.

The check lives in `AppUpdater.hasRequiredConfiguration`:

```swift
// Sources/AwakeUI/AppUpdater.swift
private var hasRequiredConfiguration: Bool {
    guard let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
      !feedURL.isEmpty,
      let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
      !publicKey.isEmpty
    else {
      return false
    }
    return true
}
```

`configureUpdaterIfPossible()` is called from `AppUpdater.init()`. It guards on `hasRequiredConfiguration` before constructing or starting `SPUUpdater`. When the guard fails the method returns silently and `isEnabled` remains `false`. When it succeeds, `isEnabled` is set to `true` and `SPUUpdater` is started; any startup error is surfaced as an `UpdateNotice` with kind `.failed`.

---

## Configuration

`scripts/bundle_app.sh` writes `Info.plist` from a heredoc and then patches in the Sparkle keys. The relevant environment variables and their `Info.plist` keys are:

| Environment variable       | Info.plist key              | Default   | Notes                                          |
|----------------------------|-----------------------------|-----------|------------------------------------------------|
| `SPARKLE_FEED_URL`         | `SUFeedURL`                 | _(empty)_ | Required for updates. Omit to disable Sparkle. |
| `SPARKLE_PUBLIC_ED_KEY`    | `SUPublicEDKey`             | _(empty)_ | Required for updates. Omit to disable Sparkle. |
| `SPARKLE_CHECK_INTERVAL`   | `SUScheduledCheckInterval`  | `86400`   | Seconds between background checks (24 h).      |
| _(always set)_             | `SUEnableAutomaticChecks`   | `true`    | Hard-coded in the heredoc.                     |
| _(always set)_             | `SUAutomaticallyUpdate`     | `false`   | Hard-coded; user must accept every update.     |

`SUFeedURL` and `SUPublicEDKey` are injected conditionally — the script only calls `PlistBuddy` when the variable is non-empty:

```bash
if [[ -n "$SPARKLE_FEED_URL" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SPARKLE_FEED_URL" "$CONTENTS_DIR/Info.plist"
fi

if [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$CONTENTS_DIR/Info.plist"
fi
```

`SUAutomaticallyUpdate = false` is intentional. Sparkle will never silently replace the binary; every install requires explicit user action through the menu UI.

---

## AppUpdater Architecture

**File:** `Sources/AwakeUI/AppUpdater.swift`

`AppUpdater` is an `NSObject` subclass annotated `@MainActor` that conforms to both `SPUUpdaterDelegate` and `SPUUserDriver`. It is also `ObservableObject` so SwiftUI views can react to its published state.

```swift
@MainActor
public final class AppUpdater: NSObject, ObservableObject {
    @Published private(set) var notice: UpdateNotice?
    @Published private(set) var isEnabled = false

    private var updater: SPUUpdater?
    private var pendingChoiceReply: ((SPUUserUpdateChoice) -> Void)?
    private var immediateInstallHandler: (() -> Void)?
    ...
}
```

Key responsibilities:

- Holds the single `SPUUpdater` instance (`updater`).
- Stores the two install-path closures Sparkle can provide (`pendingChoiceReply` and `immediateInstallHandler`).
- Tracks download byte counts (`downloadExpectedLength`, `downloadReceivedLength`) to compute normalized progress.
- Exposes `notice: UpdateNotice?` that the menu view observes. `nil` means nothing to show.
- Exposes `isEnabled: Bool` so the menu can conditionally show an "Check for updates" option (not currently wired but available).

`AppUpdater` acts as `SPUUserDriver` directly rather than using the standard `SPUStandardUserDriver`. This keeps all update UI inside the menu popover and avoids Sparkle opening separate windows or alerts.

---

## UpdateNotice Lifecycle

`UpdateNotice` is a value type nested inside `AppUpdater`. It carries the data needed to render a single card in the menu:

```swift
struct UpdateNotice: Equatable {
    enum Kind: Equatable {
        case available
        case downloading(progress: Double?)
        case preparing
        case readyToInstall
        case installing
        case failed
    }

    let kind: Kind
    let title: String
    let message: String
    let version: String?
    let primaryActionTitle: String?
    let secondaryActionTitle: String?
}
```

### Phases and UI

| Kind                        | Title               | Primary button   | Secondary button | Triggered by                                     |
|-----------------------------|---------------------|------------------|------------------|--------------------------------------------------|
| `.available`                | "Update available"  | "Install update" | "Later"          | `showUpdateFound(with:state:reply:)`             |
| `.downloading(progress:)`   | "Update available"  | _(none)_         | _(none)_         | `showDownloadInitiated`, `showDownloadDidReceiveData`, `showDownloadDidReceiveExpectedContentLength` |
| `.preparing`                | "Preparing update"  | _(none)_         | _(none)_         | `showDownloadDidStartExtractingUpdate`, `showExtractionReceivedProgress` |
| `.readyToInstall`           | "Update ready"      | "Install update" | "Later" or none  | `showReady(toInstallAndRelaunch:)` or `updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)` |
| `.installing`               | "Installing update" | _(none)_         | _(none)_         | `showInstallingUpdate(withApplicationTerminated:retryTerminatingApplication:)` or `installUpdate()` immediate path |
| `.failed`                   | "Update failed"     | _(none)_         | "Dismiss"        | `showUpdaterError`, `updater(_:didFinishUpdateCycleFor:error:)` |

`notice` is set to `nil` by `dismissUpdateInstallation()` (called by Sparkle at the end of any flow) and by `dismissNotice()` (called when the user taps "Later" or "Dismiss").

The `.downloading(progress:)` associated value is `Double?`. It is `nil` when Sparkle has not yet provided an expected content length, which causes `UpdateNoticeCard` to hide the `ProgressView` until the length is known.

---

## UI Integration

**UpdateNoticeCard** is defined in `Sources/AwakeUI/Components.swift`. It takes a `AppUpdater.UpdateNotice` and two action closures:

```swift
struct UpdateNoticeCard: View {
    let notice: AppUpdater.UpdateNotice
    let primaryAction: () -> Void
    let secondaryAction: () -> Void
    ...
}
```

The card renders:
- A blue circular refresh icon.
- `notice.title` and `notice.message`.
- A linear `ProgressView` when `notice.kind` is `.downloading(progress:)` and `progress` is non-nil.
- Primary and secondary `Button` views when `notice.primaryActionTitle` / `notice.secondaryActionTitle` are non-nil.

**MenuContentView** (`Sources/AwakeUI/MenuContentView.swift`) holds an `@ObservedObject var updater: AppUpdater` and places the card in the layout between the `TimerHeroView` and the preset grid:

```swift
// After TimerHeroView, before the Presets section:
if let notice = updater.notice {
    UpdateNoticeCard(
        notice: notice,
        primaryAction: { updater.installUpdate() },
        secondaryAction: { updater.dismissNotice() }
    )
}
```

The card appears and disappears automatically as `updater.notice` transitions between `nil` and non-nil.

---

## Install Flow

There are two code paths through `AppUpdater.installUpdate()`.

### Immediate install (staged update on quit)

When Sparkle has already staged an update and is waiting for the app to quit, it calls the `SPUUpdaterDelegate` method:

```swift
public func updater(
    _ updater: SPUUpdater,
    willInstallUpdateOnQuit item: SUAppcastItem,
    immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
) -> Bool
```

`AppUpdater` stores this closure in `self.immediateInstallHandler` and shows a `.readyToInstall` notice with a single "Install update" button (no "Later").

When the user taps "Install update", `installUpdate()` calls the stored closure, clears it, and immediately transitions the notice to `.installing`:

```swift
func installUpdate() {
    if let immediateInstallHandler {
        immediateInstallHandler()
        self.immediateInstallHandler = nil
        notice = UpdateNotice(kind: .installing, ...)
        return
    }
    ...
}
```

Calling `immediateInstallHandler()` tells Sparkle to quit and replace the binary right away.

### Deferred install (normal download flow)

For updates discovered during a normal check cycle, Sparkle calls `showUpdateFound(with:state:reply:)` first, then `showReady(toInstallAndRelaunch:reply:)` after the download and extraction complete. Both store their `reply` closure in `pendingChoiceReply`.

When the user taps "Install update", `installUpdate()` invokes the pending reply with `.install`:

```swift
func installUpdate() {
    ...
    guard let pendingChoiceReply else { return }
    self.pendingChoiceReply = nil
    pendingChoiceReply(.install)
}
```

When the user taps "Later" or "Dismiss", `dismissNotice()` invokes it with `.dismiss` and clears `notice`.

Sparkle then proceeds with the installation and eventually calls `showInstallingUpdate(withApplicationTerminated:retryTerminatingApplication:)`, which transitions the notice to `.installing`, followed by `dismissUpdateInstallation()` which resets all state to `nil`.
