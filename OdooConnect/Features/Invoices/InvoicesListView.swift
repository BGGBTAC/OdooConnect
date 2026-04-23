import SwiftUI

struct InvoicesListView: View {
    @Environment(AuthManager.self) private var auth
    @State private var invoices: [Invoice] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var searchText = ""

    var body: some View {
        List(invoices) { invoice in
            NavigationLink(value: invoice) {
                InvoiceRow(invoice: invoice)
            }
        }
        .navigationTitle("Rechnungen")
        .searchable(text: $searchText, prompt: "Kunde oder Nummer")
        .navigationDestination(for: Invoice.self) { InvoiceDetailView(invoiceId: $0.id) }
        .refreshable { await load() }
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await load()
        }
        .overlay {
            if invoices.isEmpty && !isLoading {
                BrandedEmptyState(
                    title: searchText.isEmpty ? "Noch keine Rechnungen" : "Keine Treffer",
                    systemImage: "doc.plaintext",
                    message: searchText.isEmpty ? nil : "Versuche einen anderen Suchbegriff."
                )
            }
        }
    }

    private func load() async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var domain: [JSON] = [
                .array([.string("move_type"), .string("="), .string("out_invoice")])
            ]
            let needle = searchText.trimmingCharacters(in: .whitespaces)
            if !needle.isEmpty {
                domain.append(.string("|"))
                domain.append(.array([.string("name"), .string("ilike"), .string(needle)]))
                domain.append(.array([.string("partner_id.name"), .string("ilike"), .string(needle)]))
            }
            invoices = try await client.searchRead(
                model: "account.move",
                domain: domain,
                fields: Invoice.fields,
                limit: 200,
                order: "invoice_date desc, id desc"
            )
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct InvoiceRow: View {
    let invoice: Invoice

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(invoice.name).font(.headline)
                Text(invoice.partner_id.name).font(.subheadline).foregroundStyle(.secondary)
                if let date = invoice.invoice_date {
                    Text(date, style: .date).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(invoice.amount_total, format: .currency(code: invoice.currency_id.name))
                    .font(.headline.monospacedDigit())
                Text(invoice.paymentLabel)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(paymentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(paymentColor)
            }
        }
    }

    private var paymentColor: Color {
        switch invoice.payment_state {
        case "paid": return .green
        case "partial", "in_payment": return .orange
        case "not_paid": return .red
        default: return .secondary
        }
    }
}
