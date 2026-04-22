import SwiftUI
import Charts

struct DashboardView: View {
    @Environment(AuthManager.self) private var auth
    @State private var model = DashboardViewModel()

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                StatCard(title: "Umsatz (Monat)",
                         value: model.monthlyRevenue.formatted(currency: model.currency),
                         systemImage: "eurosign.circle.fill",
                         tint: .green)
                StatCard(title: "Offene Angebote",
                         value: "\(model.openQuotes)",
                         systemImage: "doc.text",
                         tint: .blue)
                StatCard(title: "Offene Bestellungen",
                         value: "\(model.openOrders)",
                         systemImage: "cart.fill",
                         tint: .orange)
                StatCard(title: "Offene Rechnungen",
                         value: model.outstandingReceivable.formatted(currency: model.currency),
                         systemImage: "exclamationmark.circle.fill",
                         tint: .red)
            }
            .padding(.horizontal)

            if !model.weeklyRevenue.isEmpty {
                revenueChart
                    .padding()
            }
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage).foregroundStyle(tint)
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
            Text(value).font(.title2.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private extension Double {
    func formatted(currency: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        return f.string(from: self as NSNumber) ?? "\(self)"
    }
}
