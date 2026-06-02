import Foundation
import SwiftData

/// Background actor that owns its own `ModelContext` and pushes locally
/// stored draft quotes to Odoo via an `OdooClient`. Runs off the main actor
/// so it never blocks the UI.
///
/// Concurrency notes:
/// - `process(client:)` is re-entry-guarded by `isProcessing`.
/// - SwiftData models are not Sendable across awaits; mutations after a
///   network suspension re-fetch the model via `PersistentIdentifier`.
/// - The remote `client_order_ref` carries the local draft UUID so that a
///   retry after a partial failure (server created the order, response was
///   lost) finds the existing record instead of creating a duplicate.
@ModelActor
actor OutboxProcessor {
    private var isProcessing = false

    func process(client: any OdooReadWriting) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        let pending = DraftStatus.pending.rawValue
        let sending = DraftStatus.sending.rawValue
        let failed = DraftStatus.failed.rawValue
        let max = DraftQuote.maxAttempts
        let descriptor = FetchDescriptor<DraftQuote>(
            predicate: #Predicate { draft in
                draft.statusRaw == pending ||
                draft.statusRaw == sending ||
                (draft.statusRaw == failed && draft.attempts < max)
            },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        guard let drafts = try? modelContext.fetch(descriptor) else { return }
        let ids = drafts.map(\.persistentModelID)
        for id in ids {
            await pushById(id, using: client)
        }
    }

    private func pushById(_ id: PersistentIdentifier, using client: any OdooReadWriting) async {
        guard let draft = modelContext.model(for: id) as? DraftQuote else { return }
        draft.statusRaw = DraftStatus.sending.rawValue
        let snapshot = DraftSnapshot(draft: draft)
        try? modelContext.save()

        do {
            _ = try await pushOrFindExisting(snapshot, using: client)
            // Re-fetch — the user may have deleted the draft mid-flight.
            if let after = modelContext.model(for: id) as? DraftQuote {
                modelContext.delete(after)
                try modelContext.save()
            }
        } catch {
            if let after = modelContext.model(for: id) as? DraftQuote {
                after.attempts += 1
                after.statusRaw = DraftStatus.failed.rawValue
                after.lastError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                try? modelContext.save()
            }
        }
    }

    private func pushOrFindExisting(_ snap: DraftSnapshot, using client: any OdooReadWriting) async throws -> Int {
        let ref = snap.id.uuidString
        let existing: [ExistingOrderDTO] = try await client.searchRead(
            model: "sale.order",
            domain: [.array([.string("client_order_ref"), .string("="), .string(ref)])],
            fields: ["id"],
            limit: 1,
            offset: 0,
            order: nil,
            as: ExistingOrderDTO.self
        )
        if let found = existing.first {
            return found.id
        }

        let lines: [JSON] = snap.lines.map { Self.makeLineValues($0) }
        var values: [String: JSON] = [
            "partner_id": .int(snap.partnerId),
            "order_line": .array(lines),
            "client_order_ref": .string(ref)
        ]
        if snap.currencyId > 0 {
            values["currency_id"] = .int(snap.currencyId)
        }
        if let carrierId = snap.carrierId, carrierId > 0 {
            values["carrier_id"] = .int(carrierId)
        }
        return try await client.create(model: "sale.order", values: values)
    }

    /// Builds one `(0, 0, {...})` create command for a sale.order.line. Pure +
    /// `internal` so the payload shape can be unit-tested. `price_unit` is sent
    /// ONLY when the rep manually overrode it; otherwise it is omitted so Odoo
    /// computes the price from the partner pricelist (price_unit is a
    /// precompute=True stored-computed field on sale.order.line).
    static func makeLineValues(_ line: LineSnapshot) -> JSON {
        var lineValues: [String: JSON] = [
            "product_id": .int(line.productId),
            "product_uom_qty": .double(line.quantity)
        ]
        if line.priceOverridden {
            lineValues["price_unit"] = .double(line.priceUnit)
        }
        if line.discount > 0 {
            lineValues["discount"] = .double(line.discount)
        }
        // Empty taxIds -> let Odoo apply onchange defaults. Non-empty ->
        // override with an explicit (6, 0, [ids]) many2many command.
        if !line.taxIds.isEmpty {
            lineValues["tax_id"] = .array([
                .array([.int(6), .int(0), .array(line.taxIds.map { .int($0) })])
            ])
        }
        return .array([.int(0), .int(0), .object(lineValues)])
    }
}

private struct DraftSnapshot: Sendable {
    let id: UUID
    let partnerId: Int
    let currencyId: Int
    let carrierId: Int?
    let lines: [LineSnapshot]

    init(draft: DraftQuote) {
        self.id = draft.id
        self.partnerId = draft.partnerId
        self.currencyId = draft.currencyId
        self.carrierId = draft.carrierId
        self.lines = draft.lines.map {
            LineSnapshot(
                productId: $0.productId,
                quantity: $0.quantity,
                priceUnit: $0.priceUnit,
                discount: $0.discount,
                taxIds: $0.taxIds,
                priceOverridden: $0.priceOverridden
            )
        }
    }
}

struct LineSnapshot: Sendable {
    let productId: Int
    let quantity: Double
    let priceUnit: Double
    let discount: Double
    let taxIds: [Int]
    let priceOverridden: Bool
}

private struct ExistingOrderDTO: Decodable, Sendable {
    let id: Int
}
