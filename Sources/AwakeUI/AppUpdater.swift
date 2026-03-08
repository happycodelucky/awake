// MARK: - AppUpdater
// Wraps Sparkle's SPUUpdater and SPUUserDriver into observable state that
// MenuContentView can display as an UpdateNoticeCard.

import Foundation
import Sparkle

@MainActor
/// Wraps Sparkle update flows in menu-friendly observable state.
public final class AppUpdater: NSObject, ObservableObject {
  /// Describes the update state currently presented to the user.
  struct UpdateNotice: Equatable {
    /// Represents the updater lifecycle phases surfaced in the UI.
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

  /// Creates and configures the Sparkle updater when the bundle supports updates.
  public override init() {
    super.init()
    configureUpdaterIfPossible()
  }

  /// Creates a preview-only updater state.
  /// - Parameters:
  ///   - previewNotice: The notice to expose in previews.
  ///   - isEnabled: Indicates whether updates should appear enabled in previews.
  init(previewNotice: UpdateNotice?, isEnabled: Bool = true) {
    self.notice = previewNotice
    self.isEnabled = isEnabled
    super.init()
  }

  /// Accepts the current install action, either immediate or deferred through Sparkle.
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

  /// Dismisses the active notice and replies to Sparkle when required.
  func dismissNotice() {
    if let pendingChoiceReply {
      self.pendingChoiceReply = nil
      pendingChoiceReply(.dismiss)
    }

    notice = nil
  }

  // AGENT: Sparkle is only started when both SUFeedURL and SUPublicEDKey are
  // present in Info.plist. This lets development builds skip update checks
  // without needing a separate build configuration or feature flag.
  /// Starts Sparkle if the bundle contains the required feed configuration.
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

  /// Indicates whether the app bundle includes the keys Sparkle requires.
  private var hasRequiredConfiguration: Bool {
    guard let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
      !feedURL.isEmpty,
      let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
      !publicKey.isEmpty
    else {
      return false
    }
    return true
  }

  /// Chooses the best version string to show for an appcast item.
  /// - Parameter item: The appcast item being rendered.
  /// - Returns: A display-friendly version string.
  private func makeVersionString(for item: SUAppcastItem) -> String {
    let displayVersion = item.displayVersionString.trimmingCharacters(in: .whitespacesAndNewlines)
    if displayVersion.isEmpty {
      return item.versionString
    }
    return displayVersion
  }

  /// Rebuilds the downloading notice using the latest byte counts.
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

#if DEBUG
  extension AppUpdater.UpdateNotice {
    /// Builds a preview notice without going through Sparkle.
    /// - Parameters:
    ///   - kind: The lifecycle kind to preview.
    ///   - title: The headline text to display.
    ///   - message: The body text to display.
    ///   - version: The version associated with the notice.
    ///   - primaryActionTitle: The primary action label, if any.
    ///   - secondaryActionTitle: The secondary action label, if any.
    /// - Returns: A preview-ready notice.
    static func preview(
      kind: AppUpdater.UpdateNotice.Kind,
      title: String,
      message: String,
      version: String? = nil,
      primaryActionTitle: String? = nil,
      secondaryActionTitle: String? = nil
    ) -> Self {
      Self(
        kind: kind,
        title: title,
        message: message,
        version: version,
        primaryActionTitle: primaryActionTitle,
        secondaryActionTitle: secondaryActionTitle
      )
    }
  }
#endif

extension AppUpdater: SPUUpdaterDelegate {
  /// Captures the immediate install callback when Sparkle has staged an update.
  /// - Parameters:
  ///   - updater: The Sparkle updater issuing the callback.
  ///   - item: The appcast item ready to install.
  ///   - immediateInstallHandler: The closure that performs installation.
  /// - Returns: `true` to allow Sparkle to continue.
  public func updater(
    _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
    immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
  ) -> Bool {
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

  /// Surfaces a failed update cycle when the UI is already presenting updater state.
  /// - Parameters:
  ///   - updater: The Sparkle updater issuing the callback.
  ///   - updateCheck: The update check that finished.
  ///   - error: The error produced by the update cycle, if any.
  public func updater(
    _ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?
  ) {
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
  /// Opts into automatic checks without sending a system profile.
  /// - Parameters:
  ///   - request: The permission request from Sparkle.
  ///   - reply: The callback used to return the chosen permission response.
  public func show(
    _ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void
  ) {
    reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
  }

  /// Handles the start of a user-initiated update check.
  /// - Parameter cancellation: A closure Sparkle can use to cancel the check.
  public func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
  }

  /// Handles dismissal of a user-initiated update check UI.
  public func dismissUserInitiatedUpdateCheck() {
  }

  /// Presents an available update and stores the pending user reply callback.
  /// - Parameters:
  ///   - appcastItem: The discovered update item.
  ///   - state: The current Sparkle update state.
  ///   - reply: The callback to invoke with the user's choice.
  public func showUpdateFound(
    with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
    reply: @escaping (SPUUserUpdateChoice) -> Void
  ) {
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

  /// Ignores release notes because the menu UI does not display them.
  /// - Parameter downloadData: The downloaded release notes payload.
  public func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
  }

  /// Ignores release note download failures because the UI does not surface them separately.
  /// - Parameter error: The error returned while fetching release notes.
  public func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
  }

  /// Acknowledges a completed update check when no update is available.
  /// - Parameters:
  ///   - error: The optional informational error returned by Sparkle.
  ///   - acknowledgement: The callback that dismisses Sparkle's flow.
  public func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
    acknowledgement()
  }

  /// Presents an updater failure message and acknowledges the Sparkle flow.
  /// - Parameters:
  ///   - error: The update error to display.
  ///   - acknowledgement: The callback that dismisses Sparkle's flow.
  public func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
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

  /// Clears update-installation state after Sparkle dismisses its install flow.
  public func dismissUpdateInstallation() {
    pendingChoiceReply = nil
    immediateInstallHandler = nil
    downloadExpectedLength = nil
    downloadReceivedLength = 0
    notice = nil
  }

  /// Starts presenting download progress for the active update.
  /// - Parameter cancellation: A closure Sparkle can use to cancel the download.
  public func showDownloadInitiated(cancellation: @escaping () -> Void) {
    downloadExpectedLength = nil
    downloadReceivedLength = 0
    updateDownloadingNotice()
  }

  /// Stores the expected download length so the UI can render progress.
  /// - Parameter expectedContentLength: The total expected byte count.
  public func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
    downloadExpectedLength = expectedContentLength
    updateDownloadingNotice()
  }

  /// Advances the received byte count for the current download.
  /// - Parameter length: The additional number of bytes received.
  public func showDownloadDidReceiveData(ofLength length: UInt64) {
    downloadReceivedLength += length
    updateDownloadingNotice()
  }

  /// Switches the notice into the extraction and preparation phase.
  public func showDownloadDidStartExtractingUpdate() {
    notice = UpdateNotice(
      kind: .preparing,
      title: "Preparing update",
      message: "Version \(availableVersion ?? "new") has downloaded and is being prepared.",
      version: availableVersion,
      primaryActionTitle: nil,
      secondaryActionTitle: nil
    )
  }

  /// Updates the preparation progress once extraction has started.
  /// - Parameter progress: The normalized extraction progress.
  public func showExtractionReceivedProgress(_ progress: Double) {
    notice = UpdateNotice(
      kind: .preparing,
      title: "Preparing update",
      message: "Version \(availableVersion ?? "new") is being prepared (\(Int(progress * 100))%).",
      version: availableVersion,
      primaryActionTitle: nil,
      secondaryActionTitle: nil
    )
  }

  /// Presents the final install-and-relaunch prompt for a prepared update.
  /// - Parameter reply: The callback used to deliver the user's choice.
  public func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
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

  /// Presents installation progress while Sparkle terminates and replaces the app.
  /// - Parameters:
  ///   - applicationTerminated: Indicates whether the current app instance has terminated.
  ///   - retryTerminatingApplication: A closure Sparkle can use to retry termination.
  public func showInstallingUpdate(
    withApplicationTerminated applicationTerminated: Bool,
    retryTerminatingApplication: @escaping () -> Void
  ) {
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

  /// Acknowledges completion once Sparkle finishes installation and relaunch.
  /// - Parameters:
  ///   - relaunched: Indicates whether the app relaunched successfully.
  ///   - acknowledgement: The callback that dismisses Sparkle's flow.
  public func showUpdateInstalledAndRelaunched(
    _ relaunched: Bool, acknowledgement: @escaping () -> Void
  ) {
    acknowledgement()
  }

  /// Handles Sparkle requesting focus for an update flow.
  public func showUpdateInFocus() {
  }
}
