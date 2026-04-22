import Foundation

/// Minimal JSON value type used to build JSON-RPC request bodies and decode
/// heterogeneous responses (Odoo returns many-to-one fields as `[id, name]` tuples).
enum JSON: Sendable, Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSON].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSON].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    var intValue: Int? {
        if case .int(let v) = self { return v }
        if case .double(let v) = self { return Int(v) }
        return nil
    }

    var doubleValue: Double? {
        if case .double(let v) = self { return v }
        if case .int(let v) = self { return Double(v) }
        return nil
    }

    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }
}

/// Odoo encodes many2one fields as `[id, display_name]` or `false` when empty.
struct Many2One: Decodable, Sendable, Hashable {
    let id: Int
    let name: String

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self), b == false {
            self.id = 0
            self.name = ""
            return
        }
        let tuple = try c.decode([JSON].self)
        guard tuple.count == 2, let id = tuple[0].intValue, let name = tuple[1].stringValue else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Not a many2one pair")
        }
        self.id = id
        self.name = name
    }

    var isEmpty: Bool { id == 0 }
}

/// Many fields come back as `false` instead of an empty string when empty.
@propertyWrapper
struct OdooOptionalString: Decodable, Sendable, Hashable {
    var wrappedValue: String?

    init(wrappedValue: String?) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self), b == false {
            self.wrappedValue = nil
        } else {
            self.wrappedValue = try? c.decode(String.self)
        }
    }
}
