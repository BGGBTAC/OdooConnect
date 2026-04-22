import Foundation

struct ProductDetail: Identifiable, Sendable, Hashable, Decodable {
    let id: Int
    /// Template name (e.g. "T-Shirt"). Stays variant-agnostic so we can show
    /// the parent name distinctly from the variant suffix.
    let name: String
    /// Computed by Odoo, includes variant attribute combination —
    /// e.g. "T-Shirt (Red, L)". Use this anywhere the user expects the
    /// fully-qualified product name.
    let display_name: String
    let list_price: Double
    let standard_price: Double
    @OdooOptionalString var default_code: String?
    @OdooOptionalString var barcode: String?
    @OdooOptionalString var description_sale: String?
    let uom_id: Many2One?
    let categ_id: Many2One?
    /// Parent template — present even for products without variants.
    let product_tmpl_id: Many2One?
    /// `product.template.attribute.value` IDs that distinguish this variant
    /// (e.g. [Red-id, L-id]). Empty when the product has no variants.
    let product_template_attribute_value_ids: [Int]
    /// Base64-encoded medium-size image (~512×512). `nil` when the product
    /// has no image set.
    @OdooOptionalString var image_512: String?
    let qty_available: Double
    let virtual_available: Double
    let incoming_qty: Double
    let outgoing_qty: Double
    let sale_ok: Bool
    let purchase_ok: Bool
    let active: Bool

    /// Base fields — safe for any Odoo install.
    static let baseFields: [String] = [
        "id", "name", "display_name", "list_price", "standard_price",
        "default_code", "barcode", "description_sale",
        "uom_id", "categ_id", "product_tmpl_id",
        "product_template_attribute_value_ids",
        "sale_ok", "purchase_ok", "active"
    ]

    /// Stock fields — only available when the `stock` module is installed.
    static let stockFields: [String] = [
        "qty_available", "virtual_available",
        "incoming_qty", "outgoing_qty"
    ]

    /// Image field — split out so the lighter list view can omit it and only
    /// the detail screen pays the per-row payload cost.
    static let imageFields: [String] = ["image_512"]

    static let fields: [String] = baseFields + stockFields
    static let fieldsWithImage: [String] = baseFields + stockFields + imageFields

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        display_name = try c.decodeIfPresent(String.self, forKey: .display_name) ?? name
        list_price = try c.decodeIfPresent(Double.self, forKey: .list_price) ?? 0
        standard_price = try c.decodeIfPresent(Double.self, forKey: .standard_price) ?? 0
        _default_code = try c.decode(OdooOptionalString.self, forKey: .default_code)
        _barcode = try c.decode(OdooOptionalString.self, forKey: .barcode)
        _description_sale = try c.decode(OdooOptionalString.self, forKey: .description_sale)
        uom_id = try c.decodeIfPresent(Many2One.self, forKey: .uom_id)
        categ_id = try c.decodeIfPresent(Many2One.self, forKey: .categ_id)
        product_tmpl_id = try c.decodeIfPresent(Many2One.self, forKey: .product_tmpl_id)
        // attribute_value_ids: Odoo returns either [id1, id2, ...] or `false`
        if let ids = try? c.decode([Int].self, forKey: .product_template_attribute_value_ids) {
            product_template_attribute_value_ids = ids
        } else {
            product_template_attribute_value_ids = []
        }
        // image_512: present only when imageFields is requested
        if c.contains(.image_512) {
            _image_512 = try c.decode(OdooOptionalString.self, forKey: .image_512)
        } else {
            _image_512 = OdooOptionalString(wrappedValue: nil)
        }
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
        case id, name, display_name, list_price, standard_price, default_code, barcode,
             description_sale, uom_id, categ_id, product_tmpl_id,
             product_template_attribute_value_ids, image_512,
             qty_available, virtual_available, incoming_qty, outgoing_qty,
             sale_ok, purchase_ok, active
    }

    var uomSymbol: String { uom_id?.name ?? "Stk" }

    var hasVariants: Bool { !product_template_attribute_value_ids.isEmpty }

    var stockStateColor: StockState {
        if qty_available <= 0 { return .outOfStock }
        if qty_available <= 5 { return .low }
        return .healthy
    }

    enum StockState: Sendable {
        case healthy, low, outOfStock
    }
}
