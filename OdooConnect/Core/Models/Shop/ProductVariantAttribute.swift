import Foundation

/// One row of `product.template.attribute.value`. Resolves a single
/// variant-distinguishing value (e.g. "Red") together with its parent
/// attribute (e.g. "Color"), so the UI can render `Color: Red`.
struct ProductVariantAttribute: Identifiable, Sendable, Hashable, Decodable {
    let id: Int
    /// The value name, e.g. "Red".
    let name: String
    /// (id, display_name) of the parent attribute, e.g. (2, "Color").
    let attribute_id: Many2One

    static let fields: [String] = ["id", "name", "attribute_id"]

    /// Convenience for inline labels — `Color: Red` style.
    var displayLabel: String {
        attribute_id.isEmpty ? name : "\(attribute_id.name): \(name)"
    }
}
