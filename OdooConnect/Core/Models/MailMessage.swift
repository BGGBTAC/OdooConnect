import Foundation

/// One `mail.message` row from Odoo — a chatter entry / inbound email.
/// Decoding is defensive: Odoo returns `false` for empty char/text fields
/// and an empty many2one for a missing author.
struct MailMessageDTO: Decodable, Sendable {
    let id: Int
    let date: Date
    let author_id: Many2One
    let subject: String?
    let emailFrom: String?
    let body: String?           // HTML
    let model: String?
    let resId: Int
    let recordName: String?

    enum CodingKeys: String, CodingKey {
        case id, date, author_id, subject
        case emailFrom = "email_from"
        case body, model
        case resId = "res_id"
        case recordName = "record_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        author_id = try c.decode(Many2One.self, forKey: .author_id)
        subject = Self.optString(c, .subject)
        emailFrom = Self.optString(c, .emailFrom)
        body = Self.optString(c, .body)
        model = Self.optString(c, .model)
        recordName = Self.optString(c, .recordName)
        resId = (try? c.decode(Int.self, forKey: .resId)) ?? 0
    }

    /// Odoo char/text fields come back as `false` when empty.
    private static func optString(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        if let b = try? c.decode(Bool.self, forKey: key), b == false { return nil }
        let value = try? c.decode(String.self, forKey: key)
        return (value?.isEmpty == true) ? nil : value
    }

    static let fields: [String] = [
        "id", "date", "author_id", "subject", "email_from", "body", "model", "res_id", "record_name"
    ]
}

/// Display model for the inbox list + thread. Hashable so it can be a
/// navigation value.
struct InboxMessage: Identifiable, Hashable, Sendable {
    let id: Int
    let authorName: String
    let subject: String
    let preview: String
    let date: Date
    let model: String?
    let resId: Int
    let recordName: String

    init(dto: MailMessageDTO) {
        id = dto.id
        let resolved = dto.author_id.isEmpty ? (dto.emailFrom ?? "") : dto.author_id.name
        authorName = resolved.isEmpty ? "Unbekannt" : resolved
        subject = dto.subject ?? ""
        preview = MailBody.plainText(dto.body)
        date = dto.date
        model = dto.model
        resId = dto.resId
        recordName = dto.recordName ?? ""
    }
}

/// Crude HTML → text for previews and read-only threads. A full renderer
/// (AttributedString(html:)) is heavyweight and main-actor-bound; a snippet
/// just needs the words.
enum MailBody {
    static func plainText(_ html: String?) -> String {
        guard let html, !html.isEmpty else { return "" }
        let stripped = html.replacingOccurrences(
            of: "<[^>]+>", with: " ", options: .regularExpression
        )
        let decoded = stripped
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        return decoded
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
