// MARK: - KeepAwakeSession
// Protocol defining a named awake session with identifier, label, and expiry.

import Foundation

/// A protocol representing a named awake session with expiry tracking.
///
/// Sessions are identified by a caller-provided ID and have human-readable labels.
/// The duration and remaining time are computed from creation and end dates.
public protocol KeepAwakeSession: Identifiable, Sendable {
    /// Caller-provided identifier used to activate and deactivate this session.
    var id: String { get }
    
    /// Human-readable label indentify the job (e.g. "Refactoring code base").
    var label: String { get }
    
    /// Human-readable source label shown in a a UI (e.g. "Claude Code").
    var source: String? { get }
    
    /// Absolute timestamp when this session expires.
    var endDate: Date { get }
    
    /// Absolute timestamp when this session was created or last refreshed.
    var createdDate: Date { get }
    
    /// The full duration of this session from creation to expiry.
    var duration: TimeInterval { get }
    
    /// Returns the remaining interval relative to a reference date.
    /// - Parameter now: The current date to compare against.
    /// - Returns: Seconds remaining, floored at zero.
    func remaining(at now: Date) -> TimeInterval
    
    /// Indicates whether this session has not yet expired at the given date.
    /// - Parameter now: The current date to compare against.
    /// - Returns: `true` if the session end date is still in the future.
    func isActive(at now: Date) -> Bool
}

extension KeepAwakeSession {
    /// The full duration of this session from creation to expiry.
    public var duration: TimeInterval {
        max(0, endDate.timeIntervalSince(createdDate))
    }
    
    /// Returns the remaining interval relative to a reference date.
    /// - Parameter now: The current date to compare against.
    /// - Returns: Seconds remaining, floored at zero.
    public func remaining(at now: Date = Date.now) -> TimeInterval {
        max(0, endDate.timeIntervalSince(now))
    }
    
    /// Indicates whether this session has not yet expired at the given date.
    /// - Parameter now: The current date to compare against.
    /// - Returns: `true` if the session end date is still in the future.
    public func isActive(at now: Date = Date.now) -> Bool {
        endDate > now
    }
}
