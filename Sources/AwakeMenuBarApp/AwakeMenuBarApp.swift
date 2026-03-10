// MARK: - AwakeMenuBarApp
// App entry point — creates AwakeController and AppUpdater, hosts the
// MenuBarExtra scene. Runs as an accessory (no Dock icon).

import AppKit
import AwakeUI
import Combine
import SwiftUI
import os

// MARK: - App delegate

// AGENT: On macOS 26 (Tahoe), SwiftUI's onOpenURL does not fire for
// MenuBarExtra-only apps (apps with no regular window scene). The Apple Event
// for kAEGetURL (URL scheme open) is delivered to NSApplicationDelegate but
// SwiftUI does not bridge it through to onOpenURL in this configuration.
//
// We use NSApplicationDelegateAdaptor to intercept the URL event at the
// AppKit layer. The delegate owns the AwakeController (strong reference) and
// the App struct accesses it via the delegate rather than creating its own.
// This ensures the controller exists before the first URL event arrives.
// AGENT: @MainActor is required because AwakeController is @MainActor-isolated.
// NSApplicationDelegate methods are always called on the main thread on macOS,
// so marking the class @MainActor is safe and correct here.
//
// AGENT: AwakeAppDelegate conforms to ObservableObject so that
// @NSApplicationDelegateAdaptor wraps it as @ObservedObject in the App struct.
// When the delegate's @Published properties change, the App struct body
// re-evaluates — which re-reads controller.hasSession and controller.menuBarClockText,
// updating the menu bar label. Without ObservableObject conformance the App
// struct body never re-runs and the menu bar pill freezes.
@MainActor
final class AwakeAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
  // AGENT: The delegate owns the controller — NOT the App struct. This
  // ensures the controller is created eagerly when the delegate is
  // instantiated (during NSApplicationDelegate setup, before the SwiftUI
  // body runs), so it is always available when application(_:open:) fires.
  //
  // AGENT: @Published here is intentional. AwakeController is an
  // ObservableObject, but @Published on a reference type does NOT forward
  // child objectWillChange signals automatically. Instead, we subscribe to
  // the controller's objectWillChange publisher in init() and forward it
  // through the delegate's own objectWillChange sink so the App struct
  // body re-evaluates whenever any @Published property on the controller
  // fires. See controllerSubscription below.
  let controller = AwakeController()

  // AGENT: Holds the AnyCancellable for the controller → delegate
  // objectWillChange forwarding subscription. Must be stored as a property
  // or the subscription is immediately cancelled.
  private var controllerSubscription: AnyCancellable?

  /// Subscribes to the controller's change publisher so this delegate's own
  /// objectWillChange fires whenever the controller mutates. This keeps the
  /// App struct's body (which reads controller state for the menu bar label)
  /// in sync with every @Published change on the controller.
  override init() {
    super.init()
    // Forward controller changes through the delegate's objectWillChange.
    // The App struct observes the delegate via @NSApplicationDelegateAdaptor,
    // so this chain: controller change → delegate objectWillChange → App body re-run.
    controllerSubscription = controller.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.objectWillChange.send() }
  }

  /// Called by AppKit when the app receives a URL to open (kAEGetURL Apple Event).
  /// This fires for both cold launch (URL queued before app started) and
  /// hot open (URL delivered to running instance).
  func application(_ application: NSApplication, open urls: [URL]) {
    ipcLog.info("AppDelegate.application(_:open:) received \(urls.count) URL(s)")
    for url in urls {
      ipcLog.info("URL: \(url.absoluteString, privacy: .public)")
      guard let command = parseAwakeURL(url) else {
        ipcLog.warning("AppDelegate.application(_:open:): unrecognized or malformed URL — ignored")
        continue
      }
      // AGENT: Since the class is @MainActor, we are already on the main actor
      // here. No Task dispatch needed.
      switch command {
      case .activate(let id, let label, let duration):
        ipcLog.info("AppDelegate: activate session=\(id, privacy: .public) label=\(label, privacy: .public) duration=\(duration)")
        controller.activateIPCSession(id: id, label: label, duration: duration)
      case .deactivate(let id):
        ipcLog.info("AppDelegate: deactivate session=\(id, privacy: .public)")
        controller.deactivateIPCSession(id: id)
      }
    }
  }
}

// MARK: - App struct

/// Hosts the menu bar extra and shared observable app state.
@main
struct AwakeMenuBarApp: App {
  @NSApplicationDelegateAdaptor(AwakeAppDelegate.self) private var appDelegate
  @StateObject private var updater = AppUpdater()

  // AGENT: setActivationPolicy(.accessory) hides the app from the Dock and
  // Cmd-Tab switcher. This is standard for menu bar-only utilities. The
  // Info.plist also sets LSUIElement=true as a fallback.
  /// Configures the process to run as an accessory app without a Dock icon.
  init() {
    NSApplication.shared.setActivationPolicy(.accessory)
  }

  /// The controller is owned by the app delegate to ensure it exists before
  /// the first URL open event fires. The App struct accesses it via the delegate.
  private var controller: AwakeController { appDelegate.controller }

  /// Builds the menu bar scene for the app.
  var body: some Scene {
    MenuBarExtra {
      MenuContentView(controller: controller, updater: updater)
        // AGENT: onOpenURL is kept here as a secondary handler for forward
        // compatibility. On macOS versions where it does fire for MenuBarExtra,
        // it routes the URL. On macOS 26, AppDelegate.application(_:open:) is
        // the primary path. The two handlers are idempotent — an activate for
        // the same session ID is a no-op replacement.
        .onOpenURL { url in
          ipcLog.info("onOpenURL received: \(url.absoluteString, privacy: .public)")
          guard let command = parseAwakeURL(url) else {
            ipcLog.warning("onOpenURL: unrecognized or malformed URL — ignored")
            return
          }
          switch command {
          case .activate(let id, let label, let duration):
            ipcLog.info("onOpenURL: activate session=\(id, privacy: .public) label=\(label, privacy: .public) duration=\(duration)")
            controller.activateIPCSession(id: id, label: label, duration: duration)
          case .deactivate(let id):
            ipcLog.info("onOpenURL: deactivate session=\(id, privacy: .public)")
            controller.deactivateIPCSession(id: id)
          }
        }
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

// MARK: - IPC Logging

/// Shared logger for URL scheme IPC dispatch events. Subsystem matches the
/// bundle ID so Console.app and `log stream` can filter by subsystem + category.
private let ipcLog = Logger(subsystem: "com.akkio.apps.awake", category: "ipc")

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
