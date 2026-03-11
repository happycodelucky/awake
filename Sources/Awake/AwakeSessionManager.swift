// MARK: - AwakeSessionManager
// Central singleton for timer lifecycle, IOKit power assertions, IPC sessions,
// and managed policy detection. All UI and the app delegate observe this shared instance.

import AppKit
import Foundation
import IOKit.pwr_mgt
import ServiceManagement
import os

@MainActor
/// Singleton that manages timer lifecycle, IOKit power assertions, IPC sessions, and policy state.
final class AwakeSessionManager: ObservableObject {
  /// Captures a stable controller snapshot used by previews.
  struct PreviewState {
    let now: Date
    let endDate: Date?
    let sessionDuration: TimeInterval?
    let pausedRemaining: TimeInterval?
    let ipcSessions: [String: IPCSession]
    let powerAssertionIsActive: Bool
    let assertionErrorMessage: String?
    let sleepBehavior: SleepBehavior
    let appearanceMode: AppearanceMode
    let managedPolicyState: ManagedPolicyState
  }

  /// A predefined timer duration with display metadata.
  struct Preset: Identifiable {
    /// User-facing label (e.g. "5 minutes", "1 hour").
    let label: String
    /// Compact label for buttons (e.g. "5m", "1h").
    let shortLabel: String
    /// Duration in minutes.
    let minutes: Int
    /// Category tag (e.g. "quick", "task", "workday").
    let mode: String

    /// Identifies the preset by its minute value.
    var id: Int { minutes }
  }

  /// Represents the managed macOS policies that may still interrupt an awake session.
  struct ManagedPolicyState {
    let screenSaverIdleTime: TimeInterval?
    let loginWindowIdleTime: TimeInterval?
    let asksForPasswordAfterScreenSaver: Bool
    let askForPasswordDelay: TimeInterval?
    let autoLogoutDelay: TimeInterval?
    let disablesAutoLogin: Bool

    /// Indicates whether the loaded policy state should surface a warning card.
    var hasRelevantWarnings: Bool {
      screenSaverIdleTime != nil || asksForPasswordAfterScreenSaver || autoLogoutDelay != nil
    }

    /// Loads managed policy values that can affect inactive sessions for a user.
    /// - Parameter user: The short user name whose managed preferences should be inspected.
    /// - Returns: The merged managed policy state.
    static func load(forUser user: String) -> ManagedPolicyState {
      let managedPreferencesURL = URL(
        fileURLWithPath: "/Library/Managed Preferences", isDirectory: true)
      let systemScreensaver = plist(
        at: managedPreferencesURL.appendingPathComponent("com.apple.screensaver.plist"))
      let userScreensaver = plist(
        at: managedPreferencesURL.appendingPathComponent(user, isDirectory: true)
          .appendingPathComponent("com.apple.screensaver.plist"))
      let mergedScreensaver = systemScreensaver.merging(
        userScreensaver, uniquingKeysWith: { _, userValue in userValue })

      let systemLoginWindow = plist(
        at: managedPreferencesURL.appendingPathComponent("com.apple.loginwindow.plist"))
      let userLoginWindow = plist(
        at: managedPreferencesURL.appendingPathComponent(user, isDirectory: true)
          .appendingPathComponent("com.apple.loginwindow.plist"))
      let mergedLoginWindow = systemLoginWindow.merging(
        userLoginWindow, uniquingKeysWith: { _, userValue in userValue })

      return ManagedPolicyState(
        screenSaverIdleTime: timeInterval(forKey: "idleTime", in: mergedScreensaver),
        loginWindowIdleTime: timeInterval(forKey: "loginWindowIdleTime", in: mergedScreensaver),
        asksForPasswordAfterScreenSaver: bool(forKey: "askForPassword", in: mergedScreensaver)
          ?? false,
        askForPasswordDelay: timeInterval(forKey: "askForPasswordDelay", in: mergedScreensaver),
        autoLogoutDelay: timeInterval(forKey: "autoLogoutDelay", in: mergedLoginWindow),
        disablesAutoLogin: bool(
          forKey: "com.apple.login.mcx.DisableAutoLoginClient", in: mergedLoginWindow) ?? false
      )
    }

    /// Loads a property list dictionary from disk, returning an empty dictionary on failure.
    /// - Parameter url: The property list URL to read.
    /// - Returns: The decoded dictionary or an empty dictionary.
    private static func plist(at url: URL) -> [String: Any] {
      guard let data = try? Data(contentsOf: url) else { return [:] }
      guard let raw = try? PropertyListSerialization.propertyList(from: data, format: nil) else {
        return [:]
      }
      return raw as? [String: Any] ?? [:]
    }

    /// Extracts a time interval value from a managed preference dictionary.
    /// - Parameters:
    ///   - key: The key to read.
    ///   - values: The source dictionary.
    /// - Returns: The decoded time interval, if present.
    private static func timeInterval(forKey key: String, in values: [String: Any]) -> TimeInterval?
    {
      if let value = values[key] as? NSNumber {
        return value.doubleValue
      }
      if let value = values[key] as? Double {
        return value
      }
      if let value = values[key] as? Int {
        return Double(value)
      }
      return nil
    }

    /// Extracts a Boolean value from a managed preference dictionary.
    /// - Parameters:
    ///   - key: The key to read.
    ///   - values: The source dictionary.
    /// - Returns: The decoded Boolean, if present.
    private static func bool(forKey key: String, in values: [String: Any]) -> Bool? {
      if let value = values[key] as? Bool {
        return value
      }
      if let value = values[key] as? NSNumber {
        return value.boolValue
      }
      return nil
    }
  }

  /// Groups user-facing messaging about managed policies into known and possible outcomes.
  struct BehaviorPolicyNotice {
    let title: String
    let known: [String]
    let possible: [String]
  }

  /// Describes which macOS idle-sleep behavior the current assertion should block.
  enum SleepBehavior: String {
    case keepDisplayAwake
    case allowDisplaySleep

    /// Returns the IOKit assertion type matching the selected behavior.
    var assertionType: CFString {
      switch self {
      case .keepDisplayAwake:
        return kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
      case .allowDisplaySleep:
        return kIOPMAssertionTypeNoIdleSleep as CFString
      }
    }
  }

  /// Describes the user's preferred appearance override for the app.
  enum AppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    /// Returns the `NSAppearance` that should be applied, or nil for system default.
    var nsAppearance: NSAppearance? {
      switch self {
      case .system: return nil
      case .light: return NSAppearance(named: .aqua)
      case .dark: return NSAppearance(named: .darkAqua)
      }
    }

    /// User-facing label for the appearance mode.
    var label: String {
      switch self {
      case .system: return "System"
      case .light: return "Light"
      case .dark: return "Dark"
      }
    }
  }

  @Published private(set) var now = Date()
  @Published private(set) var endDate: Date?
  @Published private(set) var sessionDuration: TimeInterval?
  @Published private(set) var pausedRemaining: TimeInterval?
  /// Active IPC sessions keyed by caller-provided session identifier.
  @Published private(set) var ipcSessions: [String: IPCSession] = [:]
  @Published private(set) var powerAssertionIsActive = false
  @Published private(set) var assertionErrorMessage: String?
  @Published private(set) var sleepBehavior: SleepBehavior = .keepDisplayAwake
  @Published private(set) var appearanceMode: AppearanceMode = .system
  @Published private(set) var managedPolicyState = ManagedPolicyState(
    screenSaverIdleTime: nil,
    loginWindowIdleTime: nil,
    asksForPasswordAfterScreenSaver: false,
    askForPasswordDelay: nil,
    autoLogoutDelay: nil,
    disablesAutoLogin: false
  )

  // AGENT: clockTimer is nonisolated(unsafe) because Timer.scheduledTimer
  // requires a non-isolated context, but the callback dispatches back to
  // @MainActor via Task. The timer is only mutated in init and deinit.
  nonisolated(unsafe) private var clockTimer: Timer?
  private var powerAssertionID: IOPMAssertionID = 0
  // AGENT: Policy refresh is throttled to 60s because reading plist files
  // from /Library/Managed Preferences on every clock tick (1s) would cause
  // unnecessary disk I/O. 60s balances freshness with performance.
  private var lastPolicyRefresh = Date.distantPast
  // AGENT: UserDefaults keys use the "awake." prefix to namespace them within
  // the app's defaults domain and avoid collisions with system or framework keys.
  private let endDateDefaultsKey = "awake.endDate"
  private let durationDefaultsKey = "awake.duration"
  private let pausedRemainingDefaultsKey = "awake.pausedRemaining"
  private let sleepBehaviorDefaultsKey = "awake.sleepBehavior"
  private let appearanceModeDefaultsKey = "awake.appearanceMode"
  private let ipcSessionsDefaultsKey = "awake.ipcSessions"
  private let powerAssertionReason = "Keep the Mac awake for an active Awake timer" as CFString

  /// Maximum duration allowed for IPC-initiated sessions (24 hours).
  private let maxIPCDuration: TimeInterval = 86400

  /// Logger for IPC session lifecycle events. Use Console.app or `log stream`
  /// with subsystem matching the bundle ID and category `ipc` to observe.
  private let ipcLog = Logger(subsystem: "com.happycodelucky.apps.awake", category: "ipc")

  // AGENT: shared is the single live instance used by the app. The preview
  // init (init(previewState:)) creates additional instances for Xcode Previews
  // only — it bypasses singleton enforcement and never starts live timers.
  /// The singleton session manager instance used by all app components.
  static let shared = AwakeSessionManager()

  /// Available timer presets shown in the menu grid.
  let presets: [Preset] = [
    Preset(label: "5 minutes",  shortLabel: "5m",  minutes: 5,       mode: "quick"),
    Preset(label: "10 minutes", shortLabel: "10m", minutes: 10,      mode: "quick"),
    Preset(label: "15 minutes", shortLabel: "15m", minutes: 15,      mode: "task"),
    Preset(label: "30 minutes", shortLabel: "30m", minutes: 30,      mode: "task"),
    Preset(label: "1 hour",     shortLabel: "1h",  minutes: 60,      mode: "task"),
    Preset(label: "2 hours",    shortLabel: "2h",  minutes: 2 * 60,  mode: "long task"),
    Preset(label: "4 hours",    shortLabel: "4h",  minutes: 4 * 60,  mode: "long task"),
    Preset(label: "8 hours",    shortLabel: "8h",  minutes: 8 * 60,  mode: "workday"),
    Preset(label: "12 hours",   shortLabel: "12h", minutes: 12 * 60, mode: "good luck"),
  ]

  /// Restores persisted session state and starts the live timer loop.
  /// Use `AwakeSessionManager.shared` — do not call directly.
  private init() {
    restoreSavedState()
    restoreIPCSessions()
    // AGENT: applyAppearance() must NOT be called here. NSApp is not yet
    // initialized when AwakeSessionManager.init() runs (shared is accessed
    // before NSApplicationMain completes). Appearance is applied later via
    // applyAppearance(), which is called from
    // AwakeAppDelegate.applicationDidFinishLaunching after NSApp is live.
    refreshManagedPolicyState(force: true)
    startClock()
    syncPowerAssertion()
  }

  /// Creates a session manager seeded with preview data.
  /// - Parameter previewState: The preview snapshot to expose.
  init(previewState: PreviewState) {
    now = previewState.now
    endDate = previewState.endDate
    sessionDuration = previewState.sessionDuration
    pausedRemaining = previewState.pausedRemaining
    ipcSessions = previewState.ipcSessions
    powerAssertionIsActive = previewState.powerAssertionIsActive
    assertionErrorMessage = previewState.assertionErrorMessage
    sleepBehavior = previewState.sleepBehavior
    appearanceMode = previewState.appearanceMode
    managedPolicyState = previewState.managedPolicyState
    lastPolicyRefresh = previewState.now
  }

  /// Releases timers and power assertions before the controller is deallocated.
  deinit {
    clockTimer?.invalidate()
    if powerAssertionID != 0 {
      IOPMAssertionRelease(powerAssertionID)
    }
  }

  /// Indicates whether the app session specifically has an active end date.
  var hasAppSession: Bool {
    guard let endDate else { return false }
    return endDate > now
  }

  /// Indicates whether any awake session (app or IPC) is currently running.
  var isActive: Bool {
    effectiveEndDate != nil
  }

  /// Indicates whether a session is paused with remaining time preserved.
  var isPaused: Bool {
    guard let pausedRemaining else { return false }
    return pausedRemaining > 0
  }

  /// Indicates whether there is either an active or paused session.
  var hasSession: Bool {
    isActive || isPaused
  }

  /// Indicates whether any IPC sessions are active.
  var hasIPCSessions: Bool {
    !ipcSessions.isEmpty
  }

  /// Returns normalized progress remaining for the effective session.
  var progress: Double {
    let duration = effectiveSessionDuration
    guard duration > 0 else { return 0 }
    return min(max(effectiveRemaining / duration, 0), 1)
  }

  /// Returns the short status line shown in the main menu header.
  var pulseStatusLine: String {
    if isPaused {
      return "Paused with \(formattedRemaining()) left"
    }
    guard isActive else { return "Not keeping the Mac awake" }
    guard powerAssertionIsActive else {
      return assertionErrorMessage ?? "Unable to prevent idle sleep"
    }
    // AGENT: When only IPC sessions are active (no app session), show a
    // distinct status line so the user knows external callers are driving.
    if !hasAppSession && hasIPCSessions {
      let count = ipcSessions.count
      let noun = count == 1 ? "session" : "sessions"
      return "Kept awake by \(count) external \(noun)"
    }
    switch sleepBehavior {
    case .keepDisplayAwake:
      return "Keeping display and Mac awake"
    case .allowDisplaySleep:
      return "Keeping Mac awake while display can sleep"
    }
  }

  /// Indicates whether the current behavior also prevents display sleep.
  var keepsDisplayAwake: Bool {
    sleepBehavior == .keepDisplayAwake
  }

  // AGENT: launchAtLogin is cached as @Published rather than reading
  // SMAppService.mainApp.status live in a computed property, because the
  // status call is an IPC syscall to the ServiceManagement daemon and
  // SwiftUI re-evaluates bindings on every render cycle (once per second
  // while the settings panel is open via the clock timer).
  /// Indicates whether the app is registered as a login item.
  @Published private(set) var launchAtLogin: Bool = false

  /// Registers or unregisters the app as a login item.
  /// - Parameter enabled: `true` to register, `false` to unregister.
  func setLaunchAtLogin(_ enabled: Bool) {
    // AGENT: SMAppService can fail if the app is unsigned or if the user
    // revoked the login item in System Settings. We log but do not surface
    // errors in the UI because the toggle re-reads the actual system state
    // after each attempt, so it self-corrects.
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      print("SMAppService error: \(error)")
    }
    launchAtLogin = SMAppService.mainApp.status == .enabled
  }

  /// Updates the app appearance mode and persists the choice.
  /// - Parameter mode: The appearance mode the user selected.
  func setAppearanceMode(_ mode: AppearanceMode) {
    guard mode != appearanceMode else { return }
    appearanceMode = mode
    UserDefaults.standard.set(mode.rawValue, forKey: appearanceModeDefaultsKey)
    applyAppearance()
  }

  /// Builds a warning notice when managed policies may interrupt the session.
  var behaviorPolicyNotice: BehaviorPolicyNotice? {
    guard managedPolicyState.hasRelevantWarnings else { return nil }

    var known: [String] = []
    var possible: [String] = []

    if let autoLogoutDelay = managedPolicyState.autoLogoutDelay {
      known.append(
        "Managed auto-logout is set for \(formattedPolicyInterval(autoLogoutDelay)) of inactivity. Background work may stop when the session is logged out."
      )
    }

    if let screenSaverIdleTime = managedPolicyState.screenSaverIdleTime {
      // AGENT: Use the app-session remaining (remainingInterval) for the policy
      // threshold check, not effectiveRemaining. IPC sessions could push effective
      // remaining far into the future, but managed policy warnings should only
      // reflect the app session the user is explicitly managing here.
      let willTriggerWithinSession = hasSession && remainingInterval > screenSaverIdleTime
      let timing =
        willTriggerWithinSession
        ? "during this session"
        : "after \(formattedPolicyInterval(screenSaverIdleTime)) of inactivity"
      known.append("Managed screen saver behavior can start \(timing).")
    }

    if managedPolicyState.asksForPasswordAfterScreenSaver {
      if let askForPasswordDelay = managedPolicyState.askForPasswordDelay {
        known.append(
          "Password is required \(formattedPasswordDelay(askForPasswordDelay)) after screen saver or sleep."
        )
      } else {
        known.append("Password is required after screen saver or sleep.")
      }
    }

    if let screenSaverIdleTime = managedPolicyState.screenSaverIdleTime {
      let formattedIdleTime = formattedPolicyInterval(screenSaverIdleTime)
      switch sleepBehavior {
      case .keepDisplayAwake:
        possible.append(
          "Keeping the display awake should help with normal idle sleep, but a managed screen saver or lock policy may still interrupt the session after \(formattedIdleTime)."
        )
      case .allowDisplaySleep:
        possible.append(
          "The Mac should stay awake for background work, but the display can sleep and the managed screen saver or lock flow may still appear after \(formattedIdleTime)."
        )
      }
    }

    if let loginWindowIdleTime = managedPolicyState.loginWindowIdleTime {
      possible.append(
        "If the Mac returns to the login window, the login screen screen saver can start after \(formattedPolicyInterval(loginWindowIdleTime))."
      )
    }

    let title: String
    if managedPolicyState.autoLogoutDelay != nil {
      title = "Managed policies can end or interrupt long idle sessions"
    } else {
      title = "Managed policies may still lock or cover the session"
    }

    return BehaviorPolicyNotice(title: title, known: known, possible: possible)
  }

  /// Formats the compact countdown shown in the menu bar pill.
  var menuBarClockText: String {
    guard hasSession else { return "" }

    let remaining = effectiveRemaining
    let remainingSeconds = max(0, Int(remaining.rounded(.down)))
    let sessionStartedWithHour = effectiveSessionDuration >= 3600
    let totalMinutes = remainingSeconds / 60

    if remainingSeconds >= 3600 || sessionStartedWithHour {
      let hours = totalMinutes / 60
      let minutes = totalMinutes % 60
      return String(format: "%dh %02dm", hours, minutes)
    }

    return "\(totalMinutes)m"
  }

  /// Starts a new awake session for the requested number of minutes.
  /// - Parameter minutes: The session length in minutes.
  func start(minutes: Int) {
    let duration = Double(minutes * 60)
    let startDate = Date()

    now = startDate
    sessionDuration = duration
    endDate = startDate.addingTimeInterval(duration)
    pausedRemaining = nil
    saveState()
    syncPowerAssertion()
  }

  /// Pauses the app session while retaining the remaining duration.
  /// IPC sessions are not affected by pause.
  func pause() {
    guard hasAppSession else { return }

    pausedRemaining = appSessionRemaining
    endDate = nil
    saveState()
    syncPowerAssertion()
  }

  /// Resumes a previously paused session.
  func resume() {
    guard isPaused, let pausedRemaining else { return }

    let resumeDate = Date()
    now = resumeDate
    endDate = resumeDate.addingTimeInterval(pausedRemaining)
    self.pausedRemaining = nil
    saveState()
    syncPowerAssertion()
  }

  /// Stops all sessions (app and IPC) and clears persisted timer state.
  func stop() {
    endDate = nil
    sessionDuration = nil
    pausedRemaining = nil
    ipcSessions = [:]
    saveState()
    saveIPCSessions()
    syncPowerAssertion()
  }

  // MARK: - IPC session management

  /// Registers or refreshes a named IPC session from an external caller.
  ///
  /// If a session with the same ID already exists, it is replaced with the new
  /// duration. Durations are capped at `maxIPCDuration` (24 hours).
  ///
  /// - Parameters:
  ///   - id: Caller-provided session identifier. Must be non-empty.
  ///   - label: Display label shown in the session list. Must be non-empty.
  ///   - duration: Requested duration in seconds. Capped at 24 hours.
  /// - Returns: `true` if the session was accepted, `false` if validation failed.
  @discardableResult
  func activateIPCSession(id: String, label: String, duration: TimeInterval) -> Bool {
    guard !id.isEmpty, !label.isEmpty, duration > 0 else {
      ipcLog.warning("activateIPCSession: rejected — id=\(id, privacy: .public) label=\(label, privacy: .public) duration=\(duration)")
      return false
    }

    let clampedDuration = min(duration, maxIPCDuration)
    ipcLog.info("activateIPCSession: id=\(id, privacy: .public) label=\(label, privacy: .public) raw=\(duration) clamped=\(clampedDuration)")

    let activationDate = Date()

    ipcSessions[id] = IPCSession(
      id: id,
      label: label,
      endDate: activationDate.addingTimeInterval(clampedDuration),
      createdDate: activationDate
    )
    saveIPCSessions()
    syncPowerAssertion()
    ipcLog.info("activateIPCSession: stored, total ipcSessions=\(self.ipcSessions.count)")
    return true
  }

  /// Removes a named IPC session by its identifier.
  /// - Parameter id: The session identifier to deactivate.
  func deactivateIPCSession(id: String) {
    if ipcSessions.removeValue(forKey: id) != nil {
      ipcLog.info("deactivateIPCSession: removed id=\(id, privacy: .public), remaining=\(self.ipcSessions.count)")
      saveIPCSessions()
      syncPowerAssertion()
    } else {
      ipcLog.warning("deactivateIPCSession: id=\(id, privacy: .public) not found — ignored")
    }
  }

  /// Updates the sleep behavior and refreshes the power assertion when necessary.
  /// - Parameter enabled: `true` to keep the display awake, `false` to allow display sleep.
  func setKeepsDisplayAwake(_ enabled: Bool) {
    let newBehavior: SleepBehavior = enabled ? .keepDisplayAwake : .allowDisplaySleep
    guard newBehavior != sleepBehavior else { return }

    sleepBehavior = newBehavior
    saveState()

    guard effectiveEndDate != nil else { return }

    releasePowerAssertion()
    acquirePowerAssertionIfNeeded()
  }

  /// Formats the remaining session time for either the menu bar or expanded UI.
  /// - Parameter compact: Indicates whether to use a short compact format.
  /// - Returns: A human-readable remaining-time string.
  func formattedRemaining(compact: Bool = false) -> String {
    let remaining = max(0, Int(effectiveRemaining))
    guard remaining > 0 else { return compact ? "Idle" : "00:00" }
    let hours = remaining / 3600
    let minutes = (remaining % 3600) / 60
    let seconds = remaining % 60

    if compact {
      if remaining <= 90 {
        return "\(remaining)s"
      }
      if remaining >= 3600 || effectiveSessionDuration >= 3600 {
        return String(format: "%d:%02d", hours, minutes)
      }
      return "\(remaining / 60)m"
    }

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
  }

  /// Starts the one-second timer that advances session state, checks for
  /// expiration, and throttles policy refreshes. The timer is added to
  /// `.common` run loop mode so it fires during modal tracking.
  private func startClock() {
    clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        self.now = Date()
        self.refreshManagedPolicyState()
        self.pruneExpiredIPCSessions()
        // AGENT: Only stop the app session here — IPC sessions are pruned
        // independently above. If IPC sessions still hold the Mac awake,
        // the power assertion remains via syncPowerAssertion in prune.
        if let endDate = self.endDate, endDate <= self.now {
          self.endDate = nil
          self.sessionDuration = nil
          self.pausedRemaining = nil
          self.saveState()
          self.syncPowerAssertion()
        }
      }
    }
    RunLoop.main.add(clockTimer!, forMode: .common)
  }

  /// Applies the current appearance mode to `NSApp`.
  ///
  /// Only assigns `NSApp.appearance` when an explicit override (light/dark)
  /// is active, or when reverting a previous override back to system default.
  // AGENT: Setting NSApp.appearance = nil is NOT the same as never setting it.
  // The MenuBarExtra .window style panel inherits special vibrancy/material
  // from the menu bar. Assigning nil when NSApp.appearance was never touched
  // forces AppKit to re-resolve the appearance chain, which breaks the
  // panel's native material and makes controls (Toggle, backgrounds) render
  // differently. We guard against this by only assigning when there is
  // already an override in place or when we need to install one.
      /// Applies the stored appearance mode to NSApp. Must only be called after
      /// NSApp is fully initialized (i.e., from applicationDidFinishLaunching or
      /// later). Calling this from init() will crash because NSApp is nil at that
      /// point.
  func applyAppearance() {
    let desired = appearanceMode.nsAppearance
    guard desired != nil || NSApp.appearance != nil else { return }
    NSApp.appearance = desired
  }

  /// Ensures the power assertion matches the current effective timer state.
  /// The assertion is held whenever any session (app or IPC) is active.
  private func syncPowerAssertion() {
    if effectiveEndDate != nil {
      acquirePowerAssertionIfNeeded()
    } else {
      releasePowerAssertion()
    }
  }

  /// Acquires the active power assertion if one is not already held.
  private func acquirePowerAssertionIfNeeded() {
    guard !powerAssertionIsActive else { return }

    var assertionID: IOPMAssertionID = 0
    let result = IOPMAssertionCreateWithName(
      sleepBehavior.assertionType,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      powerAssertionReason,
      &assertionID
    )

    guard result == kIOReturnSuccess else {
      powerAssertionIsActive = false
      assertionErrorMessage = "Power assertion failed (\(result))"
      return
    }

    powerAssertionID = assertionID
    powerAssertionIsActive = true
    assertionErrorMessage = nil
  }

  /// Releases the current power assertion and clears related error state.
  private func releasePowerAssertion() {
    guard powerAssertionIsActive else { return }

    IOPMAssertionRelease(powerAssertionID)
    powerAssertionID = 0
    powerAssertionIsActive = false
    assertionErrorMessage = nil
  }

  /// Restores any persisted session and behavior state from user defaults.
  private func restoreSavedState() {
    let endDateInterval = UserDefaults.standard.double(forKey: endDateDefaultsKey)
    let duration = UserDefaults.standard.double(forKey: durationDefaultsKey)
    let pausedRemaining = UserDefaults.standard.double(forKey: pausedRemainingDefaultsKey)
    let savedSleepBehavior = UserDefaults.standard.string(forKey: sleepBehaviorDefaultsKey)

    if let savedSleepBehavior, let behavior = SleepBehavior(rawValue: savedSleepBehavior) {
      sleepBehavior = behavior
    }

    if let savedAppearanceMode = UserDefaults.standard.string(forKey: appearanceModeDefaultsKey),
      let mode = AppearanceMode(rawValue: savedAppearanceMode)
    {
      appearanceMode = mode
    }

    launchAtLogin = SMAppService.mainApp.status == .enabled

    sessionDuration = duration > 0 ? duration : nil

    if pausedRemaining > 0 {
      self.pausedRemaining = pausedRemaining
      endDate = nil
      return
    }

    guard endDateInterval > 0 else { return }

    let restoredEndDate = Date(timeIntervalSince1970: endDateInterval)
    if restoredEndDate > Date() {
      endDate = restoredEndDate
      sessionDuration = duration > 0 ? duration : restoredEndDate.timeIntervalSince(Date())
    } else {
      endDate = nil
      sessionDuration = nil
      self.pausedRemaining = nil
      UserDefaults.standard.removeObject(forKey: endDateDefaultsKey)
      UserDefaults.standard.removeObject(forKey: durationDefaultsKey)
      UserDefaults.standard.removeObject(forKey: pausedRemainingDefaultsKey)
    }
  }

  /// Persists the current session and behavior state to user defaults.
  private func saveState() {
    if let endDate {
      UserDefaults.standard.set(endDate.timeIntervalSince1970, forKey: endDateDefaultsKey)
    } else {
      UserDefaults.standard.removeObject(forKey: endDateDefaultsKey)
    }

    if let sessionDuration {
      UserDefaults.standard.set(sessionDuration, forKey: durationDefaultsKey)
    } else {
      UserDefaults.standard.removeObject(forKey: durationDefaultsKey)
    }

    if let pausedRemaining {
      UserDefaults.standard.set(pausedRemaining, forKey: pausedRemainingDefaultsKey)
    } else {
      UserDefaults.standard.removeObject(forKey: pausedRemainingDefaultsKey)
    }

    UserDefaults.standard.set(sleepBehavior.rawValue, forKey: sleepBehaviorDefaultsKey)
  }

  // MARK: - Effective state (merged app + IPC sessions)

  // AGENT: The "effective" properties merge the app session with all IPC sessions.
  // The app session's own end date and the IPC sessions' end dates are combined
  // to find the true awake deadline. This lets the UI, menu bar pill, and power
  // assertion all reflect the maximum remaining time across all callers.

  /// The furthest end date across the app session and all active IPC sessions.
  /// Returns `nil` when no session of any kind is active.
  private var effectiveEndDate: Date? {
    var candidates: [Date] = []
    if let endDate, endDate > now { candidates.append(endDate) }
    candidates += ipcSessions.values.filter { $0.isActive(at: now) }.map(\.endDate)
    return candidates.max()
  }

  /// The effective remaining interval across all active sessions.
  /// Paused app sessions contribute their frozen remaining value.
  private var effectiveRemaining: TimeInterval {
    if let pausedRemaining, pausedRemaining > 0 {
      // When paused, the app session contributes its frozen time.
      // IPC sessions may still be running, so take the max.
      let ipcMax = ipcSessions.values
        .filter { $0.isActive(at: now) }
        .map { $0.remaining(at: now) }
        .max() ?? 0
      return max(pausedRemaining, ipcMax)
    }
    guard let effective = effectiveEndDate else { return 0 }
    return max(0, effective.timeIntervalSince(now))
  }

  /// The app-session-only remaining interval (excludes IPC sessions).
  /// Used by `behaviorPolicyNotice` for policy threshold comparisons.
  private var remainingInterval: TimeInterval {
    if let endDate {
      return max(0, endDate.timeIntervalSince(now))
    }
    if let pausedRemaining {
      return max(0, pausedRemaining)
    }
    return 0
  }

  /// The full duration of whichever session drives the effective end date.
  /// Used by the progress ring to compute the full-arc reference.
  private var effectiveSessionDuration: TimeInterval {
    // If the app session drives the effective end date, use its explicit duration.
    if let endDate, let effectiveEnd = effectiveEndDate, endDate == effectiveEnd {
      return sessionDuration ?? effectiveRemaining
    }
    // If the app session is paused, use its duration for the ring.
    if isPaused, let sessionDuration { return sessionDuration }
    // Otherwise an IPC session is driving — use its creation-to-end duration.
    if let winner = ipcSessions.values
      .filter({ $0.isActive(at: now) })
      .max(by: { $0.endDate < $1.endDate })
    {
      return winner.duration
    }
    // Fallback for edge cases.
    return sessionDuration ?? effectiveRemaining
  }

  /// Returns the remaining duration for the app session only (not IPC sessions).
  /// Used by pause to capture the app session's own remaining time.
  private var appSessionRemaining: TimeInterval {
    if let endDate {
      return max(0, endDate.timeIntervalSince(now))
    }
    if let pausedRemaining {
      return max(0, pausedRemaining)
    }
    return 0
  }

  // MARK: - IPC session persistence

  /// Removes IPC sessions that have expired, persisting and syncing if any changed.
  private func pruneExpiredIPCSessions() {
    let expiredIDs = ipcSessions.values.filter { !$0.isActive(at: now) }.map(\.id)
    guard !expiredIDs.isEmpty else { return }
    ipcLog.info("pruneExpiredIPCSessions: pruning \(expiredIDs.count) expired session(s): \(expiredIDs.joined(separator: ","), privacy: .public)")
    for id in expiredIDs { ipcSessions.removeValue(forKey: id) }
    saveIPCSessions()
    syncPowerAssertion()
  }

  /// Persists active IPC sessions to UserDefaults as a JSON-encoded array.
  private func saveIPCSessions() {
    let active = ipcSessions.values.filter { $0.isActive(at: Date()) }
    if active.isEmpty {
      UserDefaults.standard.removeObject(forKey: ipcSessionsDefaultsKey)
      return
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    if let data = try? encoder.encode(Array(active)) {
      UserDefaults.standard.set(data, forKey: ipcSessionsDefaultsKey)
    }
  }

  /// Restores IPC sessions from UserDefaults, filtering out any that have expired.
  private func restoreIPCSessions() {
    guard let data = UserDefaults.standard.data(forKey: ipcSessionsDefaultsKey) else {
      ipcLog.info("restoreIPCSessions: no persisted sessions found")
      return
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    guard let sessions = try? decoder.decode([IPCSession].self, from: data) else { return }
    let restoreDate = Date()
    let active = sessions.filter { $0.isActive(at: restoreDate) }
    ipcSessions = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
    ipcLog.info("restoreIPCSessions: restored \(self.ipcSessions.count) active session(s)")
  }

  /// Refreshes managed policy state on demand or at a throttled interval.
  /// - Parameter force: Set to `true` to bypass the refresh throttle.
  private func refreshManagedPolicyState(force: Bool = false) {
    let refreshDate = Date()
    guard force || refreshDate.timeIntervalSince(lastPolicyRefresh) >= 60 else { return }

    managedPolicyState = ManagedPolicyState.load(forUser: NSUserName())
    lastPolicyRefresh = refreshDate
  }

  /// Formats a managed-policy interval for warning messages.
  /// - Parameter interval: The interval to format.
  /// - Returns: A short human-readable duration.
  private func formattedPolicyInterval(_ interval: TimeInterval) -> String {
    let seconds = max(0, Int(interval.rounded()))
    if seconds < 60 {
      return "\(seconds)s"
    }

    let minutes = seconds / 60
    let remainderSeconds = seconds % 60
    if minutes < 60 {
      return remainderSeconds == 0 ? "\(minutes)m" : "\(minutes)m \(remainderSeconds)s"
    }

    let hours = minutes / 60
    let remainderMinutes = minutes % 60
    return remainderMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainderMinutes)m"
  }

  /// Formats a password prompt delay for managed-policy messaging.
  /// - Parameter interval: The delay before a password prompt appears.
  /// - Returns: A localized description of the delay.
  private func formattedPasswordDelay(_ interval: TimeInterval) -> String {
    if interval <= 0 {
      return "immediately"
    }
    return "\(formattedPolicyInterval(interval)) later"
  }
}

#if DEBUG
  extension AwakeSessionManager.PreviewState {
    /// Builds a preview state with no active session.
    /// - Returns: An idle preview state.
    static func idle() -> Self {
      Self(
        now: Date(timeIntervalSinceReferenceDate: 0),
        endDate: nil,
        sessionDuration: nil,
        pausedRemaining: nil,
        ipcSessions: [:],
        powerAssertionIsActive: false,
        assertionErrorMessage: nil,
        sleepBehavior: .keepDisplayAwake,
        appearanceMode: .system,
        managedPolicyState: .init(
          screenSaverIdleTime: nil,
          loginWindowIdleTime: nil,
          asksForPasswordAfterScreenSaver: false,
          askForPasswordDelay: nil,
          autoLogoutDelay: nil,
          disablesAutoLogin: false
        )
      )
    }

    /// Builds a preview state for an active session.
    /// - Parameters:
    ///   - remaining: The remaining duration in seconds.
    ///   - sessionDuration: The full session duration in seconds.
    ///   - keepsDisplayAwake: Indicates whether display sleep is prevented.
    ///   - policyState: Managed policy values to expose in the preview.
    ///   - powerAssertionIsActive: Indicates whether the power assertion should appear active.
    ///   - assertionErrorMessage: The assertion failure text to expose, if any.
    ///   - ipcSessions: IPC sessions to include in the preview.
    /// - Returns: An active preview state.
    static func active(
      remaining: TimeInterval,
      sessionDuration: TimeInterval,
      keepsDisplayAwake: Bool = true,
      policyState: AwakeSessionManager.ManagedPolicyState? = nil,
      powerAssertionIsActive: Bool = true,
      assertionErrorMessage: String? = nil,
      ipcSessions: [String: IPCSession] = [:]
    ) -> Self {
      let now = Date(timeIntervalSinceReferenceDate: 0)
      return Self(
        now: now,
        endDate: now.addingTimeInterval(remaining),
        sessionDuration: sessionDuration,
        pausedRemaining: nil,
        ipcSessions: ipcSessions,
        powerAssertionIsActive: powerAssertionIsActive,
        assertionErrorMessage: assertionErrorMessage,
        sleepBehavior: keepsDisplayAwake ? .keepDisplayAwake : .allowDisplaySleep,
        appearanceMode: .system,
        managedPolicyState: policyState
          ?? .init(
            screenSaverIdleTime: nil,
            loginWindowIdleTime: nil,
            asksForPasswordAfterScreenSaver: false,
            askForPasswordDelay: nil,
            autoLogoutDelay: nil,
            disablesAutoLogin: false
          )
      )
    }

    /// Builds a preview state for a paused session.
    /// - Parameters:
    ///   - remaining: The paused time remaining in seconds.
    ///   - sessionDuration: The full session duration in seconds.
    /// - Returns: A paused preview state.
    static func paused(remaining: TimeInterval, sessionDuration: TimeInterval) -> Self {
      let now = Date(timeIntervalSinceReferenceDate: 0)
      return Self(
        now: now,
        endDate: nil,
        sessionDuration: sessionDuration,
        pausedRemaining: remaining,
        ipcSessions: [:],
        powerAssertionIsActive: false,
        assertionErrorMessage: nil,
        sleepBehavior: .keepDisplayAwake,
        appearanceMode: .system,
        managedPolicyState: .init(
          screenSaverIdleTime: nil,
          loginWindowIdleTime: nil,
          asksForPasswordAfterScreenSaver: false,
          askForPasswordDelay: nil,
          autoLogoutDelay: nil,
          disablesAutoLogin: false
        )
      )
    }
  }
#endif
