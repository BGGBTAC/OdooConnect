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
    var discount: Double
    var taxIds: [Int]
    var taxLabel: String
    /// Set once the rep edits the price field; gates whether price_unit is
    /// pushed to Odoo (vs. left to pricelist computation).
    var priceOverridden: Bool

    init(
        id: UUID = UUID(),
        productId: Int,
        productName: String,
        quantity: Double,
        priceUnit: Double,
        discount: Double = 0,
        taxIds: [Int] = [],
        taxLabel: String = "",
        priceOverridden: Bool = false
    ) {
        self.id = id
        self.productId = productId
        self.productName = productName
        self.quantity = quantity
        self.priceUnit = priceUnit
        self.discount = discount
        self.taxIds = taxIds
        self.taxLabel = taxLabel
        self.priceOverridden = priceOverridden
    }

    var subtotal: Double {
        quantity * priceUnit * (1 - discount / 100)
    }
}

struct QuoteEditorView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(DraftSync.self) private var draftSync
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let draft: DraftQuote?

    @State private var partner: EditorPartner?
    @State private var lines: [EditorLine] = []
    @State private var carrierId: Int?
    @State private var carrierName: String?
    @State private var isSaving = false
    @State private var error: String?
    @State private var showingPartnerPicker = false
    @State private var showingProductPicker = false
    @State private var showingCarrierPicker = false
    @State private var taxEditingLineId: UUID?
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
                    lineEditor(line: $line)
                }
                .onDelete { lines.remove(atOffsets: $0) }

                Button {
                    showingProductPicker = true
                } label: {
                    Label("Produkt hinzufügen", systemImage: "plus.circle")
                }
            }

            Section("Versand") {
                Button {
                    showingCarrierPicker = true
                } label: {
                    HStack {
                        Image(systemName: "shippingbox.and.arrow.backward")
                            .foregroundStyle(Theme.brand)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(carrierName ?? "Kein Versender gewählt")
                                .foregroundStyle(carrierName == nil ? .secondary : .primary)
                            Text("Optional — wird auf den Auftrag geschrieben.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
                if carrierId != nil {
                    Button(role: .destructive) {
                        carrierId = nil
                        carrierName = nil
                    } label: {
                        Label("Versender entfernen", systemImage: "xmark.circle")
                    }
                }
            }

            Section("Summe") {
                HStack {
                    Text("Netto vor Steuern").foregroundStyle(.secondary)
                    Spacer()
                    Text(total, format: .currency(code: code))
                        .monospacedDigit()
                }
                Text("Steuern werden von Odoo nach den hier hinterlegten Steuersätzen beim Speichern berechnet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
        .sheet(isPresented: $showingCarrierPicker) {
            QuoteCarrierPickerSheet(
                currentCarrierId: carrierId
            ) { picked in
                carrierId = picked?.id
                carrierName = picked?.name
            }
        }
        .sheet(item: Binding(
            get: { taxEditingLineId.flatMap { id in lines.first { $0.id == id } } },
            set: { taxEditingLineId = $0?.id }
        )) { line in
            TaxPickerSheet(
                initialSelection: Set(line.taxIds)
            ) { taxes in
                guard let idx = lines.firstIndex(where: { $0.id == line.id }) else { return }
                lines[idx].taxIds = taxes.map(\.id)
                lines[idx].taxLabel = taxes.map(\.shortLabel).joined(separator: ", ")
            }
        }
        .onAppear(perform: hydrate)
    }

    @ViewBuilder
    private func lineEditor(line: Binding<EditorLine>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(line.wrappedValue.productName).font(.headline)
            Stepper(value: line.quantity, in: 0.01...9999, step: 1) {
                Text("Menge: \(line.wrappedValue.quantity, specifier: "%.2f")")
            }
            HStack {
                Text("Preis")
                Spacer()
                TextField("", value: Binding(
                    get: { line.wrappedValue.priceUnit },
                    set: { newValue in
                        line.wrappedValue.priceUnit = newValue
                        // A manual edit pins the price; otherwise Odoo computes
                        // it from the partner pricelist on create.
                        line.wrappedValue.priceOverridden = true
                    }
                ), format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .frame(maxWidth: 100)
            }
            HStack {
                Text("Rabatt %")
                Spacer()
                TextField("", value: line.discount, format: .number.precision(.fractionLength(0...2)))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .frame(maxWidth: 80)
                Text("%").foregroundStyle(.secondary)
            }
            Button {
                taxEditingLineId = line.wrappedValue.id
            } label: {
                HStack {
                    Image(systemName: "percent")
                        .foregroundStyle(Theme.brand)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Steuern")
                        Text(line.wrappedValue.taxLabel.isEmpty
                             ? "Odoo-Default"
                             : line.wrappedValue.taxLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            HStack {
                Text("Zwischensumme").foregroundStyle(.secondary)
                Spacer()
                Text(line.wrappedValue.subtotal, format: .currency(code: code))
                    .monospacedDigit()
            }
        }
    }

    private var canSave: Bool {
        partner != nil && !lines.isEmpty && !isSaving
    }

    private func hydrate() {
        guard !hydrated else { return }
        hydrated = true
        guard let draft else { return }
        partner = EditorPartner(id: draft.partnerId, name: draft.partnerName)
        carrierId = draft.carrierId
        carrierName = draft.carrierName
        lines = draft.lines.map { line in
            EditorLine(
                productId: line.productId,
                productName: line.productName,
                quantity: line.quantity,
                priceUnit: line.priceUnit,
                discount: line.discount,
                taxIds: line.taxIds,
                taxLabel: line.taxLabel,
                priceOverridden: line.priceOverridden
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
            draft.carrierId = carrierId
            draft.carrierName = carrierName
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
            new.carrierId = carrierId
            new.carrierName = carrierName
            modelContext.insert(new)
            target = new
        }
        for line in lines {
            target.lines.append(DraftLine(
                productId: line.productId,
                productName: line.productName,
                quantity: line.quantity,
                priceUnit: line.priceUnit,
                discount: line.discount,
                taxIds: line.taxIds,
                taxLabel: line.taxLabel,
                priceOverridden: line.priceOverridden
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

/// Self-loading wrapper around `CarrierPickerSheet` for the quote editor —
/// the editor doesn't fetch the carrier list eagerly because most quotes
/// don't change the carrier, so we lazy-load only when the user taps in.
private struct QuoteCarrierPickerSheet: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let currentCarrierId: Int?
    let onSelect: (DeliveryCarrier?) -> Void

    @State private var carriers: [DeliveryCarrier] = []
    @State private var isLoading = false

    var body: some View {
        Group {
            if isLoading && carriers.isEmpty {
                NavigationStack {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .navigationTitle("Versender wählen")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Abbrechen") { dismiss() }
                            }
                        }
                }
            } else {
                CarrierPickerSheet(
                    carriers: carriers,
                    currentCarrierId: currentCarrierId,
                    onSelect: onSelect
                )
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard carriers.isEmpty, let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        carriers = (try? await client.searchRead(
            model: "delivery.carrier",
            domain: [.array([.string("active"), .string("="), .bool(true)])],
            fields: DeliveryCarrier.fields,
            limit: 100,
            order: "name asc"
        )) ?? []
    }
}
