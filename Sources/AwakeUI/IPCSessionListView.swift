// MARK: - IPCSessionListView
// Compact card listing active IPC sessions with label, remaining time, and
// a deactivate button. Shown below the timer hero when external callers are
// keeping the Mac awake via the awake:// URL scheme.

import SwiftUI

/// Renders a list of active IPC sessions inside a card.
///
/// When there are 7 or fewer sessions, the list renders as a tight `VStack`
/// with no scroll container. When there are more than 7, the rows are wrapped
/// in a `ScrollView` capped at the height of 7 rows to keep the popover
/// from growing unbounded.
struct IPCSessionListView: View {
  /// Active sessions to display, expected to be sorted by end date descending.
  let sessions: [IPCSession]

  /// The current reference date used to compute remaining time.
  let now: Date

  /// Called with the session ID when the user taps the deactivate button.
  let onDeactivate: (String) -> Void

  /// The maximum number of rows shown before enabling scrolling.
  private let maxVisibleRows = 7

  /// Approximate height of a single session row including padding.
  private let rowHeight: CGFloat = 28

  /// Builds the session list card.
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      let count = sessions.count
      Text(count == 1 ? "External Session" : "External Sessions")
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .tracking(1.4)

      let rowContent = VStack(spacing: 0) {
        ForEach(sessions) { session in
          sessionRow(session)
          if session.id != sessions.last?.id {
            Divider()
              .padding(.horizontal, 10)
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

      if count > maxVisibleRows {
        ScrollView {
          rowContent
        }
        .frame(maxHeight: CGFloat(maxVisibleRows) * rowHeight)
      } else {
        rowContent
      }
    }
  }

  /// Builds a single session row with label, remaining time, and deactivate button.
  /// - Parameter session: The IPC session to display.
  /// - Returns: The session row view.
  @ViewBuilder
  private func sessionRow(_ session: IPCSession) -> some View {
    HStack(spacing: 8) {
      Text(session.label)
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .truncationMode(.tail)

      Spacer(minLength: 4)

      Text(compactRemaining(session.remaining(at: now)))
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .monospacedDigit()
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
  #Preview("1 IPC Session") {
    IPCSessionListView(
      sessions: [
        .preview(id: "claude-1", label: "Claude response", remaining: 1800)
      ],
      now: Date(timeIntervalSinceReferenceDate: 0),
      onDeactivate: { _ in }
    )
    .padding()
    .frame(width: 312)
  }

  #Preview("3 IPC Sessions") {
    IPCSessionListView(
      sessions: [
        .preview(id: "claude-1", label: "Claude agent run", remaining: 3600),
        .preview(id: "build-2", label: "Xcode build", remaining: 1200),
        .preview(id: "deploy-3", label: "Deployment pipeline", remaining: 300),
      ],
      now: Date(timeIntervalSinceReferenceDate: 0),
      onDeactivate: { _ in }
    )
    .padding()
    .frame(width: 312)
  }

  #Preview("8 IPC Sessions (scrollable)") {
    IPCSessionListView(
      sessions: (1...8).map { i in
        .preview(
          id: "session-\(i)",
          label: "Session \(i)",
          remaining: TimeInterval(i * 600)
        )
      },
      now: Date(timeIntervalSinceReferenceDate: 0),
      onDeactivate: { _ in }
    )
    .padding()
    .frame(width: 312)
  }
#endif
