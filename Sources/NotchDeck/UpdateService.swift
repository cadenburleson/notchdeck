import AppKit
import Sparkle

/// Thin wrapper around Sparkle. Updates only make sense from inside a real
/// `.app` bundle (Sparkle reads the feed URL and public key from Info.plist),
/// so `swift run` builds get a no-op.
final class UpdateService: NSObject {
    private var controller: SPUStandardUpdaterController?

    override init() {
        super.init()
        let inBundle = Bundle.main.bundleURL.pathExtension == "app"
        let hasFeed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        guard inBundle, hasFeed else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
    }

    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }

    /// User-initiated check. Waits for the updater to finish starting (it does
    /// so asynchronously) instead of silently dropping the request.
    func checkForUpdates(attempt: Int = 0) {
        guard let controller else { return }
        guard controller.updater.canCheckForUpdates || attempt >= 20 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.checkForUpdates(attempt: attempt + 1) }
            return
        }
        // We are an accessory app with no Dock icon; make sure Sparkle's window comes forward.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}

extension UpdateService: SPUStandardUserDriverDelegate {
    /// Sparkle holds scheduled-update alerts for background apps until the app
    /// becomes active, which a menu-bar app never does on its own. Opting into
    /// "gentle reminders" lets us bring the app forward so the alert shows.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !state.userInitiated, !handleShowingUpdate else { return }
        // Sparkle found an update in the background and is leaving the reminder
        // to us. Resume it as a user-facing check so the standard alert appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.controller?.updater.checkForUpdates()
        }
    }
}

extension UpdateService: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        // Nothing to save: AppStore persists on every change.
        return true
    }
}
