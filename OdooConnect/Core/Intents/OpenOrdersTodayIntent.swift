import AppIntents
import Foundation

/// "Hey Siri, neue Bestellungen heute in OdooCompanion?" — counts
/// confirmed orders since midnight and names the first few customers.
struct OpenOrdersTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Neue Bestellungen heute"
    static let description = IntentDescription(
        "Anzahl bestätigter Bestellungen seit Mitternacht plus die ersten Kundennamen.",
        categoryName: "Auswertungen"
    )
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let client: OdooClient
        do {
            client = try IntentSession.requireClient()
        } catch {
            return .result(dialog: "Bitte erst in OdooCompanion anmelden.")
        }

        let today = Calendar.current.startOfDay(for: Date())
        let orders: [SaleOrder]
        do {
            orders = try await client.searchRead(
                model: "sale.order",
                domain: [
                    .array([.string("state"), .string("="), .string("sale")]),
                    .array([.string("date_order"), .string(">="),
                            .string(DateFormatter.odooDateTime.string(from: today))])
                ],
                fields: SaleOrder.fields,
                limit: 50,
                order: "date_order desc"
            )
        } catch {
            return .result(dialog: "Odoo nicht erreichbar: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
        }

        if orders.isEmpty {
            return .result(dialog: "Heute noch keine bestätigten Bestellungen.")
        }
        let count = orders.count
        let topCustomers = uniqueCustomerNames(from: orders, limit: 3)
        let names = topCustomers.formatted(.list(type: .and, width: .narrow))
        if count == 1, let only = orders.first {
            return .result(dialog: "Eine Bestellung heute, von \(only.partner_id.name).")
        }
        return .result(dialog: "\(count) Bestellungen heute, unter anderem von \(names).")
    }

    private func uniqueCustomerNames(from orders: [SaleOrder], limit: Int) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for order in orders {
            let name = order.partner_id.name
            guard !name.isEmpty, !seen.contains(name) else { continue }
            seen.insert(name)
            ordered.append(name)
            if ordered.count >= limit { break }
        }
        return ordered
    }
}
