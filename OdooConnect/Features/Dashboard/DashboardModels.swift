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

/// One slice of the invoice pipeline — confirmed sale.orders grouped by
/// their `invoice_status`. We deliberately *don't* surface raw order
/// states because Odoo writes a `draft` order for every shopping cart,
/// which makes the funnel meaningless on a busy shop.
struct InvoicePipelineBucket: Identifiable, Sendable, Equatable {
    let status: String
    let count: Int
    let total: Double
    var id: String { status }

    var label: String {
        switch status {
        case "to invoice":  return "Zu fakturieren"
        case "invoiced":    return "Fakturiert"
        case "no":          return "Keine Rechnung"
        case "upselling":   return "Nachverkauf"
        default:            return status.capitalized
        }
    }
}

struct LowStockRow: Identifiable, Sendable, Equatable {
    let productId: Int
    let name: String
    /// On-hand quantity in internal locations.
    let onHand: Double
    /// Forecast = onHand + incoming – outgoing reservations.
    let forecast: Double
    /// Configured reorder threshold via stock.warehouse.orderpoint, or `nil`
    /// when the customer has no orderpoint defined for this product.
    let minQty: Double?
    var id: Int { productId }

    /// `true` when the customer has configured a reorder rule that this
    /// product is currently below — these are the most actionable rows.
    var isBelowReorderRule: Bool {
        guard let minQty else { return false }
        return forecast < minQty
    }
}

/// Converts monetary amounts from arbitrary Odoo currencies into the company
/// currency using `res.currency.rate` (rate = foreign units per 1 company
/// unit; the company currency itself has rate 1). companyAmount = amount / rate.
/// A missing or non-positive rate degrades to identity rather than producing
/// a NaN/zero — better to show the raw figure than a wrong one.
struct CurrencyConverter: Sendable, Equatable {
    private let rateByCurrency: [Int: Double]
    let companyCurrencyId: Int

    init(rates: [Int: Double], companyCurrencyId: Int) {
        self.rateByCurrency = rates
        self.companyCurrencyId = companyCurrencyId
    }

    func toCompany(_ amount: Double, currencyId: Int) -> Double {
        if currencyId == companyCurrencyId { return amount }
        guard let rate = rateByCurrency[currencyId], rate > 0 else { return amount }
        return amount / rate
    }
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
