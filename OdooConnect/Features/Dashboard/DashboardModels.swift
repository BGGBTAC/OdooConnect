import Foundation

struct RevenuePoint: Identifiable, Sendable, Equatable {
    let bucketStart: Date
    let total: Double
    var id: Date { bucketStart }
}

struct StatDelta: Sendable, Equatable {
    let current: Double
    let previous: Double

    /// Relative change. `nil` when the previous period is zero (division would
    /// be meaningless; UI renders a neutral pill in that case).
    var ratio: Double? {
        guard previous != 0 else { return nil }
        return (current - previous) / previous
    }

    var isPositive: Bool { current >= previous }
}

struct TopProductRow: Identifiable, Sendable, Equatable {
    let productId: Int
    let name: String
    let quantity: Double
    let revenue: Double
    var id: Int { productId }
}

struct OrderStateBucket: Identifiable, Sendable, Equatable {
    let state: String
    let count: Int
    let total: Double
    var id: String { state }

    var label: String {
        switch state {
        case "draft":  return "Entwurf"
        case "sent":   return "Angebot"
        case "sale":   return "Bestellt"
        case "done":   return "Abgeschlossen"
        case "cancel": return "Storniert"
        default:       return state.capitalized
        }
    }
}

struct LowStockRow: Identifiable, Sendable, Equatable {
    let productId: Int
    let name: String
    let quantity: Double
    var id: Int { productId }
}

struct ShopKPIs: Sendable, Equatable {
    var revenue: StatDelta = StatDelta(current: 0, previous: 0)
    var orderCount: StatDelta = StatDelta(current: 0, previous: 0)
    var averageOrderValue: StatDelta = StatDelta(current: 0, previous: 0)
    var newCustomers: StatDelta = StatDelta(current: 0, previous: 0)
    var cancelRate: Double = 0
    var pendingDeliveries: Int?
    var lowStockCount: Int?
    var outstandingReceivable: Double = 0
    var openQuotes: Int = 0
}
