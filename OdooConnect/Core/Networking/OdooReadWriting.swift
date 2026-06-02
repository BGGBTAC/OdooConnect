import Foundation

/// Read/write seam over Odoo JSON-RPC. `OdooClient` is the production
/// conformer; tests inject a fake (see `FakeOdooClient`). Only the instance
/// methods that consumers call are declared here — `authenticate` and
/// `Config` stay on the concrete `OdooClient`.
///
/// Protocol requirements intentionally carry no default arguments (Swift
/// requirements can't). Call sites reached through `any OdooReadWriting`
/// pass every argument explicitly; concrete `OdooClient` call sites keep
/// using the method defaults exactly as before, so this seam is a pure
/// compile-time abstraction with no runtime behaviour change.
protocol OdooReadWriting: Sendable {
    func callKw<Result: Decodable & Sendable>(
        model: String,
        method: String,
        args: [JSON],
        kwargs: [String: JSON],
        as type: Result.Type
    ) async throws -> Result

    func searchRead<T: Decodable & Sendable>(
        model: String,
        domain: [JSON],
        fields: [String],
        limit: Int?,
        offset: Int,
        order: String?,
        as _: T.Type
    ) async throws -> [T]

    func readGroup(
        model: String,
        domain: [JSON],
        fields: [String],
        groupBy: [String]
    ) async throws -> [[String: JSON]]

    func create(model: String, values: [String: JSON]) async throws -> Int

    func write(model: String, ids: [Int], values: [String: JSON]) async throws -> Bool

    func writeWithGuard(
        model: String,
        id: Int,
        values: [String: JSON],
        lastSeenWriteDate: Date
    ) async throws -> Bool
}

// OdooClient already implements every requirement (its methods add default
// arguments, which a witness is allowed to do), so this conformance is empty.
extension OdooClient: OdooReadWriting {}
