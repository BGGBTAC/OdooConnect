import SwiftUI

/// Generic KPI card. Pass any `Text` (or other view) as the value so callers
/// can apply `.contentTransition(.numericText)` where appropriate.
struct StatCard<Value: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let delta: StatDelta?
    let value: () -> Value

    init(
        title: String,
        systemImage: String,
        tint: Color,
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).foregroundStyle(tint)
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if let delta {
                    DeltaBadge(delta: delta)
                }
            }
            value()
                .font(.title2.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

struct DeltaBadge: View {
    let delta: StatDelta

    var body: some View {
        let ratio = delta.ratio
        HStack(spacing: 2) {
            Image(systemName: delta.isPositive ? "arrow.up.right" : "arrow.down.right")
                .contentTransition(.symbolEffect(.replace))
            if let ratio {
                Text(ratio, format: .percent.precision(.fractionLength(0...1)))
                    .contentTransition(.numericText(value: ratio))
            } else {
                Text("—")
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(delta.isPositive ? .green : .red)
        .background(
            (delta.isPositive ? Color.green : Color.red).opacity(0.15),
            in: Capsule()
        )
        .animation(.snappy, value: delta.isPositive)
    }
}
