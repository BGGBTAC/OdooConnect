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
        guard let orderId = info["orderId"] as? Int else { return }
        await MainActor.run { [weak self] in
            self?.router?.openOrder(id: orderId)
        }
    }
}
