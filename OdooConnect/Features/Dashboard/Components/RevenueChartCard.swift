import SwiftUI
import Charts

struct RevenueChartCard: View {
    let title: String
    let points: [RevenuePoint]
    let currencyCode: String
    let interval: DashboardPeriod.SeriesInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if let latest = points.last {
                    Text(latest.total, format: .currency(code: currencyCode))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Chart(points) { point in
                AreaMark(
                    x: .value("Zeit", point.bucketStart, unit: chartUnit),
                    y: .value("Umsatz", point.total)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.accentColor.opacity(0.55), .accentColor.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("Zeit", point.bucketStart, unit: chartUnit),
                    y: .value("Umsatz", point.total)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(.tint)
            }
            .frame(height: 220)
            .chartXAxis {
                AxisMarks(preset: .aligned) { _ in
                    AxisValueLabel(format: axisFormat, centered: false)
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var chartUnit: Calendar.Component {
        switch interval {
        case .hour: return .hour
        case .day:  return .day
        case .week: return .weekOfYear
        }
    }

    private var axisFormat: Date.FormatStyle {
        switch interval {
        case .hour: return .dateTime.hour()
        case .day:  return .dateTime.day().month(.abbreviated)
        case .week: return .dateTime.day().month(.abbreviated)
        }
    }
}
