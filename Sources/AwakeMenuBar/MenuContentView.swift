import AppKit
import SwiftUI

@MainActor
final class ModifierKeyObserver: ObservableObject {
    @Published private(set) var isOptionPressed = false

    nonisolated(unsafe) private var localMonitor: Any?

    init() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.isOptionPressed = event.modifierFlags.contains(.option)
            return event
        }
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    func refresh() {
        isOptionPressed = NSEvent.modifierFlags.contains(.option)
    }
}

struct MenuContentView: View {
    @ObservedObject var controller: AwakeController
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var modifierKeys = ModifierKeyObserver()

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Awake")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text(controller.pulseStatusLine)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Label(statusTitle, systemImage: statusSymbol)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(statusStyle)
            }

            TimerHeroView(
                timeText: controller.formattedRemaining(),
                statusText: controller.isPaused ? "PAUSED" : (controller.isActive ? "TIME LEFT" : "READY"),
                detailText: heroDetailText,
                progress: controller.progress,
                isActive: controller.hasSession,
                colorScheme: colorScheme,
                actionButton: AnyView(heroActionButton)
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("Presets")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.4)

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(controller.presets, id: \.minutes) { preset in
                        Button {
                            controller.start(minutes: preset.minutes)
                        } label: {
                            VStack(spacing: 2) {
                                Text(presetButtonTitle(for: preset))
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                Text(presetButtonSubtitle(for: preset))
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                        }
                        .buttonStyle(PresetButtonStyle())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Behavior")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.4)

                if let policyNotice = controller.behaviorPolicyNotice {
                    PolicyWarningCard(
                        title: policyNotice.title,
                        known: policyNotice.known,
                        possible: policyNotice.possible
                    )
                }

                Toggle(isOn: keepDisplayAwakeBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep display awake")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text("Turn off for long background runs when the Mac should stay awake but the screen can sleep.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.12))
                )
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(FooterButtonStyle())
        }
        .padding(14)
        .frame(width: 312)
        .onAppear {
            modifierKeys.refresh()
        }
    }

    private var accentGradient: AnyShapeStyle {
        AnyShapeStyle(
            LinearGradient(
                colors: colorScheme == .dark ? [Color.cyan, Color.green] : [Color.blue, Color.teal],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var statusTitle: String {
        if controller.isPaused {
            return "Paused"
        }
        if controller.isActive {
            return "Active"
        }
        return "Idle"
    }

    private var statusSymbol: String {
        if controller.isPaused {
            return "pause.fill"
        }
        if controller.isActive {
            return "bolt.fill"
        }
        return "moon.zzz.fill"
    }

    private var statusStyle: AnyShapeStyle {
        if controller.isPaused {
            return AnyShapeStyle(Color.orange)
        }
        if controller.isActive {
            return accentGradient
        }
        return AnyShapeStyle(.secondary)
    }

    private var heroDetailText: String {
        if controller.isPaused {
            return "Resume or pick a new timer"
        }
        if controller.isActive {
            if controller.powerAssertionIsActive {
                return controller.keepsDisplayAwake
                    ? "macOS will keep the display on for this session"
                    : "macOS will keep background work running while the display can sleep"
            }
            return "macOS could not acquire the power assertion"
        }
        return "Choose a timer to begin"
    }

    private var keepDisplayAwakeBinding: Binding<Bool> {
        Binding(
            get: { controller.keepsDisplayAwake },
            set: { controller.setKeepsDisplayAwake($0) }
        )
    }

    @ViewBuilder
    private var heroActionButton: some View {
        if controller.isPaused {
            Button {
                controller.resume()
            } label: {
                CircleActionIcon(symbolName: "play.fill", fillColor: .orange)
            }
            .buttonStyle(.plain)
            .help("Resume")
        } else if controller.isActive {
            Button {
                if modifierKeys.isOptionPressed {
                    controller.pause()
                } else {
                    controller.stop()
                }
            } label: {
                CircleActionIcon(
                    symbolName: modifierKeys.isOptionPressed ? "pause.fill" : "xmark",
                    fillColor: modifierKeys.isOptionPressed ? .orange : .red
                )
            }
            .buttonStyle(.plain)
            .help(modifierKeys.isOptionPressed ? "Pause" : "Stop")
        }
    }

    private func presetButtonTitle(for preset: (label: String, minutes: Int)) -> String {
        switch preset.minutes {
        case 60:
            return "1h"
        case 2 * 60:
            return "2h"
        case 4 * 60:
            return "4h"
        case 8 * 60:
            return "8h"
        case 12 * 60:
            return "12h"
        default:
            return "\(preset.minutes)m"
        }
    }

    private func presetButtonSubtitle(for preset: (label: String, minutes: Int)) -> String {
        if preset.minutes < 60 {
            return "quick"
        }
        if preset.minutes == 60 {
            return "focus"
        }
        return "long"
    }
}
