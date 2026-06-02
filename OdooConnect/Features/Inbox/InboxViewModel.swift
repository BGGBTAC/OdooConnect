import Foundation
import Observation

/// Loads incoming customer messages (mail.message authored by external /
/// portal partners) for the Posteingang, and the full thread for one record.
@Observable
@MainActor
final class InboxViewModel {
    var messages: [InboxMessage] = []
    var isLoading = false
    var error: String?

    /// Domain for "incoming customer messages": chatter emails/comments whose
    /// author is an external (portal-shared) partner — i.e. a customer reply,
    /// not an internal note. (Validate `author_id.partner_share` against the
    /// live tenant; some flows use `email_from` without a resolved partner.)
    private var customerDomain: [JSON] {
        [
            .array([.string("message_type"), .string("in"), .array([.string("email"), .string("comment")])]),
            .array([.string("author_id.partner_share"), .string("="), .bool(true)])
        ]
    }

    func load(using client: OdooClient?) async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let dtos: [MailMessageDTO] = try await client.searchRead(
                model: "mail.message",
                domain: customerDomain,
                fields: MailMessageDTO.fields,
                limit: 80,
                order: "date desc"
            )
            messages = dtos.map(InboxMessage.init)
            error = nil
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// All chatter messages for one record (model + res_id), oldest first —
    /// the read-only thread behind a tapped inbox row.
    func thread(model: String, resId: Int, using client: OdooClient?) async -> [InboxMessage] {
        guard let client, !model.isEmpty, resId > 0 else { return [] }
        let dtos: [MailMessageDTO] = (try? await client.searchRead(
            model: "mail.message",
            domain: [
                .array([.string("model"), .string("="), .string(model)]),
                .array([.string("res_id"), .string("="), .int(resId)]),
                .array([.string("message_type"), .string("in"), .array([.string("email"), .string("comment")])])
            ],
            fields: MailMessageDTO.fields,
            limit: 100,
            order: "date asc"
        )) ?? []
        return dtos.map(InboxMessage.init)
    }
}
