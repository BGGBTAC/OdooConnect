import Foundation
import Observation
import BackgroundTasks
import UserNotifications

/// Polls Odoo for newly confirmed sale orders and posts local notifications
/// for them. Designed to run from a `BGAppRefreshTask` so the app does not
/// need any push infrastructure on the Odoo side — the device wakes us
/// periodically and we ask whoever's online about new business.
@Observable
@MainActor
final class OrderWatcher {
    static let backgroundTaskIdentifier = "com.benedict.odooconnect.refresh"
    static let categoryIdentifier = "NEW_ORDER_CATEGORY"
    static let openActionIdentifier = "NEW_ORDER_OPEN"
    static let threadIdentifier = "new-orders"

    private weak var auth: AuthManager?
    private let lastSeenKey = "orderWatcher.lastSeenId"
    private let unreadCountKey = "orderWatcher.unreadCount"

    var notificationsEnabled: Bool {
        UserDefaults.standard.bool(forKey: "orderWatcher.enabled")
    }

    init(auth: AuthManager) {
        self.auth = auth
        Self.registerCategories()
    }

    /// Asks for permission and persists the user's choice. Safe to call on
    /// every launch — the system collapses repeated requests.
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            UserDefaults.standard.set(granted, forKey: "orderWatcher.enabled")
            if granted { scheduleNextRefresh() }
            return granted
        } catch {
            return false
        }
    }

    /// True only if the user has explicitly denied — the toggle should
    /// then point at iOS Settings instead of re-prompting (which iOS
    /// silently ignores after the first denial).
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func disable() {
        UserDefaults.standard.set(false, forKey: "orderWatcher.enabled")
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
    }

    /// Called when the user opens the Orders tab — clears the badge and
    /// the queued group of new-order notifications so the next batch
    /// summary starts at 0.
    func clearUnread() {
        UserDefaults.standard.set(0, forKey: unreadCountKey)
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(0)
            UNUserNotificationCenter.current()
                .removeDeliveredNotifications(withIdentifiers: [])
            // Cheaper than enumerating: drop the whole group by thread.
            let center = UNUserNotificationCenter.current()
            let delivered = await center.deliveredNotifications()
            let ids = delivered
                .filter { $0.request.content.threadIdentifier == Self.threadIdentifier }
                .map(\.request.identifier)
            if !ids.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: ids)
            }
        }
    }

    private static func registerCategories() {
        let open = UNNotificationAction(
            identifier: Self.openActionIdentifier,
            title: "Öffnen",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [open],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Neue Bestellung",
            categorySummaryFormat: "%u weitere Bestellungen",
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Hook called from the BG task handler — performs one polling cycle.
    /// Returns the count of notifications posted so the caller can mark
    /// the BGTask completed with a meaningful flag.
    func performRefresh() async -> Int {
        guard let client = auth?.client, notificationsEnabled else { return 0 }
        let lastSeen = UserDefaults.standard.integer(forKey: lastSeenKey)
        do {
            let orders: [SaleOrder] = try await client.searchRead(
                model: "sale.order",
                domain: [
                    .array([.string("state"), .string("="), .string("sale")]),
                    .array([.string("id"), .string(">"), .int(lastSeen)])
                ],
                fields: SaleOrder.fields,
                limit: 20,
                order: "id desc"
            )
            for order in orders.reversed() {
                await postNotification(for: order)
            }
            if let newest = orders.first {
                UserDefaults.standard.set(newest.id, forKey: lastSeenKey)
            }
            scheduleNextRefresh()
            return orders.count
        } catch {
            scheduleNextRefresh()
            return 0
        }
    }

    func scheduleNextRefresh() {
        guard notificationsEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        // 15 minutes is the system's effective minimum for app refresh.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func postNotification(for order: SaleOrder) async {
        let nextBadge = UserDefaults.standard.integer(forKey: unreadCountKey) + 1
        UserDefaults.standard.set(nextBadge, forKey: unreadCountKey)

        let content = UNMutableNotificationContent()
        content.title = order.partner_id.name.isEmpty ? "Neue Bestellung" : order.partner_id.name
        content.subtitle = order.name
        let formatted = order.amount_total.formatted(
            .currency(code: IntentSession.cachedCurrencyCode)
        )
        content.body = "Neue Bestellung – \(formatted)"
        content.sound = .default
        content.badge = NSNumber(value: nextBadge)
        content.threadIdentifier = Self.threadIdentifier
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["orderId": order.id]
        let request = UNNotificationRequest(
            identifier: "order.\(order.id)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
