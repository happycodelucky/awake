# Awake Features

Awake is a macOS menu bar utility that keeps your Mac awake for a set duration. Click the mug icon in your menu bar to open the control panel and get started.

---

## Timer Presets

Awake offers nine duration presets, arranged in a grid inside the popover:

| Preset | Category |
|--------|----------|
| 5m     | quick    |
| 10m    | quick    |
| 15m    | quick    |
| 30m    | quick    |
| 1h     | focus    |
| 2h     | long     |
| 4h     | long     |
| 8h     | long     |
| 12h    | long     |

Click any preset to start a countdown immediately. If a session is already running, clicking a preset replaces it with the new duration.

---

## Menu Bar Countdown

Once a session starts, a pill-shaped badge appears next to the Awake icon in your menu bar, showing how much time is left. The format adapts to how much time remains:

- **Hours remaining** — shown as `2:30` (hours and minutes, e.g. two and a half hours left)
- **Minutes remaining** — shown as `25m`
- **Last 90 seconds** — shown as `45s`, counting down second by second

The badge disappears when the session ends.

---

## Pause & Resume

While a session is running, you can pause it instead of stopping it entirely.

**To pause:** Hold the **Option key** (⌥) while clicking the stop button in the popover. The button changes from a red X to an orange pause icon while Option is held. Releasing the click pauses the session and saves the remaining time. The button tooltip also updates to reflect the alternate action.

When paused, the popover shows a play button. Click it to resume — the countdown picks up exactly where it left off.

**To stop while paused:** Hold the **Option key** (⌥) while clicking the resume button. The button changes from an orange play icon to a red X, and clicking it ends the session completely.

The menu bar badge remains visible while paused.

---

## Settings

Click the **gear icon** in the bottom-right corner of the Awake popover to open the settings panel. The timer remains visible at the top while you adjust settings.

### Start at Login

Turn on "Start at login" to launch Awake automatically when you log in to your Mac. When you restart or log back in, Awake will start in the menu bar with your previous session restored (if it has not expired).

### Appearance

Choose between **System**, **Light**, or **Dark** theme modes. System follows your Mac's current appearance setting. Light and Dark override it for the Awake popover only.

### MCP Server

A future feature that will allow AI agents and automation tools to control Awake sessions over the Model Context Protocol. The controls are visible but disabled.

Click **Done** to return to the main timer view.

---

## Two Sleep Modes

The "Keep display awake" toggle in the **Behavior** section of the main view controls which type of sleep Awake prevents.

**Keep display awake — ON (default)**

Both the display and the system are kept awake. Use this when you need the screen to stay on, such as during presentations, screen sharing, or watching a progress indicator.

**Keep display awake — OFF**

The system stays awake but the display can turn off on its own schedule. Use this for long-running background work — builds, downloads, AI agent runs — where you do not need to see the screen but your Mac must not sleep.

You can switch between modes at any time, even during an active session.

---

## Persistent Sessions

Awake saves your session to disk whenever you start, pause, or change settings. If the app quits unexpectedly — due to an update, a crash, or a system reboot — it restores the session the next time it launches.

The countdown resumes from the saved end time. If the end time has already passed while Awake was not running, the session is cleared and the app starts fresh.

---

## Auto-Updates

When an update is available, Awake shows a notice card inside the menu popover. The card displays the new version number and a short description.

- Click **Install update** to apply the update immediately.
- Click **Dismiss** to hide the card and continue using the current version.

Awake checks for updates automatically in the background when this feature is configured. No action is needed on your part unless an update card appears.

---

## URL Scheme (Remote Control)

Awake can be controlled by other apps, scripts, and AI agents using the `awake://` URL scheme. External tools can start and stop named awake sessions without opening the Awake menu.

Multiple sessions from different tools can overlap — your Mac stays awake until the longest one finishes. Active external sessions appear in a list below the timer in the Awake popover, where you can also stop them individually.

See the [URL Scheme guide](url-scheme.md) for details and integration examples.
