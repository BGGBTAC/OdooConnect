import Foundation
import Observation

@Observable
@MainActor
final class QuotesViewModel {
    var quotes: [SaleOrder] = []
    var isLoading: Bool = false
    var error: String?

    func load(using client: OdooClient?, search: String = "") async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var domain: [JSON] = [
                .array([.string("state"), .string("in"),
                        .array([.string("draft"), .string("sent")])])
            ]
            let needle = search.trimmingCharacters(in: .whitespaces)
            if !needle.isEmpty {
                domain.append(.string("|"))
                domain.append(.array([.string("name"), .string("ilike"), .string(needle)]))
                domain.append(.array([.string("partner_id.name"), .string("ilike"), .string(needle)]))
            }
            quotes = try await client.searchRead(
                model: "sale.order",
                domain: domain,
                fields: SaleOrder.fields,
                limit: 200,
                order: "date_order desc"
            )
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
