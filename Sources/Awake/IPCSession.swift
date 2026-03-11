// MARK: - IPCSession
// Value type representing a named awake session initiated via URL scheme IPC.
// Each session has a caller-provided identifier, a human-readable label for the
// UI, an absolute expiry timestamp, and a creation timestamp used to derive the
// full session duration for ring progress.

import Foundation

/// A named awake session created by an external caller through the `awake://` URL scheme.
///
/// Sessions are stored in a dictionary keyed by `id` inside `AwakeSessionManager`.
/// Multiple sessions can coexist — the effective awake duration is the maximum
/// end date across all active sessions.
public struct IPCSession: Codable, Equatable, Identifiable, Sendable {
  /// Caller-provided identifier used to activate and deactivate this session.
  public let id: String

  /// Human-readable label shown in the session list UI (e.g. "Claude response").
  public let label: String

  /// Absolute timestamp when this session expires.
  public let endDate: Date

  /// Absolute timestamp when this session was created or last refreshed.
  public let createdDate: Date

  /// Creates a new IPC session.
  /// - Parameters:
  ///   - id: Caller-provided session identifier.
  ///   - label: Display label for the UI.
  ///   - endDate: When this session expires.
  ///   - createdDate: When this session was created.
  public init(id: String, label: String, endDate: Date, createdDate: Date) {
    self.id = id
    self.label = label
    self.endDate = endDate
    self.createdDate = createdDate
  }

  /// The full duration of this session from creation to expiry.
  public var duration: TimeInterval {
    max(0, endDate.timeIntervalSince(createdDate))
  }

  /// Returns the remaining interval relative to a reference date.
  /// - Parameter now: The current date to compare against.
  /// - Returns: Seconds remaining, floored at zero.
  public func remaining(at now: Date) -> TimeInterval {
    max(0, endDate.timeIntervalSince(now))
  }

  /// Indicates whether this session has not yet expired at the given date.
  /// - Parameter now: The current date to compare against.
  /// - Returns: `true` if the session end date is still in the future.
  public func isActive(at now: Date) -> Bool {
    endDate > now
  }
}

#if DEBUG
  extension IPCSession {
    /// Creates a preview session with the given remaining duration.
    /// - Parameters:
    ///   - id: Session identifier.
    ///   - label: Display label.
    ///   - remaining: Seconds remaining from the reference date.
    ///   - totalDuration: Full session duration in seconds.
    ///   - now: Reference date (defaults to a fixed preview date).
    /// - Returns: A session suitable for SwiftUI previews.
    static func preview(
      id: String,
      label: String,
      remaining: TimeInterval,
      totalDuration: TimeInterval? = nil,
      now: Date = Date(timeIntervalSinceReferenceDate: 0)
    ) -> IPCSession {
      let duration = totalDuration ?? remaining
      return IPCSession(
        id: id,
        label: label,
        endDate: now.addingTimeInterval(remaining),
        createdDate: now.addingTimeInterval(remaining - duration)
      )
    }
  }
#endif
