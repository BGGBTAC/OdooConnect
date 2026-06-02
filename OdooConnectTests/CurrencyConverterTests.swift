import Testing
@testable import OdooConnect

@Suite struct CurrencyConverterTests {
    @Test func companyCurrencyIsIdentity() {
        let c = CurrencyConverter(rates: [2: 1.1], companyCurrencyId: 1)
        #expect(c.toCompany(100, currencyId: 1) == 100)
    }

    @Test func foreignConvertsByDividingRate() {
        // 110 EUR at rate 1.1 (EUR per 1 company unit) == 100 company.
        let c = CurrencyConverter(rates: [2: 1.1], companyCurrencyId: 1)
        #expect(abs(c.toCompany(110, currencyId: 2) - 100) < 1e-9)
    }

    @Test func missingRateFallsBackToIdentity() {
        let c = CurrencyConverter(rates: [:], companyCurrencyId: 1)
        #expect(c.toCompany(100, currencyId: 9) == 100)
    }

    @Test func zeroRateFallsBackToIdentity() {
        let c = CurrencyConverter(rates: [2: 0], companyCurrencyId: 1)
        #expect(c.toCompany(100, currencyId: 2) == 100)
    }
}
