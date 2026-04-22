import SwiftUI

struct InvoicesListView: View {
    @Environment(AuthManager.self) private var auth
    @State private var invoices: [Invoice] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        List(invoices) { invoice in
            NavigationLink(value: invoice) {
                InvoiceRow(invoice: invoice)
            }
        }
        .navigationTitle("Rechnungen")
        .navigationDestination(for: Invoice.self) { InvoiceDetailView(invoiceId: $0.id) }
        .refreshable { await load() }
        .task { await load() }
        .overlay {
            if invoices.isEmpty && !isLoading {
                ContentUnavailableView("Keine Rechnungen", systemImage: "doc.plaintext")
            }
        }
    }

    private func load() async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            invoices = try await client.searchRead(
                model: "account.move",
                domain: [
                    .array([.string("move_type"), .string("="), .string("out_invoice")])
                ],
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
                Text(invoice.amount_total, format: .currency(code: "EUR"))
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
