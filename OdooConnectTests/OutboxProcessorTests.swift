import Testing
import SwiftData
import Foundation
@testable import OdooConnect

@Suite struct OutboxProcessorTests {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let cfg = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: DraftQuote.self, DraftLine.self, configurations: cfg)
    }

    @MainActor
    @discardableResult
    private func insertDraft(
        _ container: ModelContainer,
        attempts: Int = 0,
        status: DraftStatus = .pending
    ) throws -> UUID {
        let ctx = container.mainContext
        let draft = DraftQuote(partnerId: 1, partnerName: "Acme", currencyId: 1, currencyCode: "EUR")
        draft.attempts = attempts
        draft.status = status
        if status == .failed { draft.lastError = "boom" }
        draft.lines.append(DraftLine(productId: 7, productName: "Widget", quantity: 2, priceUnit: 9.99))
        ctx.insert(draft)
        try ctx.save()
        return draft.id
    }

    @MainActor
    private func allDrafts(_ container: ModelContainer) throws -> [DraftQuote] {
        try container.mainContext.fetch(FetchDescriptor<DraftQuote>())
    }

    @Test func existingOrderFound_doesNotCreate_andDeletesDraft() async throws {
        let container = try await makeContainer()
        try await insertDraft(container)
        let fake = FakeOdooClient()
        fake.searchReadJSON = { _ in [.object(["id": .int(99)])] }   // idempotency hit

        let proc = OutboxProcessor(modelContainer: container)
        await proc.process(client: fake)

        #expect(fake.count(model: "sale.order", method: "create") == 0)
        #expect(try await allDrafts(container).isEmpty)
    }

    @Test func noExisting_createsOnce_andDeletesDraft() async throws {
        let container = try await makeContainer()
        try await insertDraft(container)
        let fake = FakeOdooClient()
        fake.searchReadJSON = { _ in [] }            // idempotency miss
        fake.createResult = { _, _ in 1234 }

        let proc = OutboxProcessor(modelContainer: container)
        await proc.process(client: fake)

        #expect(fake.count(model: "sale.order", method: "create") == 1)
        #expect(try await allDrafts(container).isEmpty)
    }

    @Test func createThrows_incrementsAttempts_andMarksFailed() async throws {
        let container = try await makeContainer()
        let id = try await insertDraft(container)
        let fake = FakeOdooClient()
        fake.searchReadJSON = { _ in [] }
        fake.createResult = { _, _ in throw OdooError.httpStatus(500) }

        let proc = OutboxProcessor(modelContainer: container)
        await proc.process(client: fake)

        let drafts = try await allDrafts(container)
        let draft = try #require(drafts.first { $0.id == id })
        #expect(draft.attempts == 1)
        #expect(draft.status == .failed)
        #expect(draft.lastError != nil)
    }

    @Test func deadLetteredDraft_isSkippedEntirely() async throws {
        let container = try await makeContainer()
        try await insertDraft(container, attempts: DraftQuote.maxAttempts, status: .failed)
        let fake = FakeOdooClient()

        let proc = OutboxProcessor(modelContainer: container)
        await proc.process(client: fake)

        // The fetch predicate excludes attempts >= maxAttempts, so the
        // processor never even searches for it.
        #expect(fake.calls.isEmpty)
        #expect(try await allDrafts(container).count == 1)
    }
}
