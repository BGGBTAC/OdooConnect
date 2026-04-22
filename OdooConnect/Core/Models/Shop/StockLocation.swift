import Foundation

struct StockLocation: Identifiable, Sendable, Hashable, Decodable {
    let id: Int
    let display_name: String
    let usage: String
    let warehouse_id: Many2One?

    static let fields: [String] = ["id", "display_name", "usage", "warehouse_id"]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        display_name = try c.decode(String.self, forKey: .display_name)
        usage = try c.decode(String.self, forKey: .usage)
        warehouse_id = try? c.decode(Many2One.self, forKey: .warehouse_id)
    }

    enum CodingKeys: String, CodingKey {
        case id, display_name, usage, warehouse_id
    }
}

struct PickingType: Identifiable, Sendable, Hashable, Decodable {
    let id: Int
    let name: String
    let code: String
    let warehouse_id: Many2One?

    static let fields: [String] = ["id", "name", "code", "warehouse_id"]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        code = try c.decode(String.self, forKey: .code)
        warehouse_id = try? c.decode(Many2One.self, forKey: .warehouse_id)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, code, warehouse_id
    }
}
