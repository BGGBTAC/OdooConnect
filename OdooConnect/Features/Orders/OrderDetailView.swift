import SwiftUI

struct OrderDetailView: View {
    @Environment(AuthManager.self) private var auth
    let orderId: Int

    @State private var order: SaleOrder?
    @State private var lines: [SaleOrderLine] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        List {
            if let order {
                Section {
                    LabeledContent("Nummer", value: order.name)
                    LabeledContent("Kunde", value: order.partner_id.name)
                    LabeledContent("Datum", value: order.date_order.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("Status", value: order.stateLabel)
                }
                Section("Positionen") {
                    ForEach(lines) { line in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(line.product_id.name).font(.headline)
                            HStack {
                                Text("\(line.product_uom_qty, specifier: "%.2f") × \(line.price_unit, format: .currency(code: "EUR"))")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Spacer()
                                Text(line.price_subtotal, format: .currency(code: "EUR"))
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                Section("Summe") {
                    HStack {
                        Text("Netto").foregroundStyle(.secondary)
                        Spacer()
                        Text(order.amount_untaxed, format: .currency(code: "EUR")).monospacedDigit()
                    }
                    HStack {
                        Text("Gesamt").font(.headline)
                        Spacer()
                        Text(order.amount_total, format: .currency(code: "EUR"))
                            .font(.headline.monospacedDigit())
                    }
                }
            }
        }
        .navigationTitle(order?.name ?? "Bestellung")
        .task { await load() }
        .overlay { if isLoading && order == nil { ProgressView() } }
    }

    private func load() async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let orders: [SaleOrder] = try await client.searchRead(
                model: "sale.order",
                domain: [.array([.string("id"), .string("="), .int(orderId)])],
                fields: SaleOrder.fields,
                limit: 1
            )
            self.order = orders.first
            self.lines = try await client.searchRead(
                model: "sale.order.line",
                domain: [.array([.string("order_id"), .string("="), .int(orderId)])],
                fields: SaleOrderLine.fields,
                limit: 500,
                order: "sequence asc, id asc"
            )
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
