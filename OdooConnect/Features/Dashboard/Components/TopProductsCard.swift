import SwiftUI

struct TopProductsCard: View {
    let products: [TopProductRow]
    let currencyCode: String

    private var maxQuantity: Double {
        products.map(\.quantity).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Top Produkte").font(.headline)
                Text("Meistverkauft im Zeitraum")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if products.isEmpty {
                ContentUnavailableView("Keine Verkäufe", systemImage: "shippingbox")
                    .frame(minHeight: 140)
            } else {
                VStack(spacing: 14) {
                    ForEach(products) { row in
                        productRow(row)
                    }
                }
            }
        }
        .padding()
        .contentCard(cornerRadius: 16)
    }

    @ViewBuilder
    private func productRow(_ row: TopProductRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(row.quantity, specifier: "%.0f") Stk")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(.primary)
            }
            HStack(spacing: 8) {
                ProgressView(value: row.quantity / maxQuantity)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                Text(row.revenue, format: .currency(code: currencyCode))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
