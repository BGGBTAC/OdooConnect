import Testing
@testable import OdooConnect

@Suite struct PricingPayloadTests {
    private func line(
        overridden: Bool,
        price: Double = 9.99,
        discount: Double = 0,
        taxIds: [Int] = []
    ) -> LineSnapshot {
        LineSnapshot(
            productId: 7,
            quantity: 2,
            priceUnit: price,
            discount: discount,
            taxIds: taxIds,
            priceOverridden: overridden
        )
    }

    /// Extracts the line-values dict from a `(0, 0, {...})` command.
    private func dict(_ json: JSON) -> [String: JSON]? {
        guard let arr = json.arrayValue, arr.count == 3 else { return nil }
        return arr[2].objectValue
    }

    @Test func priceUnitOmittedWhenNotOverridden() {
        let d = dict(OutboxProcessor.makeLineValues(line(overridden: false)))
        #expect(d?["price_unit"] == nil)
        #expect(d?["product_id"] == .int(7))
        #expect(d?["product_uom_qty"] == .double(2))
    }

    @Test func priceUnitSentWhenOverridden() {
        let d = dict(OutboxProcessor.makeLineValues(line(overridden: true, price: 42.5)))
        #expect(d?["price_unit"] == .double(42.5))
    }

    @Test func discountOmittedWhenZeroSentWhenPositive() {
        #expect(dict(OutboxProcessor.makeLineValues(line(overridden: false, discount: 0)))?["discount"] == nil)
        #expect(dict(OutboxProcessor.makeLineValues(line(overridden: false, discount: 10)))?["discount"] == .double(10))
    }

    @Test func taxCommandShapeWhenSet() {
        let d = dict(OutboxProcessor.makeLineValues(line(overridden: false, taxIds: [1, 2])))
        #expect(d?["tax_id"] == .array([.array([.int(6), .int(0), .array([.int(1), .int(2)])])]))
    }

    @Test func taxOmittedWhenEmpty() {
        let d = dict(OutboxProcessor.makeLineValues(line(overridden: false, taxIds: [])))
        #expect(d?["tax_id"] == nil)
    }
}
