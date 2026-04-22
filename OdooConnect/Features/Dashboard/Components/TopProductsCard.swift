import SwiftUI
import Charts

struct TopProductsCard: View {
    let products: [TopProductRow]
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Produkte").font(.headline)
            if products.isEmpty {
                ContentUnavailableView("Keine Verkäufe", systemImage: "shippingbox")
                    .frame(height: 180)
            } else {
                Chart(products) { row in
                    BarMark(
                        x: .value("Umsatz", row.revenue),
                        y: .value("Produkt", row.name)
                    )
                    .foregroundStyle(by: .value("Produkt", row.name))
                    .cornerRadius(6)
                    .annotation(position: .trailing) {
                        Text(row.revenue, format: .currency(code: currencyCode))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .chartLegend(.hidden)
                .chartXAxis { AxisMarks { _ in AxisValueLabel() } }
                .frame(height: max(180, CGFloat(products.count) * 42))
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}
