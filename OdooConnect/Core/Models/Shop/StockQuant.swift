import Foundation

struct StockQuant: Identifiable, Sendable, Hashable, Decodable {
    let id: Int
    let product_id: Many2One
    let location_id: Many2One
    let quantity: Double
    let reserved_quantity: Double
    let available_quantity: Double
    let inventory_quantity: Double

    static let fields: [String] = [
        "id", "product_id", "location_id", "quantity",
        "reserved_quantity", "available_quantity", "inventory_quantity"
    ]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        product_id = try c.decode(Many2One.self, forKey: .product_id)
        location_id = try c.decode(Many2One.self, forKey: .location_id)
        quantity = try c.decodeIfPresent(Double.self, forKey: .quantity) ?? 0
        reserved_quantity = try c.decodeIfPresent(Double.self, forKey: .reserved_quantity) ?? 0
        available_quantity = try c.decodeIfPresent(Double.self, forKey: .available_quantity) ?? 0
        inventory_quantity = try c.decodeIfPresent(Double.self, forKey: .inventory_quantity) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case id, product_id, location_id, quantity, reserved_quantity,
             available_quantity, inventory_quantity
    }
}
