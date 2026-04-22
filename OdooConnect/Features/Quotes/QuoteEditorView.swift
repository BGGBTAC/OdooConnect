import SwiftUI
import SwiftData

/// In-flight editor state. Decoupled from the network `Partner` / `Product`
/// types so the editor can be re-opened from a locally stored `DraftQuote`
/// without round-tripping through the API.
struct EditorPartner: Identifiable, Equatable, Hashable, Sendable {
    let id: Int
    let name: String
}

struct EditorLine: Identifiable, Sendable {
    let id: UUID
    var productId: Int
    var productName: String
    var quantity: Double
    var priceUnit: Double

    init(id: UUID = UUID(), productId: Int, productName: String, quantity: Double, priceUnit: Double) {
        self.id = id
        self.productId = productId
        self.productName = productName
        self.quantity = quantity
        self.priceUnit = priceUnit
    }

    var subtotal: Double { quantity * priceUnit }
}

struct QuoteEditorView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(DraftSync.self) private var draftSync
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let draft: DraftQuote?

    @State private var partner: EditorPartner?
    @State private var lines: [EditorLine] = []
    @State private var isSaving = false
    @State private var error: String?
    @State private var showingPartnerPicker = false
    @State private var showingProductPicker = false
    @State private var hydrated = false

    init(draft: DraftQuote? = nil) {
        self.draft = draft
    }

    var total: Double { lines.reduce(0) { $0 + $1.subtotal } }

    private var code: String {
        draft?.currencyCode ?? auth.companyCurrency.code
    }

    var body: some View {
        Form {
            Section("Kunde") {
                Button {
                    showingPartnerPicker = true
                } label: {
                    HStack {
                        Text(partner?.name ?? "Kunden auswählen")
                            .foregroundStyle(partner == nil ? .secondary : .primary)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
            }

            Section("Positionen") {
                ForEach($lines) { $line in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(line.productName).font(.headline)
                        Stepper(value: $line.quantity, in: 0.01...9999, step: 1) {
                            Text("Menge: \(line.quantity, specifier: "%.2f")")
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
                            Text(line.subtotal, format: .currency(code: code))
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
                    Text(total, format: .currency(code: code))
                        .font(.title3.bold().monospacedDigit())
                }
            }

            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle(draft == nil ? "Neues Angebot" : "Entwurf bearbeiten")
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
            PartnerPickerView { picked in
                partner = EditorPartner(id: picked.id, name: picked.name)
                showingPartnerPicker = false
            }
        }
        .sheet(isPresented: $showingProductPicker) {
            ProductPickerView { product in
                lines.append(EditorLine(
                    productId: product.id,
                    productName: product.name,
                    quantity: 1,
                    priceUnit: product.list_price
                ))
                showingProductPicker = false
            }
        }
        .onAppear(perform: hydrate)
    }

    private var canSave: Bool {
        partner != nil && !lines.isEmpty && !isSaving
    }

    private func hydrate() {
        guard !hydrated else { return }
        hydrated = true
        guard let draft else { return }
        partner = EditorPartner(id: draft.partnerId, name: draft.partnerName)
        lines = draft.lines.map { line in
            EditorLine(
                productId: line.productId,
                productName: line.productName,
                quantity: line.quantity,
                priceUnit: line.priceUnit
            )
        }
    }

    private func save() async {
        guard let partner else { return }
        isSaving = true
        defer { isSaving = false }

        let target: DraftQuote
        if let draft {
            draft.partnerId = partner.id
            draft.partnerName = partner.name
            draft.lines.removeAll()
            draft.status = .pending
            draft.attempts = 0
            draft.lastError = nil
            target = draft
        } else {
            let new = DraftQuote(
                partnerId: partner.id,
                partnerName: partner.name,
                currencyId: auth.companyCurrency.id,
                currencyCode: auth.companyCurrency.code
            )
            modelContext.insert(new)
            target = new
        }
        for line in lines {
            target.lines.append(DraftLine(
                productId: line.productId,
                productName: line.productName,
                quantity: line.quantity,
                priceUnit: line.priceUnit
            ))
        }

        do {
            try modelContext.save()
        } catch {
            self.error = "Lokales Speichern fehlgeschlagen: \(error.localizedDescription)"
            return
        }

        dismiss()
        // The list listens to draftSync.lastSyncedAt and refreshes itself
        // when this completes — no need to thread a callback through here.
        Task { await draftSync.sync() }
    }
}
