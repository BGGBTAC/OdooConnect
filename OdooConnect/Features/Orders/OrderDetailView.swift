import SwiftUI

struct OrderDetailView: View {
    @Environment(AuthManager.self) private var auth
    let orderId: Int

    @State private var order: SaleOrder?
    @State private var lines: [SaleOrderLine] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var showingSignature = false
    @State private var signatureUploaded = false
    @State private var signatureMessage: String?

    var body: some View {
        List {
            if let order {
                Section {
                    LabeledContent("Nummer", value: order.name)
                    LabeledContent("Kunde", value: order.partner_id.name)
                    LabeledContent("Datum", value: order.date_order.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("Status", value: order.stateLabel)
                }
                Section("Positionen") {
                    ForEach(lines) { line in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(line.product_id.name).font(.headline)
                            HStack {
                                Text("\(line.product_uom_qty, specifier: "%.2f") × \(line.price_unit, format: .currency(code: code))")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Spacer()
                                Text(line.price_subtotal, format: .currency(code: code))
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                Section("Summe") {
                    HStack {
                        Text("Netto").foregroundStyle(.secondary)
                        Spacer()
                        Text(order.amount_untaxed, format: .currency(code: code)).monospacedDigit()
                    }
                    HStack {
                        Text("Gesamt").font(.headline)
                        Spacer()
                        Text(order.amount_total, format: .currency(code: code))
                            .font(.headline.monospacedDigit())
                    }
                }
            }
        }
        .navigationTitle(order?.name ?? "Bestellung")
        .task { await load() }
        .overlay { if isLoading && order == nil { ProgressView() } }
        .toolbar {
            if order != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSignature = true
                    } label: {
                        Label {
                            Text(signatureUploaded ? "Signiert" : "Unterschreiben")
                                .contentTransition(.opacity)
                        } icon: {
                            Image(systemName: signatureUploaded ? "checkmark.seal.fill" : "signature")
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .tint(signatureUploaded ? .green : .accentColor)
                    .animation(.snappy, value: signatureUploaded)
                }
            }
        }
        .sheet(isPresented: $showingSignature) {
            SignatureSheet(title: "Unterschrift") { png in
                await uploadSignature(png)
            }
        }
        .alert("Hinweis", isPresented: .constant(signatureMessage != nil)) {
            Button("OK") { signatureMessage = nil }
        } message: {
            Text(signatureMessage ?? "")
        }
    }

    private var code: String {
        order?.currency_id.name ?? auth.companyCurrency.code
    }

    private func uploadSignature(_ png: Data) async {
        guard let client = auth.client, let order else { return }
        let base64 = png.base64EncodedString()
        do {
            _ = try await client.create(model: "ir.attachment", values: [
                "name": .string("signature_\(order.name).png"),
                "type": .string("binary"),
                "datas": .string(base64),
                "res_model": .string("sale.order"),
                "res_id": .int(order.id),
                "mimetype": .string("image/png")
            ])
            signatureUploaded = true
            signatureMessage = "Unterschrift wurde an die Bestellung angehängt."
        } catch {
            signatureMessage = "Upload fehlgeschlagen: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    private func load() async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let orders: [SaleOrder] = try await client.searchRead(
                model: "sale.order",
                domain: [.array([.string("id"), .string("="), .int(orderId)])],
                fields: SaleOrder.fields,
                limit: 1
            )
            self.order = orders.first
            self.lines = try await client.searchRead(
                model: "sale.order.line",
                domain: [.array([.string("order_id"), .string("="), .int(orderId)])],
                fields: SaleOrderLine.fields,
                limit: 500,
                order: "sequence asc, id asc"
            )
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
