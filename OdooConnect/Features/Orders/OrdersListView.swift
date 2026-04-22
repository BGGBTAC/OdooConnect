import SwiftUI

struct OrdersListView: View {
    @Environment(AuthManager.self) private var auth
    @State private var orders: [SaleOrder] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        List(orders) { order in
            NavigationLink(value: order) {
                QuoteRow(quote: order)
            }
        }
        .navigationTitle("Bestellungen")
        .navigationDestination(for: SaleOrder.self) { order in
            OrderDetailView(orderId: order.id)
        }
        .refreshable { await load() }
        .task { await load() }
        .overlay {
            if orders.isEmpty && !isLoading {
                ContentUnavailableView("Keine Bestellungen", systemImage: "cart")
            }
        }
    }

    private func load() async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            orders = try await client.searchRead(
                model: "sale.order",
                domain: [.array([.string("state"), .string("in"), .array([.string("sale"), .string("done")])])],
                fields: SaleOrder.fields,
                limit: 200,
                order: "date_order desc"
            )
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
