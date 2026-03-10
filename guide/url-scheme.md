# URL Scheme — Remote Control

Awake can be controlled remotely by other apps, scripts, and AI agents using the `awake://` URL scheme. This lets external tools keep your Mac awake for a set duration without needing to open the Awake menu.

---

## How It Works

Any tool that can run a shell command can activate or deactivate an Awake session:

```sh
# Keep the Mac awake for 30 minutes
open "awake://activate?session=my-task&label=My%20Task&duration=1800"

# Stop keeping the Mac awake
open "awake://deactivate?session=my-task"
```

Each session has a name (`session`) and a display label (`label`). Multiple sessions from different tools can overlap — your Mac stays awake until the longest one finishes or all are stopped.

If Awake is not already running, macOS launches it automatically when a URL is opened.

---

## URL Reference

### Start a session

```
awake://activate?session=<id>&label=<name>&duration=<seconds>
```

- **session** — A unique ID for this session (any text, no spaces)
- **label** — A name shown in the Awake menu (use `%20` for spaces)
- **duration** — How long in seconds (max 24 hours / 86400 seconds)

### Stop a session

```
awake://deactivate?session=<id>
```

- **session** — The same ID used when activating

---

## Multiple Sessions

When multiple sessions are active, Awake shows each one in a list below the timer. The countdown and ring always reflect the longest remaining time across all sessions.

Clicking the Stop button in Awake stops everything — your own timer and all external sessions.

---

## For AI Agents and Chatbots

The URL scheme is designed for AI agents (like Claude) to keep the Mac awake during long-running tasks. Here are integration patterns:

### Shell Command (simplest)

Run at the start of a long task:

```sh
open "awake://activate?session=claude-$(date +%s)&label=Claude%20Task&duration=3600"
```

Run when done:

```sh
open "awake://deactivate?session=claude-$(date +%s)"
```

### Claude Code Hook

Create a hook that activates Awake when Claude starts working and deactivates when done. Add to `.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "open \"awake://activate?session=claude-code&label=Claude%20Code&duration=7200\""
      }
    ]
  }
}
```

### Claude Code Skill

Build a skill that activates Awake before long tasks:

```sh
open "awake://activate?session=${SESSION_ID}&label=Claude%20Skill&duration=3600"
```

Where `SESSION_ID` is the chat ID, worktree name, or any stable identifier.

### Tips for AI Agents

- Use a stable session ID (chat ID, worktree path hash) so repeated activations extend the same session rather than creating new ones.
- Always deactivate when your task completes, even if the duration has not expired.
- Duration is capped at 24 hours. For longer tasks, re-activate periodically.
- The label appears in the Awake menu — use something descriptive so the user knows what is keeping their Mac awake.
- URL-encode the label (spaces as `%20`, special characters as percent-encoded).

---

## Troubleshooting

### URLs are not activating sessions

**Most likely cause:** Awake's URL scheme registration is stale — macOS is routing `awake://` to an older binary, or the app has not been registered yet.

**Fix:** Run `open /path/to/Awake.app` once after each rebuild, then resend the URL:

```bash
open dist/Awake.app
open "awake://activate?session=test&label=Test&duration=60"
```

This forces macOS to re-register that specific bundle as the `awake://` handler.

### Verifying URLs are arriving

Stream Awake's IPC logs in a Terminal window while you send URLs:

```bash
log stream --predicate 'subsystem == "com.akkio.apps.awake" AND category == "ipc"' --level info
```

You should see an `onOpenURL received:` entry within a second of sending a URL. If nothing appears, the URL is not reaching the app — see the registration fix above.

If you do see the log entry but the menu does not update, look for a subsequent `unrecognized or malformed URL` warning, which means a required parameter (`label`, `session`, `duration`) was missing or invalid.

### Sessions appear in logs but not in the menu

If `activateIPCSession: stored` appears in the log but the Awake popover does not show the session, click the menu bar icon to open the popover — the session list only updates when the popover is open.
