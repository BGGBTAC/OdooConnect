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
    private let lastSeenWriteDateKey = "orderWatcher.lastSeenWriteDate"
    private let notifiedOrderIdsKey = "orderWatcher.notifiedOrderIds"
    private let maxRememberedNotificationIds = 200
    private let unreadCountKey = "orderWatcher.unreadCount"
    private let lastSeenMessageDateKey = "orderWatcher.lastSeenMessageDate"
    private let notifiedMessageIdsKey = "orderWatcher.notifiedMessageIds"
    private let messageUnreadCountKey = "orderWatcher.messageUnreadCount"
    static let messageThreadIdentifier = "new-messages"

    /// Unread customer-message count for the Posteingang tab badge. Stored
    /// (observable) so the badge updates live; mirrored to UserDefaults.
    var messageUnread: Int = 0

    var notificationsEnabled: Bool {
        UserDefaults.standard.bool(forKey: "orderWatcher.enabled")
    }

    init(auth: AuthManager) {
        self.auth = auth
        self.messageUnread = UserDefaults.standard.integer(forKey: messageUnreadCountKey)
        Self.registerCategories()
    }

    /// Asks for permission and persists the user's choice. Safe to call on
    /// every launch — the system collapses repeated requests.
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            UserDefaults.standard.set(granted, forKey: "orderWatcher.enabled")
            if granted {
                await seedNotificationWatermarkIfNeeded(using: auth?.client)
                scheduleNextRefresh()
            }
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

    /// Called when the user opens the Posteingang — clears the message badge
    /// and drops the delivered message-notification group.
    func clearMessageUnread() {
        messageUnread = 0
        UserDefaults.standard.set(0, forKey: messageUnreadCountKey)
        Task {
            let center = UNUserNotificationCenter.current()
            let delivered = await center.deliveredNotifications()
            let ids = delivered
                .filter { $0.request.content.threadIdentifier == Self.messageThreadIdentifier }
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
        guard let watermark = UserDefaults.standard.string(forKey: lastSeenWriteDateKey) else {
            await seedNotificationWatermarkIfNeeded(using: client)
            scheduleNextRefresh()
            return 0
        }
        do {
            let orders: [WatchedOrderDTO] = try await client.searchRead(
                model: "sale.order",
                domain: [
                    .array([.string("state"), .string("="), .string("sale")]),
                    .array([.string("write_date"), .string(">"), .string(watermark)])
                ],
                fields: WatchedOrderDTO.fields,
                limit: 20,
                order: "write_date asc, id asc"
            )

            var rememberedIds = notifiedOrderIds()
            var postedCount = 0
            for order in orders {
                if !rememberedIds.contains(order.id) {
                    await postNotification(for: order.saleOrder)
                    rememberedIds.append(order.id)
                    postedCount += 1
                }
            }
            if let newest = orders.last {
                UserDefaults.standard.set(
                    DateFormatter.odooDateTime.string(from: newest.write_date),
                    forKey: lastSeenWriteDateKey
                )
            }
            if postedCount > 0 {
                storeNotifiedOrderIds(rememberedIds)
            }
            let messagePosted = await checkNewMessages(using: client)
            scheduleNextRefresh()
            return postedCount + messagePosted
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

    // MARK: - Customer message polling (Posteingang)

    private func checkNewMessages(using client: OdooClient) async -> Int {
        guard let watermark = UserDefaults.standard.string(forKey: lastSeenMessageDateKey) else {
            await seedMessageWatermarkIfNeeded(using: client)
            return 0
        }
        let dtos: [MailMessageDTO] = (try? await client.searchRead(
            model: "mail.message",
            domain: [
                // Incoming customer emails only — see InboxViewModel.customerDomain.
                .array([.string("message_type"), .string("="), .string("email")]),
                .array([.string("author_id.partner_share"), .string("="), .bool(true)]),
                .array([.string("author_id.customer_rank"), .string(">"), .int(0)]),
                .array([.string("date"), .string(">"), .string(watermark)])
            ],
            fields: MailMessageDTO.fields,
            limit: 20,
            order: "date asc, id asc"
        )) ?? []

        var remembered = notifiedMessageIds()
        var posted = 0
        for dto in dtos where !remembered.contains(dto.id) {
            await postMessageNotification(for: InboxMessage(dto: dto))
            remembered.append(dto.id)
            posted += 1
        }
        if let newest = dtos.last {
            UserDefaults.standard.set(
                DateFormatter.odooDateTime.string(from: newest.date),
                forKey: lastSeenMessageDateKey
            )
        }
        if posted > 0 {
            storeNotifiedMessageIds(remembered)
        }
        return posted
    }

    private func postMessageNotification(for message: InboxMessage) async {
        messageUnread += 1
        UserDefaults.standard.set(messageUnread, forKey: messageUnreadCountKey)

        let content = UNMutableNotificationContent()
        content.title = "Neue Antwort von \(message.authorName)"
        content.subtitle = message.recordName.isEmpty ? message.subject : message.recordName
        let detail = message.preview.isEmpty ? message.subject : message.preview
        content.body = detail.isEmpty ? "Neue Kundennachricht" : detail
        content.sound = .default
        let combined = UserDefaults.standard.integer(forKey: unreadCountKey) + messageUnread
        content.badge = NSNumber(value: combined)
        content.threadIdentifier = Self.messageThreadIdentifier
        content.userInfo = ["inbox": true]
        let request = UNNotificationRequest(
            identifier: "msg.\(message.id)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func seedMessageWatermarkIfNeeded(using client: OdooClient) async {
        guard UserDefaults.standard.string(forKey: lastSeenMessageDateKey) == nil else { return }
        let latest: [MailMessageDTO]? = try? await client.searchRead(
            model: "mail.message",
            domain: [
                .array([.string("message_type"), .string("="), .string("email")]),
                .array([.string("author_id.partner_share"), .string("="), .bool(true)]),
                .array([.string("author_id.customer_rank"), .string(">"), .int(0)])
            ],
            fields: MailMessageDTO.fields,
            limit: 1,
            order: "date desc, id desc"
        )
        let stamp = latest?.first?.date ?? .now
        UserDefaults.standard.set(
            DateFormatter.odooDateTime.string(from: stamp),
            forKey: lastSeenMessageDateKey
        )
    }

    private func notifiedMessageIds() -> [Int] {
        let raw = UserDefaults.standard.string(forKey: notifiedMessageIdsKey) ?? ""
        return raw.split(separator: ",").compactMap { Int($0) }
    }

    private func storeNotifiedMessageIds(_ ids: [Int]) {
        let bounded = Array(ids.suffix(maxRememberedNotificationIds))
        UserDefaults.standard.set(
            bounded.map(String.init).joined(separator: ","),
            forKey: notifiedMessageIdsKey
        )
    }

    private func seedNotificationWatermarkIfNeeded(using client: OdooClient?) async {
        guard UserDefaults.standard.string(forKey: lastSeenWriteDateKey) == nil else { return }

        if let client {
            let latest: [WatchedOrderDTO]? = try? await client.searchRead(
                model: "sale.order",
                domain: [.array([.string("state"), .string("="), .string("sale")])],
                fields: WatchedOrderDTO.fields,
                limit: 1,
                order: "write_date desc, id desc"
            )
            if let newest = latest?.first {
                UserDefaults.standard.set(
                    DateFormatter.odooDateTime.string(from: newest.write_date),
                    forKey: lastSeenWriteDateKey
                )
                return
            }
        }

        UserDefaults.standard.set(
            DateFormatter.odooDateTime.string(from: .now),
            forKey: lastSeenWriteDateKey
        )
    }

    private func notifiedOrderIds() -> [Int] {
        let raw = UserDefaults.standard.string(forKey: notifiedOrderIdsKey) ?? ""
        return raw
            .split(separator: ",")
            .compactMap { Int($0) }
    }

    private func storeNotifiedOrderIds(_ ids: [Int]) {
        let bounded = Array(ids.suffix(maxRememberedNotificationIds))
        UserDefaults.standard.set(
            bounded.map(String.init).joined(separator: ","),
            forKey: notifiedOrderIdsKey
        )
    }
}

private struct WatchedOrderDTO: Decodable, Sendable {
    let id: Int
    let name: String
    let partner_id: Many2One
    let date_order: Date
    let amount_total: Double
    let amount_untaxed: Double
    let state: String
    let currency_id: Many2One
    let write_date: Date

    static let fields: [String] = SaleOrder.fields + ["write_date"]

    var saleOrder: SaleOrder {
        SaleOrder(
            id: id,
            name: name,
            partner_id: partner_id,
            date_order: date_order,
            amount_total: amount_total,
            amount_untaxed: amount_untaxed,
            state: state,
            currency_id: currency_id
        )
    }
}
