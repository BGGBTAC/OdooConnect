import AppIntents
import Foundation

/// "Hey Siri, Tagesumsatz in OdooCompanion?" — reads aloud the
/// total `sale.order.amount_total` for confirmed orders since
/// midnight, in the user's company currency.
struct TodayRevenueIntent: AppIntent {
    static let title: LocalizedStringResource = "Tagesumsatz"
    static let description = IntentDescription(
        "Liest den heutigen Umsatz aus Odoo vor (bestätigte Bestellungen seit Mitternacht).",
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
        let domain: [JSON] = [
            .array([.string("state"), .string("in"),
                    .array([.string("sale"), .string("done")])]),
            .array([.string("date_order"), .string(">="),
                    .string(DateFormatter.odooDateTime.string(from: today))])
        ]
        let total: Double
        do {
            let rows = try await client.readGroup(
                model: "sale.order",
                domain: domain,
                fields: ["amount_total:sum"],
                groupBy: []
            )
            total = rows.first?["amount_total"]?.doubleValue ?? 0
        } catch {
            return .result(dialog: "Odoo nicht erreichbar: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
        }

        let formatted = total.formatted(.currency(code: IntentSession.cachedCurrencyCode))
        if total == 0 {
            return .result(dialog: "Heute noch kein Umsatz verbucht.")
        }
        return .result(dialog: "Tagesumsatz: \(formatted).")
    }
}
