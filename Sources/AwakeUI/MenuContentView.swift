// MARK: - MenuContentView
// Menu bar popover layout: preset grid, timer hero, behavior toggle,
// policy warnings, update notices, and modifier-key observation.

import AppKit
import SwiftUI

@MainActor
/// Tracks modifier-key state so the menu can switch button behavior dynamically.
final class ModifierKeyObserver: ObservableObject {
  @Published private(set) var isOptionPressed = false

  // AGENT: localMonitor is nonisolated(unsafe) because NSEvent.addLocalMonitorForEvents
  // returns an opaque token that AppKit manages. The monitor is added in init and
  // removed in deinit — no concurrent mutation occurs.
  nonisolated(unsafe) private var localMonitor: Any?

  /// Starts observing local modifier-flag changes.
  init() {
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
      self?.isOptionPressed = event.modifierFlags.contains(.option)
      return event
    }
  }

  /// Stops the local modifier monitor when the observer is released.
  deinit {
    if let localMonitor {
      NSEvent.removeMonitor(localMonitor)
    }
  }

  /// Refreshes the cached Option-key state from the current event flags.
  func refresh() {
    isOptionPressed = NSEvent.modifierFlags.contains(.option)
  }
}

/// Renders the menu bar popover content for timer control, behavior, and updates.
public struct MenuContentView: View {
  @ObservedObject var controller: AwakeController
  @ObservedObject var updater: AppUpdater
  @Environment(\.colorScheme) private var colorScheme
  @StateObject private var modifierKeys = ModifierKeyObserver()

  private let columns = [
    GridItem(.flexible(), spacing: 8),
    GridItem(.flexible(), spacing: 8),
    GridItem(.flexible(), spacing: 8),
  ]

  /// Builds the full menu content shown from the menu bar extra.
  public var body: some View {
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
      ).padding([.vertical], 8)

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

      if let notice = updater.notice {
        VStack(alignment: .leading, spacing: 10) {
          Text("Update")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(1.4)

          UpdateNoticeCard(
            notice: notice,
            primaryAction: { updater.installUpdate() },
            secondaryAction: { updater.dismissNotice() }
          )
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
            Text(
              "Turn off for long background runs when the Mac should stay awake but the screen can sleep."
            )
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

      HStack(spacing: 8) {
        Button("Quit") {
          NSApplication.shared.terminate(nil)
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(FooterButtonStyle())

        /// Settings button — placeholder for future settings UI.
        Button {
          // TODO: Open settings
        } label: {
          Image(systemName: "gearshape.fill")
        }
        .buttonStyle(FooterIconButtonStyle())
        .help("Settings")
      }
    }
    .padding(14)
    .frame(width: 312)
    .onAppear {
      modifierKeys.refresh()
    }
  }

  /// Creates the menu content view.
  /// - Parameters:
  ///   - controller: The timer controller backing the UI.
  ///   - updater: The updater state backing update notices.
  public init(controller: AwakeController, updater: AppUpdater) {
    self.controller = controller
    self.updater = updater
  }

  /// Returns the accent gradient shared by active-state treatments.
  private var accentGradient: AnyShapeStyle {
    AnyShapeStyle(
      LinearGradient(
        colors: colorScheme == .dark ? [Color.cyan, Color.green] : [Color.blue, Color.teal],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    )
  }

  /// Returns the short status label shown in the header badge.
  private var statusTitle: String {
    if controller.isPaused {
      return "Paused"
    }
    if controller.isActive {
      return "Active"
    }
    return "Idle"
  }

  /// Returns the SF Symbol used by the header badge.
  private var statusSymbol: String {
    if controller.isPaused {
      return "pause.fill"
    }
    if controller.isActive {
      return "bolt.fill"
    }
    return "moon.zzz.fill"
  }

  /// Returns the visual style used by the header badge.
  private var statusStyle: AnyShapeStyle {
    if controller.isPaused {
      return AnyShapeStyle(Color.orange)
    }
    if controller.isActive {
      return accentGradient
    }
    return AnyShapeStyle(.secondary)
  }

  /// Returns the descriptive line shown beneath the main timer value.
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

  /// Bridges controller sleep behavior into a toggle-friendly binding.
  private var keepDisplayAwakeBinding: Binding<Bool> {
    Binding(
      get: { controller.keepsDisplayAwake },
      set: { controller.setKeepsDisplayAwake($0) }
    )
  }

  @ViewBuilder
  /// Builds the context-sensitive action button beside the timer value.
  /// Both paused and active states respond to the Option key: holding ⌥
  /// reveals the alternate action (stop while paused, pause while active).
  private var heroActionButton: some View {
    if controller.isPaused {
      Button {
        if modifierKeys.isOptionPressed {
          controller.stop()
        } else {
          controller.resume()
        }
      } label: {
        CircleActionIcon(
          symbolName: modifierKeys.isOptionPressed ? "xmark" : "play.fill",
          fillColor: modifierKeys.isOptionPressed ? .red : .orange
        )
      }
      .buttonStyle(.plain)
      .help(modifierKeys.isOptionPressed ? "Stop session" : "Resume — Hold ⌥ to stop")
      .transition(.scale.combined(with: .opacity))
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
      .help(modifierKeys.isOptionPressed ? "Pause session" : "Stop — Hold ⌥ to pause")
      .transition(.scale.combined(with: .opacity))
    }
  }

  /// Formats the compact title shown on a preset button.
  /// - Parameter preset: The preset being rendered.
  /// - Returns: A short duration label.
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

  /// Returns the supporting category label for a preset button.
  /// - Parameter preset: The preset being rendered.
  /// - Returns: A short descriptive subtitle.
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

#if DEBUG
  /// Wraps the menu content in a preview-friendly container.
  private struct MenuContentPreviewContainer: View {
    let controller: AwakeController
    let updater: AppUpdater

    /// Builds the preview container layout.
    var body: some View {
      MenuContentView(controller: controller, updater: updater)
        .padding()
        .frame(width: 340)
    }
  }

  private let previewManagedPolicyState = AwakeController.ManagedPolicyState(
    screenSaverIdleTime: 900,
    loginWindowIdleTime: 300,
    asksForPasswordAfterScreenSaver: true,
    askForPasswordDelay: 0,
    autoLogoutDelay: 7200,
    disablesAutoLogin: true
  )

  #Preview("Menu · Timer Off") {
    MenuContentPreviewContainer(
      controller: AwakeController(previewState: .idle()),
      updater: AppUpdater(previewNotice: nil)
    )
  }

  #Preview("Menu · 2h Timer") {
    MenuContentPreviewContainer(
      controller: AwakeController(
        previewState: .active(
          remaining: 2 * 3600,
          sessionDuration: 2 * 3600
        )),
      updater: AppUpdater(previewNotice: nil)
    )
  }

  #Preview("Menu · 11:59 with Policy Warning") {
    MenuContentPreviewContainer(
      controller: AwakeController(
        previewState: .active(
          remaining: 11 * 3600 + 59 * 60,
          sessionDuration: 12 * 3600,
          policyState: previewManagedPolicyState
        )),
      updater: AppUpdater(previewNotice: nil)
    )
  }

  #Preview("Menu · 29s Remaining") {
    MenuContentPreviewContainer(
      controller: AwakeController(
        previewState: .active(
          remaining: 29,
          sessionDuration: 30 * 60,
          keepsDisplayAwake: false
        )),
      updater: AppUpdater(previewNotice: nil)
    )
    .preferredColorScheme(.dark)
  }

  #Preview("Menu · Paused") {
    MenuContentPreviewContainer(
      controller: AwakeController(
        previewState: .paused(
          remaining: 2 * 3600,
          sessionDuration: 4 * 3600
        )),
      updater: AppUpdater(previewNotice: nil)
    )
  }

  #Preview("Menu · Update Alert") {
    MenuContentPreviewContainer(
      controller: AwakeController(
        previewState: .active(
          remaining: 45 * 60,
          sessionDuration: 60 * 60
        )),
      updater: AppUpdater(
        previewNotice: .preview(
          kind: .readyToInstall,
          title: "Update ready",
          message: "Version 1.3.0 is ready to install.",
          version: "1.3.0",
          primaryActionTitle: "Install update"
        )
      )
    )
  }
#endif
