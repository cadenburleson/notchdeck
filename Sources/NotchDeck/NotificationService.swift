import AppKit
import UserNotifications

/// User notifications need a real bundle; when running via `swift run` we fall back to sound only.
final class NotificationService {
    static let shared = NotificationService()

    private var authorized = false
    private var canUseCenter: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    func requestAuthorizationIfPossible() {
        guard canUseCenter else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            self?.authorized = granted
        }
    }

    func notify(title: String, body: String, playSound: Bool) {
        if playSound { NSSound(named: "Glass")?.play() }
        guard canUseCenter, authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
