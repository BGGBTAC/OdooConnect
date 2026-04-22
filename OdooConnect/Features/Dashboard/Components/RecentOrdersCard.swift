import SwiftUI

struct RecentOrdersCard: View {
    let orders: [SaleOrder]
    let currencyCode: String
    let onOrderTap: (SaleOrder) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Letzte Bestellungen", systemImage: "bolt.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.headline)
                Spacer()
            }
            if orders.isEmpty {
                ContentUnavailableView("Noch keine Bestellungen", systemImage: "cart")
                    .frame(minHeight: 120)
            } else {
                VStack(spacing: 0) {
                    ForEach(orders) { order in
                        Button { onOrderTap(order) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(order.name).font(.subheadline.weight(.semibold))
                                    Text(order.partner_id.name)
                                        .font(.caption).foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(order.amount_total,
                                         format: .currency(code: order.currency_id.name.isEmpty ? currencyCode : order.currency_id.name))
                                        .font(.subheadline.monospacedDigit().weight(.semibold))
                                    Text(order.date_order, style: .relative)
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 8)
                        if order.id != orders.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}
