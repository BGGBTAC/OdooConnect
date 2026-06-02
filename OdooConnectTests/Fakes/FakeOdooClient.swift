import Foundation
@testable import OdooConnect

/// In-memory test double for `OdooReadWriting`. Records the (model, method)
/// of each call and serves canned results via per-method closures, so units
/// that talk to Odoo can be exercised without a live server or URL stubbing.
final class FakeOdooClient: OdooReadWriting, @unchecked Sendable {
    struct Call: Equatable, Sendable {
        let model: String
        let method: String
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    var calls: [Call] {
        lock.lock(); defer { lock.unlock() }
        return _calls
    }

    // Per-method stubs. Each receives the model so one fake can serve many.
    var searchReadJSON: (@Sendable (_ model: String) throws -> [JSON])?
    var createResult: (@Sendable (_ model: String, _ values: [String: JSON]) throws -> Int)?
    var writeResult: (@Sendable () throws -> Bool)?
    var readGroupRows: (@Sendable (_ model: String) throws -> [[String: JSON]])?
    var callKwJSON: (@Sendable (_ model: String, _ method: String) throws -> JSON)?
    var writeWithGuardResult: (@Sendable () throws -> Bool)?

    private func record(_ model: String, _ method: String) {
        lock.lock()
        _calls.append(Call(model: model, method: method))
        lock.unlock()
    }

    func count(model: String, method: String) -> Int {
        calls.filter { $0.model == model && $0.method == method }.count
    }

    func callKw<Result: Decodable & Sendable>(
        model: String,
        method: String,
        args: [JSON],
        kwargs: [String: JSON],
        as _: Result.Type
    ) async throws -> Result {
        record(model, method)
        let json = try callKwJSON?(model, method) ?? .null
        return try JSONDecoder.odoo.decode(Result.self, from: try json.encoded())
    }

    func searchRead<T: Decodable & Sendable>(
        model: String,
        domain: [JSON],
        fields: [String],
        limit: Int?,
        offset: Int,
        order: String?,
        as _: T.Type
    ) async throws -> [T] {
        record(model, "search_read")
        let rows = try searchReadJSON?(model) ?? []
        return try JSONDecoder.odoo.decode([T].self, from: try JSON.array(rows).encoded())
    }

    func readGroup(
        model: String,
        domain: [JSON],
        fields: [String],
        groupBy: [String]
    ) async throws -> [[String: JSON]] {
        record(model, "read_group")
        return try readGroupRows?(model) ?? []
    }

    func create(model: String, values: [String: JSON]) async throws -> Int {
        record(model, "create")
        guard let createResult else { throw OdooError.unexpectedResponse("no create stub") }
        return try createResult(model, values)
    }

    func write(model: String, ids: [Int], values: [String: JSON]) async throws -> Bool {
        record(model, "write")
        return try writeResult?() ?? true
    }

    func writeWithGuard(
        model: String,
        id: Int,
        values: [String: JSON],
        lastSeenWriteDate: Date
    ) async throws -> Bool {
        record(model, "write_with_guard")
        return try writeWithGuardResult?() ?? true
    }
}
