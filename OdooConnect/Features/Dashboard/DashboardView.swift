import SwiftUI

struct DashboardView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var model = DashboardViewModel()

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                VStack(spacing: 16) {
                    periodPicker
                        .padding(.horizontal)

                    kpiGrid
                        .padding(.horizontal)

                    if !model.revenueSeries.isEmpty {
                        RevenueChartCard(
                            title: revenueTitle,
                            points: model.revenueSeries,
                            currencyCode: code,
                            interval: model.period.seriesInterval
                        )
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }

                    adaptivePair(
                        TopProductsCard(products: model.topProducts, currencyCode: code),
                        OrderFunnelCard(buckets: model.orderBuckets)
                    )
                    .padding(.horizontal)

                    adaptivePair(
                        LowStockCard(rows: model.lowStock),
                        RecentOrdersCard(orders: model.recentOrders, currencyCode: code) { order in
                            router.selectedTab = .orders
                            router.ordersPath.append(AppRouter.OrderRoute.detail(order.id))
                        }
                    )
                    .padding(.horizontal)
                }
                .animation(.smooth, value: model.kpis)
                .animation(.smooth, value: model.revenueSeries.count)
                .padding(.vertical)
            }
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if model.isLoading {
                    ProgressView()
                } else if let refreshed = model.lastRefresh {
                    Text(refreshed, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .refreshable { await model.load(using: auth.client) }
        .task { await model.load(using: auth.client) }
        .alert("Fehler", isPresented: .constant(model.error != nil)) {
            Button("OK") { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
    }

    private var code: String { auth.companyCurrency.code }

    private var revenueTitle: String {
        switch model.period {
        case .today:  return "Umsatzverlauf heute"
        case .last7:  return "Umsatz letzte 7 Tage"
        case .last30: return "Umsatz letzte 30 Tage"
        case .ytd:    return "Umsatz laufendes Jahr"
        }
    }

    private var periodPicker: some View {
        Picker("Zeitraum", selection: Binding(
            get: { model.period },
            set: { model.period = $0 }
        )) {
            ForEach(DashboardPeriod.allCases) { period in
                Text(period.label).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            StatCard(title: "Umsatz",
                     systemImage: "eurosign.circle.fill",
                     tint: .green,
                     delta: model.kpis.revenue) {
                Text(model.kpis.revenue.current, format: .currency(code: code))
                    .contentTransition(.numericText(value: model.kpis.revenue.current))
            }
            StatCard(title: "Bestellungen",
                     systemImage: "cart.fill",
                     tint: .accentColor,
                     delta: model.kpis.orderCount) {
                Text("\(Int(model.kpis.orderCount.current))")
                    .contentTransition(.numericText(value: model.kpis.orderCount.current))
            }
            StatCard(title: "Ø Warenkorb",
                     systemImage: "basket.fill",
                     tint: .purple,
                     delta: model.kpis.averageOrderValue) {
                Text(model.kpis.averageOrderValue.current, format: .currency(code: code))
                    .contentTransition(.numericText(value: model.kpis.averageOrderValue.current))
            }
            StatCard(title: "Neue Kunden",
                     systemImage: "person.badge.plus",
                     tint: .teal,
                     delta: model.kpis.newCustomers) {
                Text("\(Int(model.kpis.newCustomers.current))")
                    .contentTransition(.numericText(value: model.kpis.newCustomers.current))
            }
            StatCard(title: "Offene Angebote",
                     systemImage: "doc.text",
                     tint: .blue) {
                Text("\(model.kpis.openQuotes)")
                    .contentTransition(.numericText(value: Double(model.kpis.openQuotes)))
            }
            StatCard(title: "Offene Lieferungen",
                     systemImage: "shippingbox.fill",
                     tint: .indigo) {
                if let value = model.kpis.pendingDeliveries {
                    Text("\(value)")
                        .contentTransition(.numericText(value: Double(value)))
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            StatCard(title: "Low Stock",
                     systemImage: "exclamationmark.triangle.fill",
                     tint: .orange) {
                if let value = model.kpis.lowStockCount {
                    Text("\(value)")
                        .contentTransition(.numericText(value: Double(value)))
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            StatCard(title: "Stornoquote",
                     systemImage: "xmark.circle.fill",
                     tint: .red) {
                Text(model.kpis.cancelRate, format: .percent.precision(.fractionLength(0...1)))
                    .contentTransition(.numericText(value: model.kpis.cancelRate))
            }
            StatCard(title: "Offene Forderungen",
                     systemImage: "creditcard.fill",
                     tint: .pink) {
                Text(model.kpis.outstandingReceivable, format: .currency(code: code))
                    .contentTransition(.numericText(value: model.kpis.outstandingReceivable))
            }
        }
    }

    @ViewBuilder
    private func adaptivePair<A: View, B: View>(_ first: A, _ second: B) -> some View {
        if hSize == .regular {
            HStack(alignment: .top, spacing: 16) {
                first.frame(maxWidth: .infinity)
                second.frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 16) {
                first
                second
            }
        }
    }
}
