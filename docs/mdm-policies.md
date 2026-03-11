# MDM Policy Detection

## Overview

Awake reads enterprise and MDM-managed device policies from macOS managed preference files to warn users about restrictions that may interrupt their awake session. Even when a power assertion is active, managed policies such as screen saver timeouts, password-after-screensaver requirements, and auto-logout delays are enforced by the operating system independently. Awake surfaces these conflicts as a warning notice so users understand what may still interrupt their session.

The policy detection system lives in `Sources/AwakeUI/AwakeSessionManager.swift` and is represented by the `ManagedPolicyState` struct nested inside `AwakeSessionManager`.

## Policy Source Files

Awake reads from `/Library/Managed Preferences/`, the standard macOS location for MDM-pushed preference files. Two domains are inspected: `com.apple.screensaver` and `com.apple.loginwindow`.

For each domain, two plists are read:

**System-level** (device-wide, applies to all users):

- `/Library/Managed Preferences/com.apple.screensaver.plist`
- `/Library/Managed Preferences/com.apple.loginwindow.plist`

**User-level** (applies only to a specific user):

- `/Library/Managed Preferences/<username>/com.apple.screensaver.plist`
- `/Library/Managed Preferences/<username>/com.apple.loginwindow.plist`

The `<username>` is resolved at runtime using `NSUserName()`.

## Merge Logic

For each domain, the system plist is loaded first. The user-level plist is then merged on top using Swift's `Dictionary.merging(_:uniquingKeysWith:)` method. When a key appears in both dictionaries, the user-level value wins.

```swift
let mergedScreensaver = systemScreensaver.merging(
    userScreensaver, uniquingKeysWith: { _, userValue in userValue })
```

This means user-level managed preferences take precedence over system-level ones when there is a conflict. If a plist file does not exist or fails to parse, it is treated as an empty dictionary — loading never throws.

## Detected Policies

The following keys are read and surfaced as typed properties on `ManagedPolicyState`:

| Key | Source Domain | Swift Property | Type | Description |
|-----|--------------|---------------|------|-------------|
| `idleTime` | `com.apple.screensaver` | `screenSaverIdleTime` | `TimeInterval?` | Screen saver idle timeout in seconds |
| `loginWindowIdleTime` | `com.apple.screensaver` | `loginWindowIdleTime` | `TimeInterval?` | Login window screen saver timeout in seconds |
| `askForPassword` | `com.apple.screensaver` | `asksForPasswordAfterScreenSaver` | `Bool` | Whether a password is required after the screen saver activates |
| `askForPasswordDelay` | `com.apple.screensaver` | `askForPasswordDelay` | `TimeInterval?` | Delay in seconds before the password prompt appears |
| `autoLogoutDelay` | `com.apple.loginwindow` | `autoLogoutDelay` | `TimeInterval?` | Auto-logout timeout after idle in seconds |
| `com.apple.login.mcx.DisableAutoLoginClient` | `com.apple.loginwindow` | `disablesAutoLogin` | `Bool` | Whether automatic login is disabled |

All `TimeInterval` properties are `nil` when the key is absent from the merged dictionaries. Both `Bool` properties default to `false` when absent.

## Type Extraction Helpers

Two private static helpers on `ManagedPolicyState` handle the type ambiguity present in managed preference plists, where numeric values may be stored as `NSNumber`, `Double`, or `Int` depending on how the MDM profile was constructed.

### `timeInterval(forKey:in:)`

```swift
private static func timeInterval(forKey key: String, in values: [String: Any]) -> TimeInterval?
```

Attempts to extract a `TimeInterval` from the dictionary in the following order:

1. `values[key] as? NSNumber` — calls `.doubleValue`
2. `values[key] as? Double` — used directly
3. `values[key] as? Int` — converted to `Double`

Returns `nil` if the key is absent or the value does not match any of these types.

### `bool(forKey:in:)`

```swift
private static func bool(forKey key: String, in values: [String: Any]) -> Bool?
```

Attempts to extract a `Bool` from the dictionary in the following order:

1. `values[key] as? Bool` — used directly
2. `values[key] as? NSNumber` — calls `.boolValue`

Returns `nil` if the key is absent or the value does not match either type.

Both helpers return `nil` — not a default — when a key is absent, so callers can distinguish "policy not set" from "policy set to zero or false."

## Refresh Throttle

Policy state is not reloaded on every clock tick. Instead, `AwakeSessionManager` stores a `lastPolicyRefresh: Date` timestamp initialized to `Date.distantPast`. The private method `refreshManagedPolicyState(force:)` enforces a minimum 60-second interval between reloads:

```swift
private func refreshManagedPolicyState(force: Bool = false) {
    let refreshDate = Date()
    guard force || refreshDate.timeIntervalSince(lastPolicyRefresh) >= 60 else { return }
    managedPolicyState = ManagedPolicyState.load(forUser: NSUserName())
    lastPolicyRefresh = refreshDate
}
```

**Force refresh on init:** `init()` calls `refreshManagedPolicyState(force: true)` so the policy state is populated immediately when the controller is created, before the first clock tick fires.

**Called from the 1-second clock timer:** `startClock()` sets up a `Timer` that fires every second. Each tick calls `refreshManagedPolicyState()` (without `force: true`), which is a no-op unless 60 seconds have elapsed since the last load.

This design keeps file I/O infrequent while ensuring policy changes (such as an MDM push) are picked up within a minute.

## ManagedPolicyState

`ManagedPolicyState` is a struct nested inside `AwakeSessionManager`, defined in `Sources/AwakeUI/AwakeSessionManager.swift`.

```swift
struct ManagedPolicyState {
    let screenSaverIdleTime: TimeInterval?
    let loginWindowIdleTime: TimeInterval?
    let asksForPasswordAfterScreenSaver: Bool
    let askForPasswordDelay: TimeInterval?
    let autoLogoutDelay: TimeInterval?
    let disablesAutoLogin: Bool
}
```

### `hasRelevantWarnings`

The computed property `hasRelevantWarnings` returns `true` when any policy that warrants a user-facing warning is present:

```swift
var hasRelevantWarnings: Bool {
    screenSaverIdleTime != nil || asksForPasswordAfterScreenSaver || autoLogoutDelay != nil
}
```

Note that `loginWindowIdleTime` and `disablesAutoLogin` do not contribute to `hasRelevantWarnings` — they appear only in the "possible" warnings section (see `BehaviorPolicyNotice` below).

### `load(forUser:)`

The static method `load(forUser:)` performs the complete load-and-merge sequence for a given username and returns a fully populated `ManagedPolicyState`:

```swift
static func load(forUser user: String) -> ManagedPolicyState
```

It reads the four plist files described in the Policy Source Files section, merges each domain pair using the user-wins strategy, extracts each key using the type helpers, and returns the resulting struct. Missing files silently produce empty dictionaries.

## BehaviorPolicyNotice

`BehaviorPolicyNotice` is a struct nested inside `AwakeSessionManager` used to carry human-readable warning text to the UI:

```swift
struct BehaviorPolicyNotice {
    let title: String
    let known: [String]
    let possible: [String]
}
```

The computed property `behaviorPolicyNotice` on `AwakeSessionManager` builds a `BehaviorPolicyNotice?`, returning `nil` when `managedPolicyState.hasRelevantWarnings` is `false`.

**Title logic:**

- If `autoLogoutDelay` is set: `"Managed policies can end or interrupt long idle sessions"`
- Otherwise: `"Managed policies may still lock or cover the session"`

**Known warnings** — confirmed-active policies that will definitely affect the session:

- `autoLogoutDelay` is set: describes the logout timeout duration.
- `screenSaverIdleTime` is set: states whether the screen saver will trigger during the current session (by comparing remaining session time against the idle timeout) or just after a given idle period.
- `asksForPasswordAfterScreenSaver` is `true`: states that a password will be required, including the delay if `askForPasswordDelay` is also set.

**Possible warnings** — conditional outcomes that depend on user behavior or display state:

- `screenSaverIdleTime` is set: explains the interaction with the current `sleepBehavior` (keepDisplayAwake vs allowDisplaySleep).
- `loginWindowIdleTime` is set: warns that if the Mac returns to the login window, the login screen saver can start after the configured timeout.

The `behaviorPolicyNotice` property is defined in `Sources/AwakeUI/AwakeSessionManager.swift` and consumed by the UI layer to render a warning card when `known` or `possible` entries are present.

## Diagnostic Script

`scripts/list_managed_policies.swift` is a standalone Swift script that dumps all managed policies found on the current machine. It is useful for diagnosing what policies are active, verifying that Awake will detect them, and understanding their scope and enforcement mode.

**Usage:**

```
swift scripts/list_managed_policies.swift [username] [--verbose] [--user-only]
```

**Arguments:**

| Argument | Description |
|----------|-------------|
| `username` | Optional. The short username to inspect. Defaults to the current user (`NSUserName()`). |
| `--verbose` | Prints all keys for every domain and includes MDM metadata source information. |
| `--user-only` | Skips system-level plists in `/Library/Managed Preferences/` and reads only from the user subdirectory. |

**Output sections:**

1. **Relevant inactivity and lock policies** — shows only the keys that Awake reads (`idleTime`, `loginWindowIdleTime`, `askForPassword`, `askForPasswordDelay`, `autoLogoutDelay`, `com.apple.login.mcx.DisableAutoLoginClient`) plus any `com.apple.PowerManagement` keys. Duration values are shown with a human-readable formatted duration in parentheses.
2. **Managed domains** — lists every managed domain plist found with its scope and key count. With `--verbose`, all key-value pairs are printed.
3. **Governed keys** — a flat list of every managed key-value pair across all domains.

The script reads `complete.plist` in each managed preferences directory when available to extract enforcement mode (`mcxdomain`) and source profile information for verbose output. The script itself does not modify any state and is safe to run at any time.
