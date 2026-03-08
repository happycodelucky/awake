#!/usr/bin/env swift

import Foundation

/// Represents the managed values collected for a single preference domain.
struct DomainReport {
  let scope: String
  let name: String
  let values: [String: Any]
  let metadata: [String: ManagedKeyMetadata]
}

/// Describes metadata attached to a managed preference key.
struct ManagedKeyMetadata {
  let mode: String?
  let sources: [String]
}

/// Selects whether the report prints summary data or expanded metadata.
enum ReportMode {
  case summary
  case verbose
}

let fileManager = FileManager.default
let currentUser =
  CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("--") }) ?? NSUserName()
let reportMode: ReportMode = CommandLine.arguments.contains("--verbose") ? .verbose : .summary
let includeSystemDomains = !CommandLine.arguments.contains("--user-only")
let baseManagedPreferencesURL = URL(
  fileURLWithPath: "/Library/Managed Preferences", isDirectory: true)
let userManagedPreferencesURL = baseManagedPreferencesURL.appendingPathComponent(
  currentUser, isDirectory: true)

/// Loads a property list dictionary from disk.
/// - Parameter url: The property list file to read.
/// - Returns: The decoded dictionary, or `nil` when loading fails.
func loadPlistDictionary(at url: URL) -> [String: Any]? {
  guard let data = try? Data(contentsOf: url) else { return nil }
  guard let object = try? PropertyListSerialization.propertyList(from: data, format: nil) else {
    return nil
  }
  return object as? [String: Any]
}

/// Normalizes raw `complete.plist` metadata into a keyed lookup table.
/// - Parameter raw: The raw domain metadata payload.
/// - Returns: Metadata keyed by managed preference name.
func normalizeMetadata(_ raw: [String: Any]) -> [String: ManagedKeyMetadata] {
  var metadata: [String: ManagedKeyMetadata] = [:]

  for (key, value) in raw {
    guard let keyPayload = value as? [String: Any] else { continue }
    let mode = keyPayload["mcxdomain"] as? String
    let sources = keyPayload["source"] as? [String] ?? []
    metadata[key] = ManagedKeyMetadata(mode: mode, sources: sources)
  }

  return metadata
}

/// Loads domain metadata from the managed preferences `complete.plist`.
/// - Parameter directoryURL: The managed preferences directory to inspect.
/// - Returns: Metadata keyed first by domain and then by preference key.
func loadCompleteMetadata(at directoryURL: URL) -> [String: [String: ManagedKeyMetadata]] {
  let completeURL = directoryURL.appendingPathComponent("complete.plist")
  guard let raw = loadPlistDictionary(at: completeURL) else { return [:] }

  var metadataByDomain: [String: [String: ManagedKeyMetadata]] = [:]
  for (domain, value) in raw {
    guard let domainPayload = value as? [String: Any] else { continue }
    metadataByDomain[domain] = normalizeMetadata(domainPayload)
  }

  return metadataByDomain
}

/// Loads all managed preference reports from a directory.
/// - Parameters:
///   - directoryURL: The managed preferences directory to inspect.
///   - scope: The scope label to attach to the loaded reports.
/// - Returns: Sorted reports for every managed domain in the directory.
func loadReports(from directoryURL: URL, scope: String) -> [DomainReport] {
  guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }

  let metadataByDomain = loadCompleteMetadata(at: directoryURL)
  guard
    let urls = try? fileManager.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
  else {
    return []
  }

  return
    urls
    .filter { $0.pathExtension == "plist" }
    .filter { $0.lastPathComponent != "complete.plist" }
    .compactMap { url in
      guard let values = loadPlistDictionary(at: url) else { return nil }
      let domain = url.deletingPathExtension().lastPathComponent
      return DomainReport(
        scope: scope,
        name: domain,
        values: values,
        metadata: metadataByDomain[domain] ?? [:]
      )
    }
    .sorted { lhs, rhs in
      if lhs.scope == rhs.scope {
        return lhs.name < rhs.name
      }
      return lhs.scope < rhs.scope
    }
}

/// Formats a managed preference value for terminal output.
/// - Parameter value: The value to render.
/// - Returns: A concise string representation.
func formatValue(_ value: Any) -> String {
  switch value {
  case let string as String:
    return string
  case let number as NSNumber:
    if CFGetTypeID(number) == CFBooleanGetTypeID() {
      return number.boolValue ? "true" : "false"
    }
    return number.stringValue
  case let array as [Any]:
    if array.isEmpty {
      return "[]"
    }
    let rendered = array.prefix(5).map(formatValue).joined(separator: ", ")
    return array.count > 5 ? "[\(rendered), ...]" : "[\(rendered)]"
  case let dictionary as [String: Any]:
    return "{\(dictionary.keys.sorted().joined(separator: ", "))}"
  default:
    return String(describing: value)
  }
}

/// Formats a second count into a compact duration string.
/// - Parameter seconds: The duration in seconds.
/// - Returns: A compact duration string.
func formatSeconds(_ seconds: Int) -> String {
  if seconds < 60 {
    return "\(seconds)s"
  }
  let minutes = seconds / 60
  let remainder = seconds % 60
  if minutes < 60 {
    return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
  }
  let hours = minutes / 60
  let remainingMinutes = minutes % 60
  if remainingMinutes == 0 {
    return "\(hours)h"
  }
  return "\(hours)h \(remainingMinutes)m"
}

/// Finds the most relevant report for a domain, preferring user scope over system scope.
/// - Parameters:
///   - name: The domain name to search for.
///   - reports: The loaded domain reports.
/// - Returns: The preferred matching report, if any.
func findReport(named name: String, in reports: [DomainReport]) -> DomainReport? {
  reports.first(where: { $0.name == name && $0.scope == "user" })
    ?? reports.first(where: { $0.name == name && $0.scope == "system" })
    ?? reports.first(where: { $0.name == name })
}

/// Finds a managed value, preferring user-scope entries over system-scope entries.
/// - Parameters:
///   - domain: The domain that owns the key.
///   - key: The managed preference key to find.
///   - reports: The loaded domain reports.
/// - Returns: The matching scope, value, and metadata, if found.
func findManagedValue(domain: String, key: String, in reports: [DomainReport]) -> (
  scope: String, value: Any, metadata: ManagedKeyMetadata?
)? {
  for scope in ["user", "system"] {
    guard let report = reports.first(where: { $0.name == domain && $0.scope == scope }) else {
      continue
    }
    guard let value = report.values[key] else { continue }
    return (scope, value, report.metadata[key])
  }

  if let report = reports.first(where: { $0.name == domain }), let value = report.values[key] {
    return (report.scope, value, report.metadata[key])
  }

  return nil
}

/// Renders a single managed preference line for terminal output.
/// - Parameters:
///   - scope: The optional scope label to include.
///   - domain: The domain that owns the key.
///   - key: The managed preference key.
///   - value: The managed preference value.
///   - metadata: Optional metadata describing the key.
/// - Returns: A formatted output line.
func renderManagedLine(
  scope: String? = nil, domain: String, key: String, value: Any, metadata: ManagedKeyMetadata?
) -> String {
  var line = "- "
  if let scope {
    line += "[\(scope)] "
  }
  line += "\(domain).\(key) = \(formatValue(value))"

  if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
    let intValue = number.intValue
    if intValue > 0,
      ["idleTime", "loginWindowIdleTime", "askForPasswordDelay", "autoLogoutDelay"].contains(key)
    {
      line += " (\(formatSeconds(intValue)))"
    }
  }

  if let metadata {
    let mode = metadata.mode ?? "managed"
    line += " [\(mode)]"
    if reportMode == .verbose, !metadata.sources.isEmpty {
      line += " sources=\(metadata.sources.joined(separator: ","))"
    }
  }

  return line
}

/// Prints the inactivity and lock-policy summary section.
/// - Parameter reports: The loaded domain reports.
func printInactivitySummary(from reports: [DomainReport]) {
  print("Relevant inactivity and lock policies")

  let screensaverDomain = "com.apple.screensaver"
  let loginWindowDomain = "com.apple.loginwindow"
  let powerManagementDomain = "com.apple.PowerManagement"

  for key in ["idleTime", "loginWindowIdleTime", "askForPassword", "askForPasswordDelay"] {
    if let managedValue = findManagedValue(domain: screensaverDomain, key: key, in: reports) {
      print(
        renderManagedLine(
          scope: managedValue.scope, domain: screensaverDomain, key: key, value: managedValue.value,
          metadata: managedValue.metadata))
    }
  }

  for key in ["autoLogoutDelay", "com.apple.login.mcx.DisableAutoLoginClient"] {
    if let managedValue = findManagedValue(domain: loginWindowDomain, key: key, in: reports) {
      print(
        renderManagedLine(
          scope: managedValue.scope, domain: loginWindowDomain, key: key, value: managedValue.value,
          metadata: managedValue.metadata))
    }
  }

  if let report = findReport(named: powerManagementDomain, in: reports) {
    for key in report.values.keys.sorted() {
      if let value = report.values[key] {
        print(
          renderManagedLine(
            scope: report.scope, domain: powerManagementDomain, key: key, value: value,
            metadata: report.metadata[key]))
      }
    }
  }

  print("")
}

/// Prints the domain-level summary section.
/// - Parameter reports: The loaded domain reports.
func printDomainSummary(_ reports: [DomainReport]) {
  print("Managed domains")
  for report in reports {
    let keys = report.values.keys.sorted()
    print("- [\(report.scope)] \(report.name): \(keys.count) keys")
    if reportMode == .verbose {
      for key in keys {
        guard let value = report.values[key] else { continue }
        print(
          "  \(renderManagedLine(scope: report.scope, domain: report.name, key: key, value: value, metadata: report.metadata[key]))"
        )
      }
    }
  }
  print("")
}

/// Prints every governed key discovered in the reports.
/// - Parameter reports: The loaded domain reports.
func printGovernedKeys(_ reports: [DomainReport]) {
  print("Governed keys")
  for report in reports {
    let keys = report.values.keys.sorted()
    for key in keys {
      guard let value = report.values[key] else { continue }
      print(
        renderManagedLine(
          scope: report.scope, domain: report.name, key: key, value: value,
          metadata: report.metadata[key]))
    }
  }
}

var reports: [DomainReport] = []
if includeSystemDomains {
  reports.append(contentsOf: loadReports(from: baseManagedPreferencesURL, scope: "system"))
}
reports.append(contentsOf: loadReports(from: userManagedPreferencesURL, scope: "user"))

print("Managed policy report")
print("User: \(currentUser)")
print("System managed prefs: \(baseManagedPreferencesURL.path)")
print("User managed prefs: \(userManagedPreferencesURL.path)")
print("")

guard !reports.isEmpty else {
  print("No managed preference plists were found.")
  exit(0)
}

printInactivitySummary(from: reports)
printDomainSummary(reports)
printGovernedKeys(reports)
