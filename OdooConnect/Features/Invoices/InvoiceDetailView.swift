import SwiftUI

struct InvoiceDetailView: View {
    @Environment(AuthManager.self) private var auth
    let invoiceId: Int

    @State private var invoice: Invoice?
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        List {
            if let invoice {
                Section {
                    LabeledContent("Nummer", value: invoice.name)
                    LabeledContent("Kunde", value: invoice.partner_id.name)
                    if let date = invoice.invoice_date {
                        LabeledContent("Datum", value: date.formatted(date: .abbreviated, time: .omitted))
                    }
                    LabeledContent("Status", value: invoice.stateLabel)
                    LabeledContent("Zahlung", value: invoice.paymentLabel)
                }
                Section("Beträge") {
                    HStack {
                        Text("Gesamt").font(.headline)
                        Spacer()
                        Text(invoice.amount_total, format: .currency(code: invoice.currency_id.name))
                            .font(.headline.monospacedDigit())
                    }
                    HStack {
                        Text("Offen")
                        Spacer()
                        Text(invoice.amount_residual, format: .currency(code: invoice.currency_id.name))
                            .monospacedDigit()
                            .foregroundStyle(invoice.amount_residual > 0 ? .red : .green)
                    }
                }
            }
        }
        .navigationTitle(invoice?.name ?? "Rechnung")
        .task { await load() }
        .overlay { if isLoading && invoice == nil { ProgressView() } }
    }

    private func load() async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let invoices: [Invoice] = try await client.searchRead(
                model: "account.move",
                domain: [.array([.string("id"), .string("="), .int(invoiceId)])],
                fields: Invoice.fields,
                limit: 1
            )
            self.invoice = invoices.first
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
