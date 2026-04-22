import Foundation

struct Product: Identifiable, Sendable, Hashable, Decodable {
    let id: Int
    let name: String
    let list_price: Double
    @OdooOptionalString var default_code: String?
    let uom_id: Many2One?

    static let fields: [String] = ["id", "name", "list_price", "default_code", "uom_id"]
}
