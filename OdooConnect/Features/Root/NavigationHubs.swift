import SwiftUI

/// Verkauf hub — a segmented control over the quote / order / invoice lists.
/// Each segment keeps its OWN NavigationStack + path, so push state, deep
/// links and the per-list search/destinations all keep working unchanged.
struct SalesHubView: View {
    @Environment(AppRouter.self) private var routerEnv

    var body: some View {
        @Bindable var router = routerEnv
        VStack(spacing: 0) {
            Picker("Bereich", selection: $router.salesSegment) {
                Text("Angebote").tag(AppRouter.SalesSegment.quotes)
                Text("Bestellungen").tag(AppRouter.SalesSegment.orders)
                Text("Rechnungen").tag(AppRouter.SalesSegment.invoices)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xs)
            .sensoryFeedback(.selection, trigger: router.salesSegment)

            switch router.salesSegment {
            case .quotes:   NavigationStack(path: $router.quotesPath)   { QuotesListView() }
            case .orders:   NavigationStack(path: $router.ordersPath)   { OrdersListView() }
            case .invoices: NavigationStack(path: $router.invoicesPath) { InvoicesListView() }
            }
        }
    }
}

/// Lager hub — a segmented control over the shipping / inventory flows.
struct WarehouseHubView: View {
    @Environment(AppRouter.self) private var routerEnv

    var body: some View {
        @Bindable var router = routerEnv
        VStack(spacing: 0) {
            Picker("Bereich", selection: $router.warehouseSegment) {
                Text("Versand").tag(AppRouter.WarehouseSegment.shipping)
                Text("Inventur").tag(AppRouter.WarehouseSegment.inventory)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xs)
            .sensoryFeedback(.selection, trigger: router.warehouseSegment)

            switch router.warehouseSegment {
            case .shipping:  NavigationStack(path: $router.shippingPath)  { ShippingListView() }
            case .inventory: NavigationStack(path: $router.inventoryPath) { InventoryView() }
            }
        }
    }
}
