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
    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "chart.bar.fill") {
                NavigationStack { DashboardView() }
            }
            Tab("Angebote", systemImage: "doc.text") {
                NavigationStack { QuotesListView() }
            }
            Tab("Bestellungen", systemImage: "cart") {
                NavigationStack { OrdersListView() }
            }
            Tab("Rechnungen", systemImage: "doc.plaintext") {
                NavigationStack { InvoicesListView() }
            }
            Tab("Einstellungen", systemImage: "gearshape") {
                NavigationStack { SettingsView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}
