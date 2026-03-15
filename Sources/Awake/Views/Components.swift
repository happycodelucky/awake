// MARK: - Components
// Reusable view components: TimerHeroView, CircleActionIcon,
// PolicyWarningCard, UpdateNoticeCard, and SettingsGroupBox.

import SwiftUI

/// Renders the primary timer summary, ring, and session action in the menu.
struct TimerHeroView<ActionButton: View>: View {
  let timeText: String
  let statusText: String
  let detailText: String
  let progress: Double
  let isActive: Bool
  let colorScheme: ColorScheme
  @ViewBuilder let actionButton: ActionButton

  @Environment(\.designTokens) var designTokens

  /// Creates the timer hero view.
  /// - Parameters:
  ///   - timeText: Formatted remaining time string.
  ///   - statusText: Short status label shown above the time (e.g. "TIME LEFT").
  ///   - detailText: Descriptive line shown beneath the time value.
  ///   - progress: Ring fill fraction from 0 to 1.
  ///   - isActive: Whether a session is running or paused.
  ///   - colorScheme: Current color scheme for gradient selection.
  ///   - actionButton: The contextual action button rendered alongside the time.
  init(
    timeText: String,
    statusText: String,
    detailText: String,
    progress: Double,
    isActive: Bool,
    colorScheme: ColorScheme,
    @ViewBuilder actionButton: () -> ActionButton
  ) {
    self.timeText = timeText
    self.statusText = statusText
    self.detailText = detailText
    self.progress = progress
    self.isActive = isActive
    self.colorScheme = colorScheme
    self.actionButton = actionButton()
  }

  /// Builds the hero card for the current timer state. Animates ring
  /// progress, text changes, and button appear/disappear transitions.
  var body: some View {
    ZStack {
      RacetrackRingShape()
        .stroke(trackStyle, style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round))

      RacetrackRingShape()
        .trim(from: 0, to: isActive ? max(progress, 0.015) : 0)
        .stroke(progressStyle, style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round))
        .animation(.easeInOut(duration: 0.4), value: progress)
        .animation(.easeInOut(duration: 0.35), value: isActive)

      VStack(spacing: 6) {
        Text(statusText)
          .font(designTokens.typography.labelLarge)
          .tracking(1.8)
          .foregroundStyle(.secondary)
          .contentTransition(.opacity)
          .animation(.easeInOut(duration: 0.25), value: statusText)

        HStack(alignment: .center, spacing: 12) {
          Text(timeText)
            .font(designTokens.typography.monospaceDisplayLarge)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .allowsTightening(true)
            .foregroundStyle(isActive ? AnyShapeStyle(progressStyle) : AnyShapeStyle(.primary))
            .contentTransition(.numericText(countsDown: true))
            .animation(.easeInOut(duration: 0.3), value: timeText)
            .animation(.easeInOut(duration: 0.35), value: isActive)

          actionButton
        }
        .fixedSize(horizontal: false, vertical: true)

        Text(detailText)
          .font(designTokens.typography.bodyMedium)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .contentTransition(.opacity)
          .animation(.easeInOut(duration: 0.25), value: detailText)
      }
      .padding(.horizontal, 28)
    }
    .frame(height: 182)
    .padding(.horizontal, 2)
  }

  /// Returns the subdued style used for the inactive ring track.
  private var trackStyle: some ShapeStyle {
    Color.secondary.opacity(colorScheme == .dark ? 0.22 : 0.16)
  }

  /// Returns the gradient style used for the active progress segment.
  private var progressStyle: LinearGradient {
    LinearGradient(
      colors: colorScheme == .dark ? [Color.cyan, Color.green] : [Color.accentColor, Color.teal],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }
}

/// Draws a circular action icon used by the hero controls.
struct CircleActionIcon: View {
  let symbolName: String
  let fillColor: Color

  /// Builds the circular symbol presentation. Animates icon morphs and
  /// fill-color changes so modifier-key swaps feel smooth.
  var body: some View {
    ZStack {
      Circle()
        .fill(fillColor)
      Image(systemName: symbolName)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(.white)
        .contentTransition(.symbolEffect(.replace))
    }
    .frame(width: 36, height: 36)
    .animation(.easeInOut(duration: 0.2), value: symbolName)
    .animation(.easeInOut(duration: 0.2), value: fillColor)
  }
}

/// Displays managed policy warnings with expandable detail sections.
struct PolicyWarningCard: View {
  let title: String
  let known: [String]
  let possible: [String]
  @State private var isExpanded = false

  @Environment(\.designTokens) var designTokens

  /// Builds the expandable policy warning card. Starts collapsed showing
  /// only the title and disclaimer. Tapping "More" reveals Known (confirmed
  /// active) and Likely (conditional) policy details.
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.orange)

        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(designTokens.typography.cardTitle)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
          Text(
            "Awake can prevent idle sleep, but it cannot guarantee bypassing managed lock or logout policies."
          )
          .font(designTokens.typography.cardBody)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
      }

      Button {
        isExpanded.toggle()
      } label: {
        HStack(spacing: 6) {
          Text(isExpanded ? "Less" : "More")
            .font(designTokens.typography.labelMedium)
          Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity, alignment: .trailing)

      if isExpanded {
        if !known.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            Text("Known")
              .font(designTokens.typography.labelSmall)
              .tracking(1.1)
              .foregroundStyle(.secondary)

            ForEach(known, id: \.self) { message in
              warningLine(message)
            }
          }
        }

        if !possible.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            Text("Likely")
              .font(designTokens.typography.labelSmall)
              .tracking(1.1)
              .foregroundStyle(.secondary)

            ForEach(possible, id: \.self) { message in
              warningLine(message)
            }
          }
        }
      }
    }
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color.orange.opacity(0.08))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(Color.orange.opacity(0.24))
    )
  }

  /// Renders a single warning bullet line.
  /// - Parameter message: The warning text to display.
  private func warningLine(_ message: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Circle()
        .fill(Color.orange.opacity(0.75))
        .frame(width: 4, height: 4)
        .padding(.top, 6)

      Text(message)
        .font(designTokens.typography.cardBody)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// Presents update status messaging and its associated actions.
struct UpdateNoticeCard: View {
  let notice: AppUpdater.UpdateNotice
  let primaryAction: () -> Void
  let secondaryAction: () -> Void

  @Environment(\.designTokens) var designTokens

  /// Builds the UI for the active updater notice.
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90.circle.fill")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(designTokens.colors.info)

        VStack(alignment: .leading, spacing: 3) {
          Text(notice.title)
            .font(designTokens.typography.cardTitle)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)

          Text(notice.message)
            .font(designTokens.typography.cardBody)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      if case .downloading(let progress) = notice.kind, let progress {
        ProgressView(value: progress)
          .progressViewStyle(.linear)
          .tint(designTokens.colors.info)
      }

      HStack(spacing: 8) {
        if let primaryActionTitle = notice.primaryActionTitle {
          Button(primaryActionTitle, action: primaryAction)
            .buttonStyle(UpdateCardPrimaryButtonStyle())
        }

        if let secondaryActionTitle = notice.secondaryActionTitle {
          Button(secondaryActionTitle, action: secondaryAction)
            .buttonStyle(UpdateCardSecondaryButtonStyle())
        }
      }
    }
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(designTokens.colors.infoCardBackground)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(designTokens.colors.infoCardStroke)
    )
  }
}

/// Wraps settings content in a card-style container matching
/// the existing `PolicyWarningCard` / `UpdateNoticeCard` visual pattern.
struct SettingsGroupBox<Content: View>: View {
  let content: Content

  /// Creates a settings group box with the provided content.
  /// - Parameter content: The settings controls to display inside the card.
  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  /// Builds the card container with material background and subtle border.
  var body: some View {
    content
      .padding(14)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(.regularMaterial)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .strokeBorder(Color.secondary.opacity(0.12))
      )
  }
}

#if DEBUG
  private let previewPolicyState = KeepAwakeSessionsManager.ManagedPolicyState(
    screenSaverIdleTime: 900,
    loginWindowIdleTime: 300,
    asksForPasswordAfterScreenSaver: true,
    askForPasswordDelay: 0,
    autoLogoutDelay: 7200,
    disablesAutoLogin: true
  )

  #Preview("Timer Hero · 11:59") {
    TimerHeroView(
      timeText: "11:59:00",
      statusText: "TIME LEFT",
      detailText: "macOS will keep the display on for this session",
      progress: 11.0 / 12.0,
      isActive: true,
      colorScheme: .light
    ) {
      CircleActionIcon(symbolName: "xmark", fillColor: .red)
    }
    .padding()
    .frame(width: 320)
  }

  #Preview("Timer Hero · 29s") {
    TimerHeroView(
      timeText: "00:29",
      statusText: "TIME LEFT",
      detailText: "macOS will keep background work running while the display can sleep",
      progress: 29.0 / 120.0,
      isActive: true,
      colorScheme: .dark
    ) {
      CircleActionIcon(symbolName: "pause.fill", fillColor: .orange)
    }
    .padding()
    .frame(width: 320)
    .preferredColorScheme(.dark)
  }

  #Preview("Timer Hero · Off") {
    TimerHeroView(
      timeText: "00:00",
      statusText: "READY",
      detailText: "Choose a timer to begin",
      progress: 0,
      isActive: false,
      colorScheme: .light
    ) {
      EmptyView()
    }
    .padding()
    .frame(width: 320)
  }

  #Preview("Policy Warning") {
    PolicyWarningCard(
      title: "Managed policies can end or interrupt long idle sessions",
      known: KeepAwakeSessionsManager(
        previewState: .active(
          remaining: 11 * 3600 + 59 * 60,
          sessionDuration: 12 * 3600,
          policyState: previewPolicyState
        )
      ).behaviorPolicyNotice?.known ?? [],
      possible: KeepAwakeSessionsManager(
        previewState: .active(
          remaining: 11 * 3600 + 59 * 60,
          sessionDuration: 12 * 3600,
          policyState: previewPolicyState
        )
      ).behaviorPolicyNotice?.possible ?? []
    )
    .padding()
    .frame(width: 320)
  }

  #Preview("Update Alert · Available") {
    UpdateNoticeCard(
      notice: .preview(
        kind: .available,
        title: "Update available",
        message: "Version 1.3.0 is available for Awake.",
        version: "1.3.0",
        primaryActionTitle: "Install update",
        secondaryActionTitle: "Later"
      ),
      primaryAction: {},
      secondaryAction: {}
    )
    .padding()
    .frame(width: 320)
  }

  #Preview("Update Alert · Downloading") {
    UpdateNoticeCard(
      notice: .preview(
        kind: .downloading(progress: 0.68),
        title: "Update available",
        message: "Version 1.3.0 is downloading (68%).",
        version: "1.3.0"
      ),
      primaryAction: {},
      secondaryAction: {}
    )
    .padding()
    .frame(width: 320)
  }
#endif
