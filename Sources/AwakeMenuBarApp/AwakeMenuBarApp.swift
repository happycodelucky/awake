import AppKit
import AwakeUI
import SwiftUI

/// Hosts the menu bar extra and shared observable app state.
@main
struct AwakeMenuBarApp: App {
  @StateObject private var controller = AwakeController()
  @StateObject private var updater = AppUpdater()

  /// Configures the process to run as an accessory app without a Dock icon.
  init() {
    NSApplication.shared.setActivationPolicy(.accessory)
  }

  /// Builds the menu bar scene for the app.
  var body: some Scene {
    MenuBarExtra {
      MenuContentView(controller: controller, updater: updater)
    } label: {
      HStack(spacing: 10) {
        Image(systemName: menuBarIconName)
          .symbolRenderingMode(.monochrome)
          .foregroundStyle(menuBarIconColor)

        if controller.hasSession {
          Text(controller.menuBarClockText)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .frame(width: 42, alignment: .center)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
              Capsule(style: .continuous)
                .fill(menuBarPillColor)
            )
        }
      }
    }
    .menuBarExtraStyle(.window)
  }

  /// Returns the menu bar icon name for the current assertion state.
  private var menuBarIconName: String {
    controller.powerAssertionIsActive ? "mug.fill" : "mug"
  }

  /// Returns the tint applied to the menu bar icon.
  private var menuBarIconColor: Color {
    if controller.powerAssertionIsActive {
      return .green
    }
    return .primary
  }

  /// Returns the background color used behind the countdown text.
  private var menuBarPillColor: Color {
    if controller.powerAssertionIsActive {
      return .green.opacity(0.16)
    }
    return .primary.opacity(0.12)
  }
}
