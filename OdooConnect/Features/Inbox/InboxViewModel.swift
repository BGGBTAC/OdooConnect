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

    /// Domain for "incoming customer messages". Odoo tags every *received*
    /// email as `message_type = 'email'` ("Incoming Email"), while everything
    /// the company *sends* — invoice mails, order confirmations, the
    /// "Rechnungsentwurf" notifications — is `'email_outgoing'`, and internal
    /// chatter notes are `'comment'`. Filtering to `'email'` alone therefore
    /// surfaces genuine inbound customer replies across *every* record,
    /// regardless of whether you follow it (no `needaction`/follower scoping),
    /// and drops the outgoing-invoice noise. We deliberately don't gate on
    /// `author_id.partner_share` — a gateway email whose sender Odoo couldn't
    /// resolve to a partner has an empty author and would be lost.
    private var customerDomain: [JSON] {
        // Incoming customer messages only. Diagnosis showed the noise ("Kasse
        // Brugg / Rechnungsentwurf") and genuine replies are *both*
        // message_type='email' with the Discussions subtype, so type alone
        // can't separate them — we filter by author instead:
        //   • partner_share = true   → drops internal users (the company side)
        //   • customer_rank > 0      → keeps only partners who are real
        //                              customers, dropping the POS/till partner
        // 'email' (Incoming Email) also excludes the 'email_outgoing' batch.
        [
            .array([.string("message_type"), .string("="), .string("email")]),
            .array([.string("author_id.partner_share"), .string("="), .bool(true)]),
            .array([.string("author_id.customer_rank"), .string(">"), .int(0)])
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

    /// The full conversation for one record (model + res_id), oldest first —
    /// the read-only thread behind a tapped inbox row. Here we keep *both*
    /// directions plus comments (`email`, `email_outgoing`, `comment`) so the
    /// thread reads as the real back-and-forth: what the customer sent, what we
    /// replied, and any notes — not just the inbound side.
    func thread(model: String, resId: Int, using client: OdooClient?) async -> [InboxMessage] {
        guard let client, !model.isEmpty, resId > 0 else { return [] }
        let dtos: [MailMessageDTO] = (try? await client.searchRead(
            model: "mail.message",
            domain: [
                .array([.string("model"), .string("="), .string(model)]),
                .array([.string("res_id"), .string("="), .int(resId)]),
                .array([.string("message_type"), .string("in"), .array([.string("email"), .string("email_outgoing"), .string("comment")])])
            ],
            fields: MailMessageDTO.fields,
            limit: 100,
            order: "date asc"
        )) ?? []
        return dtos.map(InboxMessage.init)
    }
}
