import SwiftUI

struct DashboardView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = DashboardViewModel()
    @State private var showSettings = false

    var body: some View {
        ScrollView {
            // GlassEffectContainer lets the sibling glass cards share
            // rendering and blend smoothly when they animate in/out
            // (rather than each computing its own backdrop in isolation).
            GlassEffectContainer(spacing: Spacing.lg) {
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
                    .redacted(reason: isInitialLoading ? .placeholder : [])

                    sectionLabel("Performance")

                    kpiGrid
                        .redacted(reason: isInitialLoading ? .placeholder : [])

                    if !model.revenueSeries.isEmpty {
                        RevenueChartCard(
                            title: revenueTitle,
                            points: model.revenueSeries,
                            currencyCode: code,
                            interval: model.period.seriesInterval
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }

                    sectionLabel("Verkauf & Pipeline")

                    adaptivePair(
                        TopProductsCard(products: model.topProducts, currencyCode: code),
                        OrderFunnelCard(buckets: model.invoicePipeline)
                    )

                    sectionLabel("Bestand & Aktivität")

                    adaptivePair(
                        LowStockCard(rows: model.lowStock) { row in
                            router.openProduct(id: row.productId)
                        },
                        RecentOrdersCard(orders: model.recentOrders, currencyCode: code) { order in
                            router.openOrder(id: order.id)
                        }
                    )
                }
                .animation(.spring(duration: 0.4, bounce: 0.18), value: model.kpis)
                .animation(.smooth(duration: 0.45), value: model.revenueSeries.count)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.lg)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.pageVeil.ignoresSafeArea(edges: .top))
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Einstellungen")
            }
            ToolbarItem(placement: .topBarTrailing) {
                refreshChip
            }
        }
        .refreshable { await model.load(using: auth.client, companyCurrencyId: auth.companyCurrency.id) }
        // Single owner for the initial + period-driven loads: .task(id:)
        // re-fires on period change and SwiftUI cancels the prior body; the
        // view model's in-flight guard coalesces everything else.
        .task(id: model.period) {
            await model.load(using: auth.client, companyCurrencyId: auth.companyCurrency.id)
        }
        .onAppear {
            // Tab-switch / NavigationStack pop reattaches the view but doesn't
            // re-fire .task. `lastRefresh` is nil until the first load lands,
            // so this is a no-op on first appearance (no double-fire with
            // .task) and only refreshes a stale board on re-appearance.
            if !model.isLoading,
               let last = model.lastRefresh,
               Date().timeIntervalSince(last) > 30 {
                Task { await model.load(using: auth.client, companyCurrencyId: auth.companyCurrency.id) }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await model.load(using: auth.client, companyCurrencyId: auth.companyCurrency.id) }
            }
        }
        .errorAlert(error: Bindable(model).error)
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
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

    /// First load only — render card shells as skeletons so the layout
    /// doesn't jump when data lands (vs. a bare spinner over empty cards).
    private var isInitialLoading: Bool {
        model.isLoading && model.lastRefresh == nil
    }

    private var revenueTitle: String {
        switch model.period {
        case .today: return "Umsatzverlauf heute"
        case .last7: return "Umsatz letzte 7 Tage"
        case .mtd:   return "Umsatz im Monat"
        case .ytd:   return "Umsatz laufendes Jahr"
        }
    }

    /// 4 KPIs in a 2-column grid. Colors are *semantic* (success / warning /
    /// danger / info) rather than one hue per card — see Theme.swift.
    private var kpiGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: Spacing.md)],
            spacing: Spacing.md
        ) {
            StatCard(title: "Bestellungen",
                     systemImage: "cart.fill",
                     delta: model.kpis.orderCount) {
                Text("\(Int(model.kpis.orderCount.current))")
                    .contentTransition(.numericText(value: model.kpis.orderCount.current))
            }
            StatCard(title: "Ø Bestellwert",
                     systemImage: "basket.fill",
                     delta: model.kpis.averageOrderValue) {
                Text(model.kpis.averageOrderValue.current, format: .currency(code: code))
                    .contentTransition(.numericText(value: model.kpis.averageOrderValue.current))
            }
            StatCard(title: "Neue Kunden",
                     systemImage: "person.badge.plus",
                     delta: model.kpis.newCustomers) {
                Text("\(Int(model.kpis.newCustomers.current))")
                    .contentTransition(.numericText(value: model.kpis.newCustomers.current))
            }
            StatCard(title: "Stornoquote",
                     systemImage: "xmark.circle.fill",
                     tint: model.kpis.cancelRate > 0.05 ? Theme.danger : nil) {
                Text(model.kpis.cancelRate, format: .percent.precision(.fractionLength(0...1)))
                    .contentTransition(.numericText(value: model.kpis.cancelRate))
            }
            StatCard(title: "Angebote offen",
                     systemImage: "doc.text") {
                Text("\(model.kpis.openQuotes)")
                    .contentTransition(.numericText(value: Double(model.kpis.openQuotes)))
            }
            StatCard(title: "Lieferungen offen",
                     systemImage: "shippingbox.fill") {
                if let value = model.kpis.pendingDeliveries {
                    Text("\(value)")
                        .contentTransition(.numericText(value: Double(value)))
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            StatCard(title: "Reorder fällig",
                     systemImage: "exclamationmark.triangle.fill") {
                if let value = model.kpis.lowStockCount {
                    Text("\(value)")
                        .contentTransition(.numericText(value: Double(value)))
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            StatCard(title: "Forderungen",
                     systemImage: "creditcard.fill",
                     tint: model.kpis.outstandingReceivable > 0 ? Theme.danger : nil) {
                Text(model.kpis.outstandingReceivable, format: .currency(code: code))
                    .contentTransition(.numericText(value: model.kpis.outstandingReceivable))
            }
        }
    }

    /// Thin editorial section divider — subtle rounded uppercase label
    /// with a hairline. Breaks the dashboard into scannable groups
    /// instead of one endless vertical stream of cards.
    private func sectionLabel(_ title: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(title)
                .font(.caption.weight(.bold))
                .kerning(0.5)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(.secondary.opacity(0.2))
                .frame(height: 1)
        }
        .padding(.top, Spacing.xs)
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
