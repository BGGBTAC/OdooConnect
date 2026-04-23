import Foundation

/// Row from `delivery.carrier` — one shipping method (DHL, UPS, manual, …).
struct DeliveryCarrier: Identifiable, Sendable, Hashable, Decodable {
    let id: Int
    let name: String
    @OdooOptionalString var delivery_type: String?
    let active: Bool

    static let fields: [String] = ["id", "name", "delivery_type", "active"]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        _delivery_type = try c.decode(OdooOptionalString.self, forKey: .delivery_type)
        active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? true
    }

    enum CodingKeys: String, CodingKey {
        case id, name, delivery_type, active
    }

    /// Friendlier label for the picker. Many carriers leave delivery_type
    /// as the raw integration code (e.g. "fixed", "dhl_de") which isn't
    /// useful to a human — we surface only when it's a known carrier.
    var subtitle: String? {
        switch delivery_type {
        case "fixed":          return "Pauschalpreis"
        case "base_on_rule":   return "Regelbasiert"
        case nil, "":          return nil
        case let other?:       return other.uppercased()
        }
    }
}
