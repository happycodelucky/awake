# Getting Started with Awake

Awake is a menu bar app that keeps your Mac awake for a chosen duration.

---

## Installation

Choose the method that works best for you.

### Download

1. Go to the [latest release on GitHub](https://github.com/happycodelucky/awake/releases/latest).
2. Download **Awake.zip**.
3. Unzip the file (double-click it in Finder).
4. Drag **Awake.app** into your **Applications** folder.

### Homebrew

If you use [Homebrew](https://brew.sh), run these two commands in Terminal:

```sh
brew tap happycodelucky/tap
brew install --cask awake
```

### Build from Source

Requirements: Xcode and an Apple Silicon Mac.

1. Clone the repository and open Terminal in the project folder.
2. Run the build script:

   ```sh
   ./scripts/bundle_app.sh
   ```

3. The finished app will be at `dist/Awake.app`.

---

## First Launch

1. Open **Awake** from your Applications folder (or wherever you placed it).
2. A **mug icon** appears in the menu bar at the top of your screen.
3. Click the mug icon to open the popover.
4. Pick a preset duration to start keeping your Mac awake.

That's it — Awake will prevent your Mac from sleeping for the time you selected.

---

## macOS Security Note

Because Awake is ad-hoc signed rather than distributed through the Mac App Store, macOS may show a warning the first time you open it saying the app is from an "unidentified developer."

To get past this, use either of these methods:

- **Right-click** Awake.app in Finder, choose **Open**, then click **Open** in the dialog that appears.
- Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the Awake entry.

You only need to do this once.
