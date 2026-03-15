//
//  AwakeAppDelegate.swift
//  Awake
//
//  Created by Paul Bates on 3/11/26.
//

import ObjectiveC
import AppKit
import Combine
import OSLog


// MARK: - App delegate

// AGENT: URL handling — SwiftUI's onOpenURL / .handlesExternalEvents require
// a window scene. In a MenuBarExtra-only app they are no-ops and produce a
// warning. All URL routing is done via
// NSApplicationDelegate.application(_:open:) (AppKit's kAEGetURL path).
//
// AGENT: Menu bar icon update — SwiftUI's App struct body is not a View; its
// SceneBuilder label closure does not re-evaluate reliably when an
// @ObservedObject fires. The fix is to find the NSStatusItem that MenuBarExtra
// creates internally and update its .button?.image imperatively from a Combine
// sink on KeepAwakeSessionsManager.shared.objectWillChange. This gives synchronous,
// immediate icon updates with no SwiftUI diffing in the path, while keeping
// MenuBarExtra's native panel behaviour (.window style = HUDWindow material).
//
// AGENT: Finding the status item — MenuBarExtra creates its NSStatusItem
// before applicationDidFinishLaunching returns. After setup we search
// NSStatusBar.system.statusItems for the item whose button has no image yet
// (i.e. it was just created and hasn't been given a custom image). We then
// set the image ourselves and hold a reference to update it going forward.
@MainActor
final class AwakeAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    /// App updater owned here so it survives for the app lifetime and can be
    /// passed into MenuContentView via the App struct.
    let updater = AppUpdater()
    
    /// Storage for any cancellables added
    private var cancellables: Set<AnyCancellable> = []
    
    /// Reference to the NSStatusItem created by MenuBarExtra. Populated in
    /// applicationDidFinishLaunching after MenuBarExtra has had a chance to
    /// create it.
    private weak var statusItem: NSStatusItem?
    
    
    // MARK: NSApplicationDelegate
    
    
    /// Sets up Combine observation and performs the initial icon update.
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply saved appearance now that NSApp is fully initialized.
        // AGENT: Cannot be called earlier — NSApp is nil before NSApplicationMain.
        KeepAwakeSessionsManager.shared.applyAppearance()
        
        // Find the NSStatusItem MenuBarExtra created and take a reference.
        // AGENT: NSStatusBar does not expose a public `statusItems` property in
        // Swift. We access the internal list via KVC (`value(forKey:)`) which
        // returns an NSPointerArray of weak NSStatusItem refs. MenuBarExtra
        // creates exactly one item before applicationDidFinishLaunching returns,
        // so the last (or only) pointer in the array is ours.
        if let ptrArray = NSStatusBar.system.value(forKey: "statusItems") as? NSPointerArray,
           ptrArray.count > 0,
           let ptr = ptrArray.pointer(at: ptrArray.count - 1) {
            statusItem = Unmanaged<NSStatusItem>.fromOpaque(ptr).takeUnretainedValue()
        }
        
        // Drive the icon from the manager's clock tick.
        // AGENT: objectWillChange fires *before* each @Published property is
        // written and fires once per mutation. A single clock tick writes several
        // @Published properties (now, managedPolicyState, ipcSessions when pruning,
        // etc.), scheduling multiple async hops that read intermediate states and
        // cause the icon to flicker between mug / mug.fill.
        //
        // Subscribing to $now avoids this: it is a single signal per clock tick,
        // fires *after* `now` is written, and all computed properties
        // (menuBarClockText, powerAssertionIsActive, hasSession) read from the
        // fully-settled state by the time the sink body runs on the main actor.
        //
        // For immediate icon updates on start/stop/pause/IPC (which happen
        // outside the clock tick), we also update from any powerAssertionIsActive
        // change via a second sink. Both sinks are combined into one stored value.
        let manager = KeepAwakeSessionsManager.shared
        manager.$now
            .merge(with: manager.$powerAssertionIsActive.map { _ in Date() })
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItemImage() }
            .store(in: &cancellables)
        
        // Set the initial icon state immediately.
        updateStatusItemImage()
    }
    
    /// Routes `awake://` URLs to the session manager. Called by AppKit for
    /// both cold-launch (URL queued before app started) and hot-open events.
    func application(_ application: NSApplication, open urls: [URL]) {
        Logger.apis.info("AppDelegate: received \(urls.count) URL(s)")
        for url in urls {
            Logger.apis.info("URL: \(url.absoluteString, privacy: .public)")
            guard let command = parseAwakeURL(url) else {
                Logger.apis.warning("AppDelegate: unrecognized or malformed URL — ignored")
                continue
            }
            switch command {
            case .activate(let id, let label, let duration):
                Logger.apis.info("AppDelegate: activate id=\(id, privacy: .public) label=\(label, privacy: .public) duration=\(duration)")
                KeepAwakeSessionsManager.shared.activateIPCSession(id: id, label: label, duration: duration)
            case .deactivate(let id):
                Logger.apis.info("AppDelegate: deactivate id=\(id, privacy: .public)")
                KeepAwakeSessionsManager.shared.deactivateIPCSession(id: id)
            }
        }
    }
    
    /// Updates the status item button image to reflect the current session state.
    private func updateStatusItemImage() {
        let manager = KeepAwakeSessionsManager.shared
        let iconName = manager.powerAssertionIsActive ? "mug.fill" : "mug"
        let clockText = manager.hasSession ? manager.menuBarClockText : nil
        let image = compositeMenuBarImage(iconName: iconName, badgeText: clockText)
        statusItem?.button?.image = image
    }
    
    // MARK: - URL handling

}

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
