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

private struct MainTabs: View {
    @Environment(AppRouter.self) private var routerEnv

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
            Tab("Einstellungen", systemImage: "gearshape", value: AppRouter.Tab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}
