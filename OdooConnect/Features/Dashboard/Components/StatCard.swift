import SwiftUI

/// KPI card used in the dashboard grid.
///
/// Layout is a deliberate three-row stack:
///
///     [icon] TITEL  (uppercase, tracked, single-line — always gets full width)
///     1'234.56       (big rounded monospaced-digit value, scales down if needed)
///     ↗ +12%         (compact delta pill, only when we have a comparison)
///
/// Early versions put the delta pill in the title row and forced the title
/// into a narrow column, which caused iOS to hyphenate German words like
/// "Bestellungen" into "Bestel-lungen". Giving title + value + delta each
/// their own full-width row removes every width conflict.
struct StatCard<Value: View>: View {
    let title: String
    let systemImage: String
    /// Optional semantic accent for the icon. `nil` (the default) keeps the
    /// tile neutral — iOS 26 craft rule: don't give each KPI its own hue
    /// ("rainbow dashboard"). Only pass a colour when it carries meaning
    /// (e.g. danger when a metric is in the red).
    let tint: Color?
    let delta: StatDelta?
    let value: () -> Value

    init(
        title: String,
        systemImage: String,
        tint: Color? = nil,
        delta: StatDelta? = nil,
        @ViewBuilder value: @escaping () -> Value
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.delta = delta
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            titleRow
            value()
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let delta {
                DeltaBadge(delta: delta)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: Radius.standard)
    }

    private var titleRow: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint ?? .secondary)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 14, alignment: .leading)
            Text(title)
                .font(.caption.weight(.semibold))
                .kerning(0.4)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }
}

/// Compact delta pill. Integer-precision percent so it always fits
/// on a single line inside a narrow KPI card (previously we rendered
/// "-37.2%" which wrapped to "-37." / "2%" in a tall pill).
struct DeltaBadge: View {
    let delta: StatDelta

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: delta.isPositive ? "arrow.up.right" : "arrow.down.right")
                .contentTransition(.symbolEffect(.replace))
            if let ratio = delta.ratio {
                Text(ratio, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: ratio))
            } else {
                Text("—")
            }
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.15), in: .capsule)
        .overlay(Capsule().stroke(tint.opacity(0.25), lineWidth: 0.5))
        .fixedSize(horizontal: true, vertical: false)
        .animation(.snappy, value: delta.isPositive)
    }

    private var tint: Color {
        delta.isPositive ? Theme.success : Theme.danger
    }
}
