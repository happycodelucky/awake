# Composited NSImage Menu Bar Label — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the broken HStack/Canvas menu bar label with a single composited NSImage that MenuBarExtra can actually render.

**Architecture:** A private helper function `compositeMenuBarImage(iconName:iconColor:badgeText:pillColor:)` draws the SF Symbol mug icon and optional countdown pill badge into one NSImage using AppKit drawing APIs. The MenuBarExtra label calls this via a computed property that reacts to controller state changes.

**Tech Stack:** AppKit (NSImage, NSFont, NSAttributedString, NSBezierPath, NSGraphicsContext), SwiftUI (Image(nsImage:), MenuBarExtra)

---

### Task 1: Replace MenuBarExtra label and remove MenuBarBadge

**Files:**
- Modify: `Sources/AwakeMenuBarApp/AwakeMenuBarApp.swift` (entire file)

**Step 1: Replace the file contents**

Replace the entire file with the following. This removes the `MenuBarBadge` struct, converts color properties from `Color` to `NSColor`, adds `compositeMenuBarImage(...)`, and simplifies the label to `Image(nsImage:)`.

```swift
// MARK: - AwakeMenuBarApp
// App entry point — creates AwakeController and AppUpdater, hosts the
// MenuBarExtra scene. Runs as an accessory (no Dock icon).

import AppKit
import AwakeUI
import SwiftUI

/// Hosts the menu bar extra and shared observable app state.
@main
struct AwakeMenuBarApp: App {
  @StateObject private var controller = AwakeController()
  @StateObject private var updater = AppUpdater()

  // AGENT: setActivationPolicy(.accessory) hides the app from the Dock and
  // Cmd-Tab switcher. This is standard for menu bar-only utilities. The
  // Info.plist also sets LSUIElement=true as a fallback.
  /// Configures the process to run as an accessory app without a Dock icon.
  init() {
    NSApplication.shared.setActivationPolicy(.accessory)
  }

  /// Builds the menu bar scene for the app.
  var body: some Scene {
    MenuBarExtra {
      MenuContentView(controller: controller, updater: updater)
    } label: {
      // AGENT: MenuBarExtra only renders Image and Text views in its label.
      // Custom views (HStack, Canvas, styled views) are silently ignored.
      // We composite the icon + pill badge into a single NSImage instead.
      Image(nsImage: menuBarImage)
    }
    .menuBarExtraStyle(.window)
  }

  // MARK: - Composited menu bar image

  /// Builds a composited NSImage containing the mug icon and optional countdown pill.
  private var menuBarImage: NSImage {
    if controller.hasSession {
      return compositeMenuBarImage(
        iconName: menuBarIconName,
        iconColor: menuBarIconNSColor,
        badgeText: controller.menuBarClockText,
        pillColor: menuBarPillNSColor
      )
    } else {
      return compositeMenuBarImage(
        iconName: menuBarIconName,
        iconColor: menuBarIconNSColor,
        badgeText: nil,
        pillColor: nil
      )
    }
  }

  /// Returns the SF Symbol name for the current assertion state.
  private var menuBarIconName: String {
    controller.powerAssertionIsActive ? "mug.fill" : "mug"
  }

  /// Returns the tint applied to the menu bar icon.
  private var menuBarIconNSColor: NSColor {
    controller.powerAssertionIsActive ? .systemGreen : .labelColor
  }

  /// Returns the background color used behind the countdown text.
  private var menuBarPillNSColor: NSColor {
    if controller.powerAssertionIsActive {
      return NSColor.systemGreen.withAlphaComponent(0.16)
    }
    return NSColor.labelColor.withAlphaComponent(0.12)
  }
}

// MARK: - Menu bar image compositing

/// Composites an SF Symbol icon and optional pill badge into a single NSImage
/// suitable for use as a MenuBarExtra label.
///
/// - Parameters:
///   - iconName: SF Symbol name for the icon (e.g. "mug" or "mug.fill").
///   - iconColor: Tint color applied to the icon.
///   - badgeText: Optional countdown text displayed inside a pill. Pass nil to omit the badge.
///   - pillColor: Background color of the pill. Required when `badgeText` is non-nil.
/// - Returns: A composited NSImage sized for the menu bar.
private func compositeMenuBarImage(
  iconName: String,
  iconColor: NSColor,
  badgeText: String?,
  pillColor: NSColor?
) -> NSImage {
  let iconHeight: CGFloat = 16
  let spacing: CGFloat = 4
  let hPad: CGFloat = 6
  let vPad: CGFloat = 2

  // --- Icon ---
  // AGENT: We use NSImage(systemSymbolName:) with a point-size configuration
  // to get a consistently sized SF Symbol. The image is drawn tinted by
  // setting the icon color as fill before drawing.
  let symbolConfig = NSImage.SymbolConfiguration(pointSize: iconHeight, weight: .regular)
  let rawIcon = NSImage(systemSymbolName: iconName, accessibilityDescription: "Awake")?
    .withSymbolConfiguration(symbolConfig) ?? NSImage()
  let iconSize = rawIcon.size

  // --- Badge measurement ---
  let font = roundedBoldFont(size: 11)
  var badgeSize = CGSize.zero
  var textSize = CGSize.zero
  var attrString: NSAttributedString?

  if let badgeText {
    let attrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: NSColor.labelColor,
    ]
    let str = NSAttributedString(string: badgeText, attributes: attrs)
    textSize = str.size()
    badgeSize = CGSize(width: textSize.width + hPad * 2, height: textSize.height + vPad * 2)
    attrString = str
  }

  // --- Canvas size ---
  let totalWidth: CGFloat
  if badgeText != nil {
    totalWidth = iconSize.width + spacing + badgeSize.width
  } else {
    totalWidth = iconSize.width
  }
  let totalHeight = max(iconSize.height, badgeSize.height)
  let imageSize = NSSize(width: ceil(totalWidth), height: ceil(totalHeight))

  // --- Draw ---
  // AGENT: NSImage(size:flipped:drawingHandler:) defers drawing and
  // automatically handles retina scaling via the backing store.
  let image = NSImage(size: imageSize, flipped: false) { rect in
    // Draw icon centered vertically
    let iconY = (rect.height - iconSize.height) / 2
    let iconRect = NSRect(x: 0, y: iconY, width: iconSize.width, height: iconSize.height)

    // Tint the icon by drawing it with the desired color
    iconColor.set()
    rawIcon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)

    // If the icon is template, we need to draw it as a mask with our color
    if rawIcon.isTemplate {
      NSGraphicsContext.current?.saveGraphicsState()
      rawIcon.draw(in: iconRect)
      iconColor.setFill()
      iconRect.fill(using: .sourceAtop)
      NSGraphicsContext.current?.restoreGraphicsState()
    }

    // Draw badge if present
    if let attrString, let pillColor {
      let pillX = iconSize.width + spacing
      let pillY = (rect.height - badgeSize.height) / 2
      let pillRect = NSRect(x: pillX, y: pillY, width: badgeSize.width, height: badgeSize.height)
      let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: badgeSize.height / 2, yRadius: badgeSize.height / 2)

      pillColor.setFill()
      pillPath.fill()

      let textX = pillX + hPad
      let textY = pillY + vPad
      attrString.draw(at: NSPoint(x: textX, y: textY))
    }

    return true
  }

  // AGENT: Setting isTemplate = false ensures the menu bar does not
  // override our custom colors with its own vibrancy/tinting.
  image.isTemplate = false
  return image
}

/// Returns a rounded-design bold system font at the given size.
///
/// Falls back to the standard bold system font if the rounded design
/// descriptor is unavailable.
private func roundedBoldFont(size: CGFloat) -> NSFont {
  let desc = NSFontDescriptor
    .preferredFontDescriptor(forTextStyle: .body)
    .withDesign(.rounded)?
    .withSymbolicTraits(.bold) ?? NSFontDescriptor()
  return NSFont(descriptor: desc, size: size) ?? NSFont.boldSystemFont(ofSize: size)
}
```

**Step 2: Build and verify compilation**

Run:
```bash
SWIFTPM_MODULECACHE_OVERRIDE="/Users/paulbates/Developer/awake/.build/module-cache" swift build
```
Expected: `Build complete!` with no errors.

**Step 3: Build the full app bundle and visually verify**

Run:
```bash
pkill -x Awake; ./scripts/bundle_app.sh && open dist/Awake.app
```

Verify:
- Mug icon appears in menu bar
- Starting a timer shows the countdown pill badge next to the mug
- Active state shows green mug + green pill
- Paused state shows default color mug + subtle pill
- Stopping the timer hides the pill, shows outline mug

**Step 4: Commit**

```bash
git add Sources/AwakeMenuBarApp/AwakeMenuBarApp.swift
git commit -m "Replace MenuBarExtra label with composited NSImage

MenuBarExtra only renders Image and Text in its label closure. The
previous HStack + Canvas approach was silently ignored. Now composites
the SF Symbol mug icon and countdown pill badge into a single NSImage
using AppKit drawing APIs."
```

---

### Task 2: Visual tuning (if needed)

After visual verification in Task 1 Step 3, adjust any of these if the rendering looks off:

- `iconHeight` (default 16) — SF Symbol size
- `spacing` (default 4) — gap between icon and pill
- `hPad` / `vPad` (default 6/2) — pill internal padding
- Font size (default 11) — countdown text size
- Icon tinting approach — the template-vs-non-template drawing may need adjustment depending on how `NSImage(systemSymbolName:)` behaves

This is a visual polish step — adjust constants, rebuild, and verify.
