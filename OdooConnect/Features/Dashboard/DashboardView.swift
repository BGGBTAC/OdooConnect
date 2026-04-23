import SwiftUI

struct DashboardView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = DashboardViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                PeriodPickerPills(selection: Binding(
                    get: { model.period },
                    set: { model.period = $0 }
                ))
                .padding(.top, Spacing.xs)

                RevenueHeroCard(
                    revenue: model.kpis.revenue,
                    currencyCode: code,
                    series: model.revenueSeries
                )

                kpiGrid

                if !model.revenueSeries.isEmpty {
                    RevenueChartCard(
                        title: revenueTitle,
                        points: model.revenueSeries,
                        currencyCode: code,
                        interval: model.period.seriesInterval
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }

                adaptivePair(
                    TopProductsCard(products: model.topProducts, currencyCode: code),
                    OrderFunnelCard(buckets: model.invoicePipeline)
                )

                adaptivePair(
                    LowStockCard(rows: model.lowStock) { row in
                        router.openProduct(id: row.productId)
                    },
                    RecentOrdersCard(orders: model.recentOrders, currencyCode: code) { order in
                        router.selectedTab = .orders
                        router.ordersPath.append(AppRouter.OrderRoute.detail(order.id))
                    }
                )
            }
            .animation(.spring(duration: 0.4, bounce: 0.18), value: model.kpis)
            .animation(.smooth(duration: 0.45), value: model.revenueSeries.count)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.lg)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.pageVeil.ignoresSafeArea(edges: .top))
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                refreshChip
            }
        }
        .refreshable { await model.load(using: auth.client) }
        .task { await model.load(using: auth.client) }
        .onAppear {
            // Tab-switch / NavigationStack pop reattaches the view but
            // doesn't re-fire .task. Reload if the data is older than
            // 30 s so coming back to the Dashboard always shows fresh
            // numbers without forcing a manual pull-to-refresh.
            let stale = model.lastRefresh.map { Date().timeIntervalSince($0) > 30 } ?? true
            if stale {
                Task { await model.load(using: auth.client) }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await model.load(using: auth.client) }
            }
        }
        .alert("Fehler", isPresented: .constant(model.error != nil)) {
            Button("OK") { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
    }

    @ViewBuilder
    private var refreshChip: some View {
        if model.isLoading {
            ProgressView().controlSize(.small)
        } else if let refreshed = model.lastRefresh {
            Text(refreshed, style: .relative)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
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

    /// 4 KPIs in a 2-column grid. Colors are *semantic* (success / warning /
    /// danger / info) rather than one hue per card — see Theme.swift.
    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: Spacing.md)], spacing: Spacing.md) {
            StatCard(title: "Bestellungen",
                     systemImage: "cart.fill",
                     tint: Theme.success,
                     delta: model.kpis.orderCount) {
                Text("\(Int(model.kpis.orderCount.current))")
                    .contentTransition(.numericText(value: model.kpis.orderCount.current))
            }
            StatCard(title: "Ø Warenkorb",
                     systemImage: "basket.fill",
                     tint: Theme.info,
                     delta: model.kpis.averageOrderValue) {
                Text(model.kpis.averageOrderValue.current, format: .currency(code: code))
                    .contentTransition(.numericText(value: model.kpis.averageOrderValue.current))
            }
            StatCard(title: "Neue Kunden",
                     systemImage: "person.badge.plus",
                     tint: Theme.info,
                     delta: model.kpis.newCustomers) {
                Text("\(Int(model.kpis.newCustomers.current))")
                    .contentTransition(.numericText(value: model.kpis.newCustomers.current))
            }
            StatCard(title: "Stornoquote",
                     systemImage: "xmark.circle.fill",
                     tint: model.kpis.cancelRate > 0.05 ? Theme.danger : Theme.slate) {
                Text(model.kpis.cancelRate, format: .percent.precision(.fractionLength(0...1)))
                    .contentTransition(.numericText(value: model.kpis.cancelRate))
            }
            StatCard(title: "Offene Angebote",
                     systemImage: "doc.text",
                     tint: Theme.slate) {
                Text("\(model.kpis.openQuotes)")
                    .contentTransition(.numericText(value: Double(model.kpis.openQuotes)))
            }
            StatCard(title: "Offene Lieferungen",
                     systemImage: "shippingbox.fill",
                     tint: Theme.warning) {
                if let value = model.kpis.pendingDeliveries {
                    Text("\(value)")
                        .contentTransition(.numericText(value: Double(value)))
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            StatCard(title: "Reorder fällig",
                     systemImage: "exclamationmark.triangle.fill",
                     tint: Theme.warning) {
                if let value = model.kpis.lowStockCount {
                    Text("\(value)")
                        .contentTransition(.numericText(value: Double(value)))
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            StatCard(title: "Offene Forderungen",
                     systemImage: "creditcard.fill",
                     tint: model.kpis.outstandingReceivable > 0 ? Theme.danger : Theme.slate) {
                Text(model.kpis.outstandingReceivable, format: .currency(code: code))
                    .contentTransition(.numericText(value: model.kpis.outstandingReceivable))
            }
        }
    }

    @ViewBuilder
    private func adaptivePair<A: View, B: View>(_ first: A, _ second: B) -> some View {
        if hSize == .regular {
            HStack(alignment: .top, spacing: Spacing.lg) {
                first.frame(maxWidth: .infinity)
                second.frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: Spacing.lg) {
                first
                second
            }
        }
    }
}
