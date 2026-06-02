import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(StorageHealth.self) private var storageHealth

    var body: some View {
        Group {
            switch auth.state {
            case .signedOut, .signingIn:
                LoginView()
            case .signedIn:
                MainTabs()
            }
        }
        .safeAreaInset(edge: .top) {
            if storageHealth.isDegraded {
                StorageDegradedBanner(reason: storageHealth.degradedReason)
            }
        }
    }
}

/// Persistent warning shown when the app fell back to volatile storage.
private struct StorageDegradedBanner: View {
    let reason: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive.badge.exclamationmark")
            Text(reason ?? "Lokaler Speicher nicht verfügbar.")
                .font(.footnote)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
        .background(.red)
        .accessibilityElement(children: .combine)
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
        // iOS 26 IA: five top-level destinations for the floating Liquid
        // Glass tab bar (HIG: 3–5). Verkauf + Lager are segmented hubs over
        // the underlying lists; Settings moved off the bar into the Start
        // toolbar; search lives minimized inside each list.
        TabView(selection: $router.selectedTab) {
            Tab("Start", systemImage: "house.fill", value: AppRouter.Tab.start) {
                NavigationStack { DashboardView() }
            }
            Tab("Posteingang", systemImage: "tray.full.fill", value: AppRouter.Tab.inbox) {
                InboxView()
            }
            .badge(orderWatcher.messageUnread)
            Tab("Verkauf", systemImage: "cart.fill", value: AppRouter.Tab.sales) {
                SalesHubView()
            }
            Tab("Lager", systemImage: "archivebox.fill", value: AppRouter.Tab.warehouse) {
                WarehouseHubView()
            }
            Tab("Produkte", systemImage: "shippingbox.fill", value: AppRouter.Tab.products) {
                NavigationStack(path: $router.productsPath) { ProductsListView() }
            }
        }
        // Sidebar on iPad (regular size class); floating glass tab bar on iPhone.
        .modifier(AdaptiveTabStyle(useSidebar: hSize == .regular))
        // iOS 26: collapse the bar to a hairline when the user scrolls a
        // list/grid downwards, expand back on scroll-up.
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Theme.brand)
        .onChange(of: router.selectedTab) { _, tab in
            if tab == .sales { orderWatcher.clearUnread() }
            if tab == .inbox { orderWatcher.clearMessageUnread() }
        }
    }
}
