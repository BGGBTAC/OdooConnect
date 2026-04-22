import SwiftUI

/// Full product editor. Diffs against the loaded `ProductDetail` so that
/// only changed fields are sent to `product.product.write` — keeps
/// audit trails clean and avoids overwriting fields with stale values.
struct ProductEditSheet: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let product: ProductDetail
    let onSaved: () async -> Void

    @State private var listPrice: Double
    @State private var standardPrice: Double
    @State private var defaultCode: String
    @State private var barcode: String
    @State private var descriptionSale: String
    @State private var saleOk: Bool
    @State private var purchaseOk: Bool
    @State private var active: Bool

    @State private var isSaving = false
    @State private var error: String?

    init(product: ProductDetail, onSaved: @escaping () async -> Void) {
        self.product = product
        self.onSaved = onSaved
        _listPrice = State(initialValue: product.list_price)
        _standardPrice = State(initialValue: product.standard_price)
        _defaultCode = State(initialValue: product.default_code ?? "")
        _barcode = State(initialValue: product.barcode ?? "")
        _descriptionSale = State(initialValue: product.description_sale ?? "")
        _saleOk = State(initialValue: product.sale_ok)
        _purchaseOk = State(initialValue: product.purchase_ok)
        _active = State(initialValue: product.active)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Preise") {
                    HStack {
                        Text("Listenpreis")
                        Spacer()
                        TextField("", value: $listPrice, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(maxWidth: 140)
                    }
                    HStack {
                        Text("Einkaufspreis")
                        Spacer()
                        TextField("", value: $standardPrice, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(maxWidth: 140)
                    }
                }

                Section("Stammdaten") {
                    HStack {
                        Text("Artikelnummer")
                        Spacer()
                        TextField("SKU-001", text: $defaultCode)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .frame(maxWidth: 200)
                    }
                    HStack {
                        Text("Barcode")
                        Spacer()
                        TextField("", text: $barcode)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .frame(maxWidth: 200)
                    }
                    if let categ = product.categ_id, !categ.isEmpty {
                        LabeledContent("Kategorie", value: categ.name)
                    }
                }

                Section("Beschreibung") {
                    TextEditor(text: $descriptionSale)
                        .frame(minHeight: 100)
                }

                Section("Sichtbarkeit") {
                    Toggle("Verkaufbar", isOn: $saleOk)
                    Toggle("Einkaufbar", isOn: $purchaseOk)
                    Toggle("Aktiv", isOn: $active)
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(product.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Speichern") { Task { await save() } }
                            .disabled(!hasChanges)
                    }
                }
            }
        }
    }

    private var hasChanges: Bool {
        listPrice != product.list_price
            || standardPrice != product.standard_price
            || defaultCode != (product.default_code ?? "")
            || barcode != (product.barcode ?? "")
            || descriptionSale != (product.description_sale ?? "")
            || saleOk != product.sale_ok
            || purchaseOk != product.purchase_ok
            || active != product.active
    }

    private func save() async {
        guard let client = auth.client else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }

        var values: [String: JSON] = [:]
        if listPrice != product.list_price        { values["list_price"]      = .double(listPrice) }
        if standardPrice != product.standard_price { values["standard_price"] = .double(standardPrice) }
        if defaultCode != (product.default_code ?? "") {
            values["default_code"] = defaultCode.isEmpty ? .bool(false) : .string(defaultCode)
        }
        if barcode != (product.barcode ?? "") {
            values["barcode"] = barcode.isEmpty ? .bool(false) : .string(barcode)
        }
        if descriptionSale != (product.description_sale ?? "") {
            values["description_sale"] = descriptionSale.isEmpty ? .bool(false) : .string(descriptionSale)
        }
        if saleOk != product.sale_ok         { values["sale_ok"]     = .bool(saleOk) }
        if purchaseOk != product.purchase_ok { values["purchase_ok"] = .bool(purchaseOk) }
        if active != product.active          { values["active"]      = .bool(active) }

        guard !values.isEmpty else { dismiss(); return }

        do {
            _ = try await client.write(
                model: "product.product",
                ids: [product.id],
                values: values
            )
            await onSaved()
            dismiss()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
