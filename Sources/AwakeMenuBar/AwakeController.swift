import AppKit
import Foundation
import IOKit.pwr_mgt

@MainActor
final class AwakeController: ObservableObject {
    struct ManagedPolicyState {
        let screenSaverIdleTime: TimeInterval?
        let loginWindowIdleTime: TimeInterval?
        let asksForPasswordAfterScreenSaver: Bool
        let askForPasswordDelay: TimeInterval?
        let autoLogoutDelay: TimeInterval?
        let disablesAutoLogin: Bool

        var hasRelevantWarnings: Bool {
            screenSaverIdleTime != nil || asksForPasswordAfterScreenSaver || autoLogoutDelay != nil
        }

        static func load(forUser user: String) -> ManagedPolicyState {
            let managedPreferencesURL = URL(fileURLWithPath: "/Library/Managed Preferences", isDirectory: true)
            let systemScreensaver = plist(at: managedPreferencesURL.appendingPathComponent("com.apple.screensaver.plist"))
            let userScreensaver = plist(at: managedPreferencesURL.appendingPathComponent(user, isDirectory: true).appendingPathComponent("com.apple.screensaver.plist"))
            let mergedScreensaver = systemScreensaver.merging(userScreensaver, uniquingKeysWith: { _, userValue in userValue })

            let systemLoginWindow = plist(at: managedPreferencesURL.appendingPathComponent("com.apple.loginwindow.plist"))
            let userLoginWindow = plist(at: managedPreferencesURL.appendingPathComponent(user, isDirectory: true).appendingPathComponent("com.apple.loginwindow.plist"))
            let mergedLoginWindow = systemLoginWindow.merging(userLoginWindow, uniquingKeysWith: { _, userValue in userValue })

            return ManagedPolicyState(
                screenSaverIdleTime: timeInterval(forKey: "idleTime", in: mergedScreensaver),
                loginWindowIdleTime: timeInterval(forKey: "loginWindowIdleTime", in: mergedScreensaver),
                asksForPasswordAfterScreenSaver: bool(forKey: "askForPassword", in: mergedScreensaver) ?? false,
                askForPasswordDelay: timeInterval(forKey: "askForPasswordDelay", in: mergedScreensaver),
                autoLogoutDelay: timeInterval(forKey: "autoLogoutDelay", in: mergedLoginWindow),
                disablesAutoLogin: bool(forKey: "com.apple.login.mcx.DisableAutoLoginClient", in: mergedLoginWindow) ?? false
            )
        }

        private static func plist(at url: URL) -> [String: Any] {
            guard let data = try? Data(contentsOf: url) else { return [:] }
            guard let raw = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return [:] }
            return raw as? [String: Any] ?? [:]
        }

        private static func timeInterval(forKey key: String, in values: [String: Any]) -> TimeInterval? {
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

    struct BehaviorPolicyNotice {
        let title: String
        let known: [String]
        let possible: [String]
    }

    enum SleepBehavior: String {
        case keepDisplayAwake
        case allowDisplaySleep

        var assertionType: CFString {
            switch self {
            case .keepDisplayAwake:
                return kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
            case .allowDisplaySleep:
                return kIOPMAssertionTypeNoIdleSleep as CFString
            }
        }
    }

    @Published private(set) var now = Date()
    @Published private(set) var endDate: Date?
    @Published private(set) var sessionDuration: TimeInterval?
    @Published private(set) var pausedRemaining: TimeInterval?
    @Published private(set) var powerAssertionIsActive = false
    @Published private(set) var assertionErrorMessage: String?
    @Published private(set) var sleepBehavior: SleepBehavior = .keepDisplayAwake
    @Published private(set) var managedPolicyState = ManagedPolicyState(
        screenSaverIdleTime: nil,
        loginWindowIdleTime: nil,
        asksForPasswordAfterScreenSaver: false,
        askForPasswordDelay: nil,
        autoLogoutDelay: nil,
        disablesAutoLogin: false
    )

    nonisolated(unsafe) private var clockTimer: Timer?
    private var powerAssertionID: IOPMAssertionID = 0
    private var lastPolicyRefresh = Date.distantPast
    private let endDateDefaultsKey = "awake.endDate"
    private let durationDefaultsKey = "awake.duration"
    private let pausedRemainingDefaultsKey = "awake.pausedRemaining"
    private let sleepBehaviorDefaultsKey = "awake.sleepBehavior"
    private let powerAssertionReason = "Keep the Mac awake for an active Awake timer" as CFString

    let presets: [(label: String, minutes: Int)] = [
        ("5 minutes", 5),
        ("10 minutes", 10),
        ("15 minutes", 15),
        ("30 minutes", 30),
        ("1 hour", 60),
        ("2 hours", 2 * 60),
        ("4 hours", 4 * 60),
        ("8 hours", 8 * 60),
        ("12 hours", 12 * 60)
    ]

    init() {
        restoreSavedState()
        refreshManagedPolicyState(force: true)
        startClock()
        syncPowerAssertion()
    }

    deinit {
        clockTimer?.invalidate()
        if powerAssertionID != 0 {
            IOPMAssertionRelease(powerAssertionID)
        }
    }

    var isActive: Bool {
        guard let endDate else { return false }
        return endDate > now
    }

    var isPaused: Bool {
        guard let pausedRemaining else { return false }
        return pausedRemaining > 0
    }

    var hasSession: Bool {
        isActive || isPaused
    }

    var progress: Double {
        guard let sessionDuration, sessionDuration > 0 else { return 0 }
        return min(max(remainingInterval / sessionDuration, 0), 1)
    }

    var pulseStatusLine: String {
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

    var keepsDisplayAwake: Bool {
        sleepBehavior == .keepDisplayAwake
    }

    var behaviorPolicyNotice: BehaviorPolicyNotice? {
        guard managedPolicyState.hasRelevantWarnings else { return nil }

        var known: [String] = []
        var possible: [String] = []

        if let autoLogoutDelay = managedPolicyState.autoLogoutDelay {
            known.append("Managed auto-logout is set for \(formattedPolicyInterval(autoLogoutDelay)) of inactivity. Background work may stop when the session is logged out.")
        }

        if let screenSaverIdleTime = managedPolicyState.screenSaverIdleTime {
            let willTriggerWithinSession = hasSession && remainingInterval > screenSaverIdleTime
            let timing = willTriggerWithinSession ? "during this session" : "after \(formattedPolicyInterval(screenSaverIdleTime)) of inactivity"
            known.append("Managed screen saver behavior can start \(timing).")
        }

        if managedPolicyState.asksForPasswordAfterScreenSaver {
            if let askForPasswordDelay = managedPolicyState.askForPasswordDelay {
                known.append("Password is required \(formattedPasswordDelay(askForPasswordDelay)) after screen saver or sleep.")
            } else {
                known.append("Password is required after screen saver or sleep.")
            }
        }

        if let screenSaverIdleTime = managedPolicyState.screenSaverIdleTime {
            let formattedIdleTime = formattedPolicyInterval(screenSaverIdleTime)
            switch sleepBehavior {
            case .keepDisplayAwake:
                possible.append("Keeping the display awake should help with normal idle sleep, but a managed screen saver or lock policy may still interrupt the session after \(formattedIdleTime).")
            case .allowDisplaySleep:
                possible.append("The Mac should stay awake for background work, but the display can sleep and the managed screen saver or lock flow may still appear after \(formattedIdleTime).")
            }
        }

        if let loginWindowIdleTime = managedPolicyState.loginWindowIdleTime {
            possible.append("If the Mac returns to the login window, the login screen screen saver can start after \(formattedPolicyInterval(loginWindowIdleTime)).")
        }

        let title: String
        if managedPolicyState.autoLogoutDelay != nil {
            title = "Managed policies can end or interrupt long idle sessions"
        } else {
            title = "Managed policies may still lock or cover the session"
        }

        return BehaviorPolicyNotice(title: title, known: known, possible: possible)
    }

    var menuBarClockText: String {
        guard hasSession else { return "" }

        let remainingSeconds = max(0, Int(remainingInterval.rounded(.down)))
        if remainingSeconds <= 90 {
            return "\(remainingSeconds)s"
        }

        let sessionStartedWithHour = (sessionDuration ?? 0) >= 3600
        let totalMinutes = remainingSeconds / 60

        if remainingSeconds >= 3600 || sessionStartedWithHour {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return String(format: "%d:%02d", hours, minutes)
        }

        return "\(totalMinutes)m"
    }

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

    func pause() {
        guard isActive else { return }

        pausedRemaining = remainingInterval
        endDate = nil
        saveState()
        syncPowerAssertion()
    }

    func resume() {
        guard isPaused, let pausedRemaining else { return }

        let resumeDate = Date()
        now = resumeDate
        endDate = resumeDate.addingTimeInterval(pausedRemaining)
        self.pausedRemaining = nil
        saveState()
        syncPowerAssertion()
    }

    func stop() {
        endDate = nil
        sessionDuration = nil
        pausedRemaining = nil
        saveState()
        syncPowerAssertion()
    }

    func setKeepsDisplayAwake(_ enabled: Bool) {
        let newBehavior: SleepBehavior = enabled ? .keepDisplayAwake : .allowDisplaySleep
        guard newBehavior != sleepBehavior else { return }

        sleepBehavior = newBehavior
        saveState()

        guard isActive else { return }

        releasePowerAssertion()
        acquirePowerAssertionIfNeeded()
    }

    func formattedRemaining(compact: Bool = false) -> String {
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

    private func syncPowerAssertion() {
        if isActive {
            acquirePowerAssertionIfNeeded()
        } else {
            releasePowerAssertion()
        }
    }

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

    private func releasePowerAssertion() {
        guard powerAssertionIsActive else { return }

        IOPMAssertionRelease(powerAssertionID)
        powerAssertionID = 0
        powerAssertionIsActive = false
        assertionErrorMessage = nil
    }

    private func restoreSavedState() {
        let endDateInterval = UserDefaults.standard.double(forKey: endDateDefaultsKey)
        let duration = UserDefaults.standard.double(forKey: durationDefaultsKey)
        let pausedRemaining = UserDefaults.standard.double(forKey: pausedRemainingDefaultsKey)
        let savedSleepBehavior = UserDefaults.standard.string(forKey: sleepBehaviorDefaultsKey)

        if let savedSleepBehavior, let behavior = SleepBehavior(rawValue: savedSleepBehavior) {
            sleepBehavior = behavior
        }

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

    private var remainingInterval: TimeInterval {
        if let endDate {
            return max(0, endDate.timeIntervalSince(now))
        }
        if let pausedRemaining {
            return max(0, pausedRemaining)
        }
        return 0
    }

    private func refreshManagedPolicyState(force: Bool = false) {
        let refreshDate = Date()
        guard force || refreshDate.timeIntervalSince(lastPolicyRefresh) >= 60 else { return }

        managedPolicyState = ManagedPolicyState.load(forUser: NSUserName())
        lastPolicyRefresh = refreshDate
    }

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

    private func formattedPasswordDelay(_ interval: TimeInterval) -> String {
        if interval <= 0 {
            return "immediately"
        }
        return "\(formattedPolicyInterval(interval)) later"
    }
}
