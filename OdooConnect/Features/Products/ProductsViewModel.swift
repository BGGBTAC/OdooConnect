import Foundation
import Observation

@Observable
@MainActor
final class ProductsViewModel {
    enum StockFilter: String, CaseIterable, Identifiable {
        case all, inStock, low, outOfStock
        var id: String { rawValue }

        var label: String {
            switch self {
            case .all:         return "Alle"
            case .inStock:     return "Auf Lager"
            case .low:         return "Knapp"
            case .outOfStock:  return "Leer"
            }
        }
    }

    var products: [ProductDetail] = []
    var searchText: String = ""
    var filter: StockFilter = .all
    var isLoading: Bool = false
    var error: String?

    func load(using client: OdooClient?) async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        error = nil

        var domain: [JSON] = [
            .array([.string("sale_ok"), .string("="), .bool(true)]),
            .array([.string("active"), .string("="), .bool(true)])
        ]
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        if !needle.isEmpty {
            domain.append(.string("|"))
            domain.append(.string("|"))
            domain.append(.array([.string("name"), .string("ilike"), .string(needle)]))
            domain.append(.array([.string("default_code"), .string("ilike"), .string(needle)]))
            domain.append(.array([.string("barcode"), .string("="), .string(needle)]))
        }

        switch filter {
        case .all: break
        case .inStock:
            domain.append(.array([.string("qty_available"), .string(">"), .int(5)]))
        case .low:
            domain.append(.array([.string("qty_available"), .string(">"), .int(0)]))
            domain.append(.array([.string("qty_available"), .string("<="), .int(5)]))
        case .outOfStock:
            domain.append(.array([.string("qty_available"), .string("<="), .int(0)]))
        }

        do {
            products = try await client.searchRead(
                model: "product.product",
                domain: domain,
                fields: ProductDetail.fields,
                limit: 200,
                order: "name asc"
            )
        } catch {
            // Stock fields may not exist on a minimal install — retry without them.
            do {
                products = try await client.searchRead(
                    model: "product.product",
                    domain: domain.filter { clause in
                        guard case .array(let parts) = clause, parts.count == 3,
                              case .string(let field) = parts[0]
                        else { return true }
                        return !ProductDetail.stockFields.contains(field)
                    },
                    fields: ProductDetail.baseFields,
                    limit: 200,
                    order: "name asc"
                )
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
