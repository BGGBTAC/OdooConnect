import Foundation
import Observation
import SwiftUI

/// Single source of truth for cross-tab navigation.
///
/// iOS 26 IA: five top-level tabs (Start · Posteingang · Verkauf · Lager ·
/// Produkte). The Verkauf and Lager tabs are *hubs* that segment over the
/// underlying lists, so we keep one `NavigationPath` per underlying
/// destination (push state survives tab + segment switches) plus a segment
/// selector per hub. Deep-link helpers jump to the right tab, select the
/// right segment, and push the destination in one call.
@MainActor
@Observable
final class AppRouter {
    enum Tab: Hashable {
        case start
        case inbox
        case sales
        case warehouse
        case products
    }

    /// Sub-section of the Verkauf hub.
    enum SalesSegment: Hashable, CaseIterable {
        case quotes, orders, invoices
    }

    /// Sub-section of the Lager hub.
    enum WarehouseSegment: Hashable, CaseIterable {
        case shipping, inventory
    }

    enum OrderRoute: Hashable {
        case detail(Int)
    }

    enum ProductRoute: Hashable {
        case detail(Int)
    }

    enum ShippingRoute: Hashable {
        case detail(Int)
    }

    var selectedTab: Tab = .start
    var salesSegment: SalesSegment = .quotes
    var warehouseSegment: WarehouseSegment = .shipping

    var quotesPath = NavigationPath()
    var ordersPath = NavigationPath()
    var invoicesPath = NavigationPath()
    var productsPath = NavigationPath()
    var shippingPath = NavigationPath()
    var inventoryPath = NavigationPath()

    func openInbox() {
        selectedTab = .inbox
    }

    func openOrder(id: Int) {
        selectedTab = .sales
        salesSegment = .orders
        ordersPath = NavigationPath()
        ordersPath.append(OrderRoute.detail(id))
    }

    func openProduct(id: Int) {
        selectedTab = .products
        productsPath = NavigationPath()
        productsPath.append(ProductRoute.detail(id))
    }

    func openShipment(id: Int) {
        selectedTab = .warehouse
        warehouseSegment = .shipping
        shippingPath = NavigationPath()
        shippingPath.append(ShippingRoute.detail(id))
    }
}
