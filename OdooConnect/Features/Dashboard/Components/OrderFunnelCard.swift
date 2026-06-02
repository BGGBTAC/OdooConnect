import SwiftUI
import Charts

/// Confirmed sale.orders by `invoice_status`, drawn as a horizontal bar
/// chart — better for magnitude comparison than a donut (angular area is
/// hard to judge). Surfacing invoice progress instead of raw order state
/// because Odoo writes a `draft` order for every shopping cart, which makes
/// a state chart useless.
struct OrderFunnelCard: View {
    let buckets: [InvoicePipelineBucket]

    private var total: Int { buckets.reduce(0) { $0 + $1.count } }

    private var sorted: [InvoicePipelineBucket] {
        buckets.sorted { $0.count > $1.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rechnungspipeline").font(.headline)
                    Text("Bestätigte Bestellungen nach Rechnungsstatus")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if total > 0 {
                    Text("\(total)")
                        .font(.title3.bold().monospacedDigit())
                        .contentTransition(.numericText(value: Double(total)))
                }
            }

            if buckets.isEmpty {
                BrandedEmptyState(
                    title: "Keine Bestellungen",
                    systemImage: "chart.bar",
                    message: "In dieser Periode wurden keine Bestellungen bestätigt."
                )
                .frame(minHeight: 140)
            } else {
                chart
            }
        }
        .padding()
        .contentCard(cornerRadius: 16)
    }

    private var chart: some View {
        Chart(sorted) { bucket in
            BarMark(
                x: .value("Anzahl", bucket.count),
                y: .value("Status", bucket.label)
            )
            .cornerRadius(6)
            .foregroundStyle(color(for: bucket.label))
            .annotation(position: .trailing, alignment: .leading, spacing: 6) {
                Text("\(bucket.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(Text(bucket.label))
            .accessibilityValue(Text("\(bucket.count) Bestellungen"))
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(preset: .aligned, position: .leading) { _ in
                AxisValueLabel().font(.caption)
            }
        }
        .chartLegend(.hidden)
        .frame(height: CGFloat(sorted.count) * 40 + 12)
    }

    /// Semantic status colours (warning = action needed, success = handled,
    /// slate = neutral, info = follow-up).
    private func color(for label: String) -> Color {
        switch label {
        case "Zu fakturieren": return Theme.warning
        case "Fakturiert":     return Theme.success
        case "Keine Rechnung": return Theme.slate
        case "Nachverkauf":    return Theme.info
        default:               return Theme.slate
        }
    }
}
