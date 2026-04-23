import SwiftUI
import Charts

/// Donut over confirmed sale.orders, sliced by `invoice_status`. Surfacing
/// invoice progress instead of raw order state because Odoo writes a `draft`
/// order for every shopping cart, which makes a state donut useless.
struct OrderFunnelCard: View {
    let buckets: [InvoicePipelineBucket]

    @State private var selectedCount: Int?

    private var total: Int { buckets.reduce(0) { $0 + $1.count } }

    /// Map the angular selection (which returns a count value) back to a bucket.
    /// Picks the smallest matching bucket if multiple share a count.
    private var selectedBucket: InvoicePipelineBucket? {
        guard let selectedCount else { return nil }
        // The selection gives us the *cumulative* angle as count; resolve by
        // walking the bucket list and finding which slice the angle falls in.
        var cursor = 0
        for bucket in buckets.sorted(by: { $0.count > $1.count }) {
            cursor += bucket.count
            if selectedCount <= cursor { return bucket }
        }
        return buckets.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rechnungspipeline").font(.headline)
                Text("Bestätigte Bestellungen nach Rechnungsstatus")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if buckets.isEmpty {
                BrandedEmptyState(
                    title: "Keine Bestellungen",
                    systemImage: "chart.pie",
                    message: "In dieser Periode wurden keine Bestellungen bestätigt."
                )
                .frame(minHeight: 140)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    donut
                        .aspectRatio(1, contentMode: .fit)
                        .frame(minWidth: 120, maxWidth: 180)
                    legend
                }
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var donut: some View {
        Chart(buckets) { bucket in
            SectorMark(
                angle: .value("Anzahl", bucket.count),
                innerRadius: .ratio(0.62),
                angularInset: selectedBucket?.id == bucket.id ? 3 : 1.5
            )
            .cornerRadius(4)
            .foregroundStyle(by: .value("Status", bucket.label))
            .opacity(selectedBucket == nil || selectedBucket?.id == bucket.id ? 1.0 : 0.35)
            .accessibilityLabel(Text(bucket.label))
            .accessibilityValue(Text("\(bucket.count) Bestellungen"))
        }
        .chartLegend(.hidden)
        .chartForegroundStyleScale(colorMapping)
        .chartAngleSelection(value: $selectedCount)
        .animation(.snappy, value: selectedBucket?.id)
        .overlay { centerOverlay }
    }

    @ViewBuilder
    private var centerOverlay: some View {
        if let bucket = selectedBucket {
            VStack(spacing: 2) {
                Text("\(bucket.count)")
                    .font(.title2.bold().monospacedDigit())
                    .contentTransition(.numericText(value: Double(bucket.count)))
                Text(bucket.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 4)
            }
        } else {
            VStack(spacing: 2) {
                Text("\(total)")
                    .font(.title2.bold().monospacedDigit())
                    .contentTransition(.numericText(value: Double(total)))
                Text("Gesamt").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(buckets) { bucket in
                Button {
                    if selectedBucket?.id == bucket.id {
                        selectedCount = nil
                    } else {
                        // Re-derive the cumulative count for this bucket.
                        var cursor = 0
                        for b in buckets.sorted(by: { $0.count > $1.count }) {
                            cursor += b.count
                            if b.id == bucket.id {
                                selectedCount = cursor
                                break
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(color(for: bucket.label))
                            .frame(width: 8, height: 8)
                        Text(bucket.label).font(.caption)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Text("\(bucket.count)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .opacity(selectedBucket == nil || selectedBucket?.id == bucket.id ? 1 : 0.45)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Maps invoice_status labels to semantic Theme colors so the donut
    /// reads consistently with the rest of the dashboard (warning =
    /// action needed, success = handled, slate = neutral, info = followup).
    private var colorMapping: KeyValuePairs<String, Color> {
        [
            "Zu fakturieren": Theme.warning,
            "Fakturiert":     Theme.success,
            "Keine Rechnung": Theme.slate,
            "Nachverkauf":    Theme.info
        ]
    }

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
