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
    var quote: DraftQuote?

    init(productId: Int, productName: String, quantity: Double, priceUnit: Double) {
        self.productId = productId
        self.productName = productName
        self.quantity = quantity
        self.priceUnit = priceUnit
    }

    var subtotal: Double { quantity * priceUnit }
}
