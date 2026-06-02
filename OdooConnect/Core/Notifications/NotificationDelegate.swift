import Foundation
import UserNotifications

/// Bridges `UNUserNotificationCenter` taps into the in-app `AppRouter`.
///
/// `UNNotification` and `UNNotificationResponse` are not `Sendable`, so the
/// protocol methods stay `nonisolated` to avoid actor-boundary errors. We
/// extract the Sendable payload (just an `Int` order id) inline, then hop
/// to the main actor to call the `AppRouter`.
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    weak var router: AppRouter?

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        // Anything other than an explicit dismiss should open the target.
        guard action != UNNotificationDismissActionIdentifier else { return }
        if let orderId = info["orderId"] as? Int {
            await openOrder(id: orderId)
        } else if info["inbox"] != nil {
            await openInbox()
        }
    }

    private func openOrder(id: Int) {
        router?.openOrder(id: id)
    }

    private func openInbox() {
        router?.openInbox()
    }
}
