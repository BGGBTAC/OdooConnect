import SwiftUI
import Charts

struct RevenueChartCard: View {
    let title: String
    let points: [RevenuePoint]
    let currencyCode: String
    let interval: DashboardPeriod.SeriesInterval

    @State private var selectedDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let point = highlightedPoint {
                        Text(point.bucketStart, format: dateLabelFormat)
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.brand)
                    }
                }
                Spacer()
                if let point = highlightedPoint {
                    Text(point.total, format: .currency(code: currencyCode))
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText(value: point.total))
                } else if let latest = points.last {
                    Text(latest.total, format: .currency(code: currencyCode))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            chart
                .frame(minHeight: 180, maxHeight: 320)
                .accessibilityChartDescriptor(self)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var chart: some View {
        Chart(points) { point in
            AreaMark(
                x: .value("Zeit", point.bucketStart, unit: chartUnit),
                y: .value("Umsatz", point.total)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(
                LinearGradient(
                    colors: [Theme.brand.opacity(0.55), Theme.brand.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .accessibilityLabel(Text(point.bucketStart, format: dateLabelFormat))
            .accessibilityValue(Text(point.total, format: .currency(code: currencyCode)))

            LineMark(
                x: .value("Zeit", point.bucketStart, unit: chartUnit),
                y: .value("Umsatz", point.total)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(Theme.brand)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))

            // Highlight ruler + dot only when the user is dragging.
            if let highlighted = highlightedPoint, highlighted.bucketStart == point.bucketStart {
                RuleMark(x: .value("Auswahl", highlighted.bucketStart, unit: chartUnit))
                    .foregroundStyle(Theme.brand.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                PointMark(
                    x: .value("Zeit", highlighted.bucketStart, unit: chartUnit),
                    y: .value("Umsatz", highlighted.total)
                )
                .symbolSize(120)
                .foregroundStyle(Theme.brand)
            }
        }
        .chartXAxis {
            AxisMarks(preset: .aligned) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.18))
                AxisValueLabel(format: axisFormat, centered: false)
                    .font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.18))
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount, format: compactCurrency)
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYScale(domain: .automatic(includesZero: true))
        .chartXSelection(value: $selectedDate)
    }

    // MARK: - Helpers

    /// Snap the touch X-position to the nearest bucket so the rule + dot
    /// land exactly on a real data point (selection alone would float
    /// between samples and look sloppy).
    private var highlightedPoint: RevenuePoint? {
        guard let selectedDate else { return nil }
        return points.min { lhs, rhs in
            abs(lhs.bucketStart.timeIntervalSince(selectedDate)) <
                abs(rhs.bucketStart.timeIntervalSince(selectedDate))
        }
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

    private var dateLabelFormat: Date.FormatStyle {
        switch interval {
        case .hour: return .dateTime.weekday(.abbreviated).hour()
        case .day:  return .dateTime.weekday(.abbreviated).day().month(.abbreviated)
        case .week: return .dateTime.day().month(.abbreviated)
        }
    }

    /// Shorter currency for axis labels: 12.4k € instead of CHF 12'432.50.
    private var compactCurrency: FloatingPointFormatStyle<Double>.Currency {
        .currency(code: currencyCode)
            .notation(.compactName)
            .precision(.fractionLength(0...1))
    }
}

// MARK: - Audio Graph (VoiceOver)

extension RevenueChartCard: AXChartDescriptorRepresentable {
    nonisolated func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXNumericDataAxisDescriptor(
            title: "Zeitpunkt",
            range: (points.first?.bucketStart.timeIntervalSince1970 ?? 0)
                ... (points.last?.bucketStart.timeIntervalSince1970 ?? 0),
            gridlinePositions: []
        ) { Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .omitted) }

        let totals = points.map(\.total)
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Umsatz",
            range: (totals.min() ?? 0) ... (totals.max() ?? 0),
            gridlinePositions: []
        ) { String(format: "%.0f %@", $0, currencyCode) }

        let series = AXDataSeriesDescriptor(
            name: "Umsatz",
            isContinuous: true,
            dataPoints: points.map { point in
                AXDataPoint(
                    x: point.bucketStart.timeIntervalSince1970,
                    y: point.total
                )
            }
        )

        return AXChartDescriptor(
            title: "Umsatzverlauf",
            summary: nil,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}
