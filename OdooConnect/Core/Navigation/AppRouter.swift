import Foundation
import Observation
import SwiftUI

/// Single source of truth for cross-tab navigation. Each tab keeps its
/// own `NavigationPath` so push state is preserved when the user
/// switches tabs. Deep-link helpers like `openOrder(id:)` jump to the
/// right tab and push the correct destination in one call.
@MainActor
@Observable
final class AppRouter {
    enum Tab: Hashable {
        case dashboard
        case quotes
        case orders
        case invoices
        case settings
    }

    enum OrderRoute: Hashable {
        case detail(Int)
    }

    var selectedTab: Tab = .dashboard
    var quotesPath = NavigationPath()
    var ordersPath = NavigationPath()
    var invoicesPath = NavigationPath()

    func openOrder(id: Int) {
        selectedTab = .orders
        ordersPath = NavigationPath()
        ordersPath.append(OrderRoute.detail(id))
    }
}
