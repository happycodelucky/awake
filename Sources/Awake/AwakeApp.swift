// Application entry point. Hosts the MenuBarExtra scene (native macOS panel) and
// drives the menu bar icon via a direct NSStatusItem reference.
// Runs as an accessory app — no Dock icon.

import AppKit
import Combine
import SwiftUI
import os


extension EnvironmentValues {
    @Entry var designTokens: DesignTokens = .light
}



// MARK: - App entry point

/// Hosts the MenuBarExtra scene and installs the app delegate.
@main
struct AwakeMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AwakeAppDelegate.self) private var appDelegate
    
    /// Color scheme to update design tokens
    @Environment(\.colorScheme) var colorScheme
    
    private var manager: KeepAwakeSessionsManager { KeepAwakeSessionsManager.shared }
    
    /// Hides the app from the Dock and Cmd-Tab switcher.
    // AGENT: LSUIElement=true in Info.plist covers the initial launch moment.
    // setActivationPolicy(.accessory) is belt-and-suspenders.
    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
    
    var body: some Scene {
        MenuBarExtra {
            // AGENT: MenuContentView observes AwakeSessionManager.shared directly
            // as @ObservedObject. Since it is a View (not an App), SwiftUI's normal
            // observation graph works correctly here and re-renders on every
            // @Published change from the manager.
            MenuContentView(manager: manager, updater: appDelegate.updater)
        } label: {
            // AGENT: This Image is the initial placeholder SwiftUI renders before
            // applicationDidFinishLaunching fires. The AppDelegate then takes the
            // NSStatusItem reference and replaces the button image imperatively via
            // updateStatusItemImage(). After that point the label closure is never
            // re-evaluated by SwiftUI — AppKit owns the image going forward.
            Image(systemName: "mug")
        }
        .menuBarExtraStyle(.window)
        .environment(\.designTokens, colorScheme == .dark ? .dark : .light)
    }
}

// MARK: - IPC logging

/// Shared logger for URL scheme IPC dispatch events.
private let ipcLog = Logger(subsystem: "com.happycodelucky.apps.awake", category: "ipc")
