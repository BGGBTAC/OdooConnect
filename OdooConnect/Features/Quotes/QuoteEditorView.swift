import SwiftUI

struct DraftLine: Identifiable, Sendable {
    let id = UUID()
    var product: Product
    var quantity: Double
    var priceUnit: Double

    var subtotal: Double { quantity * priceUnit }
}

struct QuoteEditorView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPartner: Partner?
    @State private var lines: [DraftLine] = []
    @State private var isSaving = false
    @State private var error: String?
    @State private var showingPartnerPicker = false
    @State private var showingProductPicker = false

    var onSaved: (() async -> Void)?

    var total: Double { lines.reduce(0) { $0 + $1.subtotal } }

    var body: some View {
        Form {
            Section("Kunde") {
                Button {
                    showingPartnerPicker = true
                } label: {
                    HStack {
                        Text(selectedPartner?.name ?? "Kunden auswählen")
                            .foregroundStyle(selectedPartner == nil ? .secondary : .primary)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
            }

            Section("Positionen") {
                ForEach($lines) { $line in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(line.product.name).font(.headline)
                        HStack {
                            Stepper(value: $line.quantity, in: 0.01...9999, step: 1) {
                                Text("Menge: \(line.quantity, specifier: "%.2f")")
                            }
                        }
                        HStack {
                            Text("Preis")
                            Spacer()
                            TextField("", value: $line.priceUnit, format: .number)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .frame(maxWidth: 100)
                        }
                        HStack {
                            Text("Zwischensumme").foregroundStyle(.secondary)
                            Spacer()
                            Text(line.subtotal, format: .currency(code: "EUR"))
                                .monospacedDigit()
                        }
                    }
                }
                .onDelete { lines.remove(atOffsets: $0) }

                Button {
                    showingProductPicker = true
                } label: {
                    Label("Produkt hinzufügen", systemImage: "plus.circle")
                }
            }

            Section("Summe") {
                HStack {
                    Text("Gesamt").font(.headline)
                    Spacer()
                    Text(total, format: .currency(code: "EUR"))
                        .font(.title3.bold().monospacedDigit())
                }
            }

            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Neues Angebot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Speichern") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
        }
        .sheet(isPresented: $showingPartnerPicker) {
            PartnerPickerView { partner in
                selectedPartner = partner
                showingPartnerPicker = false
            }
        }
        .sheet(isPresented: $showingProductPicker) {
            ProductPickerView { product in
                lines.append(DraftLine(product: product, quantity: 1, priceUnit: product.list_price))
                showingProductPicker = false
            }
        }
    }

    private var canSave: Bool {
        selectedPartner != nil && !lines.isEmpty && !isSaving
    }

    private func save() async {
        guard let client = auth.client, let partner = selectedPartner else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let linesPayload: [JSON] = lines.map { line in
                .array([
                    .int(0), .int(0),
                    .object([
                        "product_id": .int(line.product.id),
                        "product_uom_qty": .double(line.quantity),
                        "price_unit": .double(line.priceUnit)
                    ])
                ])
            }
            let values: [String: JSON] = [
                "partner_id": .int(partner.id),
                "order_line": .array(linesPayload)
            ]
            _ = try await client.create(model: "sale.order", values: values)
            await onSaved?()
            dismiss()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
