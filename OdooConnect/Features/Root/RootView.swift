import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        switch auth.state {
        case .signedOut, .signingIn:
            LoginView()
        case .signedIn:
            MainTabs()
        }
    }
}

/// Applies `.sidebarAdaptable` only when the size class is regular
/// (i.e. iPad). On iPhone the TabView keeps its default compact style.
private struct AdaptiveTabStyle: ViewModifier {
    let useSidebar: Bool
    func body(content: Content) -> some View {
        if useSidebar {
            content.tabViewStyle(.sidebarAdaptable)
        } else {
            content
        }
    }
}

private struct MainTabs: View {
    @Environment(AppRouter.self) private var routerEnv
    @Environment(OrderWatcher.self) private var orderWatcher
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        @Bindable var router = routerEnv
        TabView(selection: $router.selectedTab) {
            Tab("Dashboard", systemImage: "chart.bar.fill", value: AppRouter.Tab.dashboard) {
                NavigationStack { DashboardView() }
            }
            Tab("Angebote", systemImage: "doc.text", value: AppRouter.Tab.quotes) {
                NavigationStack(path: $router.quotesPath) { QuotesListView() }
            }
            Tab("Bestellungen", systemImage: "cart", value: AppRouter.Tab.orders) {
                NavigationStack(path: $router.ordersPath) { OrdersListView() }
            }
            Tab("Rechnungen", systemImage: "doc.plaintext", value: AppRouter.Tab.invoices) {
                NavigationStack(path: $router.invoicesPath) { InvoicesListView() }
            }
            Tab("Produkte", systemImage: "shippingbox.fill", value: AppRouter.Tab.products) {
                NavigationStack(path: $router.productsPath) { ProductsListView() }
            }
            Tab("Versand", systemImage: "truck.box.fill", value: AppRouter.Tab.shipping) {
                NavigationStack(path: $router.shippingPath) { ShippingListView() }
            }
            Tab("Inventur", systemImage: "barcode.viewfinder", value: AppRouter.Tab.inventory) {
                NavigationStack(path: $router.inventoryPath) { InventoryView() }
            }
            Tab("Einstellungen", systemImage: "gearshape", value: AppRouter.Tab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        // Sidebar only on iPad (regular size class). On iPhone the
        // .sidebarAdaptable style renders the iOS 26 Liquid Glass tab
        // bar in its expanded "icon + label per tab" form, which with
        // 8 tabs blows up to dominate the screen.
        .modifier(AdaptiveTabStyle(useSidebar: hSize == .regular))
        // iOS 26: collapse the bar to a hairline when the user
        // scrolls a list/grid downwards, expand back on scroll-up.
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Theme.brand)
        .onChange(of: router.selectedTab) { _, tab in
            if tab == .orders { orderWatcher.clearUnread() }
        }
    }
}
