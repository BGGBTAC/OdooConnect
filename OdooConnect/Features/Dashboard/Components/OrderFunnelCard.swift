import SwiftUI
import Charts

struct OrderFunnelCard: View {
    let buckets: [OrderStateBucket]

    private var total: Int { buckets.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bestellungen nach Status").font(.headline)
            if buckets.isEmpty {
                ContentUnavailableView("Keine Bestellungen", systemImage: "chart.pie")
                    .frame(height: 180)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    Chart(buckets) { bucket in
                        SectorMark(
                            angle: .value("Anzahl", bucket.count),
                            innerRadius: .ratio(0.62),
                            angularInset: 1.5
                        )
                        .cornerRadius(4)
                        .foregroundStyle(color(for: bucket.state))
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
                                    .fill(color(for: bucket.state))
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

    private func color(for state: String) -> Color {
        switch state {
        case "draft":  return .gray
        case "sent":   return .blue
        case "sale":   return .accentColor
        case "done":   return .green
        case "cancel": return .red
        default:       return .secondary
        }
    }
}
