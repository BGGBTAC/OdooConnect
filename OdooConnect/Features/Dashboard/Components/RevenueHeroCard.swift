import SwiftUI
import Charts

/// Single hero card that elevates "monthly revenue" from being one tile
/// among nine to the actual focal point of the dashboard. Big number,
/// delta pill, inline sparkline, brand-tinted glass.
struct RevenueHeroCard: View {
    let revenue: StatDelta
    let currencyCode: String
    let series: [RevenuePoint]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Umsatz")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(revenue.current, format: .currency(code: currencyCode))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .contentTransition(.numericText(value: revenue.current))
                        .animation(.spring(duration: 0.45, bounce: 0.20), value: revenue.current)
                }
                Spacer()
                deltaPill
            }

            if !series.isEmpty {
                sparkline
                    .frame(height: 64)
                    .padding(.top, Spacing.xs)
            }

            previousLine
        }
        .cardSurface(.hero)
    }

    @ViewBuilder
    private var deltaPill: some View {
        let positive = revenue.isPositive
        let tint = positive ? Theme.success : Theme.danger
        HStack(spacing: 4) {
            Image(systemName: positive ? "arrow.up.right" : "arrow.down.right")
                .contentTransition(.symbolEffect(.replace))
            if let ratio = revenue.ratio {
                Text(ratio, format: .percent.precision(.fractionLength(0...1)))
                    .contentTransition(.numericText(value: ratio))
                    .monospacedDigit()
            } else {
                Text("—")
            }
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.14), in: .capsule)
        .overlay(Capsule().stroke(tint.opacity(0.30), lineWidth: 0.5))
        .animation(.snappy, value: positive)
    }

    private var sparkline: some View {
        Chart(series) { point in
            AreaMark(
                x: .value("Zeit", point.bucketStart),
                y: .value("Umsatz", point.total)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(
                LinearGradient(
                    colors: [Theme.brand.opacity(0.55), Theme.brand.opacity(0.05)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            LineMark(
                x: .value("Zeit", point.bucketStart),
                y: .value("Umsatz", point.total)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(Theme.brand)
            .lineStyle(StrokeStyle(lineWidth: 2.0, lineCap: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { $0.background(Color.clear) }
        // The hero number above already speaks the value to VoiceOver —
        // a duplicate sparkline announcement would just be noise.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var previousLine: some View {
        if revenue.previous > 0 {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption2)
                Text("Vergleich:")
                Text(revenue.previous, format: .currency(code: currencyCode))
                    .monospacedDigit()
                    .fontWeight(.semibold)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
