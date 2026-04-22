import Foundation

struct ProductDetail: Identifiable, Sendable, Hashable, Decodable {
    let id: Int
    let name: String
    let list_price: Double
    let standard_price: Double
    @OdooOptionalString var default_code: String?
    @OdooOptionalString var barcode: String?
    @OdooOptionalString var description_sale: String?
    let uom_id: Many2One?
    let categ_id: Many2One?
    let qty_available: Double
    let virtual_available: Double
    let incoming_qty: Double
    let outgoing_qty: Double
    let sale_ok: Bool
    let purchase_ok: Bool
    let active: Bool

    /// Base fields — safe for any Odoo install.
    static let baseFields: [String] = [
        "id", "name", "list_price", "standard_price",
        "default_code", "barcode", "description_sale",
        "uom_id", "categ_id", "sale_ok", "purchase_ok", "active"
    ]

    /// Stock fields — only available when the `stock` module is installed.
    static let stockFields: [String] = [
        "qty_available", "virtual_available",
        "incoming_qty", "outgoing_qty"
    ]

    static let fields: [String] = baseFields + stockFields

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        list_price = try c.decodeIfPresent(Double.self, forKey: .list_price) ?? 0
        standard_price = try c.decodeIfPresent(Double.self, forKey: .standard_price) ?? 0
        _default_code = try c.decode(OdooOptionalString.self, forKey: .default_code)
        _barcode = try c.decode(OdooOptionalString.self, forKey: .barcode)
        _description_sale = try c.decode(OdooOptionalString.self, forKey: .description_sale)
        uom_id = try c.decodeIfPresent(Many2One.self, forKey: .uom_id)
        categ_id = try c.decodeIfPresent(Many2One.self, forKey: .categ_id)
        // Stock fields absent if the stock module isn't installed.
        qty_available = try c.decodeIfPresent(Double.self, forKey: .qty_available) ?? 0
        virtual_available = try c.decodeIfPresent(Double.self, forKey: .virtual_available) ?? 0
        incoming_qty = try c.decodeIfPresent(Double.self, forKey: .incoming_qty) ?? 0
        outgoing_qty = try c.decodeIfPresent(Double.self, forKey: .outgoing_qty) ?? 0
        sale_ok = try c.decodeIfPresent(Bool.self, forKey: .sale_ok) ?? true
        purchase_ok = try c.decodeIfPresent(Bool.self, forKey: .purchase_ok) ?? true
        active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? true
    }

    enum CodingKeys: String, CodingKey {
        case id, name, list_price, standard_price, default_code, barcode,
             description_sale, uom_id, categ_id, qty_available, virtual_available,
             incoming_qty, outgoing_qty, sale_ok, purchase_ok, active
    }

    var uomSymbol: String { uom_id?.name ?? "Stk" }

    var stockStateColor: StockState {
        if qty_available <= 0 { return .outOfStock }
        if qty_available <= 5 { return .low }
        return .healthy
    }

    enum StockState: Sendable {
        case healthy, low, outOfStock
    }
}
