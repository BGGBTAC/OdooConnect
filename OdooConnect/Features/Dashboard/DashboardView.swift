import SwiftUI
import Charts

struct DashboardView: View {
    @Environment(AuthManager.self) private var auth
    @State private var model = DashboardViewModel()

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                LazyVGrid(columns: columns, spacing: 16) {
                    StatCard(title: "Umsatz (Monat)",
                             systemImage: "eurosign.circle.fill",
                             tint: .green) {
                        Text(model.monthlyRevenue, format: .currency(code: code))
                            .contentTransition(.numericText(value: model.monthlyRevenue))
                            .animation(.snappy, value: model.monthlyRevenue)
                    }
                    StatCard(title: "Offene Angebote",
                             systemImage: "doc.text",
                             tint: .blue) {
                        Text("\(model.openQuotes)")
                            .contentTransition(.numericText(value: Double(model.openQuotes)))
                            .animation(.snappy, value: model.openQuotes)
                    }
                    StatCard(title: "Offene Bestellungen",
                             systemImage: "cart.fill",
                             tint: .orange) {
                        Text("\(model.openOrders)")
                            .contentTransition(.numericText(value: Double(model.openOrders)))
                            .animation(.snappy, value: model.openOrders)
                    }
                    StatCard(title: "Offene Rechnungen",
                             systemImage: "exclamationmark.circle.fill",
                             tint: .red) {
                        Text(model.outstandingReceivable, format: .currency(code: code))
                            .contentTransition(.numericText(value: model.outstandingReceivable))
                            .animation(.snappy, value: model.outstandingReceivable)
                    }
                }
                .padding(.horizontal)

                if !model.weeklyRevenue.isEmpty {
                    revenueChart
                        .padding()
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(.smooth, value: model.weeklyRevenue.count)
        }
        .navigationTitle("Dashboard")
        .refreshable { await model.load(using: auth.client) }
        .task { await model.load(using: auth.client) }
        .overlay { if model.isLoading && model.weeklyRevenue.isEmpty { ProgressView() } }
        .alert("Fehler", isPresented: .constant(model.error != nil)) {
            Button("OK") { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
    }

    private var code: String { auth.companyCurrency.code }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 200), spacing: 16)]
    }

    private var revenueChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Umsatz letzte 8 Wochen")
                .font(.headline)
            Chart(model.weeklyRevenue) { point in
                BarMark(
                    x: .value("Woche", point.weekStart, unit: .weekOfYear),
                    y: .value("Umsatz", point.total)
                )
                .foregroundStyle(.tint)
            }
            .frame(height: 220)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

private struct StatCard<Value: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let value: () -> Value

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage).foregroundStyle(tint)
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
            value()
                .font(.title2.bold())
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}
