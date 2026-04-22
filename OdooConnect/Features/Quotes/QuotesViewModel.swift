import Foundation
import Observation

@Observable
@MainActor
final class QuotesViewModel {
    var quotes: [SaleOrder] = []
    var isLoading: Bool = false
    var error: String?

    func load(using client: OdooClient?) async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            quotes = try await client.searchRead(
                model: "sale.order",
                domain: [.array([.string("state"), .string("in"), .array([.string("draft"), .string("sent")])])],
                fields: SaleOrder.fields,
                limit: 200,
                order: "date_order desc"
            )
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
