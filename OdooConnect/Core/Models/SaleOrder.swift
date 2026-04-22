import Foundation

struct SaleOrder: Identifiable, Sendable, Hashable, Decodable {
    let id: Int
    let name: String
    let partner_id: Many2One
    let date_order: Date
    let amount_total: Double
    let amount_untaxed: Double
    let state: String
    let currency_id: Many2One

    static let fields: [String] = [
        "id", "name", "partner_id", "date_order",
        "amount_total", "amount_untaxed", "state", "currency_id"
    ]

    var stateLabel: String {
        switch state {
        case "draft": return "Entwurf"
        case "sent": return "Angebot gesendet"
        case "sale": return "Bestellung"
        case "done": return "Abgeschlossen"
        case "cancel": return "Storniert"
        default: return state.capitalized
        }
    }

    var isQuote: Bool { state == "draft" || state == "sent" }
}

struct SaleOrderLine: Identifiable, Sendable, Hashable, Decodable {
    let id: Int
    let name: String
    let product_id: Many2One
    let product_uom_qty: Double
    let price_unit: Double
    let price_subtotal: Double
    let currency_id: Many2One

    static let fields: [String] = [
        "id", "name", "product_id", "product_uom_qty",
        "price_unit", "price_subtotal", "currency_id"
    ]
}
