import SwiftUI

struct OrdersListView: View {
    @Environment(AuthManager.self) private var auth
    @State private var orders: [SaleOrder] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var searchText = ""

    var body: some View {
        List(orders) { order in
            NavigationLink(value: order) {
                QuoteRow(quote: order)
            }
        }
        .navigationTitle("Bestellungen")
        .searchable(text: $searchText, prompt: "Kunde oder Nummer")
        .navigationDestination(for: SaleOrder.self) { order in
            OrderDetailView(orderId: order.id)
        }
        .navigationDestination(for: AppRouter.OrderRoute.self) { route in
            switch route {
            case .detail(let id): OrderDetailView(orderId: id)
            }
        }
        .refreshable { await load() }
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await load()
        }
        .overlay {
            if orders.isEmpty && !isLoading {
                ContentUnavailableView(
                    searchText.isEmpty ? "Keine Bestellungen" : "Keine Treffer",
                    systemImage: "cart"
                )
            }
        }
    }

    private func load() async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var domain: [JSON] = [
                .array([.string("state"), .string("in"),
                        .array([.string("sale"), .string("done")])])
            ]
            let needle = searchText.trimmingCharacters(in: .whitespaces)
            if !needle.isEmpty {
                domain.append(.string("|"))
                domain.append(.array([.string("name"), .string("ilike"), .string(needle)]))
                domain.append(.array([.string("partner_id.name"), .string("ilike"), .string(needle)]))
            }
            orders = try await client.searchRead(
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
