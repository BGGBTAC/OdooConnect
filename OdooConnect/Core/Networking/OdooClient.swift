import Foundation

actor OdooClient {
    struct Config: Sendable, Codable, Equatable {
        var baseURL: URL
        var database: String
        var login: String
    }

    private let config: Config
    private let apiKey: String
    private let uid: Int
    private let session: URLSession

    init(config: Config, apiKey: String, uid: Int, session: URLSession = .shared) {
        self.config = config
        self.apiKey = apiKey
        self.uid = uid
        self.session = session
    }

    static func authenticate(
        baseURL: URL,
        database: String,
        login: String,
        apiKey: String,
        session: URLSession = .shared
    ) async throws -> Int {
        let params: [String: JSON] = [
            "service": .string("common"),
            "method": .string("authenticate"),
            "args": .array([.string(database), .string(login), .string(apiKey), .object([:])])
        ]
        let result = try await Self.rawCall(baseURL: baseURL, params: params, session: session)
        switch result {
        case .int(let uid) where uid > 0:
            return uid
        case .bool(false), .null:
            throw OdooError.invalidCredentials
        default:
            throw OdooError.unexpectedResponse("authenticate returned \(result)")
        }
    }

    func callKw<Result: Decodable & Sendable>(
        model: String,
        method: String,
        args: [JSON] = [],
        kwargs: [String: JSON] = [:],
        as type: Result.Type = Result.self
    ) async throws -> Result {
        let params: [String: JSON] = [
            "service": .string("object"),
            "method": .string("execute_kw"),
            "args": .array([
                .string(config.database),
                .int(uid),
                .string(apiKey),
                .string(model),
                .string(method),
                .array(args),
                .object(kwargs)
            ])
        ]
        let json = try await Self.rawCall(baseURL: config.baseURL, params: params, session: session)
        return try JSONDecoder.odoo.decode(Result.self, from: try json.encoded())
    }

    func searchRead<T: Decodable & Sendable>(
        model: String,
        domain: [JSON] = [],
        fields: [String],
        limit: Int? = nil,
        offset: Int = 0,
        order: String? = nil,
        as _: T.Type = T.self
    ) async throws -> [T] {
        var kwargs: [String: JSON] = [
            "domain": .array(domain),
            "fields": .array(fields.map { .string($0) }),
            "offset": .int(offset)
        ]
        if let limit { kwargs["limit"] = .int(limit) }
        if let order { kwargs["order"] = .string(order) }
        return try await callKw(model: model, method: "search_read", kwargs: kwargs)
    }

    func readGroup(
        model: String,
        domain: [JSON],
        fields: [String],
        groupBy: [String]
    ) async throws -> [[String: JSON]] {
        let kwargs: [String: JSON] = [
            "domain": .array(domain),
            "fields": .array(fields.map { .string($0) }),
            "groupby": .array(groupBy.map { .string($0) }),
            "lazy": .bool(false)
        ]
        return try await callKw(model: model, method: "read_group", kwargs: kwargs)
    }

    func create(model: String, values: [String: JSON]) async throws -> Int {
        try await callKw(model: model, method: "create", args: [.object(values)])
    }

    func write(model: String, ids: [Int], values: [String: JSON]) async throws -> Bool {
        try await callKw(model: model, method: "write", args: [.array(ids.map { .int($0) }), .object(values)])
    }

    /// Optimistic-concurrency write: re-reads `write_date` on the target
    /// record and refuses the write if the server-side timestamp is
    /// newer than `lastSeenWriteDate`. "Server wins" — the caller is
    /// expected to reload and ask the user to redo the edit.
    ///
    /// This narrows but does not eliminate the race between read and
    /// write: a third party could still slip a write in *between* this
    /// guard check and the actual write call. Closing that hole would
    /// need server-side conditional update logic. Worth the trade-off
    /// for now — catches the realistic "two people on different devices"
    /// case without bridge-module changes.
    func writeWithGuard(
        model: String,
        id: Int,
        values: [String: JSON],
        lastSeenWriteDate: Date
    ) async throws -> Bool {
        let snapshot: [WriteDateDTO] = try await searchRead(
            model: model,
            domain: [.array([.string("id"), .string("="), .int(id)])],
            fields: ["write_date"],
            limit: 1
        )
        if let serverDate = snapshot.first?.write_date,
           serverDate > lastSeenWriteDate.addingTimeInterval(0.5) {
            // 0.5 s slack absorbs sub-second precision drift between
            // Odoo's stored timestamp (PostgreSQL `timestamp`) and what
            // the client decoded — Odoo stores microseconds but the
            // JSON-RPC string format only emits whole seconds, so an
            // unchanged record can decode 0–0.999 s "newer" than what
            // we last saw.
            throw OdooError.conflict(model: model, id: id)
        }
        return try await write(model: model, ids: [id], values: values)
    }

    private static func rawCall(
        baseURL: URL,
        params: [String: JSON],
        session: URLSession
    ) async throws -> JSON {
        let endpoint = baseURL.appendingPathComponent("jsonrpc")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: JSON] = [
            "jsonrpc": .string("2.0"),
            "method": .string("call"),
            "params": .object(params),
            "id": .int(Int(UInt32.random(in: 1...UInt32.max)))
        ]
        request.httpBody = try JSON.object(body).encoded()

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OdooError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OdooError.unexpectedResponse("non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OdooError.httpStatus(http.statusCode)
        }

        let envelope = try JSONDecoder.odoo.decode(Envelope.self, from: data)
        if let error = envelope.error {
            throw OdooError.server(code: error.code, message: error.message, data: error.data?.message)
        }
        return envelope.result ?? .null
    }

    private struct Envelope: Decodable {
        let result: JSON?
        let error: RPCError?
        struct RPCError: Decodable {
            let code: Int
            let message: String
            let data: RPCErrorData?
        }
        struct RPCErrorData: Decodable {
            let message: String?
        }
    }
}

private struct WriteDateDTO: Decodable, Sendable {
    let write_date: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let bool = try? c.decode(Bool.self, forKey: .write_date), bool == false {
            self.write_date = nil
        } else {
            self.write_date = try? c.decode(Date.self, forKey: .write_date)
        }
    }

    enum CodingKeys: String, CodingKey { case write_date }
}

extension JSONDecoder {
    static let odoo: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = DateFormatter.odooDateTime.date(from: string) { return date }
            if let date = DateFormatter.odooDate.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(),
                                                   debugDescription: "Unrecognised Odoo date: \(string)")
        }
        return d
    }()
}

extension DateFormatter {
    static let odooDateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
    static let odooDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
