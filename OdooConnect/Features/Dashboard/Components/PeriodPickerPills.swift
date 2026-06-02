import SwiftUI

/// Custom segmented control that replaces `.pickerStyle(.segmented)`. The
/// active pill morphs between options via matchedGeometryEffect so the
/// transition reads as physical movement, not a flat redraw.
struct PeriodPickerPills: View {
    @Binding var selection: DashboardPeriod
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pillNS

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DashboardPeriod.allCases) { period in
                pill(for: period)
            }
        }
        .padding(4)
        .glassEffect(.regular.tint(Theme.brand.opacity(0.05)), in: .capsule)
        .overlay(
            Capsule().stroke(Theme.brand.opacity(0.18), lineWidth: 0.5)
        )
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func pill(for period: DashboardPeriod) -> some View {
        let isActive = period == selection
        Button {
            if reduceMotion {
                selection = period
            } else {
                withAnimation(.spring(duration: 0.35, bounce: 0.28)) {
                    selection = period
                }
            }
        } label: {
            Text(period.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isActive ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if isActive {
                        Capsule()
                            .fill(Theme.brand)
                            .matchedGeometryEffect(id: "activePill", in: pillNS)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
