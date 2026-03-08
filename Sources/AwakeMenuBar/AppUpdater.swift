import Foundation
import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject {
    struct UpdateNotice: Equatable {
        enum Kind: Equatable {
            case available
            case downloading(progress: Double?)
            case preparing
            case readyToInstall
            case installing
            case failed
        }

        let kind: Kind
        let title: String
        let message: String
        let version: String?
        let primaryActionTitle: String?
        let secondaryActionTitle: String?
    }

    @Published private(set) var notice: UpdateNotice?
    @Published private(set) var isEnabled = false

    private var updater: SPUUpdater?
    private var pendingChoiceReply: ((SPUUserUpdateChoice) -> Void)?
    private var immediateInstallHandler: (() -> Void)?
    private var availableVersion: String?
    private var downloadExpectedLength: UInt64?
    private var downloadReceivedLength: UInt64 = 0

    override init() {
        super.init()
        configureUpdaterIfPossible()
    }

    func installUpdate() {
        if let immediateInstallHandler {
            immediateInstallHandler()
            self.immediateInstallHandler = nil
            notice = UpdateNotice(
                kind: .installing,
                title: "Installing update",
                message: "Awake will relaunch when the new version is in place.",
                version: availableVersion,
                primaryActionTitle: nil,
                secondaryActionTitle: nil
            )
            return
        }

        guard let pendingChoiceReply else { return }
        self.pendingChoiceReply = nil
        pendingChoiceReply(.install)
    }

    func dismissNotice() {
        if let pendingChoiceReply {
            self.pendingChoiceReply = nil
            pendingChoiceReply(.dismiss)
        }

        notice = nil
    }

    private func configureUpdaterIfPossible() {
        guard hasRequiredConfiguration else { return }

        isEnabled = true

        do {
            let updater = SPUUpdater(
                hostBundle: .main,
                applicationBundle: .main,
                userDriver: self,
                delegate: self
            )
            self.updater = updater
            try updater.start()
        } catch {
            isEnabled = false
            notice = UpdateNotice(
                kind: .failed,
                title: "Updates unavailable",
                message: error.localizedDescription,
                version: nil,
                primaryActionTitle: nil,
                secondaryActionTitle: "Dismiss"
            )
        }
    }

    private var hasRequiredConfiguration: Bool {
        guard let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              !feedURL.isEmpty,
              let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !publicKey.isEmpty else {
            return false
        }
        return true
    }

    private func makeVersionString(for item: SUAppcastItem) -> String {
        let displayVersion = item.displayVersionString.trimmingCharacters(in: .whitespacesAndNewlines)
        if displayVersion.isEmpty {
            return item.versionString
        }
        return displayVersion
    }

    private func updateDownloadingNotice() {
        let progress: Double?
        if let downloadExpectedLength, downloadExpectedLength > 0 {
            progress = min(max(Double(downloadReceivedLength) / Double(downloadExpectedLength), 0), 1)
        } else {
            progress = nil
        }

        let message: String
        if let progress {
            message = "Version \(availableVersion ?? "new") is downloading (\(Int(progress * 100))%)."
        } else {
            message = "Version \(availableVersion ?? "new") is downloading."
        }

        notice = UpdateNotice(
            kind: .downloading(progress: progress),
            title: "Update available",
            message: message,
            version: availableVersion,
            primaryActionTitle: nil,
            secondaryActionTitle: nil
        )
    }
}

extension AppUpdater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        availableVersion = makeVersionString(for: item)
        self.immediateInstallHandler = immediateInstallHandler
        notice = UpdateNotice(
            kind: .readyToInstall,
            title: "Update ready",
            message: "Version \(availableVersion ?? "new") is ready to install.",
            version: availableVersion,
            primaryActionTitle: "Install update",
            secondaryActionTitle: nil
        )
        return true
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        guard let error else { return }
        guard notice != nil else { return }

        notice = UpdateNotice(
            kind: .failed,
            title: "Update failed",
            message: error.localizedDescription,
            version: availableVersion,
            primaryActionTitle: nil,
            secondaryActionTitle: "Dismiss"
        )
    }
}

extension AppUpdater: SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
    }

    func dismissUserInitiatedUpdateCheck() {
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        availableVersion = makeVersionString(for: appcastItem)
        pendingChoiceReply = reply

        notice = UpdateNotice(
            kind: .available,
            title: "Update available",
            message: "Version \(availableVersion ?? "new") is available for Awake.",
            version: availableVersion,
            primaryActionTitle: "Install update",
            secondaryActionTitle: "Later"
        )
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
    }

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        notice = UpdateNotice(
            kind: .failed,
            title: "Update failed",
            message: error.localizedDescription,
            version: availableVersion,
            primaryActionTitle: nil,
            secondaryActionTitle: "Dismiss"
        )
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        pendingChoiceReply = nil
        immediateInstallHandler = nil
        downloadExpectedLength = nil
        downloadReceivedLength = 0
        notice = nil
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        downloadExpectedLength = nil
        downloadReceivedLength = 0
        updateDownloadingNotice()
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        downloadExpectedLength = expectedContentLength
        updateDownloadingNotice()
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        downloadReceivedLength += length
        updateDownloadingNotice()
    }

    func showDownloadDidStartExtractingUpdate() {
        notice = UpdateNotice(
            kind: .preparing,
            title: "Preparing update",
            message: "Version \(availableVersion ?? "new") has downloaded and is being prepared.",
            version: availableVersion,
            primaryActionTitle: nil,
            secondaryActionTitle: nil
        )
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        notice = UpdateNotice(
            kind: .preparing,
            title: "Preparing update",
            message: "Version \(availableVersion ?? "new") is being prepared (\(Int(progress * 100))%).",
            version: availableVersion,
            primaryActionTitle: nil,
            secondaryActionTitle: nil
        )
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        pendingChoiceReply = reply
        notice = UpdateNotice(
            kind: .readyToInstall,
            title: "Update ready",
            message: "Version \(availableVersion ?? "new") is ready to install.",
            version: availableVersion,
            primaryActionTitle: "Install update",
            secondaryActionTitle: "Later"
        )
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        notice = UpdateNotice(
            kind: .installing,
            title: "Installing update",
            message: applicationTerminated
                ? "Awake will relaunch when the new version is installed."
                : "Awake is waiting for the current app instance to terminate before installing the update.",
            version: availableVersion,
            primaryActionTitle: nil,
            secondaryActionTitle: nil
        )
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdateInFocus() {
    }
}
