import Foundation
import SwiftData

enum DraftStatus: String, Codable, CaseIterable, Sendable {
    case pending, sending, failed, synced
}

@Model
final class DraftQuote {
    @Attribute(.unique) var id: UUID
    var partnerId: Int
    var partnerName: String
    var currencyId: Int
    var currencyCode: String
    var createdAt: Date
    var statusRaw: String
    var attempts: Int
    var lastError: String?
    var remoteId: Int?
    /// Optional `delivery.carrier` ID. `nil` means "let Odoo keep its default
    /// or leave the order without a carrier"; we only push the field when set.
    var carrierId: Int?
    var carrierName: String?
    @Relationship(deleteRule: .cascade, inverse: \DraftLine.quote)
    var lines: [DraftLine]

    init(
        partnerId: Int,
        partnerName: String,
        currencyId: Int,
        currencyCode: String
    ) {
        self.id = UUID()
        self.partnerId = partnerId
        self.partnerName = partnerName
        self.currencyId = currencyId
        self.currencyCode = currencyCode
        self.createdAt = .now
        self.statusRaw = DraftStatus.pending.rawValue
        self.attempts = 0
        self.lines = []
    }

    var status: DraftStatus {
        get { DraftStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var total: Double {
        lines.reduce(0) { $0 + $1.subtotal }
    }
}

@Model
final class DraftLine {
    var productId: Int
    var productName: String
    var quantity: Double
    var priceUnit: Double
    /// Per-line discount in percent (0…100). 0 = no discount.
    var discount: Double = 0
    /// Optional explicit `account.tax` IDs. Empty means "use Odoo's onchange
    /// defaults" — the field is then omitted from the create call.
    var taxIds: [Int] = []
    /// Cached human label for the chosen taxes ("MwSt 19%, …"), so the editor
    /// can show what's set without re-fetching `account.tax` each time.
    var taxLabel: String = ""
    var quote: DraftQuote?

    init(
        productId: Int,
        productName: String,
        quantity: Double,
        priceUnit: Double,
        discount: Double = 0,
        taxIds: [Int] = [],
        taxLabel: String = ""
    ) {
        self.productId = productId
        self.productName = productName
        self.quantity = quantity
        self.priceUnit = priceUnit
        self.discount = discount
        self.taxIds = taxIds
        self.taxLabel = taxLabel
    }

    /// Net subtotal *after* discount but before taxes — matches what Odoo
    /// stores in `sale.order.line.price_subtotal` for a tax-exclusive line.
    var subtotal: Double {
        quantity * priceUnit * (1 - discount / 100)
    }
}
