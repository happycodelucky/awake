// MARK: - MenuContentView
// Menu bar popover layout: preset grid, timer hero, settings panel,
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

/// Renders the menu bar popover content for timer control, settings, and updates.
struct MenuContentView: View {
  @ObservedObject var manager: KeepAwakeSessionsManager
  @ObservedObject var updater: AppUpdater
  @Environment(\.colorScheme) private var colorScheme
    @Environment(\.designTokens) private var designTokens
  @StateObject private var modifierKeys = ModifierKeyObserver()
  @State private var showingSettings = false

  private var columns: [GridItem] {
    let spacing = designTokens.spacing.sm
    return [
      GridItem(.flexible(), spacing: spacing),
      GridItem(.flexible(), spacing: spacing),
      GridItem(.flexible(), spacing: spacing),
    ]
  }

  /// Builds the full menu content shown from the menu bar extra.
  /// The header and hero timer are always visible. Below them, the view
  /// conditionally shows either the main timer controls or the settings panel.
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .top) {
          Text("Awake")
            .font(designTokens.typography.titleLarge)

          Spacer(minLength: 12)
          Label(statusTitle, systemImage: statusSymbol)
            .font(designTokens.typography.labelMedium)
            .foregroundStyle(statusStyle)
        }
        Text(manager.pulseStatusLine)
          .lineLimit(2)
          .font(designTokens.typography.bodyMedium)
          .foregroundStyle(.secondary)
      }

      TimerHeroView(
        timeText: manager.formattedRemaining(),
        statusText: manager.isPaused ? "PAUSED" : (manager.isActive ? "TIME LEFT" : "READY"),
        detailText: heroDetailText,
        progress: manager.progress,
        isActive: manager.hasSession,
        colorScheme: colorScheme,
        actionButton: { heroActionButton }
      ).padding([.vertical], 8)

      if showingSettings {
        settingsContent
      } else {
        mainContent
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
  ///   - manager: The session manager backing the UI.
  ///   - updater: The updater state backing update notices.
  init(manager: KeepAwakeSessionsManager, updater: AppUpdater) {
    self.manager = manager
    self.updater = updater
  }

  /// Returns the accent gradient shared by active-state treatments.
  private var accentGradient: LinearGradient {
    LinearGradient(
      colors: colorScheme == .dark ? [Color.cyan, Color.green] : [Color.accentColor, Color.teal],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  /// Returns the short status label shown in the header badge.
  private var statusTitle: String {
    if manager.isPaused { "Paused" }
    else if manager.isActive { "Active" }
    else { "Idle" }
  }

  /// Returns the SF Symbol used by the header badge.
  private var statusSymbol: String {
    if manager.isPaused { "pause.fill" }
    else if manager.isActive { "bolt.fill" }
    else { "moon.zzz.fill" }
  }

  /// Returns the visual style used by the header badge.
  private var statusStyle: AnyShapeStyle {
    if manager.isPaused {
      AnyShapeStyle(Color.orange)
    } else if manager.isActive {
      AnyShapeStyle(accentGradient)
    } else {
      AnyShapeStyle(.secondary)
    }
  }

  /// Returns the descriptive line shown beneath the main timer value.
  private var heroDetailText: String {
    if manager.isPaused {
      return "Resume or Hold ⌥ to stop"
    }
    if manager.isActive {
      // AGENT: When only external sessions are active (no app session), show a
      // hint that external callers are driving the awake state.
      if !manager.hasAppSession && manager.hasIPCSessions {
        return "Kept awake by external sessions"
      }
      return manager.powerAssertionIsActive
        ? "Hold ⌥ to pause"
        : "macOS could not acquire the power assertion"
    }
    return "Choose a timer to begin"
  }

  // MARK: - Main content

  /// Builds the main timer control content: presets, update notice, policy
  /// warnings, and footer with Quit / Settings buttons.
  @ViewBuilder
  private var mainContent: some View {
    if manager.hasIPCSessions {
      KeepAwakeSessionList(
        sessions: Array(manager.ipcSessions.values).sorted(by: { $0.endDate > $1.endDate }),
        now: manager.now,
        // AGENT: withAnimation wraps the deactivation mutation so SwiftUI
        // runs the row's .transition removal animation. Without this wrapper
        // the @Published change fires outside any animation transaction and
        // the row disappears instantly.
        onDeactivate: { id in withAnimation { manager.deactivateIPCSession(id: id) } }
      )
    }

    VStack(alignment: .leading, spacing: 10) {
      Text("Presets")
        .font(designTokens.typography.sectionHeader)
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .tracking(1.4)

      LazyVGrid(columns: columns, spacing: 8) {
        ForEach(manager.presets) { preset in
          Button {
            manager.start(minutes: preset.minutes)
          } label: {
            VStack(spacing: 2) {
              Text(preset.shortLabel)
                .font(designTokens.typography.titleMedium)
              Text(preset.mode)
                .font(designTokens.typography.bodySmall)
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
          .font(designTokens.typography.sectionHeader)
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
        .font(designTokens.typography.sectionHeader)
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .tracking(1.4)

      if let policyNotice = manager.behaviorPolicyNotice {
        PolicyWarningCard(
          title: policyNotice.title,
          known: policyNotice.known,
          possible: policyNotice.possible
        )
      }

        Toggle(isOn: keepDisplayAwakeBinding) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Keep display awake")
              .font(designTokens.typography.titleSmall)
            Text(
              "Turn off for long background runs when the Mac should stay awake but the screen can sleep."
            )
            .font(designTokens.typography.bodySmall)
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

      Button("Settings", systemImage: "gearshape.fill") {
        showingSettings = true
      }
      .labelStyle(.iconOnly)
      .buttonStyle(FooterIconButtonStyle())
    }
  }

  // MARK: - Settings content

  /// Builds the settings panel with grouped sections for General and
  /// MCP Server. Shown when the gear icon is tapped.
  @ViewBuilder
  private var settingsContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      // --- General (login item + appearance) ---
      settingsSection("General") {
        SettingsGroupBox {
          VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: launchAtLoginBinding) {
              VStack(alignment: .leading, spacing: 2) {
                Text("Start at login")
                  .font(designTokens.typography.titleSmall)
                Text("Automatically launch Awake when you log in to your Mac.")
                  .font(designTokens.typography.bodySmall)
                  .foregroundStyle(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
            .toggleStyle(.switch)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
              Text("Appearance")
                .font(designTokens.typography.titleSmall)

              Picker("Theme", selection: appearanceModeBinding) {
                ForEach(KeepAwakeSessionsManager.AppearanceMode.allCases, id: \.self) { mode in
                  Text(mode.label).tag(mode)
                }
              }
              .pickerStyle(.segmented)
            }
          }
        }
      }

      // --- MCP Server (placeholder) ---
      settingsSection("MCP Server") {
        SettingsGroupBox {
          VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: .constant(false)) {
              VStack(alignment: .leading, spacing: 2) {
                Text("Enable MCP server")
                  .font(designTokens.typography.titleSmall)
                Text(
                  "Allow AI agents to control Awake sessions over the Model Context Protocol."
                )
                .font(designTokens.typography.bodySmall)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
              }
            }
            .toggleStyle(.switch)
            .disabled(true)

            HStack {
              Text("Port")
                .font(designTokens.typography.titleSmall)
              Spacer()
              TextField("", text: .constant("9432"))
                .font(designTokens.typography.titleSmall)
                .frame(width: 60)
                .textFieldStyle(.roundedBorder)
            }
            .disabled(true)

            Text("Coming soon")
              .font(designTokens.typography.bodySmall)
              .foregroundStyle(.tertiary)
          }
        }
        .opacity(0.6)
      }

      // --- Done ---
      Button("Done") {
        showingSettings = false
      }
      .buttonStyle(DoneButtonStyle())
    }
  }

  /// Builds a labelled settings section with a section heading and content.
  /// - Parameters:
  ///   - title: The section heading text.
  ///   - content: The section content.
  private func settingsSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(designTokens.typography.sectionHeader)
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .tracking(1.4)

      content()
    }
  }

  // MARK: - Bindings

  /// Bridges controller sleep behavior into a toggle-friendly binding.
  private var keepDisplayAwakeBinding: Binding<Bool> {
    Binding(
      get: { manager.keepsDisplayAwake },
      set: { manager.setKeepsDisplayAwake($0) }
    )
  }

  /// Bridges controller launch-at-login state into a toggle-friendly binding.
  private var launchAtLoginBinding: Binding<Bool> {
    Binding(
      get: { manager.launchAtLogin },
      set: { manager.setLaunchAtLogin($0) }
    )
  }

  /// Bridges controller appearance mode into a picker-friendly binding.
  private var appearanceModeBinding: Binding<KeepAwakeSessionsManager.AppearanceMode> {
    Binding(
      get: { manager.appearanceMode },
      set: { manager.setAppearanceMode($0) }
    )
  }

  @ViewBuilder
  /// Builds the context-sensitive action button beside the timer value.
  /// Both paused and active states respond to the Option key: holding ⌥
  /// reveals the alternate action (stop while paused, pause while active).
  private var heroActionButton: some View {
    if manager.isPaused {
      Button {
        if modifierKeys.isOptionPressed {
          manager.stop()
        } else {
          manager.resume()
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
    } else if manager.isActive {
      Button {
        if modifierKeys.isOptionPressed {
          manager.pause()
        } else {
          manager.stop()
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

}

#if DEBUG
  /// Wraps the menu content in a preview-friendly container.
  private struct MenuContentPreviewContainer: View {
    let manager: KeepAwakeSessionsManager
    let updater: AppUpdater

    /// Builds the preview container layout.
    var body: some View {
      MenuContentView(manager: manager, updater: updater)
        .padding()
        .frame(width: 340)
    }
  }

  private let previewManagedPolicyState = KeepAwakeSessionsManager.ManagedPolicyState(
    screenSaverIdleTime: 900,
    loginWindowIdleTime: 300,
    asksForPasswordAfterScreenSaver: true,
    askForPasswordDelay: 0,
    autoLogoutDelay: 7200,
    disablesAutoLogin: true
  )

  #Preview("Menu · Timer Off") {
    MenuContentPreviewContainer(
      manager: KeepAwakeSessionsManager(previewState: .idle()),
      updater: AppUpdater(previewNotice: nil)
    )
  }

  #Preview("Menu · 2h Timer") {
    MenuContentPreviewContainer(
      manager: KeepAwakeSessionsManager(
        previewState: .active(
          remaining: 2 * 3600,
          sessionDuration: 2 * 3600
        )),
      updater: AppUpdater(previewNotice: nil)
    )
  }

  #Preview("Menu · 11:59 with Policy Warning") {
    MenuContentPreviewContainer(
      manager: KeepAwakeSessionsManager(
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
      manager: KeepAwakeSessionsManager(
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
      manager: KeepAwakeSessionsManager(
        previewState: .paused(
          remaining: 2 * 3600,
          sessionDuration: 4 * 3600
        )),
      updater: AppUpdater(previewNotice: nil)
    )
  }

  #Preview("Menu · Update Alert") {
    MenuContentPreviewContainer(
      manager: KeepAwakeSessionsManager(
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

