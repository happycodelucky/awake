// MARK: - AwakeMenuBarApp
// App entry point. Owns the NSStatusItem (menu bar icon) and NSPopover
// (SwiftUI content panel). Runs as an accessory app — no Dock icon.

import AppKit
import Combine
import SwiftUI
import os

// MARK: - App delegate

// AGENT: URL handling — SwiftUI's onOpenURL / .handlesExternalEvents require
// a window scene. In a MenuBarExtra-only or statusItem-only app they are
// no-ops and produce a warning. All URL routing is done via
// NSApplicationDelegate.application(_:open:) (AppKit's kAEGetURL path).
//
// AGENT: Menu bar icon update — the previous approach used SwiftUI's
// MenuBarExtra with an Image label and tried to drive re-renders via
// @Published + objectWillChange forwarding. SwiftUI's App struct body is
// not a View; its SceneBuilder label closure does not re-evaluate reliably
// when an @ObservedObject fires. The fix is to own the NSStatusItem directly
// and update its button image imperatively from a Combine sink. This is
// synchronous, immediate, and has no SwiftUI diffing in the path.
//
// AGENT: Popover — NSPopover hosting an NSHostingController<MenuContentView>
// gives us full SwiftUI inside the panel while keeping AppKit in control of
// show/hide. The popover is attached to the status item button, which is the
// standard macOS pattern for menu bar utilities.
@MainActor
final class AwakeAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

  // MARK: - Owned objects

  /// Status item in the system menu bar.
  private var statusItem: NSStatusItem?

  /// Popover that hosts the SwiftUI menu content panel.
  private var popover: NSPopover?

  /// Hosting controller for the SwiftUI content inside the popover.
  private var hostingController: NSHostingController<AnyView>?

  /// App updater state observed by the menu content view.
  private let updater = AppUpdater()

  // AGENT: sink must be stored; if it goes out of scope the subscription
  // is cancelled and the icon stops updating.
  private var managerSink: AnyCancellable?

  // MARK: - NSApplicationDelegate

  /// Sets up the status item, popover, and Combine observation on launch.
  func applicationDidFinishLaunching(_ notification: Notification) {
    // Apply saved appearance before anything renders.
    // AGENT: Must be after NSApplicationMain — NSApp is nil before this point.
    AwakeSessionManager.shared.applyAppearance()

    setupStatusItem()
    setupPopover()

    // Drive the icon image from the manager's published state.
    // AGENT: objectWillChange fires *before* the @Published property is
    // written. DispatchQueue.main.async defers the icon update to after
    // the current run-loop iteration, by which point all mutations have
    // been applied. This is the same async-hop pattern used for any
    // "read-after-willChange" scenario.
    managerSink = AwakeSessionManager.shared.objectWillChange.sink { [weak self] _ in
      DispatchQueue.main.async { self?.updateStatusItemImage() }
    }

    // Set initial icon state.
    updateStatusItemImage()
  }

  // MARK: - URL handling

  /// Routes `awake://` URLs to the session manager. Called by AppKit for
  /// both cold-launch (URL queued before app started) and hot-open events.
  func application(_ application: NSApplication, open urls: [URL]) {
    ipcLog.info("AppDelegate: received \(urls.count) URL(s)")
    for url in urls {
      ipcLog.info("URL: \(url.absoluteString, privacy: .public)")
      guard let command = parseAwakeURL(url) else {
        ipcLog.warning("AppDelegate: unrecognized or malformed URL — ignored")
        continue
      }
      switch command {
      case .activate(let id, let label, let duration):
        ipcLog.info("AppDelegate: activate id=\(id, privacy: .public) label=\(label, privacy: .public) duration=\(duration)")
        AwakeSessionManager.shared.activateIPCSession(id: id, label: label, duration: duration)
      case .deactivate(let id):
        ipcLog.info("AppDelegate: deactivate id=\(id, privacy: .public)")
        AwakeSessionManager.shared.deactivateIPCSession(id: id)
      }
    }
  }

  // MARK: - Status item

  /// Creates the `NSStatusItem` and wires its button click to toggle the popover.
  private func setupStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.target = self
    item.button?.action = #selector(togglePopover(_:))
    item.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
    statusItem = item
  }

  /// Updates the status item button image to reflect the current session state.
  ///
  /// Called immediately on launch and after every manager state change via the
  /// Combine sink. Reads directly from `AwakeSessionManager.shared`.
  private func updateStatusItemImage() {
    let manager = AwakeSessionManager.shared
    let iconName = manager.powerAssertionIsActive ? "mug.fill" : "mug"
    let clockText = manager.hasSession ? manager.menuBarClockText : nil
    let image = compositeMenuBarImage(iconName: iconName, badgeText: clockText)
    statusItem?.button?.image = image
  }

  // MARK: - Popover

  /// Creates the `NSPopover` containing the SwiftUI menu content.
  private func setupPopover() {
    let manager = AwakeSessionManager.shared
    // AGENT: AnyView wrapping avoids the generic parameter leaking into the
    // stored hostingController type. The content view observes the manager
    // directly as @ObservedObject, so it re-renders on all @Published changes.
    let contentView = AnyView(MenuContentView(manager: manager, updater: updater))
    let hosting = NSHostingController(rootView: contentView)
    hosting.sizingOptions = .preferredContentSize
    hostingController = hosting

    let pop = NSPopover()
    pop.contentViewController = hosting
    pop.behavior = .transient
    pop.animates = true
    popover = pop
  }

  /// Toggles the popover open or closed relative to the status item button.
  @objc private func togglePopover(_ sender: AnyObject?) {
    guard let button = statusItem?.button, let popover else { return }
    if popover.isShown {
      popover.performClose(sender)
    } else {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      // Bring the popover's window to front so key events (e.g. Option key
      // monitoring) work correctly when the popover is first opened.
      popover.contentViewController?.view.window?.makeKey()
    }
  }
}

// MARK: - App entry point

/// Configures the process and installs the app delegate.
///
/// Uses `@NSApplicationDelegateAdaptor` so AppKit manages delegate lifetime.
/// No `MenuBarExtra` scene — the status item and popover are owned by the
/// delegate directly.
@main
struct AwakeMenuBarApp: App {
  @NSApplicationDelegateAdaptor(AwakeAppDelegate.self) private var appDelegate

  /// Hides the app from the Dock and Cmd-Tab switcher on startup.
  // AGENT: LSUIElement=true in Info.plist covers the initial launch moment
  // before this init runs. setActivationPolicy(.accessory) is belt-and-suspenders.
  init() {
    NSApplication.shared.setActivationPolicy(.accessory)
  }

  /// An empty scene body — all UI is driven by the AppDelegate's NSStatusItem
  /// and NSPopover. SwiftUI requires at least one scene, so we provide a no-op.
  // AGENT: Settings scene would go here if we ever need a standalone window.
  var body: some Scene {
    // Intentionally empty — status item + popover are managed by AwakeAppDelegate.
    Settings { EmptyView() }
  }
}

// MARK: - IPC logging

/// Shared logger for URL scheme IPC dispatch events.
private let ipcLog = Logger(subsystem: "com.happycodelucky.apps.awake", category: "ipc")

// MARK: - Menu bar image compositing

/// Composites an SF Symbol icon and optional pill badge into a single NSImage
/// suitable for use as a menu bar status item image.
///
/// - Parameters:
///   - iconName: SF Symbol name for the icon (e.g. `"mug"` or `"mug.fill"`).
///   - badgeText: Optional countdown text displayed inside a pill. Pass `nil` to omit.
/// - Returns: A composited `NSImage` sized for the menu bar.
private func compositeMenuBarImage(
  iconName: String,
  badgeText: String?
) -> NSImage {
  let iconHeight: CGFloat = 16
  let spacing: CGFloat = 4
  let hPad: CGFloat = 6
  let vPad: CGFloat = 2

  // --- Icon ---
  // AGENT: NSImage(systemSymbolName:) with a point-size configuration gives a
  // consistently sized SF Symbol. Template images respect menu bar vibrancy
  // automatically; we composite them with labelColor to match system style.
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
    badgeSize = CGSize(
      width: measuredSize.width + hPad * 2,
      height: measuredSize.height + vPad * 2
    )
    attrString = str
  }

  // --- Canvas size ---
  let totalWidth = badgeText != nil
    ? iconSize.width + spacing + badgeSize.width
    : iconSize.width
  let totalHeight = max(iconSize.height, badgeSize.height)
  let imageSize = NSSize(width: ceil(totalWidth), height: ceil(totalHeight))

  // --- Draw ---
  // AGENT: NSImage(size:flipped:drawingHandler:) handles retina scaling
  // automatically via the backing store.
  let image = NSImage(size: imageSize, flipped: false) { rect in
    // Draw icon centered vertically.
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
      let pillPath = NSBezierPath(
        roundedRect: pillRect,
        xRadius: badgeSize.height / 2,
        yRadius: badgeSize.height / 2
      )

      NSColor.labelColor.withAlphaComponent(0.85).setFill()
      pillPath.fill()

      let textX = pillX + hPad
      let textY = pillY + vPad

      // Knock the text out of the pill using destinationOut blend mode so it
      // reads as a "cut-out" that inherits the menu bar background color.
      if let ctx = NSGraphicsContext.current?.cgContext {
        ctx.saveGState()
        ctx.setBlendMode(.destinationOut)
        attrString.draw(at: NSPoint(x: textX, y: textY))
        ctx.restoreGState()
      }
    }

    return true
  }

  // AGENT: isTemplate = false — we manage our own color treatment.
  // Setting true would cause the menu bar to override colors with vibrancy.
  image.isTemplate = false
  return image
}

/// Returns a rounded-design bold system font at the given point size.
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
