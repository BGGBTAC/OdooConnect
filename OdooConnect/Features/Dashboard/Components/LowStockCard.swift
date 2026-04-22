import SwiftUI

struct LowStockCard: View {
    let rows: [LowStockRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Kritischer Bestand", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.headline)
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
                        HStack {
                            Text(row.name)
                                .lineLimit(2)
                            Spacer()
                            Text("\(row.quantity, specifier: "%.0f") Stk")
                                .monospacedDigit()
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(color(for: row.quantity))
                        }
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

    private func color(for quantity: Double) -> Color {
        quantity <= 0 ? .red : (quantity <= 2 ? .orange : .yellow)
    }
}
