import Foundation

struct StockPicking: Identifiable, Sendable, Hashable, Decodable {
    let id: Int
    let name: String
    let partner_id: Many2One?
    let scheduled_date: Date?
    let date_done: Date?
    let state: String
    @OdooOptionalString var origin: String?
    @OdooOptionalString var carrier_tracking_ref: String?
    let picking_type_id: Many2One
    let picking_type_code: String  // incoming / outgoing / internal
    let carrier_id: Many2One?

    static let fields: [String] = [
        "id", "name", "partner_id", "scheduled_date", "date_done",
        "state", "origin", "carrier_tracking_ref", "picking_type_id",
        "picking_type_code", "carrier_id"
    ]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        partner_id = try? c.decode(Many2One.self, forKey: .partner_id)
        state = try c.decode(String.self, forKey: .state)
        picking_type_id = try c.decode(Many2One.self, forKey: .picking_type_id)
        picking_type_code = try c.decodeIfPresent(String.self, forKey: .picking_type_code) ?? ""
        carrier_id = try? c.decode(Many2One.self, forKey: .carrier_id)
        _origin = try c.decode(OdooOptionalString.self, forKey: .origin)
        _carrier_tracking_ref = try c.decode(OdooOptionalString.self, forKey: .carrier_tracking_ref)
        scheduled_date = try Self.decodeOptionalDate(c, key: .scheduled_date)
        date_done = try Self.decodeOptionalDate(c, key: .date_done)
    }

    private static func decodeOptionalDate(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> Date? {
        if let bool = try? container.decode(Bool.self, forKey: key), bool == false {
            return nil
        }
        return try container.decodeIfPresent(Date.self, forKey: key)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, partner_id, scheduled_date, date_done, state, origin,
             carrier_tracking_ref, picking_type_id, picking_type_code, carrier_id
    }

    var stateLabel: String {
        switch state {
        case "draft":     return "Entwurf"
        case "waiting":   return "Wartet"
        case "confirmed": return "Bestätigt"
        case "assigned":  return "Bereit"
        case "done":      return "Versendet"
        case "cancel":    return "Storniert"
        default:          return state.capitalized
        }
    }

    var isActionable: Bool {
        state == "assigned" || state == "confirmed"
    }
}

struct StockMoveLine: Identifiable, Sendable, Hashable, Decodable {
    let id: Int
    let product_id: Many2One
    let quantity: Double
    let qty_done: Double?
    let product_uom_id: Many2One?

    static let fields: [String] = [
        "id", "product_id", "quantity", "qty_done", "product_uom_id"
    ]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        product_id = try c.decode(Many2One.self, forKey: .product_id)
        quantity = try c.decodeIfPresent(Double.self, forKey: .quantity) ?? 0
        qty_done = try c.decodeIfPresent(Double.self, forKey: .qty_done)
        product_uom_id = try? c.decode(Many2One.self, forKey: .product_uom_id)
    }

    enum CodingKeys: String, CodingKey {
        case id, product_id, quantity, qty_done, product_uom_id
    }
}
