import SwiftUI

struct LowStockCard: View {
    let rows: [LowStockRow]
    var onTap: ((LowStockRow) -> Void)?

    private var subtitle: String {
        guard let first = rows.first else { return "Lagerbestand-Übersicht" }
        return first.minQty != nil
            ? "Unter konfiguriertem Mindestbestand"
            : "Forecast ≤ 5 Stk (kein Reorder-Rule definiert)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Kritischer Bestand", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !rows.isEmpty {
                    Text("\(rows.count)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
            if rows.isEmpty {
                ContentUnavailableView(
                    "Alles auf Lager",
                    systemImage: "checkmark.seal",
                    description: Text("Keine Artikel unter der Schwelle.")
                )
                .frame(minHeight: 120)
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        Button {
                            onTap?(row)
                        } label: {
                            stockRow(row)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 8)
                        if row.id != rows.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    @ViewBuilder
    private func stockRow(_ row: LowStockRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    Label("\(row.onHand, specifier: "%.0f")", systemImage: "cube.box")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if row.forecast != row.onHand {
                        Label("\(row.forecast, specifier: "%.0f") prog.", systemImage: "calendar")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if let minQty = row.minQty {
                        Label("Min \(minQty, specifier: "%.0f")", systemImage: "arrow.down.to.line")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(row.forecast, specifier: "%.0f")")
                    .monospacedDigit()
                    .font(.headline)
                    .foregroundStyle(severityColor(for: row))
                Text("Forecast").font(.caption2).foregroundStyle(.secondary)
            }
            if onTap != nil {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                    .padding(.top, 4)
            }
        }
    }

    private func severityColor(for row: LowStockRow) -> Color {
        if row.forecast <= 0 { return .red }
        if let minQty = row.minQty, row.forecast < minQty * 0.5 { return .red }
        if row.forecast <= 2 { return .orange }
        return .yellow
    }
}
