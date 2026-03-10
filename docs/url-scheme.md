# URL Scheme IPC Reference

Technical reference for the `awake://` URL scheme used to control Awake programmatically from external tools, scripts, and AI agents.

---

## Overview

Awake registers the `awake` custom URL scheme via `CFBundleURLTypes` in its Info.plist. External callers use `open "awake://..."` to activate and deactivate named awake sessions. Multiple sessions can coexist — the Mac stays awake until the longest-running session expires or all are deactivated.

On macOS 26 (Tahoe), URLs are handled by `NSApplicationDelegate.application(_:open:)` via `@NSApplicationDelegateAdaptor`. SwiftUI's `onOpenURL` does not fire for `MenuBarExtra`-only apps (no regular window scene) on macOS 26. `onOpenURL` is retained as a secondary handler for forward compatibility on earlier macOS versions. macOS delivers URLs to the running instance, or launches the app first if it is not running.

---

## URL Format

### Activate a session

```
awake://activate?session=<id>&label=<name>&duration=<seconds>
```

| Parameter | Required | Type | Description |
|-----------|----------|------|-------------|
| `session` | Yes | String | Caller-provided session identifier. Must be non-empty. Used to deactivate or refresh the session later. |
| `label` | Yes | String | Human-readable display name shown in the session list UI. Must be non-empty. URL-encode spaces as `%20` or `+`. |
| `duration` | Yes | Integer | Requested duration in seconds. Must be positive. Capped at 86400 (24 hours). |

If a session with the same `id` already exists, it is replaced with the new duration and label.

### Deactivate a session

```
awake://deactivate?session=<id>
```

| Parameter | Required | Type | Description |
|-----------|----------|------|-------------|
| `session` | Yes | String | The session identifier to remove. Must match an active session. |

---

## Launch Services Registration

macOS uses Launch Services to route custom URL schemes to the correct app binary. After building a new `.app` bundle you **must** open it via `open` at least once before sending `awake://` URLs, or macOS may route them to a stale or wrong registration:

```bash
open dist/Awake.app          # forces re-registration of this bundle as the awake:// handler
open "awake://activate?..."  # now delivered to the freshly registered binary
```

This matters most during development and CI workflows where the binary is rebuilt frequently at a non-standard path. Sending a URL before re-registering results in either no action or the URL being delivered to a different (older) binary.

### Diagnosing with logs

All URL dispatch and IPC session lifecycle events are written to the unified Apple log with:

- **Subsystem:** `com.akkio.apps.awake`
- **Category:** `ipc`

Stream them live in Terminal:

```bash
log stream --predicate 'subsystem == "com.akkio.apps.awake" AND category == "ipc"' --level info
```

Or view historical entries in Console.app by filtering on the subsystem and category above.

Every incoming URL produces an `onOpenURL received:` entry immediately. If no entry appears after sending a URL, the URL is not reaching the app — the registration gotcha is the likely cause.

---

## Validation and Rejection

URLs are silently rejected (no error, no state change) when:

- The scheme is not `awake`
- The host is not `activate` or `deactivate`
- Required parameters are missing or empty
- `duration` is not a positive number

This is intentional — the caller is expected to validate its own parameters. Awake has no IPC response channel.

---

## Duration Cap

IPC sessions are capped at **86,400 seconds (24 hours)**. If a caller requests a longer duration, it is silently clamped to 24 hours.

---

## Session Semantics

- **Session ID**: Any non-empty string. The caller chooses the ID — it can be a UUID, a chat ID, a worktree name, or any stable identifier.
- **Overlap**: Multiple sessions with different IDs coexist. The effective awake time is `max(all session end dates)`. The UI ring and countdown always show the longest remaining time.
- **App session**: The user's manually-set timer (from clicking a preset) is an independent session. It coexists with IPC sessions.
- **Stop button**: Clicking Stop in the UI clears **all** sessions — both the app session and all IPC sessions.
- **Persistence**: IPC sessions survive app relaunch. They are stored as a JSON array in `UserDefaults` under the key `awake.ipcSessions`.
- **Natural expiry**: Sessions are automatically pruned every second when their end date passes.

---

## Implementation Details

### Source Files

| File | Role |
|------|------|
| `Sources/AwakeUI/IPCSession.swift` | `Codable` value type representing a named session. |
| `Sources/AwakeUI/AwakeController.swift` | Session registry (`ipcSessions`), effective-state computation, activate/deactivate/prune methods, persistence. |
| `Sources/AwakeUI/IPCSessionListView.swift` | SwiftUI view rendering the session list card in the popover. |
| `Sources/AwakeMenuBarApp/AwakeURL.swift` | Pure URL parser (`parseAwakeURL`) returning typed `AwakeURLCommand`. |
| `Sources/AwakeMenuBarApp/AwakeMenuBarApp.swift` | `onOpenURL` handler dispatching parsed commands to `AwakeController`. |
| `scripts/bundle_app.sh` | Info.plist `CFBundleURLTypes` registration. |

### Persistence Format

IPC sessions are stored in `UserDefaults.standard` under the key `"awake.ipcSessions"` as a JSON-encoded `[IPCSession]` array. Dates use `secondsSince1970` encoding to match the existing scalar timestamp convention used by the app session keys.

### Effective State Derivation

`AwakeController` computes three derived values from the merged session state:

- `effectiveEndDate` — `max(appSession.endDate, max(ipcSessions.map(\.endDate)))`, or `nil` if no session is active.
- `effectiveRemaining` — seconds until `effectiveEndDate`, or paused remaining if the app session is paused.
- `effectiveSessionDuration` — the full duration of whichever session drives the effective end date. Used for ring progress.

All UI-facing properties (`isActive`, `progress`, `menuBarClockText`, `formattedRemaining()`) read from these effective values.

---

## Launch Behavior

| Scenario | Behavior |
|----------|----------|
| App running | URL delivered to running instance via `onOpenURL`. |
| App not running | macOS launches the app, queues the URL as an Apple Event, `onOpenURL` fires after `init()` and scene body evaluation. |
| Multiple rapid URLs | Each URL is delivered and processed sequentially on the main actor. |
