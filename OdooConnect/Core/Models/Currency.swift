import Foundation

struct Currency: Identifiable, Sendable, Hashable, Decodable {
    let id: Int
    let name: String
    let symbol: String?
    let position: Position
    let decimal_places: Int
    let rounding: Double

    enum Position: String, Sendable, Decodable {
        case before, after
    }

    static let fields: [String] = [
        "id", "name", "symbol", "position", "decimal_places", "rounding"
    ]

    /// ISO 4217 currency code that Foundation's `.currency(code:)` understands.
    var code: String { name }

    /// Fallback used before the company currency has been fetched.
    static let eur = Currency(
        id: 0,
        name: "EUR",
        symbol: "€",
        position: .after,
        decimal_places: 2,
        rounding: 0.01
    )

    init(id: Int, name: String, symbol: String?, position: Position, decimal_places: Int, rounding: Double) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.position = position
        self.decimal_places = decimal_places
        self.rounding = rounding
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        if let bool = try? c.decode(Bool.self, forKey: .symbol), bool == false {
            self.symbol = nil
        } else {
            self.symbol = try? c.decode(String.self, forKey: .symbol)
        }
        let raw = (try? c.decode(String.self, forKey: .position)) ?? "after"
        self.position = Position(rawValue: raw) ?? .after
        self.decimal_places = (try? c.decode(Int.self, forKey: .decimal_places)) ?? 2
        self.rounding = (try? c.decode(Double.self, forKey: .rounding)) ?? 0.01
    }

    enum CodingKeys: String, CodingKey {
        case id, name, symbol, position, decimal_places, rounding
    }
}
