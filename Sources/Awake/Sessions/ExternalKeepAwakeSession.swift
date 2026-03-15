// Value type representing a named awake session initiated via URL scheme IPC.
// Each session has a caller-provided identifier, a human-readable label for the
// UI, an absolute expiry timestamp, and a creation timestamp used to derive the
// full session duration for ring progress.

import Foundation

/// A named awake session created by an external caller through the `awake://` URL scheme.
///
/// Sessions are stored in a dictionary keyed by `id` inside `KeepAwakeSessionsManager`.
/// Multiple sessions can coexist — the effective awake duration is the maximum
/// end date across all active sessions.
public struct ExternalKeepAwakeSession: KeepAwakeSession, Codable, Equatable, Identifiable, Sendable {
    /// Caller-provided identifier used to activate and deactivate this session.
    public let id: String
    
    /// Human-readable label shown in the session list UI (e.g. "Refactoring code").
    public let label: String
    
    /// Human-readable source label shown in a a UI (e.g. "Claude Code").
    public let source: String?
    
    /// Absolute timestamp when this session expires.
    public let endDate: Date
    
    /// Absolute timestamp when this session was created or last refreshed.
    public let createdDate: Date
    
    /// Creates a new external keep-awake session.
    /// - Parameters:
    ///   - id: Caller-provided session identifier.
    ///   - label: Display label for the UI.
    ///   - source: Source application
    ///   - endDate: When this session expires.
    ///   - createdDate: When this session was created.
    public init(id: String, label: String, source: String?, endDate: Date, createdDate: Date = Date.now) {
        self.id = id
        self.label = label
        self.source = source
        self.endDate = endDate
        self.createdDate = createdDate
    }
}

#if DEBUG
extension ExternalKeepAwakeSession {
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
    ) -> ExternalKeepAwakeSession {
        let duration = totalDuration ?? remaining
        return ExternalKeepAwakeSession(
            id: id,
            label: label,
            source: "Preview",
            endDate: now.addingTimeInterval(remaining),
            createdDate: now.addingTimeInterval(remaining - duration)
        )
    }
}
#endif
