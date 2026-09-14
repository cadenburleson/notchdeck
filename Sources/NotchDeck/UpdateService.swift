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
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }

    func checkForUpdates() {
        guard let controller else { return }
        // We are an accessory app with no Dock icon; make sure Sparkle's window comes forward.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}

extension UpdateService: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        // Nothing to save: AppStore persists on every change.
        return true
    }
}
