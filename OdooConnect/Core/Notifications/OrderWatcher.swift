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

    private weak var auth: AuthManager?
    private let lastSeenKey = "orderWatcher.lastSeenId"

    var notificationsEnabled: Bool {
        UserDefaults.standard.bool(forKey: "orderWatcher.enabled")
    }

    init(auth: AuthManager) {
        self.auth = auth
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

    func disable() {
        UserDefaults.standard.set(false, forKey: "orderWatcher.enabled")
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
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
        let content = UNMutableNotificationContent()
        content.title = "Neue Bestellung"
        content.body = "\(order.name) – \(order.partner_id.name)"
        content.sound = .default
        content.userInfo = ["orderId": order.id]
        let request = UNNotificationRequest(
            identifier: "order.\(order.id)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
