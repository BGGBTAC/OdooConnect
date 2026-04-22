import Foundation

struct Company: Identifiable, Sendable, Hashable, Decodable {
    let id: Int
    let name: String
    let currency_id: Many2One

    static let fields: [String] = ["id", "name", "currency_id"]
}
