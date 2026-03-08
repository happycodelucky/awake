import AppKit
import SwiftUI

@main
struct AwakeMenuBarApp: App {
    @StateObject private var controller = AwakeController()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(controller: controller)
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

    private var menuBarIconName: String {
        controller.powerAssertionIsActive ? "mug.fill" : "mug"
    }

    private var menuBarIconColor: Color {
        if controller.powerAssertionIsActive {
            return .green
        }
        return .primary
    }

    private var menuBarPillColor: Color {
        if controller.powerAssertionIsActive {
            return .green.opacity(0.16)
        }
        return .primary.opacity(0.12)
    }
}
