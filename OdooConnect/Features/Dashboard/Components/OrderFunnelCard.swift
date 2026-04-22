import SwiftUI
import Charts

/// Donut over confirmed sale.orders, sliced by `invoice_status`. Surfacing
/// invoice progress instead of raw order state because Odoo writes a `draft`
/// order for every shopping cart, which makes a state donut useless.
struct OrderFunnelCard: View {
    let buckets: [InvoicePipelineBucket]

    private var total: Int { buckets.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rechnungspipeline").font(.headline)
                Text("Bestätigte Bestellungen nach Rechnungsstatus")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if buckets.isEmpty {
                ContentUnavailableView("Keine Bestellungen", systemImage: "chart.pie")
                    .frame(minHeight: 140)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    Chart(buckets) { bucket in
                        SectorMark(
                            angle: .value("Anzahl", bucket.count),
                            innerRadius: .ratio(0.62),
                            angularInset: 1.5
                        )
                        .cornerRadius(4)
                        .foregroundStyle(color(for: bucket.status))
                    }
                    .chartLegend(.hidden)
                    .frame(width: 140, height: 140)
                    .overlay {
                        VStack(spacing: 2) {
                            Text("\(total)")
                                .font(.title2.bold().monospacedDigit())
                                .contentTransition(.numericText(value: Double(total)))
                            Text("Gesamt").font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(buckets) { bucket in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(color(for: bucket.status))
                                    .frame(width: 8, height: 8)
                                Text(bucket.label).font(.caption)
                                Spacer(minLength: 8)
                                Text("\(bucket.count)")
                                    .font(.caption.monospacedDigit().weight(.semibold))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func color(for status: String) -> Color {
        switch status {
        case "to invoice": return .orange
        case "invoiced":   return .green
        case "no":         return .secondary
        case "upselling":  return .blue
        default:           return .gray
        }
    }
}
