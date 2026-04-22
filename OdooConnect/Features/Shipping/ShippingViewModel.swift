import Foundation
import Observation

@Observable
@MainActor
final class ShippingViewModel {
    enum StateFilter: String, CaseIterable, Identifiable {
        case ready, waiting, done, all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .ready:   return "Bereit"
            case .waiting: return "Wartet"
            case .done:    return "Versendet"
            case .all:     return "Alle"
            }
        }
        var states: [String] {
            switch self {
            case .ready:   return ["assigned"]
            case .waiting: return ["confirmed", "waiting"]
            case .done:    return ["done"]
            case .all:     return ["draft", "waiting", "confirmed", "assigned", "done"]
            }
        }
    }

    var pickings: [StockPicking] = []
    var filter: StateFilter = .ready
    var searchText: String = ""
    var isLoading: Bool = false
    var error: String?

    func load(using client: OdooClient?) async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        error = nil

        var domain: [JSON] = [
            .array([.string("picking_type_code"), .string("="), .string("outgoing")]),
            .array([.string("state"), .string("in"),
                    .array(filter.states.map { .string($0) })])
        ]
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        if !needle.isEmpty {
            domain.append(.string("|"))
            domain.append(.string("|"))
            domain.append(.array([.string("name"), .string("ilike"), .string(needle)]))
            domain.append(.array([.string("origin"), .string("ilike"), .string(needle)]))
            domain.append(.array([.string("partner_id.name"), .string("ilike"), .string(needle)]))
        }
        do {
            pickings = try await client.searchRead(
                model: "stock.picking",
                domain: domain,
                fields: StockPicking.fields,
                limit: 200,
                order: filter == .done ? "date_done desc" : "scheduled_date asc"
            )
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
