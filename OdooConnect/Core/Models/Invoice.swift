import Foundation

struct Invoice: Identifiable, Sendable, Hashable, Decodable {
    let id: Int
    let name: String
    let partner_id: Many2One
    let invoice_date: Date?
    let amount_total: Double
    let amount_residual: Double
    let state: String
    let payment_state: String
    let move_type: String

    static let fields: [String] = [
        "id", "name", "partner_id", "invoice_date",
        "amount_total", "amount_residual", "state",
        "payment_state", "move_type"
    ]

    var stateLabel: String {
        switch state {
        case "draft": return "Entwurf"
        case "posted": return "Gebucht"
        case "cancel": return "Storniert"
        default: return state.capitalized
        }
    }

    var paymentLabel: String {
        switch payment_state {
        case "not_paid": return "Offen"
        case "in_payment": return "In Zahlung"
        case "paid": return "Bezahlt"
        case "partial": return "Teilweise"
        case "reversed": return "Storniert"
        default: return payment_state.capitalized
        }
    }

    // Custom decoder because invoice_date is optional and may arrive as `false`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        partner_id = try c.decode(Many2One.self, forKey: .partner_id)
        amount_total = try c.decode(Double.self, forKey: .amount_total)
        amount_residual = try c.decode(Double.self, forKey: .amount_residual)
        state = try c.decode(String.self, forKey: .state)
        payment_state = try c.decode(String.self, forKey: .payment_state)
        move_type = try c.decode(String.self, forKey: .move_type)

        if let bool = try? c.decode(Bool.self, forKey: .invoice_date), bool == false {
            invoice_date = nil
        } else {
            invoice_date = try c.decodeIfPresent(Date.self, forKey: .invoice_date)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, partner_id, invoice_date, amount_total, amount_residual, state, payment_state, move_type
    }
}
