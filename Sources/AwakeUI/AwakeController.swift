// MARK: - AwakeController
// Core timer lifecycle, IOKit power assertions, and managed policy detection.
// This is the central state object observed by all UI views via @ObservedObject.

import AppKit
import Foundation
import IOKit.pwr_mgt
import ServiceManagement

@MainActor
/// Manages timer lifecycle, power assertions, and managed policy awareness.
public final class AwakeController: ObservableObject {
  /// Captures a stable controller snapshot used by previews.
  struct PreviewState {
    let now: Date
    let endDate: Date?
    let sessionDuration: TimeInterval?
    let pausedRemaining: TimeInterval?
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

  @Published public private(set) var now = Date()
  @Published public private(set) var endDate: Date?
  @Published public private(set) var sessionDuration: TimeInterval?
  @Published public private(set) var pausedRemaining: TimeInterval?
  @Published public private(set) var powerAssertionIsActive = false
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
  private let powerAssertionReason = "Keep the Mac awake for an active Awake timer" as CFString

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
  public init() {
    restoreSavedState()
    applyAppearance()
    refreshManagedPolicyState(force: true)
    startClock()
    syncPowerAssertion()
  }

  /// Creates a controller seeded with preview data.
  /// - Parameter previewState: The preview snapshot to expose.
  init(previewState: PreviewState) {
    now = previewState.now
    endDate = previewState.endDate
    sessionDuration = previewState.sessionDuration
    pausedRemaining = previewState.pausedRemaining
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

  /// Indicates whether an awake session is currently running.
  public var isActive: Bool {
    guard let endDate else { return false }
    return endDate > now
  }

  /// Indicates whether a session is paused with remaining time preserved.
  public var isPaused: Bool {
    guard let pausedRemaining else { return false }
    return pausedRemaining > 0
  }

  /// Indicates whether there is either an active or paused session.
  public var hasSession: Bool {
    isActive || isPaused
  }

  /// Returns normalized progress remaining for the active or paused session.
  var progress: Double {
    guard let sessionDuration, sessionDuration > 0 else { return 0 }
    return min(max(remainingInterval / sessionDuration, 0), 1)
  }

  /// Returns the short status line shown in the main menu header.
  public var pulseStatusLine: String {
    if isPaused {
      return "Paused with \(formattedRemaining()) left"
    }
    guard isActive else { return "Not keeping the Mac awake" }
    guard powerAssertionIsActive else {
      return assertionErrorMessage ?? "Unable to prevent idle sleep"
    }
    switch sleepBehavior {
    case .keepDisplayAwake:
      return "Keeping display and Mac awake"
    case .allowDisplaySleep:
      return "Keeping Mac awake while display can sleep"
    }
  }

  /// Indicates whether the current behavior also prevents display sleep.
  public var keepsDisplayAwake: Bool {
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
  public var menuBarClockText: String {
    guard hasSession else { return "" }

    let remainingSeconds = max(0, Int(remainingInterval.rounded(.down)))
    let sessionStartedWithHour = (sessionDuration ?? 0) >= 3600
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

  /// Pauses the current session while retaining the remaining duration.
  func pause() {
    guard isActive else { return }

    pausedRemaining = remainingInterval
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

  /// Stops the current session and clears persisted timer state.
  func stop() {
    endDate = nil
    sessionDuration = nil
    pausedRemaining = nil
    saveState()
    syncPowerAssertion()
  }

  /// Updates the sleep behavior and refreshes the power assertion when necessary.
  /// - Parameter enabled: `true` to keep the display awake, `false` to allow display sleep.
  func setKeepsDisplayAwake(_ enabled: Bool) {
    let newBehavior: SleepBehavior = enabled ? .keepDisplayAwake : .allowDisplaySleep
    guard newBehavior != sleepBehavior else { return }

    sleepBehavior = newBehavior
    saveState()

    guard isActive else { return }

    releasePowerAssertion()
    acquirePowerAssertionIfNeeded()
  }

  /// Formats the remaining session time for either the menu bar or expanded UI.
  /// - Parameter compact: Indicates whether to use a short compact format.
  /// - Returns: A human-readable remaining-time string.
  public func formattedRemaining(compact: Bool = false) -> String {
    let remaining = max(0, Int(remainingInterval))
    guard remaining > 0 else { return compact ? "Idle" : "00:00" }
    let hours = remaining / 3600
    let minutes = (remaining % 3600) / 60
    let seconds = remaining % 60

    if compact {
      if remaining <= 90 {
        return "\(remaining)s"
      }
      if remaining >= 3600 || (sessionDuration ?? 0) >= 3600 {
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
        if let endDate = self.endDate, endDate <= self.now {
          self.stop()
        }
      }
    }
    RunLoop.main.add(clockTimer!, forMode: .common)
  }

  /// Applies the current appearance mode to `NSApp`.
  private func applyAppearance() {
    NSApp.appearance = appearanceMode.nsAppearance
  }

  /// Ensures the power assertion matches the current timer state.
  private func syncPowerAssertion() {
    if isActive {
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

  /// Returns the remaining duration for the active or paused session.
  private var remainingInterval: TimeInterval {
    if let endDate {
      return max(0, endDate.timeIntervalSince(now))
    }
    if let pausedRemaining {
      return max(0, pausedRemaining)
    }
    return 0
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
  extension AwakeController.PreviewState {
    /// Builds a preview state with no active session.
    /// - Returns: An idle preview state.
    static func idle() -> Self {
      Self(
        now: Date(timeIntervalSinceReferenceDate: 0),
        endDate: nil,
        sessionDuration: nil,
        pausedRemaining: nil,
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
    /// - Returns: An active preview state.
    static func active(
      remaining: TimeInterval,
      sessionDuration: TimeInterval,
      keepsDisplayAwake: Bool = true,
      policyState: AwakeController.ManagedPolicyState? = nil,
      powerAssertionIsActive: Bool = true,
      assertionErrorMessage: String? = nil
    ) -> Self {
      let now = Date(timeIntervalSinceReferenceDate: 0)
      return Self(
        now: now,
        endDate: now.addingTimeInterval(remaining),
        sessionDuration: sessionDuration,
        pausedRemaining: nil,
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
