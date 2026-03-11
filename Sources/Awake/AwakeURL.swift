// MARK: - AwakeURL
// Pure URL parsing for the awake:// URL scheme. Validates incoming URLs and
// extracts typed commands that the app entry point dispatches to AwakeSessionManager.

import Foundation

/// A parsed and validated command from an `awake://` URL.
enum AwakeURLCommand {
  /// Activate or refresh a named session.
  /// - Parameters:
  ///   - id: Caller-provided session identifier.
  ///   - label: Display name for the session list.
  ///   - duration: Requested duration in seconds (before capping).
  case activate(id: String, label: String, duration: TimeInterval)

  /// Deactivate a named session.
  /// - Parameter id: The session identifier to remove.
  case deactivate(id: String)
}

/// Parses an `awake://` URL into a typed command.
///
/// Validation rules:
/// - Scheme must be `awake` (case-insensitive).
/// - Host routes to `activate` or `deactivate`. Other hosts return `nil`.
/// - `activate` requires non-empty `session`, non-empty `label`, and positive `duration`.
/// - `deactivate` requires non-empty `session`.
/// - Malformed or missing parameters return `nil` (silent rejection).
///
/// - Parameter url: The URL to parse.
/// - Returns: A typed command, or `nil` if the URL is unrecognized or invalid.
func parseAwakeURL(_ url: URL) -> AwakeURLCommand? {
  guard let scheme = url.scheme?.lowercased(), scheme == "awake" else { return nil }
  guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
    return nil
  }

  let host = components.host?.lowercased() ?? ""
  let queryItems = components.queryItems ?? []

  func queryValue(for name: String) -> String? {
    queryItems.first(where: { $0.name == name })?.value
  }

  switch host {
  case "activate":
    guard let session = queryValue(for: "session"), !session.isEmpty else { return nil }
    guard let label = queryValue(for: "label"), !label.isEmpty else { return nil }
    guard let durationString = queryValue(for: "duration"),
      let duration = TimeInterval(durationString),
      duration > 0
    else { return nil }
    return .activate(id: session, label: label, duration: duration)

  case "deactivate":
    guard let session = queryValue(for: "session"), !session.isEmpty else { return nil }
    return .deactivate(id: session)

  default:
    return nil
  }
}
