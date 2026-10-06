import Foundation
import UserNotifications

@MainActor
final class SessionNotifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let identifier = "dev.focuskit.segment"

    override init() {
        super.init()
        center.delegate = self
    }

    func schedule(title: String, body: String, at date: Date) async {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
