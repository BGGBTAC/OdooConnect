import Testing
import Foundation
@testable import OdooConnect

@Suite struct OdooDecodingTests {

    // MARK: Many2One

    @Test func many2oneFalseDecodesEmpty() throws {
        let v = try JSONDecoder.odoo.decode(Many2One.self, from: Data("false".utf8))
        #expect(v.isEmpty)
        #expect(v.id == 0)
        #expect(v.name == "")
    }

    @Test func many2onePairDecodes() throws {
        let v = try JSONDecoder.odoo.decode(Many2One.self, from: Data("[7,\"Acme\"]".utf8))
        #expect(v.id == 7)
        #expect(v.name == "Acme")
        #expect(!v.isEmpty)
    }

    @Test func many2oneEmptyArrayThrows() {
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder.odoo.decode(Many2One.self, from: Data("[]".utf8))
        }
    }

    // MARK: OdooOptionalString

    private struct Holder: Decodable {
        @OdooOptionalString var s: String?
    }

    @Test func optionalStringFalseIsNil() throws {
        let h = try JSONDecoder.odoo.decode(Holder.self, from: Data("{\"s\":false}".utf8))
        #expect(h.s == nil)
    }

    @Test func optionalStringValueDecodes() throws {
        let h = try JSONDecoder.odoo.decode(Holder.self, from: Data("{\"s\":\"hi\"}".utf8))
        #expect(h.s == "hi")
    }

    // MARK: Date strategy

    private struct DateHolder: Decodable {
        let d: Date
    }

    @Test(arguments: [
        ("2026-06-01 14:30:00", true),   // datetime form
        ("2026-06-01", true),            // date-only form
        ("not-a-date", false),           // garbage -> throws
    ])
    func dateDecoding(_ input: String, _ shouldDecode: Bool) {
        let data = Data("{\"d\":\"\(input)\"}".utf8)
        let decoded = try? JSONDecoder.odoo.decode(DateHolder.self, from: data)
        #expect((decoded != nil) == shouldDecode)
    }

    // MARK: JSON value precedence

    @Test func jsonValuePrecedence() throws {
        let arr = try JSONDecoder().decode([JSON].self, from: Data("[5, false, 1.5, \"x\"]".utf8))
        #expect(arr[0] == .int(5))
        #expect(arr[1] == .bool(false))
        #expect(arr[2] == .double(1.5))
        #expect(arr[3] == .string("x"))
    }
}
