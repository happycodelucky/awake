// MARK: - AwakeMenuBarApp
// App entry point — creates AwakeController and AppUpdater, hosts the
// MenuBarExtra scene. Runs as an accessory (no Dock icon).

import AppKit
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
    compositeMenuBarImage(
      iconName: menuBarIconName,
      badgeText: controller.hasSession ? controller.menuBarClockText : nil,
    )
  }

  /// Returns the SF Symbol name for the current assertion state.
  private var menuBarIconName: String {
    controller.powerAssertionIsActive ? "mug.fill" : "mug"
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
  badgeText: String?,
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
  var badgeSize = CGSize.zero
  var attrString: NSAttributedString?

  if let badgeText {
    let font = roundedBoldFont(size: 11)
    let attrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: NSColor.labelColor,
    ]
    let str = NSAttributedString(string: badgeText, attributes: attrs)
    let measuredSize = str.size()
    badgeSize = CGSize(width: measuredSize.width + hPad * 2, height: measuredSize.height + vPad * 2)
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

    if rawIcon.isTemplate {
      NSGraphicsContext.current?.saveGraphicsState()
      rawIcon.draw(in: iconRect)
      NSColor.labelColor.setFill()
      iconRect.fill(using: .sourceAtop)
      NSGraphicsContext.current?.restoreGraphicsState()
    } else {
      rawIcon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

      if let attrString {
        let pillX = iconSize.width + spacing
        let pillY = (rect.height - badgeSize.height) / 2
        let pillRect = NSRect(x: pillX, y: pillY, width: badgeSize.width, height: badgeSize.height)
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: badgeSize.height / 2, yRadius: badgeSize.height / 2)

        // Fill the pill using the provided color (e.g., white)
        NSColor.labelColor.withAlphaComponent(0.85).setFill()
        pillPath.fill()

        // Compute text origin (baseline point for NSAttributedString.draw(at:))
        let textX = pillX + hPad
        let textY = pillY + vPad

        // Knock out the text from the pill by drawing with destinationOut blend mode
        if let ctx = NSGraphicsContext.current?.cgContext {
          ctx.saveGState()
          ctx.setBlendMode(.destinationOut)

          // Use fully opaque color so the glyph mask is solid; font must match measurement
        attrString.draw(at: NSPoint(x: textX, y: textY))

          ctx.restoreGState()
        }
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
