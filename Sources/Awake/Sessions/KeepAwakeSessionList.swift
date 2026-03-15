// MARK: - KeepAwakeSessionList
// Compact card listing active external keep-awake sessions with label, remaining time, and
// a deactivate button. Shown below the timer hero when external callers are
// keeping the Mac awake via the awake:// URL scheme.

import SwiftUI

/// Renders a list of active external keep-awake sessions inside a card.
///
/// When there are 7 or fewer sessions, the list renders as a tight `VStack`
/// with no scroll container. When there are more than 7, the rows are wrapped
/// in a `ScrollView` capped at the height of 7 rows to keep the popover
/// from growing unbounded.
struct KeepAwakeSessionList: View {
  /// Active sessions to display, expected to be sorted by end date descending.
  let sessions: [ExternalKeepAwakeSession]

  /// The current reference date used to compute remaining time.
  let now: Date

  /// Called with the session ID when the user taps the deactivate button.
  let onDeactivate: (String) -> Void

  @Environment(\.designTokens) var designTokens

  /// The maximum number of rows shown before enabling scrolling.
  private let maxVisibleRows = 7

  /// Approximate height of a single session row including padding.
  private let rowHeight: CGFloat = 28

  /// Builds the session list card.
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      let count = sessions.count
      Text(count == 1 ? "External Session" : "External Sessions")
        .font(designTokens.typography.sectionHeader)
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .tracking(1.4)

      // AGENT: ForEach must be a direct child of the card container (not
      // wrapped in a `let` binding) so SwiftUI can identity-track each row
      // across re-renders and apply per-row removal transitions. A `let`
      // binding replaces the whole VStack, making individual row animations
      // impossible.
      let cardContent = VStack(spacing: 0) {
        ForEach(sessions) { session in
          sessionRow(session)
            // AGENT: .transition is applied per-row so SwiftUI slides out
            // only the removed row. Insertion uses a gentle fade so newly
            // added sessions appear softly. Removal slides right and fades,
            // giving clear directional feedback matching the xmark button.
            .transition(
              .asymmetric(
                insertion: .opacity.animation(.easeIn(duration: 0.18)),
                removal: .move(edge: .trailing).combined(with: .opacity)
                  .animation(.easeOut(duration: 0.22))
              )
            )
          // Divider between rows only — not after the last row.
          if session.id != sessions.last?.id {
            Divider()
              .padding(.horizontal, 10)
              // AGENT: The divider above a removed row should fade with the
              // row, not linger. Giving it the same removal transition as the
              // row ensures both disappear together.
              .transition(.opacity.animation(.easeOut(duration: 0.22)))
          }
        }
      }
      .padding(.vertical, 4)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(.regularMaterial)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .strokeBorder(Color.secondary.opacity(0.12))
      )
      // AGENT: .animation on the card container animates the card's own
      // height change as rows are removed, so the card shrinks smoothly
      // rather than jumping. The spring gives a slight elastic feel.
      .animation(.spring(response: 0.3, dampingFraction: 0.8), value: sessions.map(\.id))

      if count > maxVisibleRows {
        ScrollView {
          cardContent
        }
        .frame(maxHeight: CGFloat(maxVisibleRows) * rowHeight)
      } else {
        cardContent
      }
    }
  }

  /// Builds a single session row with label, remaining time, and deactivate button.
  /// - Parameter session: The external keep-awake session to display.
  /// - Returns: The session row view.
  @ViewBuilder
  private func sessionRow(_ session: ExternalKeepAwakeSession) -> some View {
    HStack(spacing: 8) {
      Text(session.label)
        .font(designTokens.typography.cardTitle)
        .lineLimit(1)
        .truncationMode(.tail)

      Spacer(minLength: 4)

      Text(compactRemaining(session.remaining(at: now)))
        .font(designTokens.typography.monospaceBodySmall)
        .foregroundStyle(.secondary)

      Button {
        onDeactivate(session.id)
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 14))
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .help("Deactivate \(session.label)")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
    .frame(height: rowHeight)
  }

  /// Formats a remaining interval into a compact string.
  /// - Parameter remaining: The remaining interval in seconds.
  /// - Returns: A compact remaining-time string (e.g. "2h 30m", "15m", "45s").
  private func compactRemaining(_ remaining: TimeInterval) -> String {
    let total = max(0, Int(remaining))
    if total < 60 {
      return "\(total)s"
    }
    let minutes = total / 60
    if minutes < 60 {
      return "\(minutes)m"
    }
    let hours = minutes / 60
    let remainMinutes = minutes % 60
    return String(format: "%dh %02dm", hours, remainMinutes)
  }
}

#if DEBUG
  /// Preview container that holds live session state so the removal animation
  /// can be exercised interactively in Xcode Previews.
  private struct AnimatedPreviewContainer: View {
    @State private var sessions: [ExternalKeepAwakeSession]
    private let now = Date(timeIntervalSinceReferenceDate: 0)

    init(sessions: [ExternalKeepAwakeSession]) {
      _sessions = State(initialValue: sessions)
    }

    var body: some View {
      KeepAwakeSessionList(
        sessions: sessions,
        now: now,
        onDeactivate: { id in
          withAnimation {
            sessions.removeAll { $0.id == id }
          }
        }
      )
      .padding()
      .frame(width: 312)
    }
  }

  #Preview("1 External Session") {
    AnimatedPreviewContainer(sessions: [
      .preview(id: "claude-1", label: "Claude response", remaining: 1800),
    ])
  }

  #Preview("3 External Sessions (tap × to animate removal)") {
    AnimatedPreviewContainer(sessions: [
      .preview(id: "claude-1", label: "Claude agent run", remaining: 3600),
      .preview(id: "build-2", label: "Xcode build", remaining: 1200),
      .preview(id: "deploy-3", label: "Deployment pipeline", remaining: 300),
    ])
  }

  #Preview("8 External Sessions (scrollable)") {
    AnimatedPreviewContainer(sessions: (1...8).map { i in
      .preview(
        id: "session-\(i)",
        label: "Session \(i)",
        remaining: TimeInterval(i * 600)
      )
    })
  }
#endif
