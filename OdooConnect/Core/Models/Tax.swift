import Foundation

/// Row from `account.tax`. Used by the quote editor's per-line tax picker
/// to override Odoo's onchange defaults when needed.
struct OdooTax: Identifiable, Sendable, Hashable, Decodable {
    let id: Int
    let name: String
    let amount: Double
    let amount_type: String
    let price_include: Bool
    let type_tax_use: String

    static let fields: [String] = [
        "id", "name", "amount", "amount_type",
        "price_include", "type_tax_use"
    ]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        amount = try c.decodeIfPresent(Double.self, forKey: .amount) ?? 0
        amount_type = try c.decodeIfPresent(String.self, forKey: .amount_type) ?? "percent"
        price_include = try c.decodeIfPresent(Bool.self, forKey: .price_include) ?? false
        type_tax_use = try c.decodeIfPresent(String.self, forKey: .type_tax_use) ?? "sale"
    }

    enum CodingKeys: String, CodingKey {
        case id, name, amount, amount_type, price_include, type_tax_use
    }

    /// Short label for the editor row, e.g. "MwSt 19%" or "Pauschal 5,00".
    var shortLabel: String {
        switch amount_type {
        case "percent", "division":
            let formatted = amount.formatted(.number.precision(.fractionLength(0...2)))
            return "\(name) (\(formatted)%)"
        case "fixed":
            return "\(name) (\(amount.formatted(.number.precision(.fractionLength(0...2)))))"
        default:
            return name
        }
    }
}
