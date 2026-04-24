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
    private static let maxAttempts = 5
    private var isProcessing = false

    func process(client: OdooClient) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        let pending = DraftStatus.pending.rawValue
        let sending = DraftStatus.sending.rawValue
        let failed = DraftStatus.failed.rawValue
        let max = Self.maxAttempts
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

    private func pushById(_ id: PersistentIdentifier, using client: OdooClient) async {
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

    private func pushOrFindExisting(_ snap: DraftSnapshot, using client: OdooClient) async throws -> Int {
        let ref = snap.id.uuidString
        let existing: [ExistingOrderDTO] = try await client.searchRead(
            model: "sale.order",
            domain: [.array([.string("client_order_ref"), .string("="), .string(ref)])],
            fields: ["id"],
            limit: 1
        )
        if let found = existing.first {
            return found.id
        }

        let lines: [JSON] = snap.lines.map { line in
            .array([
                .int(0), .int(0),
                .object([
                    "product_id": .int(line.productId),
                    "product_uom_qty": .double(line.quantity),
                    "price_unit": .double(line.priceUnit)
                ])
            ])
        }
        var values: [String: JSON] = [
            "partner_id": .int(snap.partnerId),
            "order_line": .array(lines),
            "client_order_ref": .string(ref)
        ]
        if snap.currencyId > 0 {
            values["currency_id"] = .int(snap.currencyId)
        }
        return try await client.create(model: "sale.order", values: values)
    }
}

private struct DraftSnapshot: Sendable {
    let id: UUID
    let partnerId: Int
    let currencyId: Int
    let lines: [LineSnapshot]

    init(draft: DraftQuote) {
        self.id = draft.id
        self.partnerId = draft.partnerId
        self.currencyId = draft.currencyId
        self.lines = draft.lines.map {
            LineSnapshot(productId: $0.productId, quantity: $0.quantity, priceUnit: $0.priceUnit)
        }
    }
}

private struct LineSnapshot: Sendable {
    let productId: Int
    let quantity: Double
    let priceUnit: Double
}

private struct ExistingOrderDTO: Decodable, Sendable {
    let id: Int
}
